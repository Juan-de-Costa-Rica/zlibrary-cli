#!/bin/bash
# domains.sh - Domain discovery and validation for Z-Library

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/http.sh"

# Known domain discovery sources
WIKIPEDIA_URL="https://en.wikipedia.org/wiki/Z-Library"
REDDIT_WIKI_JSON="https://old.reddit.com/r/zlibrary/wiki/index/access.json"

# Known working domains (fallback list - updated from Reddit wiki Nov 2025)
KNOWN_DOMAINS=(
    "https://z-library.sk"
    "https://z-library.gs"
    "https://1lib.sk"
    "https://zlibrary-global.se"
    "https://z-lib.fm"
    "http://z-lib.gd"
    "http://z-lib.gl"
    "https://zliba.ru"
    "https://z-library.ec"
    "https://singlelogin.re"
)

# Discover domains from Wikipedia
# Returns: list of domains, one per line
discover_domains_wikipedia() {
    [ "$DEBUG" = "true" ] && echo "Fetching domains from Wikipedia..." >&2

    local page
    page=$(curl -sL "$WIKIPEDIA_URL" -H "User-Agent: Mozilla/5.0" 2>/dev/null)

    if [ $? -ne 0 ]; then
        [ "$DEBUG" = "true" ] && echo "Failed to fetch Wikipedia page" >&2
        return 1
    fi

    # Extract domains from the "Official website" or "URL" sections
    # Look for zlibrary domains in href attributes
    echo "$page" | grep -oP 'https?://[a-zA-Z0-9.-]*z-?lib[a-zA-Z0-9.-]*\.(sk|se|re|me|is|rs)' | sort -u
}

# Discover domains from Reddit wiki
# Returns: list of domains, one per line
discover_domains_reddit() {
    [ "$DEBUG" = "true" ] && echo "Fetching domains from Reddit wiki..." >&2

    # Fetch JSON from old.reddit.com
    local json_response
    json_response=$(curl -sL "$REDDIT_WIKI_JSON" -H "User-Agent: Mozilla/5.0" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$json_response" ]; then
        [ "$DEBUG" = "true" ] && echo "Failed to fetch Reddit wiki JSON" >&2
        return 1
    fi

    # Extract content_md field and find all Z-Library domains
    # Use jq to extract markdown, then grep for domains
    local domains
    if command -v jq >/dev/null 2>&1; then
        domains=$(echo "$json_response" | jq -r '.data.content_md' 2>/dev/null | \
            grep -oP 'https?://[a-zA-Z0-9.-]*(?:z-?lib|singlelogin|1lib)[a-zA-Z0-9.-]*\.(?:sk|se|re|me|is|rs|io|gs|fm|gd|gl|ru|ec)' | \
            grep -v "reddit.com" | \
            sort -u)
    else
        # Fallback: parse JSON manually (less reliable)
        domains=$(echo "$json_response" | \
            grep -oP 'https?://[a-zA-Z0-9.-]*(?:z-?lib|singlelogin|1lib)[a-zA-Z0-9.-]*\.(?:sk|se|re|me|is|rs|io|gs|fm|gd|gl|ru|ec)' | \
            grep -v "reddit.com" | \
            sort -u)
    fi

    if [ -n "$domains" ]; then
        echo "$domains"
        return 0
    else
        [ "$DEBUG" = "true" ] && echo "No domains found in Reddit wiki" >&2
        return 1
    fi
}

# Discover all available domains
# Returns: list of domains, one per line
# Always succeeds (exit 0) even if discovery sources fail, because of fallback list
discover_domains() {
    local domains=()

    # Try Wikipedia (don't let failure stop us)
    local wiki_domains
    wiki_domains=$(discover_domains_wikipedia 2>/dev/null) || true
    if [ -n "$wiki_domains" ]; then
        domains+=($wiki_domains)
    fi

    # Try Reddit (don't let failure stop us)
    local reddit_domains
    reddit_domains=$(discover_domains_reddit 2>/dev/null) || true
    if [ -n "$reddit_domains" ]; then
        domains+=($reddit_domains)
    fi

    # Add known domains as fallback
    domains+=("${KNOWN_DOMAINS[@]}")

    # Deduplicate and output
    printf '%s\n' "${domains[@]}" | sort -u

    # Always return success since we have fallback domains
    return 0
}

# Test if a domain is working
# Usage: test_domain <domain>
# Returns: 0 if working, 1 if not
test_domain() {
    local domain="$1"

    if [ -z "$domain" ]; then
        return 1
    fi

    [ "$DEBUG" = "true" ] && echo "Testing domain: $domain" >&2

    # Test by fetching the homepage
    local response
    response=$(curl -sL -w "%{http_code}" -o /dev/null \
        --max-time 10 \
        -H "User-Agent: Mozilla/5.0" \
        "$domain" 2>/dev/null)

    local http_code="$response"

    # Accept 200, 301, 302, 307, 308 (redirects are okay)
    if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ] || \
       [ "$http_code" = "307" ] || [ "$http_code" = "308" ]; then
        [ "$DEBUG" = "true" ] && echo "  ✓ $domain is working (HTTP $http_code)" >&2
        return 0
    else
        [ "$DEBUG" = "true" ] && echo "  ✗ $domain failed (HTTP $http_code)" >&2
        return 1
    fi
}

