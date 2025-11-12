#!/bin/bash
# search.sh - Search module for Z-Library

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
source "$SCRIPT_DIR/http.sh"
source "$SCRIPT_DIR/json.sh"

# Default search domain
SEARCH_DOMAIN="${ZLIB_DOMAIN:-https://z-library.sk}"

# Search for books
# Usage: zlib_search <query> [--format epub|mobi] [--lang en] [--year-from YYYY] [--year-to YYYY] [--limit N]
# Returns: 0=success, 1=no results, 3=not authenticated, 5=network error
zlib_search() {
    local query=""
    local formats=()
    local language="english"
    local year_from=""
    local year_to=""
    local limit=10

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --format)
                formats+=("$2")
                shift 2
                ;;
            --lang)
                case "$2" in
                    en|english) language="english" ;;
                    es|spanish) language="spanish" ;;
                    fr|french) language="french" ;;
                    de|german) language="german" ;;
                    *) language="$2" ;;
                esac
                shift 2
                ;;
            --year-from)
                year_from="$2"
                shift 2
                ;;
            --year-to)
                year_to="$2"
                shift 2
                ;;
            --limit)
                limit="$2"
                shift 2
                ;;
            *)
                query="$1"
                shift
                ;;
        esac
    done

    if [ -z "$query" ]; then
        echo "Error: Search query required" >&2
        return 1
    fi

    # Load authentication
    config_load
    if ! config_is_authenticated; then
        echo "Error: Not authenticated. Run: zlib-agent auth <email> <password>" >&2
        return 3
    fi

    [ "$DEBUG" = "true" ] && echo "Searching for: $query" >&2

    # Build search parameters
    local search_data="message=$(printf %s "$query" | jq -sRr @uri)"
    search_data+="&limit=$limit"

    # Add format filters
    if [ ${#formats[@]} -gt 0 ]; then
        for format in "${formats[@]}"; do
            search_data+="&extensions[]=$format"
        done
    else
        # Default to epub and mobi
        search_data+="&extensions[]=epub"
        search_data+="&extensions[]=mobi"
    fi

    # Add language filter
    search_data+="&languages[]=$language"

    # Perform search
    local response
    response=$(http_post_auth "${SEARCH_DOMAIN}/eapi/book/search" "$search_data" "$ZLIB_USERID" "$ZLIB_USERKEY")
    local http_exit=$?

    if [ $http_exit -ne 0 ]; then
        echo "Error: Search request failed on $SEARCH_DOMAIN" >&2
        echo "Hint: Try 'zlib-agent auto-domain' to find a working domain" >&2
        return 5
    fi

    [ "$DEBUG" = "true" ] && echo "Response: ${response:0:200}..." >&2

    # Parse response
    local success
    success=$(json_get "$response" '.success')

    # Handle both numeric (1) and boolean (true) success values
    if [ "$success" != "true" ] && [ "$success" != "1" ]; then
        echo "Error: Search failed" >&2
        return 1
    fi

    # Get books array
    local books_json
    books_json=$(json_get "$response" '.books')

    if [ "$books_json" = "null" ] || [ -z "$books_json" ]; then
        if [ "$QUIET" != "true" ]; then
            echo "No books found for: $query"
        fi
        return 1
    fi

    # Count results
    local count
    count=$(echo "$books_json" | jq 'length')

    if [ "$count" -eq 0 ]; then
        if [ "$QUIET" != "true" ]; then
            echo "No books found for: $query"
        fi
        return 1
    fi

    # Filter by year if specified
    if [ -n "$year_from" ] || [ -n "$year_to" ]; then
        local filter_expr="."

        if [ -n "$year_from" ] && [ -n "$year_to" ]; then
            filter_expr="map(select(.year >= $year_from and .year <= $year_to))"
        elif [ -n "$year_from" ]; then
            filter_expr="map(select(.year >= $year_from))"
        elif [ -n "$year_to" ]; then
            filter_expr="map(select(.year <= $year_to))"
        fi

        books_json=$(echo "$books_json" | jq "$filter_expr")
        count=$(echo "$books_json" | jq 'length')

        if [ "$count" -eq 0 ]; then
            if [ "$QUIET" != "true" ]; then
                echo "No books found matching year filter"
            fi
            return 1
        fi
    fi

    # Output results
    if [ "$OUTPUT_JSON" = "true" ]; then
        # JSON output
        json_build \
            "success" "true" \
            "count" "$count" \
            "query" "$query" \
            "books" "$books_json"
    else
        # Human-readable output
        echo "Found $count books:"
        echo ""

        # Iterate through books
        local index=0
        echo "$books_json" | jq -c '.[]' | while read -r book; do
            index=$((index + 1))

            local title author year format size dl_path id
            title=$(echo "$book" | jq -r '.title')
            author=$(echo "$book" | jq -r '.author')
            year=$(echo "$book" | jq -r '.year')
            format=$(echo "$book" | jq -r '.extension' | tr '[:lower:]' '[:upper:]')
            size=$(echo "$book" | jq -r '.filesizeString')
            dl_path=$(echo "$book" | jq -r '.dlPath // .href')
            id=$(echo "$book" | jq -r '.id')

            # Extract hash from path
            # Format can be: /book/ID/HASH/... or /dl/ID/HASH
            local hash
            if [[ "$dl_path" =~ /book/[0-9]+/([a-f0-9]+)/ ]] || [[ "$dl_path" =~ /dl/[0-9]+/([a-f0-9]+) ]]; then
                hash="${BASH_REMATCH[1]}"
            else
                # Fallback: second component after ID
                hash=$(echo "$dl_path" | awk -F/ '{print $4}'  | sed 's/\.html$//')
            fi

            echo "$index. $title | $author | $year | $format | $size"
            echo "   ID: $id  Hash: $hash"
            echo ""
        done
    fi

    return 0
}

# Search and output only in JSON format (for programmatic use)
# Usage: zlib_search_json <query> [options...]
zlib_search_json() {
    OUTPUT_JSON=true zlib_search "$@"
}
