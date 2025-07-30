#!/usr/bin/env bash
# =============================================================================
# Deployment State JSON Helper Functions
# Provides JSON export/import functionality for state management
# =============================================================================

# Export deployments to JSON
export_deployments_json() {
    local json_output="{"
    local first=true
    
    for key in $(aa_keys DEPLOYMENT_STATES); do
        if [[ "$key" =~ ^([^:]+):(.+)$ ]]; then
            local deployment_id="${BASH_REMATCH[1]}"
            local field="${BASH_REMATCH[2]}"
            
            # Start new deployment object if needed
            if [[ "$first" == "true" ]] || [[ ! "$json_output" =~ "\"$deployment_id\":" ]]; then
                [[ "$first" == "false" ]] && json_output="${json_output},"
                json_output="${json_output}\"${deployment_id}\":{"
                first=false
            fi
            
            # Add field
            local value=$(aa_get DEPLOYMENT_STATES "$key")
            if [[ "$json_output" =~ "\"$deployment_id\":\{[^}]+\} ]]; then
                json_output="${json_output%\}},"
            fi
            json_output="${json_output}\"${field}\":\"${value}\""
        fi
    done
    
    # Close all deployment objects
    json_output=$(echo "$json_output" | sed 's/,\(["}]\)/\1/g')
    json_output="${json_output}}"
    
    echo "$json_output"
}

# Export stacks to JSON
export_stacks_json() {
    local json_output="{"
    local first=true
    
    # Group by stack name
    declare -A stack_data
    
    for key in $(aa_keys DEPLOYMENT_STATES); do
        if [[ "$key" =~ :stack_name$ ]]; then
            local deployment_id="${key%:stack_name}"
            local stack_name=$(aa_get DEPLOYMENT_STATES "$key")
            local status=$(aa_get DEPLOYMENT_STATES "${deployment_id}:status" "unknown")
            local created_at=$(aa_get DEPLOYMENT_STATES "${deployment_id}:created_at" "0")
            
            # Initialize stack data if needed
            if [[ -z "${stack_data[$stack_name]}" ]]; then
                stack_data[$stack_name]="{\"deployments\":[],"
            fi
            
            # Add deployment to stack
            local dep_info="{\"id\":\"$deployment_id\",\"status\":\"$status\",\"created_at\":$created_at}"
            stack_data[$stack_name]="${stack_data[$stack_name]%,*},${dep_info},"
        fi
    done
    
    # Build final JSON
    for stack_name in "${!stack_data[@]}"; do
        [[ "$first" == "false" ]] && json_output="${json_output},"
        json_output="${json_output}\"${stack_name}\":${stack_data[$stack_name]%,}]}"
        first=false
    done
    
    json_output="${json_output}}"
    echo "$json_output"
}

# Export resources to JSON
export_resources_json() {
    local json_output="{"
    local first=true
    
    # This would export resource tracking data
    # For now, return empty object
    echo "{}"
}

# Export transitions to JSON
export_transitions_json() {
    local json_array="["
    local first=true
    
    for key in $(aa_keys DEPLOYMENT_TRANSITIONS); do
        if [[ "$key" =~ -transition-[0-9]+:from_state$ ]]; then
            local transition_id="${key%:from_state}"
            local from_state=$(aa_get DEPLOYMENT_TRANSITIONS "${transition_id}:from_state")
            local to_state=$(aa_get DEPLOYMENT_TRANSITIONS "${transition_id}:to_state")
            local timestamp=$(aa_get DEPLOYMENT_TRANSITIONS "${transition_id}:timestamp")
            local reason=$(aa_get DEPLOYMENT_TRANSITIONS "${transition_id}:reason")
            
            [[ "$first" == "false" ]] && json_array="${json_array},"
            json_array="${json_array}{\"id\":\"$transition_id\",\"from\":\"$from_state\",\"to\":\"$to_state\",\"timestamp\":$timestamp,\"reason\":\"$reason\"}"
            first=false
        fi
    done
    
    json_array="${json_array}]"
    echo "$json_array"
}

# Export journal to JSON
export_journal_json() {
    local json_array="["
    local first=true
    local count=0
    local max_entries=1000  # Limit to recent entries
    
    # Sort journal entries by timestamp (newest first)
    local sorted_keys=$(for key in $(aa_keys DEPLOYMENT_JOURNAL); do
        echo "$key"
    done | sort -t: -k2,2nr)
    
    for key in $sorted_keys; do
        if [[ $count -ge $max_entries ]]; then
            break
        fi
        
        if [[ "$key" =~ ^([^:]+):([0-9]+):(.+)$ ]]; then
            local deployment_id="${BASH_REMATCH[1]}"
            local timestamp="${BASH_REMATCH[2]}"
            local event_type="${BASH_REMATCH[3]}"
            local details=$(aa_get DEPLOYMENT_JOURNAL "$key")
            
            [[ "$first" == "false" ]] && json_array="${json_array},"
            json_array="${json_array}{\"deployment_id\":\"$deployment_id\",\"timestamp\":$timestamp,\"event\":\"$event_type\",\"details\":\"$details\"}"
            first=false
            count=$((count + 1))
        fi
    done
    
    json_array="${json_array}]"
    echo "$json_array"
}

# Export metrics to JSON
export_metrics_json() {
    local json_output="{"
    local first=true
    
    # Calculate aggregate metrics
    local total_deployments=0
    local successful_deployments=0
    local failed_deployments=0
    local total_duration=0
    local deployment_count=0
    
    for key in $(aa_keys DEPLOYMENT_STATES); do
        if [[ "$key" =~ :status$ ]]; then
            local status=$(aa_get DEPLOYMENT_STATES "$key")
            total_deployments=$((total_deployments + 1))
            
            case "$status" in
                "completed")
                    successful_deployments=$((successful_deployments + 1))
                    ;;
                "failed"|"rolled_back")
                    failed_deployments=$((failed_deployments + 1))
                    ;;
            esac
        fi
    done
    
    # Calculate average deployment time
    for key in $(aa_keys DEPLOYMENT_METRICS); do
        if [[ "$key" =~ :execution_time$ ]]; then
            local exec_time=$(aa_get DEPLOYMENT_METRICS "$key" "0")
            total_duration=$((total_duration + exec_time))
            deployment_count=$((deployment_count + 1))
        fi
    done
    
    local avg_deployment_time=0
    if [[ $deployment_count -gt 0 ]]; then
        avg_deployment_time=$((total_duration / deployment_count))
    fi
    
    # Build metrics JSON
    json_output="${json_output}\"total_deployments\":${total_deployments},"
    json_output="${json_output}\"successful_deployments\":${successful_deployments},"
    json_output="${json_output}\"failed_deployments\":${failed_deployments},"
    json_output="${json_output}\"average_deployment_time\":${avg_deployment_time},"
    json_output="${json_output}\"last_update\":$(date +%s)}"
    
    echo "$json_output"
}

