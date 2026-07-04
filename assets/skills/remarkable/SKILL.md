---
name: remarkable
description: Upload files (PDFs, EPUBs) to Surma's reMarkable tablet via the `rmapi` CLI (ddvk/rmapi). Use when the user asks to send a document, paper, article, or book to their reMarkable, list what's on the tablet, or manage reMarkable folders and files.
compatibility: Requires `rmapi` CLI to be installed and configured with a valid device token via the RMAPI_CONFIG environment variable.
---

# reMarkable CLI (`rmapi`)

Use this skill to interact with the user's reMarkable tablet via the `rmapi` CLI, which talks to the reMarkable Cloud API. Documents uploaded via the cloud sync automatically to the tablet.

## Verify the CLI

Before first use in a session, confirm the CLI is available and authenticated:

```bash
command -v rmapi
rmapi ls /
```

If `ls` fails with an auth error, the device token may have expired or the `RMAPI_CONFIG` env var may not be set.

## Important notes

- `rmapi` uses a **reverse-engineered, unofficial** cloud API. It can break if reMarkable changes their backend.
- All `rmapi` commands are **non-interactive** when passed as arguments (e.g. `rmapi ls /`). Do not launch the interactive shell.
- Supported upload formats: **PDF** and **EPUB**. Other formats must be converted first.
- The reMarkable cloud syncs to the tablet automatically — uploads appear on the device within seconds to minutes.

## Choosing between EPUB and PDF — IMPORTANT

The reMarkable's EPUB renderer has significant limitations. **Default to PDF** for anything with complex formatting. Only use EPUB for simple prose.

**Use PDF when the content has any of:**
- **Code blocks** — the reMarkable ignores CSS `font-family` on `<code>`/`<pre>` elements entirely and renders code in the global proportional reading font. There is no CSS workaround; this is a firmware limitation.
- **Math formulas (MathML/LaTeX)** — the reMarkable cannot render MathML. It dumps the raw text content of `<math>` elements as inline gibberish. It also ignores the `altimg` fallback attribute.
- **Embedded fonts** — `@font-face` with OTF/TTF files in the EPUB is not reliably supported. The reader may partially load the font and fail silently, preventing fallback to system fonts.
- **CSS image sizing** — the reMarkable largely ignores CSS `width`/`height` on `<img>` tags and HTML `width`/`height` attributes. Images display at unpredictable sizes.
- **Complex CSS in general** — the renderer is limited and produces poor results with anything beyond basic styling.

**EPUB is fine when:**
- The content is **simple prose** (novels, articles, essays) with no code or math
- The user specifically wants **reflowable text** with adjustable font size

**When converting web articles/blog posts:** Check for `<pre>`, `<code>`, or `<math>` elements. If present, convert to PDF. Technical blog posts almost always need PDF.

## Uploading files

Upload a single file to the root:

```bash
rmapi put document.pdf
```

Upload to a specific folder:

```bash
rmapi put document.pdf /Books
rmapi put paper.epub "/ML/Papers"
```

Upload with options:

```bash
# Force overwrite if a file with the same name exists
rmapi put --force document.pdf /Books

# Replace PDF content but preserve existing annotations
rmapi put --content-only document.pdf /Books
```

Recursively upload a directory:

```bash
rmapi mput ./local-folder /RemoteFolder
```

## Browsing files

List the root directory:

```bash
rmapi ls /
```

Entries prefixed with `[d]` are directories, `[f]` are files.

List with details (long format, grouped directories first):

```bash
rmapi ls -l -d /Books
```

Search recursively:

```bash
# Find all files matching a regex
rmapi find / ".*routing.*"

# Find starred files
rmapi find --starred /

# Find files with a specific tag
rmapi find --tag="read-later" /
```

## Managing folders

```bash
rmapi mkdir /NewFolder
rmapi mkdir "/Papers/2026"
```

## Moving and renaming

```bash
rmapi mv "/old-name.pdf" "/new-name.pdf"
rmapi mv "/Scratch/paper.pdf" "/Papers/paper.pdf"
```

## Downloading files

Download a file from the tablet to the local filesystem:

```bash
rmapi get /Books/somebook
```

Download with annotations rendered as a PDF:

```bash
rmapi geta /Notes/meeting-notes
```

## Deleting files

**Always ask the user for explicit confirmation before deleting anything on the reMarkable.**

```bash
rmapi rm "/trash/old-document"
```

Directories must be empty before deletion.

## Common workflows

### Sending a web article as PDF

Convert a URL to PDF first, then upload:

```bash
nix shell nixpkgs#chromium -c chromium --headless --disable-gpu --print-to-pdf=/tmp/article.pdf "https://example.com/article"
rmapi put /tmp/article.pdf /Scratch
```

### Sending a paper from arxiv

```bash
web-search fetch -o /tmp/paper.pdf "https://arxiv.org/pdf/2406.18665.pdf"
rmapi put /tmp/paper.pdf "/ML/Papers"
```

## Converting EPUB to PDF for the reMarkable

The reMarkable's EPUB renderer has significant limitations: it ignores CSS `font-family` on code/pre elements (no monospace), does not render MathML, and largely ignores CSS image sizing. For EPUBs with code blocks, math formulas, or complex formatting, **convert to PDF first** using Calibre's `ebook-convert`.

### Device: reMarkable Paper Pro Move

- **Screen**: 7.3", 1696 × 954 px, 264 PPI, 16:9
- **Portrait dimensions**: 954 × 1696 px → 3.61" × 6.42"

### Conversion command

```bash
nix shell nixpkgs#calibre --command ebook-convert \
  input.epub output.pdf \
  --custom-size=3.61x6.42 \
  --unit=inch \
  --pdf-page-margin-left=22 \
  --pdf-page-margin-right=22 \
  --pdf-page-margin-top=22 \
  --pdf-page-margin-bottom=22 \
  --pdf-default-font-size=12 \
  --pdf-mono-font-size=10 \
  --pdf-mono-family="DejaVu Sans Mono" \
  --pdf-page-numbers
```

### What this does

- **Page size**: Matches the Paper Pro Move screen exactly (3.61" × 6.42" portrait)
- **Margins**: 0.3" (22pt) all sides — tight but readable on the narrow screen
- **Fonts**: 12px body, 10px monospace (DejaVu Sans Mono)
- **MathML**: Calibre's PDF renderer handles MathML natively — formulas render correctly
- **Code**: Properly monospace with syntax highlighting (colors render as grayscale on e-ink, but bold/italic variants are preserved)
- **Page numbers**: Added at the bottom of each page

### When to use

- EPUBs with **code blocks** (monospace won't render in EPUB on reMarkable)
- EPUBs with **MathML formulas** (completely broken in EPUB on reMarkable)
- EPUBs with **complex CSS** or embedded fonts that the reMarkable mangles
- When the user reports formatting issues with an EPUB on the device

For simple prose EPUBs without code or math, EPUB format is fine — it allows font size adjustment and reflow.

## Folder conventions

Check the user's existing folder structure with `rmapi ls /` before uploading. Place files in an appropriate existing folder rather than creating new top-level folders without asking.
