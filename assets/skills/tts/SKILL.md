---
name: tts
description: Synthesize speech from text using the OpenAI speech API through the LLM proxy. Use when the user asks you to read something aloud, generate audio, create a voiceover, narrate text, or produce spoken output from written content.
compatibility: Requires an OpenAI-compatible endpoint that supports POST /v1/audio/speech. On Scout, use the LLM proxy through PI_PROXY_BASE_URL and PI_PROXY_API_KEY.
---

# Text-to-Speech

Synthesize speech with the OpenAI speech endpoint. The model list and the proxy
behavior in this file were checked on 2026-09-26.

## Endpoint and credentials

```
POST ${PI_PROXY_BASE_URL}/v1/audio/speech
Authorization: Bearer ${PI_PROXY_API_KEY}
```

pi exports `PI_PROXY_BASE_URL` and `PI_PROXY_API_KEY`. On other machines, use
any OpenAI-compatible base URL and key, for example `OPENAI_BASE_URL` and
`OPENAI_API_KEY`.

- Never print the API key or `PI_PROXY_AUTH_HEADER`, not even partially. Use
  them only inside request headers.
- The proxy is behind Cloudflare. Cloudflare rejects the default User-Agent of
  Python's `urllib` with HTTP 403 and an HTML page. Use curl, or send a
  User-Agent header such as `curl/8.11.0`.
- To list the speech models that the proxy offers, run:

  ```bash
  curl -sS -H "Authorization: Bearer $PI_PROXY_API_KEY" "$PI_PROXY_BASE_URL/v1/models" \
    | jq -r '.data[] | select(.task == "audio_speech") | .id'
  ```

  If the list shows a speech model that is newer than the models below, tell
  the user that this skill needs an update.

## Models

Use `gpt-4o-mini-tts-2025-12-15`. It is the newest OpenAI text-to-speech model.
Since 2026-01-13, the alias `gpt-4o-mini-tts` points to the same snapshot. Use
the dated name, so that all clips of a project come from the same model.

- `gpt-4o-mini-tts-2025-12-15` — the default. It supports `instructions` and
  all 13 voices. OpenAI reports about 35% lower word error rate than the
  previous snapshot, and more natural voices.
- `gpt-4o-mini-tts` — the alias of the snapshot above.
- `gpt-4o-mini-tts-2025-03-20` — the previous snapshot. `/v1/models` does not
  list it, but the proxy accepts it. Users report that it follows strong style
  instructions better and truncates less often, but it has more audio
  artifacts. Use it only as a fallback (see "Known problems"). It is an old
  snapshot, so do not depend on it.
- `tts-1` and `tts-1-hd` — legacy models. They support 9 voices and no
  `instructions`. `tts-1` has lower latency. `tts-1-hd` has higher quality.
  `tts-1-1106` and `tts-1-hd-1106` are dated versions of the same models.
- `tts-001` — the proxy lists it, but requests fail with HTTP 404
  `model_not_found`. Do not use it.

The proxy also has models that produce audio but are not text-to-speech models:

- `gpt-audio-1.5` — a chat model with audio output. It writes and speaks a
  reply. It does not read your text word for word. `gpt-audio` and
  `gpt-audio-mini` are deprecated and shut down on 2027-01-20.
- `gpt-live-1` and `grok-voice-think-fast-2.0` — models for live voice
  conversations.

For narration and voiceover, OpenAI recommends the speech endpoint.

## Known problems with gpt-4o-mini-tts-2025-12-15

Since January 2026, users on the OpenAI developer forum report two problems.
On 2026-09-16, OpenAI support asked for tickets, but it did not announce a fix.

- **Silent truncation.** The request returns HTTP 200 and valid audio, but the
  last sentence is missing. Often this is a short final question, such as
  "What do you get?". Reported rates are 10 to 20% of multi-sentence inputs.
  Some reports also describe silent clips and skipped middle sentences.
- **Weak style control.** Strong or theatrical `instructions` often give a flat,
  monotone delivery. Moderate directions, such as "calm, clear, moderate
  pace", work.

To reduce the risk:

1. Send short inputs: one paragraph or a few sentences per request.
2. Compare the duration of each clip with the length of its text. Normal
   speech is about 15 characters per second. In a 27-clip narration with
   `cedar`, the range was 11 to 19 characters per second. If a clip is much
   shorter than expected, generate it again.
