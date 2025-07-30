#!/bin/bash
#
# Enhanced Maintenance Suite Module
# Centralized maintenance operations with comprehensive functionality
# Consolidates all maintenance functions from various scripts
#
# Usage:
#   source maintenance-suite-enhanced.sh
#   run_maintenance --operation=fix --target=deployment --backup --dry-run
#   run_maintenance --operation=cleanup --scope=all --notify
#   run_maintenance --operation=update --component=docker --rollback
#   run_maintenance --operation=health --service=all --verbose
#   run_maintenance --operation=backup --action=create --compress
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
load_maintenance_library "modules/errors/error_types.sh" || exit 1
load_maintenance_library "error-handling.sh" || exit 1
load_maintenance_library "modules/core/variables.sh" || exit 1
load_maintenance_library "aws-deployment-common.sh" || exit 1

# Constants
declare -r MAINTENANCE_VERSION="2.0.0"
declare -r MAINTENANCE_LOG_PREFIX="[MAINTENANCE]"
declare -r MAINTENANCE_BACKUP_DIR="${MAINTENANCE_PROJECT_ROOT}/backup/maintenance"
declare -r MAINTENANCE_STATE_FILE="${MAINTENANCE_PROJECT_ROOT}/.maintenance-state"
declare -r MAINTENANCE_LOG_FILE="/var/log/GeuseMaker-maintenance.log"

# Supported operations
declare -a MAINTENANCE_OPERATIONS=("fix" "cleanup" "update" "health" "backup" "validate" "optimize" "all")
declare -a MAINTENANCE_SAFETY_FLAGS=("--backup" "--rollback" "--notify" "--dry-run" "--force" "--verbose")

# Operation targets
declare -A MAINTENANCE_FIX_TARGETS=(
    ["deployment"]="Fix deployment issues (disk, EFS, parameter store)"
    ["docker"]="Fix Docker configuration and space issues"
    ["efs"]="Fix EFS mount issues and create if missing"
    ["disk"]="Fix disk space issues and expand volumes"
    ["permissions"]="Fix file and directory permissions"
    ["parameter-store"]="Fix AWS Parameter Store integration"
    ["network"]="Fix network configuration issues"
    ["services"]="Fix service startup and configuration issues"
)

declare -A MAINTENANCE_CLEANUP_TARGETS=(
    ["logs"]="Clean up log files"
    ["docker"]="Clean Docker resources (containers, images, volumes)"
    ["temp"]="Clean temporary files"
    ["aws"]="Clean AWS resources (instances, EFS, IAM, etc)"
    ["backups"]="Clean old backup files"
    ["codebase"]="Clean redundant scripts and backup files"
    ["all"]="Clean all resources"
)

declare -A MAINTENANCE_UPDATE_TARGETS=(
    ["docker"]="Update Docker images to latest/configured versions"
    ["dependencies"]="Update system dependencies"
    ["scripts"]="Update deployment scripts"
    ["configurations"]="Update configurations"
    ["parameters"]="Update AWS Parameter Store values"
    ["certificates"]="Update SSL certificates"
)

declare -A MAINTENANCE_HEALTH_SERVICES=(
    ["postgres"]="PostgreSQL database health"
    ["n8n"]="n8n workflow engine health"
    ["ollama"]="Ollama LLM service health"
    ["qdrant"]="Qdrant vector database health"
    ["crawl4ai"]="Crawl4AI service health"
    ["gpu"]="GPU availability and usage"
    ["system"]="System resources (CPU, memory, disk)"
    ["all"]="All services and system health"
)

declare -A MAINTENANCE_BACKUP_ACTIONS=(
    ["create"]="Create new backup"
    ["restore"]="Restore from backup"
    ["list"]="List available backups"
    ["verify"]="Verify backup integrity"
    ["cleanup"]="Clean old backups"
)

# Global state
declare -g MAINTENANCE_OPERATION=""
declare -g MAINTENANCE_TARGET=""
declare -g MAINTENANCE_SCOPE=""
declare -g MAINTENANCE_COMPONENT=""
declare -g MAINTENANCE_SERVICE=""
declare -g MAINTENANCE_ACTION=""
declare -g MAINTENANCE_DRY_RUN=false
declare -g MAINTENANCE_BACKUP=false
declare -g MAINTENANCE_ROLLBACK=false
declare -g MAINTENANCE_NOTIFY=false
declare -g MAINTENANCE_VERBOSE=false
declare -g MAINTENANCE_FORCE=false
declare -g MAINTENANCE_COMPRESS=false
declare -g MAINTENANCE_STACK_NAME=""
declare -g MAINTENANCE_AWS_REGION="${AWS_REGION:-us-east-1}"

