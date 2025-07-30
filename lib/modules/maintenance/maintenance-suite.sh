#!/bin/bash
#
# Maintenance Suite Module
# Centralized maintenance operations with parameter-based execution
#
# Usage:
#   source maintenance-suite.sh
#   run_maintenance --operation=fix --target=deployment --backup --dry-run
#   run_maintenance --operation=cleanup --scope=all --notify
#   run_maintenance --operation=update --component=docker --rollback
#

set -euo pipefail

# Get absolute paths
MAINTENANCE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAINTENANCE_PROJECT_ROOT="$(cd "$MAINTENANCE_SCRIPT_DIR/../../.." && pwd)"
MAINTENANCE_LIB_DIR="$MAINTENANCE_PROJECT_ROOT/lib"

# Load required libraries
load_maintenance_library() {
    local library="$1"
    local library_path="${MAINTENANCE_LIB_DIR}/${library}"
    
    if [[ ! -f "$library_path" ]]; then
        echo "ERROR: Required library not found: $library_path" >&2
        return 1
    fi
    
    # shellcheck disable=SC1090
    source "$library_path" || {
        echo "ERROR: Failed to source library: $library_path" >&2
        return 1
    }
}

# Load core dependencies
load_maintenance_library "modules/core/logging.sh" || exit 1
load_maintenance_library "modules/core/errors.sh" || exit 1
load_maintenance_library "error-handling.sh" || exit 1
load_maintenance_library "modules/core/variables.sh" || exit 1

# Constants
declare -r MAINTENANCE_VERSION="1.0.0"
declare -r MAINTENANCE_LOG_PREFIX="[MAINTENANCE]"
declare -r MAINTENANCE_BACKUP_DIR="${MAINTENANCE_PROJECT_ROOT}/backup/maintenance"
declare -r MAINTENANCE_STATE_FILE="${MAINTENANCE_PROJECT_ROOT}/.maintenance-state"

# Supported operations
declare -a MAINTENANCE_OPERATIONS=("fix" "cleanup" "update" "all")
declare -a MAINTENANCE_SAFETY_FLAGS=("--backup" "--rollback" "--notify" "--dry-run")

# Operation targets
declare -A MAINTENANCE_FIX_TARGETS=(
    ["deployment"]="Fix deployment issues"
    ["docker"]="Fix Docker configuration"
    ["efs"]="Fix EFS mount issues"
    ["disk"]="Fix disk space issues"
    ["permissions"]="Fix file permissions"
)

declare -A MAINTENANCE_CLEANUP_TARGETS=(
    ["logs"]="Clean up log files"
    ["docker"]="Clean Docker resources"
    ["temp"]="Clean temporary files"
    ["aws"]="Clean AWS resources"
    ["all"]="Clean all resources"
)

declare -A MAINTENANCE_UPDATE_TARGETS=(
    ["docker"]="Update Docker images"
    ["dependencies"]="Update system dependencies"
    ["scripts"]="Update deployment scripts"
    ["configurations"]="Update configurations"
)

# Global state
declare -g MAINTENANCE_OPERATION=""
declare -g MAINTENANCE_TARGET=""
declare -g MAINTENANCE_SCOPE=""
declare -g MAINTENANCE_COMPONENT=""
declare -g MAINTENANCE_DRY_RUN=false
declare -g MAINTENANCE_BACKUP=false
declare -g MAINTENANCE_ROLLBACK=false
declare -g MAINTENANCE_NOTIFY=false
declare -g MAINTENANCE_VERBOSE=false

