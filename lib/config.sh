#!/bin/bash
# config.sh - Configuration management for zlib-agent

# Default config location
CONFIG_FILE="${ZLIB_CONFIG:-$HOME/.zlib-agent.conf}"

# Load configuration from file
config_load() {
    if [ -f "$CONFIG_FILE" ]; then
        # Source the config file (bash key=value format)
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
        return 0
    fi
    return 1
}

# Save configuration to file
config_save() {
    local config_dir
    config_dir=$(dirname "$CONFIG_FILE")

    # Create config directory if it doesn't exist
    if [ ! -d "$config_dir" ]; then
        mkdir -p "$config_dir" || return 1
    fi

    # Write config with secure permissions
    {
        echo "# Z-Library Agent Configuration"
        echo "# Generated: $(date)"
        echo ""
        echo "# Authentication"
        echo "ZLIB_USERID=${ZLIB_USERID:-}"
        echo "ZLIB_USERKEY=${ZLIB_USERKEY:-}"
        echo "ZLIB_EXPIRES=${ZLIB_EXPIRES:-0}"
        echo ""
        echo "# API Settings"
        echo "ZLIB_DOMAIN=${ZLIB_DOMAIN:-https://1lib.sk}"
        echo "ZLIB_TIMEOUT=${ZLIB_TIMEOUT:-30}"
        echo ""
        echo "# Download Settings"
        echo "DOWNLOAD_DIR=${DOWNLOAD_DIR:-/tmp}"
        echo "VALIDATE_DOWNLOADS=${VALIDATE_DOWNLOADS:-true}"
        echo ""
        echo "# Calibre-Web Integration"
        echo "CALIBRE_INGEST=${CALIBRE_INGEST:-}"
        echo "CALIBRE_VERIFY_IMPORT=${CALIBRE_VERIFY_IMPORT:-true}"
        echo "CALIBRE_VERIFY_TIMEOUT=${CALIBRE_VERIFY_TIMEOUT:-60}"
    } > "$CONFIG_FILE"

    # Set secure permissions (only owner can read/write)
    chmod 600 "$CONFIG_FILE"
    return 0
}

# Get configuration value
config_get() {
    local key="$1"
    config_load
    eval "echo \"\${$key}\""
}

# Set configuration value
config_set() {
    local key="$1"
    local value="$2"

    # Load existing config
    config_load

    # Set the value in current shell
    eval "export $key=\"$value\""

    # Save updated config
    config_save
}

# Check if authenticated
config_is_authenticated() {
    config_load || return 1

    [ -n "$ZLIB_USERID" ] || return 1
    [ -n "$ZLIB_USERKEY" ] || return 1

    # Check if token expired
    local now
    now=$(date +%s)
    if [ "$ZLIB_EXPIRES" -gt 0 ] && [ "$now" -gt "$ZLIB_EXPIRES" ]; then
        return 1
    fi

    return 0
}