3. If a style does not come through, simplify the `instructions`. If that
   fails, try `gpt-4o-mini-tts-2025-03-20`.

## Request format

```bash
curl -sS --max-time 120 -o output.mp3 \
  -X POST "${PI_PROXY_BASE_URL}/v1/audio/speech" \
  -H "Authorization: Bearer ${PI_PROXY_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini-tts-2025-12-15",
    "input": "The text to speak.",
    "voice": "cedar",
    "instructions": "Tone: Clear and conversational.\nPacing: Steady and moderate.",
    "response_format": "mp3"
  }'
```

**Parameters:**

- `model` (required) — see "Models".
- `input` (required) — the text to speak. The maximum is 4096 characters. The
  model also has a limit of 2000 input tokens.
- `voice` (required) — one of the built-in voices listed below. OpenAI
  accounts with approved custom voices can pass `{"id": "voice_..."}`.
- `instructions` (optional) — how to speak: accent, emotion, intonation,
  impressions, speed, tone, or whispering. `tts-1` and `tts-1-hd` do not
  support it.
- `response_format` (optional) — `mp3` (default), `opus`, `aac`, `flac`,
  `wav`, or `pcm`
- `speed` (optional) — `0.25` to `4.0`. The default is `1.0`.
- `stream_format` (optional) — `audio` (default) or `sse`. Through the proxy,
  `sse` returns HTTP 200 with an empty body. Do not use `sse`.

The response body is the raw audio file. Use `-o filename` with curl to save
it directly. With the default stream format, the audio arrives in chunks, so a
player can start before the file is complete.

## Long texts and batches

- Split long texts at paragraph or sentence boundaries. Keep each chunk well
  below 4096 characters. Short chunks also reduce the risk of truncation.
- Use the same model, voice, and instructions for all chunks.
- Send at most 2 requests at the same time. With 6 parallel requests, the proxy
  returned HTTP 429. Retry a 429 response after an increasing delay.
- Set a client timeout of about 120 seconds. Some requests stall and never
  answer. If a request times out, send it again.
- Save each clip to a file. Do not synthesize a clip again if its file exists.

## Exact durations and joined clips

Use `pcm` when you need exact timing, for example to sync narration with
video. PCM is raw 24 kHz, 16-bit, mono, little-endian audio without a header.

- The duration in seconds is the byte count divided by 48000.
- To join clips, concatenate the files. For silence, insert zero bytes: 48000
  bytes for each second.
- To convert the result, use ffmpeg:

  ```bash
  ffmpeg -f s16le -ar 24000 -ac 1 -i narration.pcm narration.mp3
  ```

## Output formats

- **mp3** — default, good for general use
- **opus** — low latency, good for streaming
- **aac** — preferred by YouTube, Android, iOS
- **flac** — lossless, good for archiving
- **wav** — uncompressed, low decoding overhead
- **pcm** — raw 24kHz 16-bit signed little-endian samples, no header

For the fastest response, use `wav` or `pcm`.

## Voices

`gpt-4o-mini-tts` supports 13 voices. For the best quality, OpenAI recommends
`marin` and `cedar`. Use `cedar` as the default. Use `marin` for a brighter
tone. `tts-1` and `tts-1-hd` support only `alloy`, `ash`, `coral`, `echo`,
`fable`, `onyx`, `nova`, `sage`, and `shimmer`.

The voices are optimized for English. They can also speak the languages that
Whisper supports. To use a language, write the input text in that language.

The descriptions below are informal impressions, not OpenAI specifications.
The 2025-12-15 snapshot changed the sound of the voices. To hear current
samples, go to https://www.openai.fm.

**alloy** — Female, contralto. Smoky, husky, smooth and steady. Very neutral
and professional. Low expressiveness. Good for: calm narration, neutral
assistants, documentary voiceover.

**ash** — Male, baritone. Slightly scratchy but upbeat and clear.
Professional with an energetic edge. Good for: business content, podcasts,
customer support.

**ballad** — Male, tenor. Warm, narrative, curious — slight British quality
with storytelling flair. Good for: audiobooks, adventure games, engaging
demos.

**coral** — Female, higher register. Friendly, approachable, playful. Clear
and even-keeled. Good for: casual conversation, education, friendly
chatbots.

**echo** — Male, tenor. Energetic, warm, bright. Straightforward
professional tone. Good for: tutorials, presentations, voice assistants.

**fable** — Female, alto. Expressive and dramatic with a slight British/NZ
accent. Warm and theatrical. Good for: fiction narration, drama, blog posts
with personality.

