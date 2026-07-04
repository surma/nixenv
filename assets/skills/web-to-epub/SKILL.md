---
name: web-to-epub
description: Convert web pages and blog posts to clean EPUB files. Use when the user asks to save an article or web page as an EPUB.
---

# Web-to-EPUB Conversion

Convert web pages and blog posts into clean, readable EPUB files. Uses Mozilla's Readability.js (the same engine behind Firefox Reader Mode) to extract article content, then packages it as an EPUB with embedded images.

## Tool: `percollate`

`percollate` is a Node.js CLI that handles the full pipeline: fetch → Readability extraction → EPUB packaging.

## Verify the CLI

```bash
command -v percollate
```

If not available, run via Nix: `nix shell nixpkgs#percollate -c percollate ...`

## Converting a single article

```bash
percollate epub -o /tmp/article-title.epub "https://example.com/blog/article"
```

This will:
1. Fetch the page HTML
2. Run Readability to extract the main article content (strips nav, ads, sidebars, footers)
3. Download and embed images referenced in the article
4. Package everything as a valid EPUB file

## Converting multiple articles into one EPUB

Pass multiple URLs to combine them as chapters in a single EPUB:

```bash
percollate epub \
  -o /tmp/collected-articles.epub \
  -t "Collected Articles on Topic X" \
  "https://example.com/part-1" \
  "https://example.com/part-2" \
  "https://example.com/part-3"
```

## Useful options

- `-o <path>` / `--output=<path>` — output file path (required for predictable placement)
- `-t <title>` / `--title=<title>` — override the EPUB title (defaults to the page title)
- `-a <author>` / `--author=<author>` — set the author metadata
- `-w <seconds>` / `--wait=<seconds>` — pause between fetching multiple URLs (polite crawling)
- `--css=<style>` — inject additional inline CSS
- `--style=<path>` — use a custom CSS file

## Other output formats

`percollate` also supports PDF, HTML, and Markdown output:

```bash
percollate pdf -o /tmp/article.pdf "https://..."
percollate md -o /tmp/article.md "https://..."
percollate html -o /tmp/article.html "https://..."
```

## File storage rules

When saving EPUBs for the user's collection:

1. **Always save to Syncthing** at `/dump/ebooks/Blog posts/<Title>.epub` — this is the canonical ebook storage location. Use a human-readable filename based on the article title.
2. **Use `/tmp/` for intermediate files** — do not write working files to `/dump/ebooks/`.
3. **Never overwrite existing files** in `/dump/ebooks/` without asking.

## Troubleshooting

- **Empty or garbled content**: Some sites use heavy JavaScript rendering. `percollate` uses a headless browser (Chromium via Puppeteer) under the hood, so most JS-rendered pages work. If content is still missing, the site may be behind authentication or use anti-bot measures.
- **Missing images**: Images are embedded by default. If they are missing, the site may block hotlinking or require cookies. Check the EPUB contents with `unzip -l file.epub`.
- **Wrong title**: Use `-t "Correct Title"` to override.
- **Very large EPUBs**: For image-heavy articles, the EPUB may be large. This is expected — images are embedded at their original resolution.
