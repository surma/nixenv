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

## Folder conventions

Check the user's existing folder structure with `rmapi ls /` before uploading. Place files in an appropriate existing folder rather than creating new top-level folders without asking.
