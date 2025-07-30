#!/usr/bin/env bash
# =============================================================================
# Resource Cleanup Module
# Comprehensive resource cleanup and management
# =============================================================================

# Prevent multiple sourcing
[ -n "${_CLEANUP_RESOURCES_SH_LOADED:-}" ] && return 0
_CLEANUP_RESOURCES_SH_LOADED=1

# =============================================================================
# CLEANUP CONFIGURATION
# =============================================================================

# Cleanup modes
CLEANUP_MODE_AUTO="auto"
CLEANUP_MODE_MANUAL="manual"
CLEANUP_MODE_EMERGENCY="emergency"
CLEANUP_MODE_DRY_RUN="dry_run"

# Resource types and their cleanup order
declare -A RESOURCE_CLEANUP_ORDER=(
    ["cloudfront"]=1
    ["alb"]=2
    ["efs"]=3
    ["compute"]=4
    ["security"]=5
    ["vpc"]=6
)

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

# Main cleanup orchestrator
cleanup_resources() {
    local stack_name="$1"
    local cleanup_mode="${2:-$CLEANUP_MODE_AUTO}"
    local force="${3:-false}"
    
    log_info "Starting resource cleanup for stack: $stack_name (mode: $cleanup_mode)" "CLEANUP"
    
    # Initialize cleanup
    if ! initialize_cleanup "$stack_name" "$cleanup_mode"; then
        log_error "Failed to initialize cleanup" "CLEANUP"
        return 1
    fi
    
    # Execute cleanup based on mode
    case "$cleanup_mode" in
        "$CLEANUP_MODE_AUTO")
            execute_automatic_cleanup "$stack_name" "$force"
            ;;
        "$CLEANUP_MODE_MANUAL")
            execute_manual_cleanup "$stack_name" "$force"
            ;;
        "$CLEANUP_MODE_EMERGENCY")
            execute_emergency_cleanup "$stack_name"
            ;;
        "$CLEANUP_MODE_DRY_RUN")
            execute_dry_run_cleanup "$stack_name"
            ;;
        *)
            log_error "Unknown cleanup mode: $cleanup_mode" "CLEANUP"
            return 1
            ;;
    esac
    
    # Finalize cleanup
    finalize_cleanup "$stack_name"
    
    log_info "Resource cleanup completed for stack: $stack_name" "CLEANUP"
}

# Initialize cleanup
initialize_cleanup() {
    local stack_name="$1"
    local cleanup_mode="$2"
    
    log_info "Initializing cleanup for stack: $stack_name" "CLEANUP"
    
    # Create cleanup state
    create_cleanup_state "$stack_name" "$cleanup_mode"
    
    # Load resource inventory
    if ! load_resource_inventory "$stack_name"; then
        log_error "Failed to load resource inventory" "CLEANUP"
        return 1
    fi
    
    # Validate cleanup prerequisites
    if ! validate_cleanup_prerequisites "$stack_name"; then
        log_error "Cleanup prerequisites not met" "CLEANUP"
        return 1
    fi
    
    log_info "Cleanup initialization completed" "CLEANUP"
    return 0
}

# Execute automatic cleanup
execute_automatic_cleanup() {
    local stack_name="$1"
    local force="$2"
    
    log_info "Executing automatic cleanup for stack: $stack_name" "CLEANUP"
    
    # Get resources in cleanup order
    local resources
    resources=$(get_resources_in_cleanup_order "$stack_name")
    
    # Cleanup each resource type
    local cleanup_success=true
    while IFS= read -r resource_type; do
        if [[ -n "$resource_type" ]]; then
            log_info "Cleaning up resource type: $resource_type" "CLEANUP"
            
            if ! cleanup_resource_type "$stack_name" "$resource_type" "$force"; then
                log_error "Failed to cleanup resource type: $resource_type" "CLEANUP"
                cleanup_success=false
                
                # Continue with other resources unless force is false
                if [[ "$force" != "true" ]]; then
                    break
                fi
            fi
        fi
    done <<< "$resources"
    
    if [[ "$cleanup_success" == "true" ]]; then
        log_info "Automatic cleanup completed successfully" "CLEANUP"
        return 0
    else
        log_error "Automatic cleanup completed with errors" "CLEANUP"
        return 1
    fi
}

# Execute manual cleanup
execute_manual_cleanup() {
    local stack_name="$1"
    local force="$2"
    
    log_info "Executing manual cleanup for stack: $stack_name" "CLEANUP"
    
    # Show available resources
    show_available_resources "$stack_name"
    
    # Prompt for confirmation
    if [[ "$force" != "true" ]]; then
        echo ""
        echo "Available resources for cleanup:"
        list_resources_for_cleanup "$stack_name"
        echo ""
        read -p "Continue with cleanup? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "Cleanup cancelled by user" "CLEANUP"
            return 0
        fi
    fi
    
    # Execute automatic cleanup
    execute_automatic_cleanup "$stack_name" "$force"
}

# Execute emergency cleanup
execute_emergency_cleanup() {
    local stack_name="$1"
    
    log_warn "Executing emergency cleanup for stack: $stack_name" "CLEANUP"
    
    # Force cleanup all resources without dependency checks
    local resources
    resources=$(get_all_resources "$stack_name")
    
    local cleanup_success=true
    while IFS= read -r resource; do
        if [[ -n "$resource" ]]; then
            local resource_id
            resource_id=$(echo "$resource" | cut -d'|' -f1)
            local resource_type
            resource_type=$(echo "$resource" | cut -d'|' -f2)
            
            log_warn "Emergency cleanup of resource: $resource_id ($resource_type)" "CLEANUP"
            
            if ! force_delete_resource "$resource_id" "$resource_type"; then
                log_error "Failed to force delete resource: $resource_id" "CLEANUP"
                cleanup_success=false
            fi
        fi
    done <<< "$resources"
    
    if [[ "$cleanup_success" == "true" ]]; then
        log_info "Emergency cleanup completed" "CLEANUP"
        return 0
    else
        log_error "Emergency cleanup completed with errors" "CLEANUP"
        return 1
    fi
}

# Execute dry run cleanup
execute_dry_run_cleanup() {
    local stack_name="$1"
    
    log_info "Executing dry run cleanup for stack: $stack_name" "CLEANUP"
    
    # Show what would be cleaned up
    echo ""
    echo "DRY RUN - Resources that would be cleaned up:"
    echo "============================================="
    
    local resources
    resources=$(get_resources_in_cleanup_order "$stack_name")
    
    while IFS= read -r resource_type; do
        if [[ -n "$resource_type" ]]; then
            echo ""
            echo "Resource Type: $resource_type"
            echo "----------------------------"
            list_resources_by_type "$stack_name" "$resource_type"
        fi
    done <<< "$resources"
    
    echo ""
    echo "DRY RUN completed - no resources were actually deleted"
    log_info "Dry run cleanup completed" "CLEANUP"
}