# Test authentication on a domain
# Usage: test_domain_auth <domain> <userid> <userkey>
# Returns: 0 if auth works, 1 if not
test_domain_auth() {
    local domain="$1"
    local userid="$2"
    local userkey="$3"

    if [ -z "$domain" ] || [ -z "$userid" ] || [ -z "$userkey" ]; then
        return 1
    fi

    [ "$DEBUG" = "true" ] && echo "Testing auth on: $domain" >&2

    # Test by doing a simple search (requires auth)
    local response
    response=$(curl -s -w "%{http_code}" -o /dev/null \
        --max-time 10 \
        -X POST \
        -H "User-Agent: Mozilla/5.0" \
        -H "Cookie: remix_userid=$userid; remix_userkey=$userkey" \
        --data "message=test&limit=1" \
        "$domain/eapi/book/search" 2>/dev/null)

    local http_code="${response: -3}"

    if [ "$http_code" = "200" ]; then
        [ "$DEBUG" = "true" ] && echo "  ✓ Auth works on $domain" >&2
        return 0
    else
        [ "$DEBUG" = "true" ] && echo "  ✗ Auth failed on $domain (HTTP $http_code)" >&2
        return 1
    fi
}

# Find first working domain
# Returns: working domain URL
find_working_domain() {
    local domains
    domains=$(discover_domains)

    if [ -z "$domains" ]; then
        [ "$DEBUG" = "true" ] && echo "No domains discovered" >&2
        return 1
    fi

    [ "$QUIET" != "true" ] && echo "Testing discovered domains..."

    while IFS= read -r domain; do
        if test_domain "$domain"; then
            echo "$domain"
            return 0
        fi
        sleep 1  # Be nice to servers
    done <<< "$domains"

    [ "$QUIET" != "true" ] && echo "No working domains found" >&2
    return 1
}

# Find best working domain (tests auth if credentials available)
# Returns: working domain URL
find_best_domain() {
    config_load

    local domains
    domains=$(discover_domains)

    if [ -z "$domains" ]; then
        [ "$DEBUG" = "true" ] && echo "No domains discovered" >&2
        return 1
    fi

    [ "$QUIET" != "true" ] && echo "Testing discovered domains..."

    # If we have credentials, test auth
    if [ -n "$ZLIB_USERID" ] && [ -n "$ZLIB_USERKEY" ]; then
        [ "$DEBUG" = "true" ] && echo "Testing with authentication..." >&2

        while IFS= read -r domain; do
            if test_domain "$domain" && test_domain_auth "$domain" "$ZLIB_USERID" "$ZLIB_USERKEY"; then
                echo "$domain"
                return 0
            fi
            sleep 1
        done <<< "$domains"
    else
        # No credentials, just test domain availability
        while IFS= read -r domain; do
            if test_domain "$domain"; then
                echo "$domain"
                return 0
            fi
            sleep 1
        done <<< "$domains"
    fi

    [ "$QUIET" != "true" ] && echo "No working domains found" >&2
    return 1
}

# Update domain in config
# Usage: update_domain <new_domain>
update_domain() {
    local new_domain="$1"

    if [ -z "$new_domain" ]; then
        echo "Error: Domain required" >&2
        return 1
    fi

    # Validate domain format
    if ! [[ "$new_domain" =~ ^https?:// ]]; then
        echo "Error: Domain must start with http:// or https://" >&2
        return 1
    fi

    # Load config and update
    config_load
    export ZLIB_DOMAIN="$new_domain"
    config_save

    [ "$QUIET" != "true" ] && echo "Updated domain to: $new_domain"
    return 0
}

# Auto-discover and update to working domain
# Returns: 0 if successful, 1 if not
auto_update_domain() {
    [ "$QUIET" != "true" ] && echo "Auto-discovering working Z-Library domain..."

    local working_domain
    working_domain=$(find_best_domain)

    if [ $? -eq 0 ] && [ -n "$working_domain" ]; then
        update_domain "$working_domain"
        return 0
    else
        echo "Error: Could not find a working domain" >&2
        return 1
    fi
}