**nova** — Female, alto. Lively, energetic, highly expressive. Most
responsive to emotional cues of all voices. Good for: marketing, hype
videos, dynamic ads, sports commentary.

**onyx** — Male, deep bass/baritone. Authoritative, husky, commanding
presence with good range. Good for: news, documentaries, authority figures,
serious narration.

**sage** — Female, soprano. Gentle, soothing, peaceful. Natural enunciation
with a calming quality. Good for: meditation, ASMR, therapy, bedtime
stories.

**shimmer** — Female, soft. Balanced, humanlike, neutral-warm. Understated
and natural. Good for: general narration, soft-spoken guides.

**verse** — Relaxed, friendly, easygoing — like talking to a chill friend.
Natural and approachable. Good for: casual conversation, everyday
assistants, informal content.

**marin** — Conversational, smooth. Recommended by OpenAI as one of the two
highest-quality voices. Good for: general use, polished voiceovers.

**cedar** — Energetic, conversational. Also recommended by OpenAI for best
quality. Good for: e-learning, short demos, energetic content.

## Quick reference by use case

- **Blog post narration:** fable, onyx, ballad, marin
- **Casual conversation:** coral, verse, echo
- **Technical explainers:** ash, alloy, echo
- **Soothing/calm content:** sage, shimmer
- **Hype/marketing:** nova, cedar

## Writing instructions

Write `instructions` as a short labeled spec. Include only the lines that you
need:

```
Voice Affect: <overall character and texture of the voice>
Tone: <attitude, formality, warmth>
Pacing: <slow, steady, brisk>
Emotion: <key emotions to convey>
Pronunciation: <words to enunciate, and how>
Pauses: <where to pause>
Emphasis: <words or phrases to stress>
Delivery: <cadence or rhythm>
```

- Use 4 to 8 short lines. Do not give conflicting directions, such as "fast"
  and "slow".
- Describe how to speak. Do not write a character backstory. Long,
  descriptive instructions confuse the model, and parts of them can leak into
  the audio.
- Make explicit only what the user asked for or implied. Do not invent a
  persona, an accent, or an emotion.
- Do not rewrite the input text to control the style. Put pronunciation help
  into the input text: write "A-I" for "AI", and give a phonetic spelling for
  unusual names.
- To get natural pauses, use punctuation and line breaks in the input text.
- When you iterate, change one thing at a time. Repeat the directions that
  must stay the same.

Example for narration:

```
Voice Affect: Warm and composed.
Tone: Friendly and confident.
Pacing: Steady and moderate.
Emphasis: Stress section titles and key terms.
Pauses: Brief pause after each section.
```

Short, single-line instructions also work:

- `"Speak in a warm, friendly tone as if chatting with a close friend."`
- `"Read this like a news anchor — clear, authoritative, measured pacing."`
- `"Whisper gently, as if telling a bedtime story."`
- `"Use a British accent with an energetic, enthusiastic delivery."`
- `"Speak slowly and calmly, pausing between sentences."`

## Disclosure

OpenAI's usage policies require a clear disclosure to listeners that the
voice is AI-generated. When you share or publish generated audio, label it as
AI-generated.

## Pricing

`gpt-4o-mini-tts` costs $0.60 per 1M text input tokens and $12 per 1M audio
output tokens. This is roughly $0.015 per minute of generated audio. `tts-1`
costs $15 and `tts-1-hd` costs $30 per 1M input characters.

## Sources

- Text to speech guide: https://developers.openai.com/api/docs/guides/text-to-speech
- Create speech API reference: https://developers.openai.com/api/reference/resources/audio/subresources/speech/methods/create
- Model page with snapshots and limits: https://developers.openai.com/api/docs/models/gpt-4o-mini-tts
- Snapshot announcement: https://developers.openai.com/blog/updates-audio-models
- Changelog and deprecations: https://developers.openai.com/api/docs/changelog and https://developers.openai.com/api/docs/deprecations
- OpenAI's own speech skill, source of the instructions template: https://github.com/openai/skills/tree/main/skills/.curated/speech
- Forum reports on style control: https://community.openai.com/t/tts-no-longer-follows-instructions-parameter/1371743
- Forum reports on truncation: https://community.openai.com/t/gpt-4o-mini-tts-2025-12-15-still-truncates-final-sentences-2025-03-20-is-being-deprecated/1379584