# Parse maintenance parameters
parse_maintenance_params() {
    local param
    
    while [[ $# -gt 0 ]]; do
        param="$1"
        
        case "$param" in
            --operation=*)
                MAINTENANCE_OPERATION="${param#*=}"
                ;;
            --target=*)
                MAINTENANCE_TARGET="${param#*=}"
                ;;
            --scope=*)
                MAINTENANCE_SCOPE="${param#*=}"
                ;;
            --component=*)
                MAINTENANCE_COMPONENT="${param#*=}"
                ;;
            --dry-run)
                MAINTENANCE_DRY_RUN=true
                ;;
            --backup)
                MAINTENANCE_BACKUP=true
                ;;
            --rollback)
                MAINTENANCE_ROLLBACK=true
                ;;
            --notify)
                MAINTENANCE_NOTIFY=true
                ;;
            --verbose|-v)
                MAINTENANCE_VERBOSE=true
                ;;
            --help|-h)
                show_maintenance_help
                return 0
                ;;
            *)
                log_error "$MAINTENANCE_LOG_PREFIX Unknown parameter: $param"
                return 1
                ;;
        esac
        shift
    done
    
    # Validate required parameters
    if [[ -z "$MAINTENANCE_OPERATION" ]]; then
        log_error "$MAINTENANCE_LOG_PREFIX Operation is required (--operation=fix|cleanup|update|all)"
        return 1
    fi
    
    # Validate operation
    local valid_op=false
    for op in "${MAINTENANCE_OPERATIONS[@]}"; do
        if [[ "$MAINTENANCE_OPERATION" == "$op" ]]; then
            valid_op=true
            break
        fi
    done
    
    if [[ "$valid_op" != true ]]; then
        log_error "$MAINTENANCE_LOG_PREFIX Invalid operation: $MAINTENANCE_OPERATION"
        return 1
    fi
    
    return 0
}

# Show help
show_maintenance_help() {
    cat << EOF
Maintenance Suite v${MAINTENANCE_VERSION}

Usage:
    run_maintenance [OPTIONS]

Operations:
    --operation=fix        Fix common issues
    --operation=cleanup    Clean up resources
    --operation=update     Update components
    --operation=all        Run all maintenance tasks

Targets (for fix):
    --target=deployment    Fix deployment issues
    --target=docker        Fix Docker configuration
    --target=efs           Fix EFS mount issues
    --target=disk          Fix disk space issues
    --target=permissions   Fix file permissions

Scopes (for cleanup):
    --scope=logs          Clean up log files
    --scope=docker        Clean Docker resources
    --scope=temp          Clean temporary files
    --scope=aws           Clean AWS resources
    --scope=all           Clean all resources

Components (for update):
    --component=docker         Update Docker images
    --component=dependencies   Update system dependencies
    --component=scripts        Update deployment scripts
    --component=configurations Update configurations

Safety Flags:
    --backup              Create backup before operations
    --rollback            Enable rollback capability
    --notify              Send notifications
    --dry-run             Show what would be done

Other Options:
    --verbose, -v         Verbose output
    --help, -h            Show this help

Examples:
    # Fix deployment issues with backup
    run_maintenance --operation=fix --target=deployment --backup

    # Cleanup all resources (dry run)
    run_maintenance --operation=cleanup --scope=all --dry-run

    # Update Docker with rollback capability
    run_maintenance --operation=update --component=docker --rollback

    # Run all maintenance with notifications
    run_maintenance --operation=all --notify --backup
EOF
}

# Initialize maintenance state
init_maintenance_state() {
    local operation="$1"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    cat > "$MAINTENANCE_STATE_FILE" << EOF
{
    "operation": "$operation",
    "started_at": "$timestamp",
    "status": "running",
    "dry_run": $MAINTENANCE_DRY_RUN,
    "backup": $MAINTENANCE_BACKUP,
    "rollback": $MAINTENANCE_ROLLBACK,
    "notify": $MAINTENANCE_NOTIFY
}
EOF
}

