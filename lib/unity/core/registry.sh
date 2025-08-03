#!/bin/bash
# Unity Service Registry - Simple stub for testing

# Use bash 3 compatible approach
if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
    declare -A UNITY_SERVICES
else
    # Fallback for bash 3
    UNITY_SERVICES_KEYS=""
    UNITY_SERVICES_VALUES=""
fi

unity_register_service() {
    local name="$1"
    local description="$2"
    local tags="$3"
    
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        UNITY_SERVICES[$name]="$description|$tags"
    else
        # Bash 3 fallback - simple storage
        UNITY_SERVICES_KEYS="$UNITY_SERVICES_KEYS $name"
        # Use a sanitized name for the variable
        local safe_name=$(echo "$name" | tr -cd 'a-zA-Z0-9_')
        eval "UNITY_SERVICE_${safe_name}='$description|$tags'"
    fi
    return 0
}