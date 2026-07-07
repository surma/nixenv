#!/usr/bin/env python3
"""Transcribe an audio/video file into a speaker-separated transcript.

Pipeline: whisperx (faster-whisper) transcription -> wav2vec2 alignment ->
pyannote speaker diarization -> speaker-labelled, timestamped transcript.

Model/data caches live under ~/.cache (HuggingFace + torch defaults), so only
the first run downloads them. Invoked by the `transcribe` launcher, which
provides ffmpeg on PATH and HF_TOKEN in the environment.
"""
import argparse
import json
import os
import sys


def ts_human(seconds: float) -> str:
    s = int(round(seconds))
    h, s = divmod(s, 3600)
    m, s = divmod(s, 60)
    return f"{h:d}:{m:02d}:{s:02d}" if h else f"{m:d}:{s:02d}"


def ts_srt(seconds: float) -> str:
    ms = int(round(seconds * 1000))
    h, ms = divmod(ms, 3600_000)
    m, ms = divmod(ms, 60_000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def build_label_map(segments, names):
    """Map raw pyannote speaker ids to display labels, in first-appearance order."""
    order = []
    for s in segments:
        spk = s.get("speaker")
        if spk and spk not in order:
            order.append(spk)
    label_map = {}
    for i, spk in enumerate(order):
        if i < len(names) and names[i]:
            label_map[spk] = names[i]
        else:
            label_map[spk] = f"Speaker {i + 1}"
    return label_map


def fill_speakers(segments):
    last = None
    for s in segments:
        if s.get("speaker"):
            last = s["speaker"]
        else:
            s["speaker"] = last
    # Any leading segments before the first labelled one: back-fill.
    first = next((s["speaker"] for s in segments if s.get("speaker")), None)
    for s in segments:
        if not s.get("speaker"):
            s["speaker"] = first
    return segments


def merge_turns(segments, label_map):
    turns = []
    for s in segments:
        text = (s.get("text") or "").strip()
        if not text:
            continue
        name = label_map.get(s.get("speaker"), s.get("speaker") or "Speaker ?")
        if turns and turns[-1]["speaker"] == name:
            turns[-1]["text"] += " " + text
            turns[-1]["end"] = s["end"]
        else:
            turns.append({"speaker": name, "start": s["start"], "end": s["end"], "text": text})
    return turns


def render_txt(segments, label_map):
    lines = []
    for t in merge_turns(segments, label_map):
        lines.append(f"[{ts_human(t['start'])}] {t['speaker']}:")
        lines.append(t["text"])
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def render_md(segments, label_map):
    lines = ["# Transcript", ""]
    for t in merge_turns(segments, label_map):
        lines.append(f"**{t['speaker']}** _({ts_human(t['start'])})_")
        lines.append("")
        lines.append(t["text"])
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def render_srt(segments, label_map):
    lines = []
    n = 1
    for s in segments:
        text = (s.get("text") or "").strip()
        if not text:
            continue
        name = label_map.get(s.get("speaker"), s.get("speaker") or "Speaker ?")
        lines.append(str(n))
        lines.append(f"{ts_srt(s['start'])} --> {ts_srt(s['end'])}")
        lines.append(f"{name}: {text}")
        lines.append("")
        n += 1
    return "\n".join(lines).rstrip() + "\n"


def main():
    ap = argparse.ArgumentParser(prog="transcribe", description=__doc__)
    ap.add_argument("input", help="audio or video file")
    ap.add_argument("-o", "--output", help="output path (default: <input>.transcript.<ext>)")
    ap.add_argument("-l", "--language", default="auto", help="language code, or 'auto'")
    ap.add_argument("-s", "--speakers", type=int, default=0, help="fixed speaker count (0 = auto)")
    ap.add_argument("-m", "--model", default="large-v3", help="whisper model")
    ap.add_argument("-f", "--format", default="txt", choices=["txt", "md", "srt", "json"])
    ap.add_argument("--device", default="cpu")
    ap.add_argument("--compute-type", default="int8")
    ap.add_argument("--batch-size", type=int, default=8)
    ap.add_argument("--names", default="", help="comma-separated speaker names, in order of first appearance")
    args = ap.parse_args()

    if not os.path.exists(args.input):
        sys.exit(f"error: input file not found: {args.input}")

    token = os.environ.get("HF_TOKEN", "").strip()
    if not token:
        sys.exit("error: HF_TOKEN not set (needed for speaker diarization)")

    import whisperx
    from whisperx import diarize as wx_diarize

    print("[transcribe] decoding audio (ffmpeg) ...", flush=True)
    audio = whisperx.load_audio(args.input)

    print(f"[transcribe] loading ASR model '{args.model}' ...", flush=True)
    model = whisperx.load_model(args.model, args.device, compute_type=args.compute_type)
    lang = None if args.language in ("auto", "") else args.language
    result = model.transcribe(audio, batch_size=args.batch_size, language=lang)
    lang = result["language"]
    print(f"[transcribe] language: {lang}", flush=True)

    print("[transcribe] aligning words ...", flush=True)
    amodel, meta = whisperx.load_align_model(language_code=lang, device=args.device)
    result = whisperx.align(result["segments"], amodel, meta, audio, args.device, return_char_alignments=False)

    print("[transcribe] diarizing speakers ...", flush=True)
    diarizer = wx_diarize.DiarizationPipeline(token=token, device=args.device)
    dia_kwargs = {}
    if args.speakers and args.speakers > 0:
        dia_kwargs["num_speakers"] = args.speakers
    diarize_segments = diarizer(audio, **dia_kwargs)
    result = whisperx.assign_word_speakers(diarize_segments, result)
    result["language"] = lang

    segments = fill_speakers(result["segments"])
    names = [n.strip() for n in args.names.split(",")] if args.names else []
    label_map = build_label_map(segments, names)

    ext = args.format
    out_path = args.output or f"{os.path.splitext(args.input)[0]}.transcript.{ext}"

    if args.format == "json":
        text = json.dumps(result, indent=2)
    elif args.format == "md":
        text = render_md(segments, label_map)
    elif args.format == "srt":
        text = render_srt(segments, label_map)
    else:
        text = render_txt(segments, label_map)

    with open(out_path, "w") as f:
        f.write(text)

    n_speakers = len(label_map)
    print(f"[transcribe] done: {n_speakers} speakers, {len(segments)} segments", flush=True)
    print(out_path)


if __name__ == "__main__":
    main()
