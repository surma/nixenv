---
name: tts
description: Synthesize speech from text using the OpenAI TTS API. Use when the user asks you to read something aloud, generate audio, create a voiceover, narrate text, or produce spoken output from written content.
compatibility: Requires an OpenAI-compatible API endpoint and key. The endpoint must support POST /v1/audio/speech.
---

# Text-to-Speech

Synthesize speech from text using the OpenAI-compatible TTS API.

## Endpoint

```
POST <base_url>/v1/audio/speech
```

The base URL and API key depend on the environment. Check for
`OPENAI_BASE_URL`, `OPENCODE_PROXY_BASE_URL`, or similar environment
variables. The API key is typically in `OPENAI_API_KEY` or
`OPENCODE_API_KEY`.

## Model

Use `gpt-4o-mini-tts`. It is the newest model with the best quality-to-speed
ratio and supports all 13 voices plus an `instructions` parameter for
controlling tone, accent, emotion, and pacing.

Older models `tts-1` and `tts-1-hd` exist but only support 9 voices and lack
the `instructions` parameter. Prefer `gpt-4o-mini-tts` unless there is a
specific reason not to.

## Request format

```bash
curl -o output.mp3 \
  -X POST "${BASE_URL}/v1/audio/speech" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini-tts",
    "input": "The text to speak.",
    "voice": "verse",
    "instructions": "Speak in a clear, conversational tone.",
    "response_format": "mp3"
  }'
```

**Parameters:**

- `model` (required) — `gpt-4o-mini-tts`
- `input` (required) — the text to synthesize (max 2000 characters)
- `voice` (required) — one of the 13 voices listed below
- `instructions` (optional) — natural-language prompt controlling delivery
  style: accent, emotion, pacing, whispering, energy level, etc.
- `response_format` (optional) — `mp3` (default), `opus`, `aac`, `flac`,
  `wav`, or `pcm`

The response body is the raw audio file. Use `-o filename` with curl to save
it directly.

## Input length limit

`gpt-4o-mini-tts` accepts up to 2000 characters per request. For longer
texts, split into chunks and concatenate the audio files, or make multiple
requests.

## Output formats

- **mp3** — default, good for general use
- **opus** — low latency, good for streaming
- **aac** — preferred by YouTube, Android, iOS
- **flac** — lossless, good for archiving
- **wav** — uncompressed, low decoding overhead
- **pcm** — raw 24kHz 16-bit signed little-endian samples, no header

## Voices

All 13 voices are available with `gpt-4o-mini-tts`.

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

## Instructions examples

The `instructions` parameter accepts natural language. Examples:

- `"Speak in a warm, friendly tone as if chatting with a close friend."`
- `"Read this like a news anchor — clear, authoritative, measured pacing."`
- `"Whisper gently, as if telling a bedtime story."`
- `"Use a British accent with an energetic, enthusiastic delivery."`
- `"Speak slowly and calmly, pausing between sentences."`

## Pricing

`gpt-4o-mini-tts` costs approximately $12 per 1M output tokens, which works
out to roughly $0.015 per minute of generated audio.