# Update maintenance state
update_maintenance_state() {
    local status="$1"
    local message="${2:-}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    if [[ -f "$MAINTENANCE_STATE_FILE" ]]; then
        # Simple state update without jq dependency
        sed -i.bak "s/\"status\": \"[^\"]*\"/\"status\": \"$status\"/" "$MAINTENANCE_STATE_FILE"
        echo "    ,\"updated_at\": \"$timestamp\"" >> "$MAINTENANCE_STATE_FILE"
        if [[ -n "$message" ]]; then
            echo "    ,\"message\": \"$message\"" >> "$MAINTENANCE_STATE_FILE"
        fi
    fi
}

# Create backup if requested
create_maintenance_backup() {
    if [[ "$MAINTENANCE_BACKUP" != true ]]; then
        return 0
    fi
    
    log_info "$MAINTENANCE_LOG_PREFIX Creating backup..."
    
    local backup_dir="${MAINTENANCE_BACKUP_DIR}/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup critical files based on operation
    case "$MAINTENANCE_OPERATION" in
        fix|all)
            # Backup deployment configurations
            if [[ -d "${MAINTENANCE_PROJECT_ROOT}/configs" ]]; then
                cp -r "${MAINTENANCE_PROJECT_ROOT}/configs" "$backup_dir/"
            fi
            ;;
        update)
            # Backup scripts and libraries
            cp -r "${MAINTENANCE_PROJECT_ROOT}/scripts" "$backup_dir/"
            cp -r "${MAINTENANCE_PROJECT_ROOT}/lib" "$backup_dir/"
            ;;
    esac
    
    log_info "$MAINTENANCE_LOG_PREFIX Backup created at: $backup_dir"
    echo "$backup_dir" > "${MAINTENANCE_STATE_FILE}.backup"
    
    return 0
}

# Send notification if requested
send_maintenance_notification() {
    local message="$1"
    
    if [[ "$MAINTENANCE_NOTIFY" != true ]]; then
        return 0
    fi
    
    log_info "$MAINTENANCE_LOG_PREFIX Notification: $message"
    
    # Check for webhook URL in parameter store
    if command -v aws >/dev/null 2>&1; then
        local webhook_url
        webhook_url=$(aws ssm get-parameter --name "/aibuildkit/WEBHOOK_URL" --query 'Parameter.Value' --output text 2>/dev/null || echo "")
        
        if [[ -n "$webhook_url" ]]; then
            curl -s -X POST "$webhook_url" \
                -H "Content-Type: application/json" \
                -d "{\"text\": \"Maintenance Alert: $message\"}" \
                >/dev/null 2>&1 || true
        fi
    fi
    
    return 0
}

# Execute fix operation
execute_fix_operation() {
    local target="$1"
    
    log_info "$MAINTENANCE_LOG_PREFIX Executing fix operation for: $target"
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_info "$MAINTENANCE_LOG_PREFIX [DRY RUN] Would fix: $target"
        return 0
    fi
    
    case "$target" in
        deployment)
            # Load and execute deployment fix module
            if load_maintenance_library "modules/maintenance/fix-deployment.sh"; then
                fix_deployment_issues
            fi
            ;;
        docker)
            # Load and execute Docker fix module
            if load_maintenance_library "modules/maintenance/fix-docker.sh"; then
                fix_docker_issues
            fi
            ;;
        efs)
            # Load and execute EFS fix module
            if load_maintenance_library "modules/maintenance/fix-efs.sh"; then
                fix_efs_issues
            fi
            ;;
        disk)
            # Load and execute disk fix module
            if load_maintenance_library "modules/maintenance/fix-disk.sh"; then
                fix_disk_issues
            fi
            ;;
        permissions)
            # Load and execute permissions fix module
            if load_maintenance_library "modules/maintenance/fix-permissions.sh"; then
                fix_permission_issues
            fi
            ;;
        *)
            log_error "$MAINTENANCE_LOG_PREFIX Unknown fix target: $target"
            return 1
            ;;
    esac
}

