# Claude Code Integration Guide

This library is designed for AI agents like Claude Code. This guide shows how to set up a Claude Code skill that uses `zlib-agent`.

## Architecture Options

### Option 1: Remote Server (Recommended)
Install `zlib-agent` on a remote server and access via SSH.

**Why?** Keeps your local machine clean, centralizes downloads, can run 24/7.

### Option 2: Local Installation
Install `zlib-agent` on the same machine running Claude Code.

**Why?** Simpler setup, no SSH needed, good for testing.

## Installation

### On Your Server/Machine

```bash
# Clone the repository
git clone https://github.com/Juan-de-Costa-Rica/zlib-agent.git ~/.zlib-agent

# Link executable to PATH
ln -s ~/.zlib-agent/zlib-agent ~/.local/bin/zlib-agent

# Authenticate (one-time)
zlib-agent auth your-email@example.com your-password

# Test it works
zlib-agent search "test" --limit 1
```

### SSH Setup (if using remote server)

On your local machine, set up passwordless SSH:

```bash
# Generate SSH key (if you don't have one)
ssh-keygen -t ed25519

# Copy to server
ssh-copy-id user@your-server.com

# Test connection
ssh user@your-server.com 'zlib-agent status'
```

## Claude Code Skill Setup

Create `~/.claude/skills/zlibrary-downloader/SKILL.md`:

```markdown
---
name: zlibrary-downloader
description: Download English EPUB/MOBI ebooks from Z-Library. Auto-invokes when user mentions downloading books or specific titles/authors.
allowed-tools: Bash,WebSearch
model: sonnet
---

# Z-Library Ebook Downloader

Download English EPUB/MOBI books from Z-Library using zlib-agent.

## Prerequisites

- `zlib-agent` installed and authenticated
- SSH access (if using remote server): `ssh YOUR_SERVER`

## Workflow

### Step 1: Research (if needed)
If user request is vague, use WebSearch to find specific book + author + rating.

### Step 2: Search Z-Library

```bash
# Local installation
zlib-agent search "QUERY" --limit 10

# Remote server (replace YOUR_SERVER)
ssh YOUR_SERVER 'zlib-agent search "QUERY" --limit 10'
```

Returns: Numbered list with ID, Hash, Title, Author, Year, Format, Size

### Step 3: Analyze Quality & Select

**Quality Criteria** (priority order):
1. Correct title/author match
2. EPUB format (preferred over MOBI)
3. Larger file size (more complete content)
4. Newer edition

**Red Flags** (avoid):
- File size < 300 KB (likely incomplete/sample)
- Author = "Unknown" or "ACADEMY"
- Spam title patterns
- Wrong publication year

**Decision**:
- Auto-pick best match (don't ask user unless truly ambiguous)
- Briefly explain your selection reasoning

### Step 4: Download

```bash
# Local
zlib-agent download ID HASH /tmp/book.epub --format epub

# Remote
ssh YOUR_SERVER 'zlib-agent download ID HASH /tmp/book.epub --format epub'
```

**Exit codes**:
- 0: Success
- 2: Rate limit (10 books/day) - tell user to wait 24h
- 3: Not authenticated - check credentials
- 4: Validation failed - try different result
- 5: Network error - try `zlib-agent auto-domain`

### Step 5: Transfer & Report

```bash
# If remote, copy to local machine
scp YOUR_SERVER:/tmp/book.epub ~/Downloads/

# Report to user
# Include: title, author, format, size, why you selected it
```

## Error Handling

### Rate Limit (Exit code 2)
Tell user: "Hit Z-Library rate limit (10 books/day). Wait 24 hours."

### Network Errors
Try auto-domain discovery first:
```bash
zlib-agent auto-domain  # or: ssh YOUR_SERVER 'zlib-agent auto-domain'
```

### No Results
- Try alternative search terms (shorter, different order)
- Try just author name if title is long
- Search for similar books

## Example Session

**User**: "Download Atomic Habits"

**Actions**:
1. Search: `zlib-agent search "atomic habits james clear" --limit 10`
2. Results show 3 options:
   - #1: MOBI, 234 KB (too small - red flag)
   - #2: EPUB, 2.3 MB, 2018 (good size, EPUB, correct year)
   - #3: EPUB, 150 KB (too small - red flag)
3. Select #2 (best quality)
4. Download: `zlib-agent download 17913839 722941 /tmp/atomic-habits.epub --format epub`
5. Report: "Downloaded 'Atomic Habits' by James Clear (2018, EPUB, 2.3 MB). Selected #2 for best file size and EPUB format."

## Customization

### Library Integration

Extend the workflow to auto-import to your library system:

**Calibre-Web**:
```bash
docker cp /tmp/book.epub calibre-container:/ingest/
```

**Apple Books** (macOS):
```bash
open -a Books /tmp/book.epub
```

**Filesystem**:
```bash
mv /tmp/book.epub ~/Books/
```

### Multiple Servers

If you have multiple servers, you can:
- Create separate skills (zlibrary-downloader-home, zlibrary-downloader-cloud)
- Or add server selection logic to a single skill

## Tips for AI Agents

- **Be autonomous**: Pick the best book automatically, only ask if truly ambiguous
- **Explain reasoning**: When selecting from multiple options, briefly say why
- **Handle errors gracefully**: Clear messages and next steps for user
- **Track rate limit**: If downloading multiple books, warn user at 8-9/10

## Troubleshooting

**"command not found: zlib-agent"**
- Check it's in PATH: `which zlib-agent`
- Or use full path: `~/.zlib-agent/zlib-agent`

**"Not authenticated"**
- Run: `zlib-agent auth email password`
- Check tokens: `zlib-agent status`

**Domain issues**
- Try: `zlib-agent auto-domain`
- Manually test: `zlib-agent test-domain https://z-library.sk`

## License

MIT
