#!/bin/bash
# download.sh - Download module for Z-Library

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/http.sh"
source "$SCRIPT_DIR/json.sh"
source "$SCRIPT_DIR/validate.sh"

# Default download settings
DOWNLOAD_DIR="${DOWNLOAD_DIR:-/tmp}"
DOWNLOAD_DOMAIN="${ZLIB_DOMAIN:-https://z-library.sk}"

# Download a book
# Usage: zlib_download <id> <hash> <output_path> [--format epub|mobi] [--no-validate]
# Returns: 0=success, 2=rate limit, 3=not authenticated, 4=validation failed, 5=network error
zlib_download() {
    local book_id=""
    local book_hash=""
    local output_path=""
    local format=""
    local do_validate=true

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --format)
                format="$2"
                shift 2
                ;;
            --no-validate)
                do_validate=false
                shift
                ;;
            *)
                if [ -z "$book_id" ]; then
                    book_id="$1"
                elif [ -z "$book_hash" ]; then
                    book_hash="$1"
                elif [ -z "$output_path" ]; then
                    output_path="$1"
                fi
                shift
                ;;
        esac
    done

    if [ -z "$book_id" ] || [ -z "$book_hash" ]; then
        echo "Error: Book ID and hash required" >&2
        echo "Usage: zlib-agent download <id> <hash> <output> [--format epub|mobi]" >&2
        return 1
    fi

    # Auto-detect format from output path if not specified
    if [ -z "$format" ] && [ -n "$output_path" ]; then
        case "$output_path" in
            *.epub) format="epub" ;;
            *.mobi) format="mobi" ;;
        esac
    fi

    # Default format if still not specified
    if [ -z "$format" ]; then
        format="epub"
    fi

    # Generate output path if not specified
    if [ -z "$output_path" ]; then
        output_path="${DOWNLOAD_DIR}/zlib-${book_id}.${format}"
    fi

    # Load authentication
    config_load
    if ! config_is_authenticated; then
        echo "Error: Not authenticated. Run: zlib-agent auth <email> <password>" >&2
        return 3
    fi

    [ "$DEBUG" = "true" ] && echo "Downloading book $book_id..." >&2

    # Fetch book page to get the actual download link
    # The hash from search API is for the book page, not the download
    local download_hash="$book_hash"

    [ "$DEBUG" = "true" ] && echo "Fetching download link from book page..." >&2

    # Fetch book page to get actual download link
    local book_page_url="${DOWNLOAD_DOMAIN}/book/${book_id}/${book_hash}"
    local book_page
    book_page=$(http_get_auth "$book_page_url" "$ZLIB_USERID" "$ZLIB_USERKEY")
    local page_exit=$?

    if [ $page_exit -eq 0 ]; then
        # Extract download link (format: /dl/ID/HASH)
        local extracted_hash
        extracted_hash=$(echo "$book_page" | grep -o 'href="/dl/[0-9]*/[a-f0-9]*"' | head -1 | sed 's|href="/dl/[0-9]*/||; s|"||')

        if [ -n "$extracted_hash" ]; then
            download_hash="$extracted_hash"
            [ "$DEBUG" = "true" ] && echo "Found download hash: $download_hash" >&2
        else
            [ "$DEBUG" = "true" ] && echo "Warning: Could not extract download hash, using provided hash" >&2
        fi
    else
        [ "$DEBUG" = "true" ] && echo "Warning: Could not fetch book page, using provided hash" >&2
    fi

    # Build download URL
    local download_url="${DOWNLOAD_DOMAIN}/dl/${book_id}/${download_hash}"

    if [ "$QUIET" != "true" ]; then
        echo "Downloading book $book_id..."
        echo "  URL: $download_url"
    fi

    # Prepare cookies
    local cookies="remix_userid=$ZLIB_USERID; remix_userkey=$ZLIB_USERKEY"

    # Download the file
    http_download "$download_url" "$output_path" "$cookies"
    local download_exit=$?

    if [ $download_exit -eq 2 ]; then
        echo "Error: Rate limit detected" >&2
        [ -f "$output_path" ] && rm -f "$output_path"
        return 2
    elif [ $download_exit -ne 0 ]; then
        echo "Error: Download failed from $DOWNLOAD_DOMAIN" >&2
        echo "Hint: Try 'zlib-agent auto-domain' to find a working domain" >&2
        [ -f "$output_path" ] && rm -f "$output_path"
        return 5
    fi

    # Validate the downloaded file
    if [ "$do_validate" = true ]; then
        [ "$DEBUG" = "true" ] && echo "Validating file..." >&2

        validate_file "$output_path" "$format"
        local validate_exit=$?

        if [ $validate_exit -eq 2 ]; then
            echo "Error: Rate limit detected (file is HTML)" >&2
            rm -f "$output_path"
            return 2
        elif [ $validate_exit -eq 4 ]; then
            echo "Error: Validation failed (invalid $format file)" >&2
            rm -f "$output_path"
            return 4
        fi
    fi

    # Success
    if [ "$QUIET" != "true" ]; then
        local file_size
        file_size=$(stat -c%s "$output_path" 2>/dev/null || stat -f%z "$output_path" 2>/dev/null)
        local size_mb
        size_mb=$(awk -v fs="$file_size" 'BEGIN {printf "%.2f", fs/1048576}')

        echo "Downloaded successfully"
        echo "  File: $output_path"
        echo "  Size: ${size_mb} MB"
        echo "  Format: ${format^^}"

        if [ "$do_validate" = true ]; then
            echo "  Validation: PASSED"
        fi
    fi

    return 0
}

