#!/usr/bin/env nu

# Speaker-separated transcription of an audio/video file.
#
# Bootstraps a cached Python env (via uv) on first run, then runs the whisperx
# + pyannote pipeline in transcribe.py. Model/data caches live under ~/.cache,
# so subsequent runs skip all downloads.
def main [
  input: string                          # audio or video file to transcribe
  --output (-o): string = ""             # output path (default: <input>.transcript.<ext>)
  --language (-l): string = "auto"       # language code, or "auto" to detect
  --speakers (-s): int = 0               # fixed speaker count (0 = auto-detect)
  --model (-m): string = "large-v3"      # whisper model
  --format (-f): string = "txt"          # txt | md | srt | json
  --device: string = "cpu"               # cpu (mps/cuda if you know your setup)
  --names: string = ""                   # comma-separated speaker names, in order
  --reinstall                            # force-rebuild the Python environment
] {
  if not ($input | path exists) {
    error make { msg: $"transcribe: input file not found: ($input)" }
  }

  # Resolve the HuggingFace token (needed for diarization): env first, then the
  # decrypted secret written by nixenv activation.
  let token = ($env | get -o HF_TOKEN | default "")
  let token = if ($token | is-empty) {
    let f = ([$env.HOME ".config" "nixenv" "huggingface-token"] | path join)
    if ($f | path exists) { (open --raw $f | decode utf-8 | str trim) } else { "" }
  } else {
    $token
  }
  if ($token | is-empty) {
    error make { msg: "transcribe: no HuggingFace token. Set $HF_TOKEN, or add the huggingface-token secret to this machine and re-activate nixenv." }
  }

  # Persistent Python environment under the cache dir.
  let cache = ($env | get -o XDG_CACHE_HOME | default ([$env.HOME ".cache"] | path join))
  let root = ([$cache "nixenv-transcribe"] | path join)
  let venv = ([$root "venv"] | path join)
  let py = ([$venv "bin" "python"] | path join)
  let spec = "whisperx==3.8.6"
  let marker = ([$venv ".nixenv-spec"] | path join)

  let need_install = (
    if $reinstall { true
    } else if not ($py | path exists) { true
    } else if not ($marker | path exists) { true
    } else { (open --raw $marker | decode utf-8 | str trim) != $spec }
  )
  if $need_install {
    print "[transcribe] setting up Python environment (first run downloads a few GB)…"
    mkdir $root
    ^uv venv --python 3.11 $venv
    ^uv pip install --python $py $spec
    $spec | save -f $marker
  }

  # Assemble args for the pipeline (immutable, so the closure below can capture it).
  let pyargs = (
    [$input "--language" $language "--model" $model "--format" $format "--device" $device]
    | append (if ($output | is-not-empty) { ["--output" $output] } else { [] })
    | append (if $speakers > 0 { ["--speakers" ($speakers | into string)] } else { [] })
    | append (if ($names | is-not-empty) { ["--names" $names] } else { [] })
  )

  with-env { HF_TOKEN: $token } {
    ^$py "@TRANSCRIBE_PY@" ...$pyargs
  }
}
