#!/bin/bash
# Unity Event Bus - Compatibility Layer

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the compatibility layer which loads the actual implementation
source "$SCRIPT_DIR/event-bus-compat.sh" || {
    echo "Error: Failed to load event-bus-compat.sh" >&2
    
    # Fallback to simple implementation if compat layer fails
    # Use bash 3 compatible approach
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        declare -A EVENT_HANDLERS
    else
        # Fallback for bash 3
        EVENT_HANDLERS_KEYS=""
    fi
    
    # Define fallback functions
    unity_event_init() {
        return 0
    }
    
    unity_register_handler() {
        unity_event_on "$@"
    }
    
    unity_emit_event() {
        unity_event_emit "$@"
    }

    unity_event_on() {
    local event="$1"
    local handler="$2"
    
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        EVENT_HANDLERS[$event]="$handler"
    else
        # Bash 3 fallback
        EVENT_HANDLERS_KEYS="$EVENT_HANDLERS_KEYS $event"
        # Sanitize event name for variable
        local safe_event=$(echo "$event" | tr '.' '_' | tr -cd 'a-zA-Z0-9_')
        eval "EVENT_HANDLER_${safe_event}='$handler'"
    fi
    return 0
}

unity_event_emit() {
    local event="$1"
    shift
    local args=("$@")
    
    local handler=""
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        handler="${EVENT_HANDLERS[$event]:-}"
    else
        # Bash 3 fallback
        local safe_event=$(echo "$event" | tr '.' '_' | tr -cd 'a-zA-Z0-9_')
        eval "handler=\"\${EVENT_HANDLER_${safe_event}:-}\""
    fi
    
    if [[ -n "$handler" ]] && type "$handler" >/dev/null 2>&1; then
        "$handler" "${args[@]}"
    fi
    return 0
}
}