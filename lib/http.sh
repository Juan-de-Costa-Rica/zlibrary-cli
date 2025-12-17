#!/bin/bash
# http.sh - HTTP utilities using curl

# User agent for requests (updated to recent Chrome version)
USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Timeout for requests (seconds)
HTTP_TIMEOUT="${ZLIB_TIMEOUT:-30}"

# Common browser headers to bypass anti-bot protection
BROWSER_HEADERS=(
    "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
    "Accept-Language: en-US,en;q=0.9"
    "Accept-Encoding: gzip, deflate, br"
    "DNT: 1"
    "Connection: keep-alive"
    "Upgrade-Insecure-Requests: 1"
    "Sec-Fetch-Dest: document"
    "Sec-Fetch-Mode: navigate"
    "Sec-Fetch-Site: none"
    "Sec-Fetch-User: ?1"
    "Cache-Control: max-age=0"
)

# HTTP GET request
# Usage: http_get <url> [additional curl options]
# Returns: response body
# Exit codes: 0=success, 5=network error
http_get() {
    local url="$1"
    shift

    # Build curl command with browser headers
    local curl_cmd=(curl -s -L --compressed)

    # Add User-Agent
    curl_cmd+=(-H "User-Agent: $USER_AGENT")

    # Add all browser headers
    for header in "${BROWSER_HEADERS[@]}"; do
        curl_cmd+=(-H "$header")
    done

    # Add timeout
    curl_cmd+=(--max-time "$HTTP_TIMEOUT")

    # Add any additional options passed to function
    curl_cmd+=("$@")

    # Add URL last
    curl_cmd+=("$url")

    local response
    response=$("${curl_cmd[@]}" 2>&1)
    local exit_code=$?

    # Check if response is HTML error page (503, etc)
    if echo "$response" | grep -q "503\|Service Unavailable\|Temporarily Unavailable"; then
        [ "$DEBUG" = "true" ] && echo "HTTP GET failed: $url (503 Service Unavailable)" >&2
        return 5
    fi

    if [ $exit_code -eq 0 ] && [ -n "$response" ]; then
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

    # Build curl command with browser headers
    local curl_cmd=(curl -s -L --compressed -X POST)

    # Add User-Agent
    curl_cmd+=(-H "User-Agent: $USER_AGENT")

    # Add Content-Type for POST
    curl_cmd+=(-H "Content-Type: application/x-www-form-urlencoded")

    # Add timeout
    curl_cmd+=(--max-time "$HTTP_TIMEOUT")

    # Add POST data
    curl_cmd+=(--data "$data")

    # Add any additional options
    curl_cmd+=("$@")

    # Add URL last
    curl_cmd+=("$url")

    local response
    response=$("${curl_cmd[@]}" 2>&1)
    local exit_code=$?

    if [ $exit_code -eq 0 ] && [ -n "$response" ]; then
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

    # Build curl command with browser headers
    local curl_opts=(curl -s -L --compressed)

    # Add User-Agent
    curl_opts+=(-H "User-Agent: $USER_AGENT")

    # Add all browser headers
    for header in "${BROWSER_HEADERS[@]}"; do
        curl_opts+=(-H "$header")
    done

    # Add cookies if provided
    if [ -n "$cookies" ]; then
        curl_opts+=(-H "Cookie: $cookies")
    fi

    # Add timeout and output
    curl_opts+=(--max-time "$HTTP_TIMEOUT")
    curl_opts+=(-o "$output")

    # Download file
    "${curl_opts[@]}" "$url"
    local exit_code=$?

    if [ $exit_code -eq 0 ] && [ -f "$output" ]; then
        # Check if file looks like HTML (rate limit response or error page)
        if file "$output" | grep -q "HTML"; then
            # Check for specific error messages
            if grep -q "503\|Service Unavailable\|rate limit\|too many requests" "$output" 2>/dev/null; then
                [ "$DEBUG" = "true" ] && echo "HTTP download failed: rate limit or service unavailable" >&2
                rm -f "$output"
                return 2
            fi
            # Generic HTML instead of book file
            rm -f "$output"
            return 2
        fi
        return 0
    else
        [ "$DEBUG" = "true" ] && echo "HTTP download failed: $url" >&2
        [ -f "$output" ] && rm -f "$output"
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