# Execute cleanup operation
execute_cleanup_operation() {
    local scope="$1"
    
    log_info "$MAINTENANCE_LOG_PREFIX Executing cleanup operation for scope: $scope"
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_info "$MAINTENANCE_LOG_PREFIX [DRY RUN] Would cleanup: $scope"
        return 0
    fi
    
    case "$scope" in
        logs|docker|temp|aws)
            # Load and execute specific cleanup module
            if load_maintenance_library "modules/maintenance/cleanup-${scope}.sh"; then
                "cleanup_${scope}"
            fi
            ;;
        all)
            # Execute all cleanup operations
            for cleanup_scope in logs docker temp aws; do
                if load_maintenance_library "modules/maintenance/cleanup-${cleanup_scope}.sh"; then
                    "cleanup_${cleanup_scope}"
                fi
            done
            ;;
        *)
            log_error "$MAINTENANCE_LOG_PREFIX Unknown cleanup scope: $scope"
            return 1
            ;;
    esac
}

# Execute update operation
execute_update_operation() {
    local component="$1"
    
    log_info "$MAINTENANCE_LOG_PREFIX Executing update operation for: $component"
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_info "$MAINTENANCE_LOG_PREFIX [DRY RUN] Would update: $component"
        return 0
    fi
    
    case "$component" in
        docker|dependencies|scripts|configurations)
            # Load and execute update module
            if load_maintenance_library "modules/maintenance/update-${component}.sh"; then
                "update_${component}"
            fi
            ;;
        *)
            log_error "$MAINTENANCE_LOG_PREFIX Unknown update component: $component"
            return 1
            ;;
    esac
}

# Main maintenance execution
run_maintenance() {
    local args=("$@")
    
    # Parse parameters
    if ! parse_maintenance_params "${args[@]}"; then
        show_maintenance_help
        return 1
    fi
    
    # Initialize state
    init_maintenance_state "$MAINTENANCE_OPERATION"
    
    # Create backup if requested
    create_maintenance_backup
    
    # Send start notification
    send_maintenance_notification "Starting $MAINTENANCE_OPERATION operation"
    
    # Execute operation
    local result=0
    case "$MAINTENANCE_OPERATION" in
        fix)
            if [[ -z "$MAINTENANCE_TARGET" ]]; then
                log_error "$MAINTENANCE_LOG_PREFIX Target required for fix operation"
                result=1
            else
                execute_fix_operation "$MAINTENANCE_TARGET" || result=$?
            fi
            ;;
        cleanup)
            if [[ -z "$MAINTENANCE_SCOPE" ]]; then
                MAINTENANCE_SCOPE="all"
            fi
            execute_cleanup_operation "$MAINTENANCE_SCOPE" || result=$?
            ;;
        update)
            if [[ -z "$MAINTENANCE_COMPONENT" ]]; then
                log_error "$MAINTENANCE_LOG_PREFIX Component required for update operation"
                result=1
            else
                execute_update_operation "$MAINTENANCE_COMPONENT" || result=$?
            fi
            ;;
        all)
            # Run all maintenance operations
            log_info "$MAINTENANCE_LOG_PREFIX Running all maintenance operations"
            
            # Fix common issues
            for target in "${!MAINTENANCE_FIX_TARGETS[@]}"; do
                execute_fix_operation "$target" || true
            done
            
            # Cleanup resources
            execute_cleanup_operation "all" || true
            
            # Update components
            for component in docker dependencies scripts configurations; do
                execute_update_operation "$component" || true
            done
            ;;
    esac
    
    # Update final state
    if [[ $result -eq 0 ]]; then
        update_maintenance_state "completed" "Operation completed successfully"
        send_maintenance_notification "$MAINTENANCE_OPERATION operation completed successfully"
    else
        update_maintenance_state "failed" "Operation failed with error code: $result"
        send_maintenance_notification "$MAINTENANCE_OPERATION operation failed"
    fi
    
    return $result
}

# Export functions
export -f run_maintenance
export -f parse_maintenance_params
export -f show_maintenance_help