#!/bin/bash
# http.sh - HTTP utilities using curl

# User agent for requests
USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.110 Safari/537.36"

# Timeout for requests (seconds)
HTTP_TIMEOUT="${ZLIB_TIMEOUT:-30}"

# HTTP GET request
# Usage: http_get <url> [additional curl options]
# Returns: response body
# Exit codes: 0=success, 5=network error
http_get() {
    local url="$1"
    shift

    local response
    response=$(curl -s -f -L \
        -H "User-Agent: $USER_AGENT" \
        --max-time "$HTTP_TIMEOUT" \
        "$@" \
        "$url" 2>&1)

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "$response"
        return 0
    else
        [ "$DEBUG" = "true" ] && echo "HTTP GET failed: $url" >&2
        return 5
    fi
}

# HTTP POST request
# Usage: http_post <url> <data> [additional curl options]
# Returns: response body
# Exit codes: 0=success, 5=network error
http_post() {
    local url="$1"
    local data="$2"
    shift 2

    local response
    response=$(curl -s -f -L -X POST \
        -H "User-Agent: $USER_AGENT" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --max-time "$HTTP_TIMEOUT" \
        --data "$data" \
        "$@" \
        "$url" 2>&1)

    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        echo "$response"
        return 0
    else
        [ "$DEBUG" = "true" ] && echo "HTTP POST failed: $url" >&2
        return 5
    fi
}

# Download file to specified path
# Usage: http_download <url> <output_path> [cookie_string]
# Returns: nothing
# Exit codes: 0=success, 2=rate limit, 5=network error
http_download() {
    local url="$1"
    local output="$2"
    local cookies="$3"

    # Build curl command
    local curl_opts=(
        -s -f -L
        -H "User-Agent: $USER_AGENT"
        --max-time "$HTTP_TIMEOUT"
        -o "$output"
    )

    # Add cookies if provided
    if [ -n "$cookies" ]; then
        curl_opts+=(-H "Cookie: $cookies")
    fi

    # Download file
    curl "${curl_opts[@]}" "$url"
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        # Check if file looks like HTML (rate limit response)
        if file "$output" | grep -q "HTML"; then
            rm -f "$output"
            return 2
        fi
        return 0
    else
        [ "$DEBUG" = "true" ] && echo "HTTP download failed: $url" >&2
        return 5
    fi
}

# Perform authenticated request with cookies
# Usage: http_get_auth <url> <userid> <userkey> [additional curl options]
http_get_auth() {
    local url="$1"
    local userid="$2"
    local userkey="$3"
    shift 3

    local cookies="remix_userid=$userid; remix_userkey=$userkey"

    http_get "$url" -H "Cookie: $cookies" "$@"
}

# Perform authenticated POST with cookies
# Usage: http_post_auth <url> <data> <userid> <userkey> [additional curl options]
http_post_auth() {
    local url="$1"
    local data="$2"
    local userid="$3"
    local userkey="$4"
    shift 4

    local cookies="remix_userid=$userid; remix_userkey=$userkey"

    http_post "$url" "$data" -H "Cookie: $cookies" "$@"
}
