# Z-Library Agent

AI-agent-optimized bash library for downloading ebooks from Z-Library.

## Purpose

CLI tool for AI agents (like Claude Code) to search and download English EPUB/MOBI books from Z-Library. Not designed for human interaction - optimized for programmatic use.

## Installation

```bash
# Clone to ~/.zlibrary-cli
git clone <repo-url> ~/.zlibrary-cli

# Link executable to PATH
ln -s ~/.zlibrary-cli/zlibrary-cli ~/.local/bin/zlibrary-cli

# Verify
zlibrary-cli version
```

## Authentication

```bash
# One-time setup
zlibrary-cli auth <email> <password>

# Check status
zlibrary-cli status
```

Tokens stored in `~/.zlibrary-cli/.tokens` (gitignored).

## Usage

### Search
```bash
zlibrary-cli search "atomic habits" --limit 10
```

Returns: Numbered list with ID, Hash, Title, Author, Year, Format, Size

### Download
```bash
zlibrary-cli download <id> <hash> /tmp/output.epub --format epub
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
zlibrary-cli auto-domain

# Test specific domain
zlibrary-cli test-domain https://z-library.sk

# Set domain manually
zlibrary-cli set-domain https://z-library.sk
```

## Architecture

```
zlibrary-cli (main CLI)
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

## Claude Code Integration

Want to use this with Claude Code? See **[CLAUDE_CODE_INTEGRATION.md](CLAUDE_CODE_INTEGRATION.md)** for:
- Complete skill setup instructions
- Quality criteria and decision-making logic
- Error handling workflows
- Example usage sessions

## License

MIT
