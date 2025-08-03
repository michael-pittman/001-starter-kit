#!/bin/bash
# Unity Event Bus Compatibility Layer
# Provides compatibility aliases for expected function names

# Source the actual event implementation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../core/unity-events.sh" || {
    echo "Error: Failed to load unity-events.sh" >&2
    return 1
}

# Provide compatibility aliases
unity_register_handler() {
    # Map to the actual function
    unity_on_event "$@"
}

unity_event_init() {
    # Map to the actual function
    unity_init_events "$@"
}

# Also ensure unity_emit_event is available (it should be)
if ! type -t unity_emit_event >/dev/null 2>&1; then
    unity_emit_event() {
        # This should not be needed as unity-events.sh defines it
        # But include as a safety fallback
        unity_event_emit "$@"
    }
fi

# Export functions for use by other scripts
export -f unity_register_handler
export -f unity_event_init
export -f unity_emit_event

return 0