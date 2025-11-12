#!/bin/bash
# auth.sh - Authentication module for Z-Library

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/http.sh"
source "$SCRIPT_DIR/json.sh"

# Default authentication domain
AUTH_DOMAIN="https://z-library.sk"

# Login and obtain tokens
# Usage: zlib_auth_login <email> <password> [domain]
# Returns: 0=success, 3=auth failed, 5=network error
# Sets: ZLIB_USERID, ZLIB_USERKEY, ZLIB_EXPIRES
zlib_auth_login() {
    local email="$1"
    local password="$2"
    local auth_domain="${3:-$AUTH_DOMAIN}"

    # Load config to get saved domain
    config_load
    if [ -n "$ZLIB_DOMAIN" ]; then
        auth_domain="$ZLIB_DOMAIN"
    fi

    if [ -z "$email" ] || [ -z "$password" ]; then
        echo "Error: Email and password required" >&2
        return 1
    fi

    # Create temporary file for cookies
    local cookie_file
    cookie_file=$(mktemp)
    trap "rm -f $cookie_file" RETURN

    [ "$DEBUG" = "true" ] && echo "Authenticating with $auth_domain..." >&2

    # Build POST data (CRITICAL: isModal=True with capital T!)
    local post_data
    post_data="isModal=True"
    post_data+="&email=$(printf %s "$email" | jq -sRr @uri)"
    post_data+="&password=$(printf %s "$password" | jq -sRr @uri)"
    post_data+="&site_mode=books"
    post_data+="&action=login"
    post_data+="&isSingleLogin=1"
    post_data+="&redirectUrl="
    post_data+="&gg_json_mode=1"

    # Perform login request
    local response
    response=$(curl -s -X POST "${auth_domain}/rpc.php" \
        -H "User-Agent: $USER_AGENT" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --max-time "$HTTP_TIMEOUT" \
        --data "$post_data" \
        -c "$cookie_file" 2>&1)

    local curl_exit=$?

    if [ $curl_exit -ne 0 ]; then
        [ "$QUIET" != "true" ] && echo "Error: Network request failed to $auth_domain" >&2
        [ "$QUIET" != "true" ] && echo "Hint: Try 'zlib-agent auto-domain' to find a working domain" >&2
        return 5
    fi

    [ "$DEBUG" = "true" ] && echo "Response: $response" >&2

    # Check for validation error
    if echo "$response" | grep -q '"validationError":true'; then
        local error_msg
        error_msg=$(json_get "$response" '.message')
        [ "$QUIET" != "true" ] && echo "Error: Authentication failed - $error_msg" >&2
        return 3
    fi

    # Extract user ID and key from response
    local user_id user_key
    user_id=$(json_get "$response" '.response.user_id')
    user_key=$(json_get "$response" '.response.user_key')

    [ "$DEBUG" = "true" ] && echo "User ID: $user_id, User Key: ${user_key:0:10}..." >&2

    # Check if we got valid credentials
    if [ -z "$user_id" ] || [ "$user_id" = "null" ] || [ -z "$user_key" ] || [ "$user_key" = "null" ]; then
        # Try extracting from cookies as fallback
        if [ -f "$cookie_file" ]; then
            user_id=$(grep 'remix_userid' "$cookie_file" | awk '{print $NF}')
            user_key=$(grep 'remix_userkey' "$cookie_file" | awk '{print $NF}')
        fi

        if [ -z "$user_id" ] || [ -z "$user_key" ]; then
            [ "$QUIET" != "true" ] && echo "Error: Failed to extract authentication tokens" >&2
            return 3
        fi
    fi

    # Calculate expiration (41 days from now, based on observed token lifetime)
    local expires
    expires=$(($(date +%s) + 3542400))

    # Store credentials
    export ZLIB_USERID="$user_id"
    export ZLIB_USERKEY="$user_key"
    export ZLIB_EXPIRES="$expires"
    export ZLIB_DOMAIN="$auth_domain"

    # Save to config file
    config_save

    if [ "$QUIET" != "true" ]; then
        echo "Authentication successful"
        echo "  User ID: $user_id"
        echo "  Token expires: $(date -d "@$expires" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$expires" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
    fi

    return 0
}

# Validate current authentication
# Usage: zlib_auth_validate
# Returns: 0=valid, 1=invalid/expired
zlib_auth_validate() {
    config_is_authenticated
}

# Get authentication status
# Usage: zlib_auth_status
# Returns: 0=authenticated, 1=not authenticated
zlib_auth_status() {
    config_load

    if [ -z "$ZLIB_USERID" ] || [ -z "$ZLIB_USERKEY" ]; then
        if [ "$QUIET" != "true" ]; then
            echo "Status: Not authenticated"
            echo "Run: zlib-agent auth <email> <password>"
        fi
        return 1
    fi

    # Check expiration
    local now expires_date
    now=$(date +%s)
    expires_date=$(date -d "@$ZLIB_EXPIRES" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$ZLIB_EXPIRES" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)

    if [ "$ZLIB_EXPIRES" -gt 0 ] && [ "$now" -gt "$ZLIB_EXPIRES" ]; then
        if [ "$QUIET" != "true" ]; then
            echo "Status: Authenticated (EXPIRED)"
            echo "  User ID: $ZLIB_USERID"
            echo "  Expired: $expires_date"
            echo "Run: zlib-agent auth <email> <password>"
        fi
        return 1
    fi

    if [ "$QUIET" != "true" ]; then
        echo "Status: Authenticated"
        echo "  User ID: $ZLIB_USERID"
        echo "  Expires: $expires_date"

        # Calculate days remaining
        local days_remaining
        days_remaining=$(( (ZLIB_EXPIRES - now) / 86400 ))
        echo "  Days remaining: $days_remaining"
    fi

    return 0
}

# Logout (clear stored credentials)
# Usage: zlib_auth_logout
zlib_auth_logout() {
    config_load

    # Clear credentials
    export ZLIB_USERID=""
    export ZLIB_USERKEY=""
    export ZLIB_EXPIRES=0

    # Save cleared config
    config_save

    [ "$QUIET" != "true" ] && echo "Logged out successfully"
    return 0
}