# Resource counters
declare -g RESOURCES_PROCESSED=0
declare -g RESOURCES_FIXED=0
declare -g RESOURCES_FAILED=0
declare -g RESOURCES_SKIPPED=0

# Load operation modules
load_maintenance_operations() {
    local modules=(
        "maintenance-utilities.sh"
        "maintenance-safety-operations.sh"
        "maintenance-notifications.sh"
        "maintenance-fix-operations.sh"
        "maintenance-cleanup-operations.sh"
        "maintenance-update-operations.sh"
        "maintenance-health-operations.sh"
        "maintenance-backup-operations.sh"
        "maintenance-optimization-operations.sh"
    )
    
    for module in "${modules[@]}"; do
        if [[ -f "${MAINTENANCE_SCRIPT_DIR}/${module}" ]]; then
            # shellcheck disable=SC1090
            source "${MAINTENANCE_SCRIPT_DIR}/${module}" || {
                log_warning "$MAINTENANCE_LOG_PREFIX Failed to load module: $module"
            }
        fi
    done
}

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
            --service=*)
                MAINTENANCE_SERVICE="${param#*=}"
                ;;
            --action=*)
                MAINTENANCE_ACTION="${param#*=}"
                ;;
            --stack=*|--stack-name=*)
                MAINTENANCE_STACK_NAME="${param#*=}"
                ;;
            --region=*)
                MAINTENANCE_AWS_REGION="${param#*=}"
                export AWS_REGION="$MAINTENANCE_AWS_REGION"
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
            --force|-f)
                MAINTENANCE_FORCE=true
                ;;
            --compress)
                MAINTENANCE_COMPRESS=true
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
        log_error "$MAINTENANCE_LOG_PREFIX Operation is required (--operation=fix|cleanup|update|health|backup|validate|optimize|all)"
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
    
    # Set defaults based on operation
    case "$MAINTENANCE_OPERATION" in
        fix)
            [[ -z "$MAINTENANCE_TARGET" ]] && MAINTENANCE_TARGET="deployment"
            ;;
        cleanup)
            [[ -z "$MAINTENANCE_SCOPE" ]] && MAINTENANCE_SCOPE="all"
            ;;
        update)
            [[ -z "$MAINTENANCE_COMPONENT" ]] && MAINTENANCE_COMPONENT="docker"
            ;;
        health)
            [[ -z "$MAINTENANCE_SERVICE" ]] && MAINTENANCE_SERVICE="all"
            ;;
        backup)
            [[ -z "$MAINTENANCE_ACTION" ]] && MAINTENANCE_ACTION="create"
            ;;
    esac
    
    return 0
}

