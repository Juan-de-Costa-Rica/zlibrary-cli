# Z-Library Agent

AI-agent-optimized bash library for downloading ebooks from Z-Library.

## Purpose

CLI tool for AI agents (like Claude Code) to search and download English EPUB/MOBI books from Z-Library. Not designed for human interaction - optimized for programmatic use.

## Installation

```bash
# Clone to ~/.zlib-agent
git clone <repo-url> ~/.zlib-agent

# Link executable to PATH
ln -s ~/.zlib-agent/zlib-agent ~/.local/bin/zlib-agent

# Verify
zlib-agent version
```

## Authentication

```bash
# One-time setup
zlib-agent auth <email> <password>

# Check status
zlib-agent status
```

Tokens stored in `~/.zlib-agent/.tokens` (gitignored).

## Usage

### Search
```bash
zlib-agent search "atomic habits" --limit 10
```

Returns: Numbered list with ID, Hash, Title, Author, Year, Format, Size

### Download
```bash
zlib-agent download <id> <hash> /tmp/output.epub --format epub
```

Exit codes:
- 0: Success
- 2: Rate limit (10 books/day)
- 3: Not authenticated
- 4: Validation failed
- 5: Network error

### Domain Management
```bash
# Auto-discover working domain
zlib-agent auto-domain

# Test specific domain
zlib-agent test-domain https://z-library.sk

# Set domain manually
zlib-agent set-domain https://z-library.sk
```

## Architecture

```
zlib-agent (main CLI)
├── lib/auth.sh      - Authentication & token management  
├── lib/config.sh    - Configuration loading
├── lib/domains.sh   - Domain discovery (Reddit wiki, Wikipedia)
├── lib/download.sh  - Book download & validation
├── lib/http.sh      - HTTP utilities (curl wrapper)
├── lib/json.sh      - JSON parsing (jq wrapper)
├── lib/search.sh    - Book search
└── lib/validate.sh  - File validation (size + magic bytes)
```

## Features

- **Language filtering**: Only English EPUB/MOBI
- **Validation**: 2-layer (file size + magic bytes) prevents HTML error pages
- **Domain resilience**: Auto-discovers working domains from Reddit wiki + Wikipedia
- **Rate limiting**: Detects and reports 10 books/day limit
- **No dependencies**: Pure bash + curl + jq

## For AI Agents

**Quality criteria** (priority order):
1. Correct title/author match
2. EPUB > MOBI format
3. Larger file size (more complete)
4. Newer edition

**Red flags**:
- Size < 300KB (incomplete/sample)
- Author = "Unknown" or "ACADEMY"
- Spam title patterns

**Error handling**:
- Exit code 2 = rate limit hit (tell user to wait 24h)
- Network errors = try `auto-domain` first
- Import fails = wait up to 60s before reporting

## License

MIT