# Load deployment data to memory
load_deployment_to_memory() {
    local deployment_id="$1"
    local deployment_json="$2"
    
    # Parse JSON and load into associative arrays
    if command -v jq >/dev/null 2>&1; then
        # Load deployment states
        local fields=$(echo "$deployment_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
        while IFS='=' read -r field value; do
            if [[ -n "$field" ]]; then
                aa_set DEPLOYMENT_STATES "${deployment_id}:${field}" "$value"
            fi
        done <<< "$fields"
    fi
}

# Generate summary report
generate_summary_report() {
    local output_format="$1"
    local deployment_filter="$2"
    
    case "$output_format" in
        "json")
            echo "{\"summary\":$(export_metrics_json)}"
            ;;
        "text"|*)
            echo "=== Deployment State Summary ==="
            echo "Total Deployments: $(count_deployments)"
            echo "Active Deployments: $(count_deployments_by_status 'running')"
            echo "Completed: $(count_deployments_by_status 'completed')"
            echo "Failed: $(count_deployments_by_status 'failed')"
            echo "================================"
            ;;
    esac
}

# Count deployments
count_deployments() {
    local count=0
    for key in $(aa_keys DEPLOYMENT_STATES); do
        if [[ "$key" =~ :session_id$ ]]; then
            count=$((count + 1))
        fi
    done
    echo "$count"
}

# Count deployments by status
count_deployments_by_status() {
    local status_filter="$1"
    local count=0
    
    for key in $(aa_keys DEPLOYMENT_STATES); do
        if [[ "$key" =~ :status$ ]]; then
            local status=$(aa_get DEPLOYMENT_STATES "$key")
            if [[ "$status" == "$status_filter" ]]; then
                count=$((count + 1))
            fi
        fi
    done
    echo "$count"
}

# Schedule health checks
schedule_state_health_checks() {
    # This would implement periodic health checking
    # For now, just log
    log "Health check scheduling initialized"
}

# Sync full state
sync_full_state() {
    # Persist all state to disk
    persist_deployment_state "system" "false"
    
    # Verify integrity
    validate_state_file
}

# Sync partial state
sync_partial_state() {
    local deployment_id="$1"
    
    # Update specific deployment in state file
    persist_deployment_state "$deployment_id" "false"
}

# Sync metadata only
sync_metadata_only() {
    # Update only metadata fields
    local temp_file="${STATE_FILE}.meta.$$"
    
    jq --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.metadata.last_modified = $timestamp' "$STATE_FILE" > "$temp_file" && \
        mv -f "$temp_file" "$STATE_FILE"
}

# Export helper functions
export -f export_deployments_json export_stacks_json export_resources_json
export -f export_transitions_json export_journal_json export_metrics_json
export -f load_deployment_to_memory generate_summary_report
export -f count_deployments count_deployments_by_status
export -f schedule_state_health_checks sync_full_state sync_partial_state sync_metadata_only