# Show comprehensive help
show_maintenance_help() {
    cat << EOF
Enhanced Maintenance Suite v${MAINTENANCE_VERSION}

Usage:
    run_maintenance [OPTIONS]

Operations:
    --operation=fix        Fix common issues and problems
    --operation=cleanup    Clean up resources and files
    --operation=update     Update components and configurations
    --operation=health     Check service and system health
    --operation=backup     Backup and restore operations
    --operation=validate   Validate configurations and scripts
    --operation=optimize   Optimize system performance
    --operation=all        Run all maintenance tasks

Fix Targets (--operation=fix):
$(for target in "${!MAINTENANCE_FIX_TARGETS[@]}"; do
    printf "    --target=%-20s %s\n" "$target" "${MAINTENANCE_FIX_TARGETS[$target]}"
done | sort)

Cleanup Scopes (--operation=cleanup):
$(for scope in "${!MAINTENANCE_CLEANUP_TARGETS[@]}"; do
    printf "    --scope=%-20s %s\n" "$scope" "${MAINTENANCE_CLEANUP_TARGETS[$scope]}"
done | sort)

Update Components (--operation=update):
$(for component in "${!MAINTENANCE_UPDATE_TARGETS[@]}"; do
    printf "    --component=%-20s %s\n" "$component" "${MAINTENANCE_UPDATE_TARGETS[$component]}"
done | sort)

Health Services (--operation=health):
$(for service in "${!MAINTENANCE_HEALTH_SERVICES[@]}"; do
    printf "    --service=%-20s %s\n" "$service" "${MAINTENANCE_HEALTH_SERVICES[$service]}"
done | sort)

Backup Actions (--operation=backup):
$(for action in "${!MAINTENANCE_BACKUP_ACTIONS[@]}"; do
    printf "    --action=%-20s %s\n" "$action" "${MAINTENANCE_BACKUP_ACTIONS[$action]}"
done | sort)

Additional Options:
    --stack-name=NAME     Stack name for AWS operations
    --region=REGION       AWS region (default: us-east-1)
    --backup              Create backup before operations
    --rollback            Enable rollback capability
    --notify              Send notifications
    --dry-run             Show what would be done
    --force, -f           Force operations without confirmation
    --verbose, -v         Verbose output
    --compress            Use compression for backups
    --help, -h            Show this help

Examples:
    # Fix all deployment issues with backup
    run_maintenance --operation=fix --target=deployment --backup --stack-name=prod

    # Cleanup all resources (dry run)
    run_maintenance --operation=cleanup --scope=all --dry-run

    # Update Docker images with rollback capability
    run_maintenance --operation=update --component=docker --rollback

    # Check all services health
    run_maintenance --operation=health --service=all --verbose

    # Create compressed backup
    run_maintenance --operation=backup --action=create --compress

    # Run all maintenance with notifications
    run_maintenance --operation=all --notify --backup

Environment Variables:
    AWS_REGION            Default AWS region
    MAINTENANCE_LOG_FILE  Log file location (default: /var/log/GeuseMaker-maintenance.log)
    WEBHOOK_URL           Webhook URL for notifications
EOF
}

# Initialize maintenance state
init_maintenance_state() {
    local operation="$1"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    mkdir -p "$(dirname "$MAINTENANCE_STATE_FILE")"
    
    cat > "$MAINTENANCE_STATE_FILE" << EOF
{
    "operation": "$operation",
    "started_at": "$timestamp",
    "status": "running",
    "dry_run": $MAINTENANCE_DRY_RUN,
    "backup": $MAINTENANCE_BACKUP,
    "rollback": $MAINTENANCE_ROLLBACK,
    "notify": $MAINTENANCE_NOTIFY,
    "stack_name": "$MAINTENANCE_STACK_NAME",
    "region": "$MAINTENANCE_AWS_REGION",
    "counters": {
        "processed": 0,
        "fixed": 0,
        "failed": 0,
        "skipped": 0
    }
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
        # Update state with counters
        local temp_file="${MAINTENANCE_STATE_FILE}.tmp"
        jq --arg status "$status" \
           --arg timestamp "$timestamp" \
           --arg message "$message" \
           --argjson processed "$RESOURCES_PROCESSED" \
           --argjson fixed "$RESOURCES_FIXED" \
           --argjson failed "$RESOURCES_FAILED" \
           --argjson skipped "$RESOURCES_SKIPPED" \
           '.status = $status | 
            .updated_at = $timestamp | 
            .message = $message |
            .counters.processed = $processed |
            .counters.fixed = $fixed |
            .counters.failed = $failed |
            .counters.skipped = $skipped' \
           "$MAINTENANCE_STATE_FILE" > "$temp_file" && mv "$temp_file" "$MAINTENANCE_STATE_FILE"
    fi
}

# Increment resource counter
increment_counter() {
    local counter_type="$1"
    case $counter_type in
        "processed") ((RESOURCES_PROCESSED++)) ;;
        "fixed") ((RESOURCES_FIXED++)) ;;
        "failed") ((RESOURCES_FAILED++)) ;;
        "skipped") ((RESOURCES_SKIPPED++)) ;;
    esac
    
    # Update state file with new counters
    if [[ -f "$MAINTENANCE_STATE_FILE" ]]; then
        update_maintenance_state "running" "Processing: $RESOURCES_PROCESSED, Fixed: $RESOURCES_FIXED, Failed: $RESOURCES_FAILED, Skipped: $RESOURCES_SKIPPED"
    fi
}

