#!/bin/bash
# Unity Lock Manager CLI - Command line interface for lock management operations
# Provides tools for monitoring, debugging, and managing the Unity lock system

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNITY_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source Unity event system
source "$UNITY_ROOT/lib/unity/core/unity-events.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Display usage information
show_usage() {
    cat << EOF
Unity Lock Manager CLI - v2.0

USAGE:
    $(basename "$0") <command> [options]

COMMANDS:
    status          Show comprehensive lock status report
    list            List all active locks
    owners          Show lock ownership information
    dependencies    Show lock dependency graph
    cleanup         Clean up stale locks
    monitor         Monitor lock operations in real-time
    test            Test lock system functionality
    deadlock        Check for potential deadlocks
    force-release   Force release a specific lock (use with caution)
    help            Show this help message

OPTIONS:
    --verbose       Enable verbose output
    --json          Output in JSON format (where applicable)
    --watch         Continuous monitoring mode
    --timeout=N     Set timeout for operations (default: 30s)

EXAMPLES:
    $(basename "$0") status                    # Show lock status
    $(basename "$0") list --json              # List locks in JSON
    $(basename "$0") monitor --watch          # Continuous monitoring
    $(basename "$0") cleanup --verbose        # Clean up with details
    $(basename "$0") force-release processing.lock  # Force release lock

LOCK TYPES:
    processing.lock     - Event processing operations
    deployment.lock     - Deployment operations
    config.lock         - Configuration updates
    monitor.lock        - Monitoring operations
    cleanup.lock        - Cleanup operations

EOF
}

# Initialize lock management
init_lock_manager() {
    unity_init_events "false" >/dev/null 2>&1
}

# Format output based on options
format_output() {
    local content="$1"
    local type="${2:-text}"
    
    case "$type" in
        json)
            echo "$content" | jq '.' 2>/dev/null || echo "$content"
            ;;
        *)
            echo "$content"
            ;;
    esac
}

# Show comprehensive lock status
cmd_status() {
    local verbose="${1:-false}"
    local format="${2:-text}"
    
    echo -e "${CYAN}Unity Lock Management Status${NC}"
    echo "=================================="
    
    if [[ "$format" == "json" ]]; then
        local json_output
        json_output=$(cat <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "lock_system": {
    "active_locks": $(cmd_list_json),
    "owners": $(cmd_owners_json),
    "dependencies": $(cmd_dependencies_json)
  }
}
EOF
        )
        format_output "$json_output" "json"
    else
        _get_lock_status_report
        
        if [[ "$verbose" == "true" ]]; then
            echo ""
            echo -e "${YELLOW}Recent Lock Operations (last 10):${NC}"
            if [[ -f "$UNITY_LOCK_ACQUISITION_LOG" ]]; then
                tail -n 10 "$UNITY_LOCK_ACQUISITION_LOG" | while IFS='|' read -r timestamp level component message; do
                    case "$level" in
                        ERROR) echo -e "${RED}$timestamp [$level]${NC} $message" ;;
                        WARN)  echo -e "${YELLOW}$timestamp [$level]${NC} $message" ;;
                        *)     echo "$timestamp [$level] $message" ;;
                    esac
                done
            else
                echo "No lock operation log found"
            fi
        fi
    fi
}

