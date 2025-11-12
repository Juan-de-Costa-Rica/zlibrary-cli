#!/bin/bash
# validate.sh - File validation utilities

# Minimum file size (100KB) - anything smaller is likely an error page
MIN_FILE_SIZE=102400

# Magic bytes for file formats
# EPUB: PK (ZIP format) - 0x504b
# MOBI: BOOKMOBI at offset 60
declare -A MAGIC_BYTES=(
    [epub]="504b"
    [mobi]="BOOKMOBI"
)

# Validate file size
# Usage: validate_size <file_path>
# Returns: 0 if valid, 4 if too small
validate_size() {
    local file="$1"

    if [ ! -f "$file" ]; then
        [ "$DEBUG" = "true" ] && echo "File not found: $file" >&2
        return 4
    fi

    local size
    size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)

    if [ "$size" -lt "$MIN_FILE_SIZE" ]; then
        [ "$DEBUG" = "true" ] && echo "File too small: $size bytes (min: $MIN_FILE_SIZE)" >&2
        return 4
    fi

    return 0
}

# Validate magic bytes
# Usage: validate_magic <file_path> <format>
# Returns: 0 if valid, 4 if invalid
validate_magic() {
    local file="$1"
    local format="$2"

    if [ ! -f "$file" ]; then
        [ "$DEBUG" = "true" ] && echo "File not found: $file" >&2
        return 4
    fi

    case "$format" in
        epub)
            # EPUB files are ZIP archives, should start with PK (0x50 0x4b)
            # Use file command as it's more reliable
            if ! file "$file" | grep -qi "zip\|epub"; then
                [ "$DEBUG" = "true" ] && echo "Invalid EPUB file type" >&2
                return 4
            fi
            ;;

        mobi)
            # MOBI files have "BOOKMOBI" at offset 60
            local signature
            signature=$(dd if="$file" bs=1 skip=60 count=8 2>/dev/null)

            if [ "$signature" != "${MAGIC_BYTES[mobi]}" ]; then
                [ "$DEBUG" = "true" ] && echo "Invalid MOBI signature: $signature" >&2
                return 4
            fi
            ;;

        *)
            [ "$DEBUG" = "true" ] && echo "Unknown format: $format" >&2
            return 4
            ;;
    esac

    return 0
}

# Validate downloaded file (size + magic bytes)
# Usage: validate_file <file_path> <format>
# Returns: 0 if valid, 2 if rate limit detected, 4 if validation failed
validate_file() {
    local file="$1"
    local format="$2"

    # Check size first
    if ! validate_size "$file"; then
        # Small file likely means rate limit (HTML error page)
        return 2
    fi

    # Check magic bytes
    if ! validate_magic "$file" "$format"; then
        return 4
    fi

    return 0
}

# Check if file is HTML (error response)
# Usage: is_html <file_path>
# Returns: 0 if HTML, 1 if not
is_html() {
    local file="$1"

    if [ ! -f "$file" ]; then
        return 1
    fi

    # Check for common HTML indicators
    if head -n 5 "$file" | grep -qi "<!DOCTYPE\|<html\|<head"; then
        return 0
    fi

    return 1
}

# Sanitize filename (remove dangerous characters)
# Usage: sanitize_filename <filename>
sanitize_filename() {
    local filename="$1"

    # Remove/replace dangerous characters
    filename=$(echo "$filename" | tr '/' '_')
    filename=$(echo "$filename" | tr -d '\n\r\t')
    filename=$(echo "$filename" | sed 's/[[:space:]]\+/ /g')
    filename=$(echo "$filename" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

    # Limit length to 200 characters
    if [ ${#filename} -gt 200 ]; then
        filename="${filename:0:200}"
    fi

    echo "$filename"
}