# Import book to Calibre-Web
# Usage: zlib_import <file_path> [--verify] [--timeout SECONDS]
# Returns: 0=success, 1=import failed, 4=verification timeout
zlib_import() {
    local file_path=""
    local do_verify=false
    local timeout=60

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --verify)
                do_verify=true
                shift
                ;;
            --timeout)
                timeout="$2"
                shift 2
                ;;
            *)
                file_path="$1"
                shift
                ;;
        esac
    done

    if [ -z "$file_path" ]; then
        echo "Error: File path required" >&2
        return 1
    fi

    if [ ! -f "$file_path" ]; then
        echo "Error: File not found: $file_path" >&2
        return 1
    fi

    # Load config
    config_load

    if [ -z "$CALIBRE_INGEST" ]; then
        echo "Error: CALIBRE_INGEST not configured" >&2
        echo "Set in config: CALIBRE_INGEST=/path/to/ingest/folder" >&2
        return 1
    fi

    if [ "$QUIET" != "true" ]; then
        echo "Importing to Calibre-Web..."
        echo "  File: $(basename "$file_path")"
        echo "  Destination: $CALIBRE_INGEST"
    fi

    # Copy file to ingest folder (may require sudo)
    if [ -w "$CALIBRE_INGEST" ]; then
        cp "$file_path" "$CALIBRE_INGEST/"
    else
        echo "puravida" | sudo -S cp "$file_path" "$CALIBRE_INGEST/" 2>/dev/null
    fi

    if [ $? -ne 0 ]; then
        echo "Error: Failed to copy file to ingest folder" >&2
        return 1
    fi

    # Set permissions (1000:1000)
    local filename
    filename=$(basename "$file_path")

    if [ -w "$CALIBRE_INGEST/$filename" ]; then
        chown 1000:1000 "$CALIBRE_INGEST/$filename" 2>/dev/null
    else
        echo "puravida" | sudo -S chown 1000:1000 "$CALIBRE_INGEST/$filename" 2>/dev/null
    fi

    [ "$QUIET" != "true" ] && echo "  Copied to ingest folder"

    # Verify import if requested
    if [ "$do_verify" = true ]; then
        [ "$QUIET" != "true" ] && echo "  Waiting for Calibre-Web to process..."

        local elapsed=0
        local verified=false

        # Extract author from filename (format: "Author - Title.ext")
        local author
        author=$(basename "$file_path" | sed 's/\.epub$//; s/\.mobi$//' | cut -d'-' -f1 | xargs)

        while [ $elapsed -lt $timeout ]; do
            sleep 5
            elapsed=$((elapsed + 5))

            # Check if author directory was created with today's date
            local library_path="/var/lib/docker/volumes/homelab_shared_ebooks/_data"
            if ssh homelab "docker exec calibre-web-automated ls -lah $library_path | grep -i '$author' | grep '$(date +%b\ %d)'" >/dev/null 2>&1; then
                verified=true
                break
            fi
        done

        if [ "$verified" = true ]; then
            [ "$QUIET" != "true" ] && echo "  Import verified"
        else
            echo "Warning: Import verification timed out after ${timeout}s" >&2
            return 4
        fi
    fi

    [ "$QUIET" != "true" ] && echo "Import completed"
    return 0
}