# List active locks
cmd_list() {
    local format="${1:-text}"
    
    if [[ "$format" == "json" ]]; then
        cmd_list_json
        return
    fi
    
    echo -e "${CYAN}Active Locks:${NC}"
    
    if [[ ! -f "$UNITY_LOCK_OWNERS_REGISTRY" ]]; then
        echo "No active locks"
        return
    fi
    
    local count=0
    while IFS=':' read -r pid lock_name timestamp command requester; do
        if [[ "$pid" =~ ^[0-9]+$ ]] && _is_process_alive "$pid"; then
            local age=$(($(date +%s) - timestamp))\n            local age_formatted\n            \n            if [[ $age -lt 60 ]]; then\n                age_formatted=\"${age}s\"\n            elif [[ $age -lt 3600 ]]; then\n                age_formatted=\"$((age / 60))m $((age % 60))s\"\n            else\n                age_formatted=\"$((age / 3600))h $((age % 3600 / 60))m\"\n            fi\n            \n            echo -e \"  ${GREEN}$lock_name${NC}\"\n            echo -e \"    Owner: PID $pid ($command)\"\n            echo -e \"    Age: $age_formatted\"\n            echo -e \"    Requester: $requester\"\n            echo \"\"\n            count=$((count + 1))\n        fi\n    done < \"$UNITY_LOCK_OWNERS_REGISTRY\"\n    \n    if [[ $count -eq 0 ]]; then\n        echo \"No active locks found\"\n    else\n        echo \"Total active locks: $count\"\n    fi\n}\n\n# List active locks in JSON format\ncmd_list_json() {\n    local locks_json=\"[]\"\n    \n    if [[ -f \"$UNITY_LOCK_OWNERS_REGISTRY\" ]]; then\n        locks_json=\"[\"\n        local first=true\n        \n        while IFS=':' read -r pid lock_name timestamp command requester; do\n            if [[ \"$pid\" =~ ^[0-9]+$ ]] && _is_process_alive \"$pid\"; then\n                local age=$(($(date +%s) - timestamp))\n                \n                if [[ \"$first\" == \"false\" ]]; then\n                    locks_json=\"$locks_json,\"\n                fi\n                \n                locks_json=\"$locks_json{\"\n                locks_json=\"$locks_json\\\"lock_name\\\":\\\"$lock_name\\\",\"\n                locks_json=\"$locks_json\\\"owner_pid\\\":$pid,\"\n                locks_json=\"$locks_json\\\"command\\\":\\\"$command\\\",\"\n                locks_json=\"$locks_json\\\"requester\\\":\\\"$requester\\\",\"\n                locks_json=\"$locks_json\\\"timestamp\\\":$timestamp,\"\n                locks_json=\"$locks_json\\\"age_seconds\\\":$age\"\n                locks_json=\"$locks_json}\"\n                \n                first=false\n            fi\n        done < \"$UNITY_LOCK_OWNERS_REGISTRY\"\n        \n        locks_json=\"$locks_json]\"\n    fi\n    \n    echo \"$locks_json\"\n}\n\n# Show lock owners\ncmd_owners() {\n    local format=\"${1:-text}\"\n    \n    if [[ \"$format\" == \"json\" ]]; then\n        cmd_owners_json\n        return\n    fi\n    \n    echo -e \"${CYAN}Lock Ownership Information:${NC}\"\n    \n    if [[ ! -f \"$UNITY_LOCK_OWNERS_REGISTRY\" ]]; then\n        echo \"No ownership information available\"\n        return\n    fi\n    \n    printf \"%-20s %-8s %-15s %-10s %s\\n\" \"LOCK\" \"PID\" \"COMMAND\" \"AGE\" \"REQUESTER\"\n    printf \"%-20s %-8s %-15s %-10s %s\\n\" \"----\" \"---\" \"-------\" \"---\" \"---------\"\n    \n    while IFS=':' read -r pid lock_name timestamp command requester; do\n        if [[ \"$pid\" =~ ^[0-9]+$ ]] && _is_process_alive \"$pid\"; then\n            local age=$(($(date +%s) - timestamp))\n            local age_formatted\n            \n            if [[ $age -lt 60 ]]; then\n                age_formatted=\"${age}s\"\n            elif [[ $age -lt 3600 ]]; then\n                age_formatted=\"$((age / 60))m\"\n            else\n                age_formatted=\"$((age / 3600))h\"\n            fi\n            \n            printf \"%-20s %-8s %-15s %-10s %s\\n\" \"$lock_name\" \"$pid\" \"$command\" \"$age_formatted\" \"$requester\"\n        fi\n    done < \"$UNITY_LOCK_OWNERS_REGISTRY\"\n}\n\n# Show lock owners in JSON\ncmd_owners_json() {\n    cmd_list_json\n}\n\n# Show lock dependencies\ncmd_dependencies() {\n    local format=\"${1:-text}\"\n    \n    if [[ \"$format\" == \"json\" ]]; then\n        cmd_dependencies_json\n        return\n    fi\n    \n    echo -e \"${CYAN}Lock Dependencies:${NC}\"\n    \n    if [[ ! -f \"$UNITY_LOCK_DEPENDENCY_GRAPH\" ]]; then\n        echo \"No dependency information available\"\n        return\n    fi\n    \n    local count=0\n    while IFS=':' read -r pid lock_name status; do\n        if [[ \"$pid\" =~ ^[0-9]+$ ]] && _is_process_alive \"$pid\"; then\n            echo -e \"  PID ${GREEN}$pid${NC}: $lock_name -> $status\"\n            count=$((count + 1))\n        fi\n    done < \"$UNITY_LOCK_DEPENDENCY_GRAPH\"\n    \n    if [[ $count -eq 0 ]]; then\n        echo \"No active dependencies\"\n    fi\n}\n\n# Show dependencies in JSON\ncmd_dependencies_json() {\n    local deps_json=\"[]\"\n    \n    if [[ -f \"$UNITY_LOCK_DEPENDENCY_GRAPH\" ]]; then\n        deps_json=\"[\"\n        local first=true\n        \n        while IFS=':' read -r pid lock_name status; do\n            if [[ \"$pid\" =~ ^[0-9]+$ ]] && _is_process_alive \"$pid\"; then\n                if [[ \"$first\" == \"false\" ]]; then\n                    deps_json=\"$deps_json,\"\n                fi\n                \n                deps_json=\"$deps_json{\"\n                deps_json=\"$deps_json\\\"pid\\\":$pid,\"\n                deps_json=\"$deps_json\\\"lock_name\\\":\\\"$lock_name\\\",\"\n                deps_json=\"$deps_json\\\"status\\\":\\\"$status\\\"\"\n                deps_json=\"$deps_json}\"\n                \n                first=false\n            fi\n        done < \"$UNITY_LOCK_DEPENDENCY_GRAPH\"\n        \n        deps_json=\"$deps_json]\"\n    fi\n    \n    echo \"$deps_json\"\n}\n\n# Clean up stale locks\ncmd_cleanup() {\n    local verbose=\"${1:-false}\"\n    \n    echo -e \"${CYAN}Cleaning up stale locks...${NC}\"\n    \n    local before_count\n    before_count=$(find \"$UNITY_EVENT_LOCK_DIR\" -name \"*.lock\" -type f 2>/dev/null | wc -l)\n    \n    _cleanup_stale_locks\n    \n    local after_count\n    after_count=$(find \"$UNITY_EVENT_LOCK_DIR\" -name \"*.lock\" -type f 2>/dev/null | wc -l)\n    \n    local cleaned_count=$((before_count - after_count))\n    \n    if [[ $cleaned_count -gt 0 ]]; then\n        echo -e \"${GREEN}Cleaned up $cleaned_count stale locks${NC}\"\n    else\n        echo \"No stale locks found\"\n    fi\n    \n    if [[ \"$verbose\" == \"true\" && -f \"$UNITY_LOCK_ACQUISITION_LOG\" ]]; then\n        echo \"\"\n        echo \"Recent cleanup operations:\"\n        grep \"stale_cleanup\\|STALE_LOCK_CLEANED\" \"$UNITY_LOCK_ACQUISITION_LOG\" | tail -n 5\n    fi\n}\n\n# Monitor lock operations in real-time\ncmd_monitor() {\n    local watch_mode=\"${1:-false}\"\n    \n    if [[ \"$watch_mode\" == \"true\" ]]; then\n        echo -e \"${CYAN}Monitoring lock operations (Ctrl+C to stop)...${NC}\"\n        echo \"\"\n        \n        if [[ -f \"$UNITY_LOCK_ACQUISITION_LOG\" ]]; then\n            tail -f \"$UNITY_LOCK_ACQUISITION_LOG\" | while IFS='|' read -r timestamp level component message; do\n                case \"$level\" in\n                    ERROR) echo -e \"${RED}$timestamp [$level]${NC} $message\" ;;\n                    WARN)  echo -e \"${YELLOW}$timestamp [$level]${NC} $message\" ;;\n                    INFO)  echo -e \"${GREEN}$timestamp [$level]${NC} $message\" ;;\n                    *)     echo \"$timestamp [$level] $message\" ;;\n                esac\n            done\n        else\n            echo \"Lock acquisition log not found: $UNITY_LOCK_ACQUISITION_LOG\"\n            return 1\n        fi\n    else\n        echo -e \"${CYAN}Recent lock operations (last 20):${NC}\"\n        if [[ -f \"$UNITY_LOCK_ACQUISITION_LOG\" ]]; then\n            tail -n 20 \"$UNITY_LOCK_ACQUISITION_LOG\" | while IFS='|' read -r timestamp level component message; do\n                case \"$level\" in\n                    ERROR) echo -e \"${RED}$timestamp [$level]${NC} $message\" ;;\n                    WARN)  echo -e \"${YELLOW}$timestamp [$level]${NC} $message\" ;;\n                    *)     echo \"$timestamp [$level] $message\" ;;\n                esac\n            done\n        else\n            echo \"No lock operation log found\"\n        fi\n    fi\n}\n\n# Test lock system functionality\ncmd_test() {\n    echo -e \"${CYAN}Testing lock system functionality...${NC}\"\n    \n    # Run the comprehensive test suite\n    local test_script=\"$UNITY_ROOT/tests/unity/events/test-enhanced-lock-management.sh\"\n    \n    if [[ -x \"$test_script\" ]]; then\n        \"$test_script\"\n    else\n        echo -e \"${RED}Test script not found or not executable: $test_script${NC}\"\n        return 1\n    fi\n}\n\n# Check for potential deadlocks\ncmd_deadlock() {\n    echo -e \"${CYAN}Checking for potential deadlocks...${NC}\"\n    \n    local potential_deadlocks=0\n    \n    # Analyze dependency graph for cycles\n    if [[ -f \"$UNITY_LOCK_DEPENDENCY_GRAPH\" ]]; then\n        # Simple cycle detection: look for processes waiting on each other\n        local waiting_processes\n        waiting_processes=$(grep \":waiting:\" \"$UNITY_LOCK_DEPENDENCY_GRAPH\" 2>/dev/null || true)\n        \n        if [[ -n \"$waiting_processes\" ]]; then\n            echo \"Processes waiting for locks:\"\n            echo \"$waiting_processes\" | while IFS=':' read -r pid lock_name status; do\n                local waiting_for\n                waiting_for=$(echo \"$status\" | cut -d':' -f2)\n                echo \"  PID $pid waiting for lock $lock_name (held by PID $waiting_for)\"\n                \n                # Check if the holder is also waiting\n                if grep -q \"^$waiting_for:.*:waiting:\" \"$UNITY_LOCK_DEPENDENCY_GRAPH\" 2>/dev/null; then\n                    echo -e \"    ${RED}POTENTIAL DEADLOCK: PID $waiting_for is also waiting${NC}\"\n                    potential_deadlocks=$((potential_deadlocks + 1))\n                fi\n            done\n        else\n            echo \"No processes currently waiting for locks\"\n        fi\n    else\n        echo \"No dependency graph available\"\n    fi\n    \n    if [[ $potential_deadlocks -gt 0 ]]; then\n        echo -e \"${RED}Found $potential_deadlocks potential deadlock(s)${NC}\"\n        return 1\n    else\n        echo -e \"${GREEN}No deadlocks detected${NC}\"\n        return 0\n    fi\n}\n\n# Force release a specific lock\ncmd_force_release() {\n    local lock_name=\"$1\"\n    \n    if [[ -z \"$lock_name\" ]]; then\n        echo -e \"${RED}Error: Lock name is required${NC}\"\n        echo \"Usage: $(basename \"$0\") force-release <lock_name>\"\n        return 1\n    fi\n    \n    echo -e \"${YELLOW}WARNING: Force releasing lock $lock_name${NC}\"\n    read -p \"Are you sure? This may cause data corruption! [y/N]: \" -r\n    \n    if [[ $REPLY =~ ^[Yy]$ ]]; then\n        local lock_file=\"$UNITY_EVENT_LOCK_DIR/$lock_name\"\n        \n        if [[ -f \"$lock_file\" ]]; then\n            if rm -f \"$lock_file\"; then\n                echo -e \"${GREEN}Lock $lock_name force-released${NC}\"\n                \n                # Clean up registry entries\n                local owner_pid\n                owner_pid=$(grep \":$lock_name:\" \"$UNITY_LOCK_OWNERS_REGISTRY\" 2>/dev/null | cut -d':' -f1 | head -n1)\n                \n                if [[ -n \"$owner_pid\" ]]; then\n                    _unregister_lock_owner \"$lock_name\" \"$owner_pid\"\n                    _update_dependency_graph \"$lock_name\" \"$owner_pid\" \"force_released\"\n                fi\n                \n                echo \"Registry entries cleaned up\"\n            else\n                echo -e \"${RED}Failed to remove lock file: $lock_file${NC}\"\n                return 1\n            fi\n        else\n            echo -e \"${YELLOW}Lock file not found: $lock_file${NC}\"\n        fi\n    else\n        echo \"Operation cancelled\"\n    fi\n}\n\n# Main command dispatcher\nmain() {\n    local command=\"${1:-help}\"\n    shift || true\n    \n    # Parse global options\n    local verbose=false\n    local json_format=false\n    local watch_mode=false\n    local timeout=30\n    \n    while [[ $# -gt 0 ]]; do\n        case \"$1\" in\n            --verbose)\n                verbose=true\n                shift\n                ;;\n            --json)\n                json_format=true\n                shift\n                ;;\n            --watch)\n                watch_mode=true\n                shift\n                ;;\n            --timeout=*)\n                timeout=\"${1#*=}\"\n                shift\n                ;;\n            *)\n                break\n                ;;\n        esac\n    done\n    \n    # Initialize lock management\n    init_lock_manager\n    \n    # Execute command\n    case \"$command\" in\n        status)\n            cmd_status \"$verbose\" \"$([ \"$json_format\" = true ] && echo json || echo text)\"\n            ;;\n        list)\n            cmd_list \"$([ \"$json_format\" = true ] && echo json || echo text)\"\n            ;;\n        owners)\n            cmd_owners \"$([ \"$json_format\" = true ] && echo json || echo text)\"\n            ;;\n        dependencies)\n            cmd_dependencies \"$([ \"$json_format\" = true ] && echo json || echo text)\"\n            ;;\n        cleanup)\n            cmd_cleanup \"$verbose\"\n            ;;\n        monitor)\n            cmd_monitor \"$watch_mode\"\n            ;;\n        test)\n            cmd_test\n            ;;\n        deadlock)\n            cmd_deadlock\n            ;;\n        force-release)\n            cmd_force_release \"$1\"\n            ;;\n        help|--help|-h)\n            show_usage\n            ;;\n        *)\n            echo -e \"${RED}Unknown command: $command${NC}\"\n            echo \"\"\n            show_usage\n            exit 1\n            ;;\n    esac\n}\n\n# Run main function if script is executed directly\nif [[ \"${BASH_SOURCE[0]}\" == \"${0}\" ]]; then\n    main \"$@\"\nfi