# Execute fix operation
execute_fix_operation() {
    local target="$1"
    
    log_info "$MAINTENANCE_LOG_PREFIX Executing fix operation for: $target"
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        log_info "$MAINTENANCE_LOG_PREFIX [DRY RUN] Would fix: $target"
        return 0
    fi
    
    # Load fix operations module if available
    if declare -f "fix_${target//-/_}_issues" >/dev/null 2>&1; then
        "fix_${target//-/_}_issues"
    else
        log_error "$MAINTENANCE_LOG_PREFIX Fix function not found for target: $target"
        return 1
    fi
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
        all)
            # Execute all cleanup operations
            for cleanup_scope in logs docker temp aws backups codebase; do
                if declare -f "cleanup_${cleanup_scope}" >/dev/null 2>&1; then
                    "cleanup_${cleanup_scope}"
                fi
            done
            ;;
        *)
            # Execute specific cleanup
            if declare -f "cleanup_${scope}" >/dev/null 2>&1; then
                "cleanup_${scope}"
            else
                log_error "$MAINTENANCE_LOG_PREFIX Cleanup function not found for scope: $scope"
                return 1
            fi
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
    
    # Load update function
    if declare -f "update_${component//-/_}" >/dev/null 2>&1; then
        "update_${component//-/_}"
    else
        log_error "$MAINTENANCE_LOG_PREFIX Update function not found for component: $component"
        return 1
    fi
}

# Execute health check operation
execute_health_operation() {
    local service="$1"
    
    log_info "$MAINTENANCE_LOG_PREFIX Executing health check for: $service"
    
    case "$service" in
        all)
            # Check all services
            for health_service in postgres n8n ollama qdrant crawl4ai gpu system; do
                if declare -f "check_${health_service}" >/dev/null 2>&1; then
                    "check_${health_service}"
                fi
            done
            ;;
        *)
            # Check specific service
            if declare -f "check_${service}" >/dev/null 2>&1; then
                "check_${service}"
            else
                log_error "$MAINTENANCE_LOG_PREFIX Health check function not found for service: $service"
                return 1
            fi
            ;;
    esac
}

# Execute backup operation
execute_backup_operation() {
    local action="$1"
    
    log_info "$MAINTENANCE_LOG_PREFIX Executing backup operation: $action"
    
    if declare -f "backup_${action}" >/dev/null 2>&1; then
        "backup_${action}"
    else
        log_error "$MAINTENANCE_LOG_PREFIX Backup function not found for action: $action"
        return 1
    fi
}

# Execute validation operation
execute_validation_operation() {
    log_info "$MAINTENANCE_LOG_PREFIX Executing validation checks..."
    
    local validation_passed=true
    
    # Validate scripts
    if declare -f "validate_scripts" >/dev/null 2>&1; then
        validate_scripts || validation_passed=false
    fi
    
    # Validate configurations
    if declare -f "validate_configurations" >/dev/null 2>&1; then
        validate_configurations || validation_passed=false
    fi
    
    # Validate AWS resources
    if declare -f "validate_aws_resources" >/dev/null 2>&1; then
        validate_aws_resources || validation_passed=false
    fi
    
    if [[ "$validation_passed" == true ]]; then
        log_success "$MAINTENANCE_LOG_PREFIX All validations passed"
        return 0
    else
        log_error "$MAINTENANCE_LOG_PREFIX Some validations failed"
        return 1
    fi
}

# Execute optimization operation
execute_optimization_operation() {
    log_info "$MAINTENANCE_LOG_PREFIX Executing optimization tasks..."
    
    # Optimize Docker
    if declare -f "optimize_docker" >/dev/null 2>&1; then
        optimize_docker
    fi
    
    # Optimize system resources
    if declare -f "optimize_system_resources" >/dev/null 2>&1; then
        optimize_system_resources
    fi
    
    # Optimize AWS resources
    if declare -f "optimize_aws_resources" >/dev/null 2>&1; then
        optimize_aws_resources
    fi
}

