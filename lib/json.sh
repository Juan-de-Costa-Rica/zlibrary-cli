#!/bin/bash
# json.sh - JSON utilities using jq

# Extract field from JSON
# Usage: json_get <json_string> <field_path>
# Example: json_get "$response" '.response.user_id'
json_get() {
    local json="$1"
    local path="$2"

    echo "$json" | jq -r "$path" 2>/dev/null
}

# Check if JSON is valid
# Usage: json_validate <json_string>
# Returns: 0 if valid, 1 if invalid
json_validate() {
    local json="$1"
    echo "$json" | jq empty 2>/dev/null
}

# Iterate over JSON array
# Usage: json_array <json_string> <array_path>
# Returns: array elements, one per line
json_array() {
    local json="$1"
    local path="$2"

    echo "$json" | jq -c "${path}[]" 2>/dev/null
}

# Get array length
# Usage: json_array_length <json_string> <array_path>
json_array_length() {
    local json="$1"
    local path="$2"

    echo "$json" | jq "${path} | length" 2>/dev/null
}

# Build JSON object from key-value pairs
# Usage: json_build "key1" "value1" "key2" "value2" ...
json_build() {
    local -a pairs=()

    while [ $# -gt 0 ]; do
        local key="$1"
        local value="$2"
        shift 2

        # Escape value for JSON
        value=$(echo "$value" | jq -R .)
        pairs+=("\"$key\": $value")
    done

    # Join pairs with commas
    local json_content
    json_content=$(IFS=,; echo "${pairs[*]}")

    echo "{$json_content}"
}

# Pretty print JSON
# Usage: json_pretty <json_string>
json_pretty() {
    local json="$1"
    echo "$json" | jq '.'
}

# Minify JSON (remove whitespace)
# Usage: json_minify <json_string>
json_minify() {
    local json="$1"
    echo "$json" | jq -c '.'
}