# Print comprehensive summary
print_summary() {
    echo ""
    echo "📊 MAINTENANCE SUMMARY"
    echo "====================="
    echo "Operation: $MAINTENANCE_OPERATION"
    [[ -n "$MAINTENANCE_TARGET" ]] && echo "Target: $MAINTENANCE_TARGET"
    [[ -n "$MAINTENANCE_SCOPE" ]] && echo "Scope: $MAINTENANCE_SCOPE"
    [[ -n "$MAINTENANCE_COMPONENT" ]] && echo "Component: $MAINTENANCE_COMPONENT"
    [[ -n "$MAINTENANCE_SERVICE" ]] && echo "Service: $MAINTENANCE_SERVICE"
    [[ -n "$MAINTENANCE_ACTION" ]] && echo "Action: $MAINTENANCE_ACTION"
    [[ -n "$MAINTENANCE_STACK_NAME" ]] && echo "Stack: $MAINTENANCE_STACK_NAME"
    echo "Region: $MAINTENANCE_AWS_REGION"
    echo "Dry Run: $MAINTENANCE_DRY_RUN"
    echo ""
    echo "Resources processed:"
    echo "  📋 Total Processed: $RESOURCES_PROCESSED"
    echo "  ✅ Fixed/Completed: $RESOURCES_FIXED"
    echo "  ❌ Failed: $RESOURCES_FAILED"
    echo "  ⏭️  Skipped: $RESOURCES_SKIPPED"
    echo ""
    
    if [ $RESOURCES_FAILED -eq 0 ]; then
        log_success "Maintenance completed successfully!"
    else
        log_warning "Maintenance completed with $RESOURCES_FAILED failures"
    fi
}

# Main maintenance execution
run_maintenance() {
    local args=("$@")
    local start_time=$(date +%s)
    
    # Set up trap for cleanup on exit
    trap 'cleanup_on_exit' EXIT INT TERM
    
    # Load operation modules
    load_maintenance_operations
    
    # Parse parameters
    if ! parse_maintenance_params "${args[@]}"; then
        show_maintenance_help
        return 1
    fi
    
    # Initialize state
    init_maintenance_state "$MAINTENANCE_OPERATION"
    
    # Initialize logging
    mkdir -p "$(dirname "$MAINTENANCE_LOG_FILE")"
    echo "[$MAINTENANCE_OPERATION] Starting at $(date)" >> "$MAINTENANCE_LOG_FILE"
    
    # Perform pre-operation safety checks
    local operation_key="${MAINTENANCE_OPERATION}:${MAINTENANCE_TARGET:-${MAINTENANCE_SCOPE:-${MAINTENANCE_COMPONENT:-${MAINTENANCE_SERVICE:-${MAINTENANCE_ACTION:-default}}}}}"
    
    if ! perform_safety_checks "$MAINTENANCE_OPERATION" "$operation_key"; then
        log_error "$MAINTENANCE_LOG_PREFIX Safety checks failed, aborting operation"
        update_maintenance_state "failed" "Safety checks failed"
        notify_operation_complete "$MAINTENANCE_OPERATION" "$operation_key" "failed" "Safety checks prevented operation"
        return 1
    fi
    
    # Send start notification
    notify_operation_start "$MAINTENANCE_OPERATION" "$operation_key"
    
    # Create safety backup if needed
    local backup_tag=""
    if [[ "$MAINTENANCE_BACKUP" == true ]] || is_destructive_operation "$MAINTENANCE_OPERATION" "$operation_key"; then
        log_info "$MAINTENANCE_LOG_PREFIX Creating safety backup..."
        backup_tag=$(create_safety_backup "$MAINTENANCE_OPERATION" "$operation_key")
        
        if [[ -z "$backup_tag" ]] && [[ "$MAINTENANCE_DRY_RUN" != true ]]; then
            log_error "$MAINTENANCE_LOG_PREFIX Failed to create safety backup"
            update_maintenance_state "failed" "Backup creation failed"
            notify_operation_complete "$MAINTENANCE_OPERATION" "$operation_key" "failed" "Backup creation failed"
            return 1
        fi
        
        notify_backup_status "safety" "completed" "$backup_tag"
    fi
    
    # Execute operation
    local result=0
    case "$MAINTENANCE_OPERATION" in
        fix)
            execute_fix_operation "$MAINTENANCE_TARGET" || result=$?
            ;;
        cleanup)
            execute_cleanup_operation "$MAINTENANCE_SCOPE" || result=$?
            ;;
        update)
            execute_update_operation "$MAINTENANCE_COMPONENT" || result=$?
            ;;
        health)
            execute_health_operation "$MAINTENANCE_SERVICE" || result=$?
            ;;
        backup)
            execute_backup_operation "$MAINTENANCE_ACTION" || result=$?
            ;;
        validate)
            execute_validation_operation || result=$?
            ;;
        optimize)
            execute_optimization_operation || result=$?
            ;;
        all)
            # Run all maintenance operations in sequence
            log_info "$MAINTENANCE_LOG_PREFIX Running all maintenance operations"
            
            # 1. Health checks first
            execute_health_operation "all" || true
            
            # 2. Fix common issues
            for target in "${!MAINTENANCE_FIX_TARGETS[@]}"; do
                execute_fix_operation "$target" || true
            done
            
            # 3. Update components
            for component in docker dependencies scripts configurations; do
                execute_update_operation "$component" || true
            done
            
            # 4. Optimize system
            execute_optimization_operation || true
            
            # 5. Cleanup resources
            execute_cleanup_operation "all" || true
            
            # 6. Final validation
            execute_validation_operation || true
            ;;
    esac
    
    # Calculate duration
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    MAINTENANCE_DURATION="${duration}s"
    
    # Handle operation result
    if [[ $result -eq 0 ]]; then
        update_maintenance_state "completed" "Operation completed successfully"
        local status="completed"
    else
        update_maintenance_state "failed" "Operation failed with error code: $result"
        local status="failed"
        
        # Check if rollback is needed
        if [[ "$MAINTENANCE_ROLLBACK" == true ]] && [[ -n "$backup_tag" ]]; then
            log_warning "$MAINTENANCE_LOG_PREFIX Operation failed, initiating rollback..."
            notify_rollback_status "safety" "started" "$backup_tag"
            
            if perform_safety_rollback "$backup_tag"; then
                notify_rollback_status "safety" "completed" "$backup_tag"
                log_success "$MAINTENANCE_LOG_PREFIX Rollback completed successfully"
            else
                notify_rollback_status "safety" "failed" "$backup_tag"
                log_error "$MAINTENANCE_LOG_PREFIX Rollback failed"
                notify_critical_error "Rollback Failed" "Failed to rollback from backup: $backup_tag"
            fi
        fi
    fi
    
    # Send completion notification with summary
    local summary=$(get_operation_summary)
    notify_operation_complete "$MAINTENANCE_OPERATION" "$operation_key" "$status" "$summary"
    
    # Send detailed summary notification
    local counters_json=$(cat << EOF
{
    "processed": $RESOURCES_PROCESSED,
    "fixed": $RESOURCES_FIXED,
    "failed": $RESOURCES_FAILED,
    "skipped": $RESOURCES_SKIPPED
}
EOF
)
    send_operation_summary "$MAINTENANCE_OPERATION" "$operation_key" "$counters_json"
    
    # Print summary
    print_summary
    
    # Log completion
    echo "[$MAINTENANCE_OPERATION] Completed at $(date) with result: $result" >> "$MAINTENANCE_LOG_FILE"
    
    return $result
}

# Create maintenance backup helper
create_maintenance_backup() {
    if [[ "$MAINTENANCE_BACKUP" != true ]]; then
        return 0
    fi
    
    log_info "$MAINTENANCE_LOG_PREFIX Creating backup before maintenance..."
    
    local backup_dir="${MAINTENANCE_BACKUP_DIR}/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Determine what to backup based on operation
    case "$MAINTENANCE_OPERATION" in
        fix|update|all)
            # Backup configurations and scripts
            for dir in configs scripts lib; do
                if [[ -d "${MAINTENANCE_PROJECT_ROOT}/${dir}" ]]; then
                    cp -r "${MAINTENANCE_PROJECT_ROOT}/${dir}" "$backup_dir/" || true
                fi
            done
            ;;
        cleanup)
            # Create list of resources to be cleaned
            echo "Resources to be cleaned:" > "$backup_dir/cleanup-manifest.txt"
            echo "Operation: $MAINTENANCE_OPERATION" >> "$backup_dir/cleanup-manifest.txt"
            echo "Scope: $MAINTENANCE_SCOPE" >> "$backup_dir/cleanup-manifest.txt"
            echo "Timestamp: $(date)" >> "$backup_dir/cleanup-manifest.txt"
            ;;
    esac
    
    log_info "$MAINTENANCE_LOG_PREFIX Backup created at: $backup_dir"
    echo "$backup_dir" > "${MAINTENANCE_STATE_FILE}.backup"
    
    return 0
}

# Send maintenance notification helper
send_maintenance_notification() {
    local message="$1"
    
    if [[ "$MAINTENANCE_NOTIFY" != true ]]; then
        return 0
    fi
    
    log_info "$MAINTENANCE_LOG_PREFIX Notification: $message"
    
    # Check for webhook URL in parameter store or environment
    local webhook_url="${WEBHOOK_URL:-}"
    
    if [[ -z "$webhook_url" ]] && command -v aws >/dev/null 2>&1; then
        webhook_url=$(aws ssm get-parameter \
            --name "/aibuildkit/WEBHOOK_URL" \
            --query 'Parameter.Value' \
            --output text \
            --region "$MAINTENANCE_AWS_REGION" 2>/dev/null || echo "")
    fi
    
    if [[ -n "$webhook_url" ]] && [[ "$webhook_url" != "None" ]]; then
        local payload=$(jq -n \
            --arg text "🔧 GeuseMaker Maintenance: $message" \
            --arg operation "$MAINTENANCE_OPERATION" \
            --arg stack "$MAINTENANCE_STACK_NAME" \
            --arg region "$MAINTENANCE_AWS_REGION" \
            '{
                text: $text,
                fields: {
                    operation: $operation,
                    stack: $stack,
                    region: $region,
                    timestamp: now | strftime("%Y-%m-%d %H:%M:%S UTC")
                }
            }')
        
        curl -s -X POST "$webhook_url" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            >/dev/null 2>&1 || true
    fi
    
    return 0
}

# Cleanup on exit
cleanup_on_exit() {
    local exit_code=$?
    
    # Remove lock file
    cleanup_maintenance_lock
    
    # Clean up old safety backups if needed
    if [[ "$MAINTENANCE_OPERATION" != "backup" ]]; then
        cleanup_old_safety_backups
    fi
    
    # Update state if still running
    if [[ -f "$MAINTENANCE_STATE_FILE" ]]; then
        local current_status=$(jq -r '.status' "$MAINTENANCE_STATE_FILE" 2>/dev/null)
        if [[ "$current_status" == "running" ]]; then
            update_maintenance_state "interrupted" "Operation was interrupted"
        fi
    fi
    
    return $exit_code
}

# Get operation summary
get_operation_summary() {
    local summary=""
    
    summary+="Operation: $MAINTENANCE_OPERATION\n"
    summary+="Duration: ${MAINTENANCE_DURATION:-unknown}\n"
    summary+="Processed: $RESOURCES_PROCESSED\n"
    summary+="Fixed: $RESOURCES_FIXED\n"
    summary+="Failed: $RESOURCES_FAILED\n"
    summary+="Skipped: $RESOURCES_SKIPPED\n"
    
    if [[ "$MAINTENANCE_DRY_RUN" == true ]]; then
        summary+="Mode: DRY RUN\n"
    fi
    
    if [[ -n "${backup_tag:-}" ]]; then
        summary+="Backup: $backup_tag\n"
    fi
    
    echo -e "$summary"
}

# Validate JSON helper
validate_json() {
    local file="$1"
    jq empty "$file" >/dev/null 2>&1
}

# Get directory size helper
get_directory_size() {
    local dir="$1"
    local human_readable="${2:-false}"
    
    if [[ "$human_readable" == true ]]; then
        du -sh "$dir" 2>/dev/null | cut -f1
    else
        du -sb "$dir" 2>/dev/null | cut -f1 || echo "0"
    fi
}

# Export main function
export -f run_maintenance
export -f parse_maintenance_params
export -f show_maintenance_help
export -f increment_counter
export -f create_maintenance_backup
export -f send_maintenance_notification

# Export state variables
export MAINTENANCE_VERSION
export MAINTENANCE_LOG_PREFIX
export MAINTENANCE_BACKUP_DIR
export MAINTENANCE_STATE_FILE
export MAINTENANCE_LOG_FILE