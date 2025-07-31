#!/usr/bin/env bash
# =============================================================================
# Consolidated AWS Resource Cleanup Script
# Unified cleanup for all AWS resources with comprehensive error handling
# =============================================================================

# =============================================================================
# CONFIGURATION AND SETUP
# =============================================================================

set -euo pipefail

# Initialize library loader
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/utils/library-loader.sh" || {
    echo "Error: Failed to load library loader" >&2
    exit 1
}

# Load required libraries
safe_source "error-handling.sh" true "Error handling utilities"
safe_source "aws-deployment-common.sh" true "AWS deployment common functions"
safe_source "aws-config.sh" true "AWS configuration"

# Load required modules through the library system
load_module "config-management"

# Load deployment variable management
safe_source "deployment-variable-management.sh" false "Deployment variable management"

# Initialize variable store and load environment configuration
if declare -f init_variable_store >/dev/null 2>&1; then
    init_variable_store || {
        echo "WARNING: Failed to initialize variable store" >&2
    }
fi

if declare -f load_environment_config >/dev/null 2>&1; then
    load_environment_config || {
        echo "WARNING: Failed to load environment configuration" >&2
    }
fi

# Set AWS region if not already set
export AWS_REGION="${AWS_REGION:-us-east-1}"

# =============================================================================
# ENHANCED LOGGING AND OUTPUT
# =============================================================================

log() { echo -e "\033[0;34m[$(date +'%Y-%m-%d %H:%M:%S')] $1\033[0m" >&2; }
error() { echo -e "\033[0;31m❌ [ERROR] $1\033[0m" >&2; }
success() { echo -e "\033[0;32m✅ [SUCCESS] $1\033[0m" >&2; }
warning() { echo -e "\033[0;33m⚠️  [WARNING] $1\033[0m" >&2; }
info() { echo -e "\033[0;36mℹ️  [INFO] $1\033[0m" >&2; }
step() { echo -e "\033[0;35m🔸 [STEP] $1\033[0m" >&2; }

# =============================================================================
# GLOBAL VARIABLES AND CONFIGURATION
# =============================================================================

# Default values
STACK_NAME=""
CLEANUP_MODE="stack"  # stack, efs, all, specific, codebase
DRY_RUN=false
FORCE=false
VERBOSE=false
QUIET=false

# Resource type flags
CLEANUP_EFS=false
CLEANUP_INSTANCES=false
CLEANUP_IAM=false
CLEANUP_NETWORK=false
CLEANUP_MONITORING=false
CLEANUP_STORAGE=false
CLEANUP_CODEBASE=false

# Resource counters
RESOURCES_DELETED=0
RESOURCES_SKIPPED=0
RESOURCES_FAILED=0

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Safe AWS command execution that doesn't exit on failure
safe_aws() {
    local aws_command="$1"
    local description="$2"
    
    if [ "$VERBOSE" = true ]; then
        log "Executing: $aws_command"
    fi
    
    # Execute AWS command and capture exit code
    local output
    local exit_code
    output=$(eval "$aws_command" 2>&1) || exit_code=$?
    
    if [ ${exit_code:-0} -eq 0 ]; then
        echo "$output"
        return 0
    else
        # Log the error but don't exit
        if [ "$VERBOSE" = true ]; then
            warning "$description failed (exit code: ${exit_code:-0}): $output"
        fi
        return ${exit_code:-1}
    fi
}

# Increment resource counter
increment_counter() {
    local counter_type="$1"
    case $counter_type in
        "deleted") ((RESOURCES_DELETED++)) ;;
        "skipped") ((RESOURCES_SKIPPED++)) ;;
        "failed") ((RESOURCES_FAILED++)) ;;
    esac
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [STACK_NAME]

Consolidated AWS Resource Cleanup Script

OPTIONS:
    -m, --mode MODE           Cleanup mode: stack, efs, failed-deployments, all, specific, codebase (default: stack)
    -r, --region REGION       AWS region (default: us-east-1)
    -d, --dry-run            Show what would be deleted without actually deleting
    -f, --force              Force deletion without confirmation prompts
    -v, --verbose            Verbose output
    -q, --quiet              Suppress non-error output
    -h, --help               Show this help message

RESOURCE TYPE FLAGS (for specific mode):
    --instances              Cleanup EC2 instances and related resources
    --efs                    Cleanup EFS file systems and mount targets
    --iam                    Cleanup IAM roles, policies, and instance profiles
    --network                Cleanup VPC, security groups, load balancers
    --monitoring             Cleanup CloudWatch alarms, logs, and dashboards
    --storage                Cleanup EBS volumes, snapshots, and other storage
    --codebase               Cleanup local codebase files (backups, temp files, etc.)

CLEANUP MODES:
    stack                    Cleanup resources for specific stack (requires STACK_NAME)
    efs                      Cleanup EFS file systems matching pattern (uses STACK_NAME as pattern)
    failed-deployments       Cleanup specific failed deployment EFS file systems (051-efs through 059-efs)
    all                      Cleanup all resources for all stacks
    specific                 Cleanup specific resource types (use with resource flags)
    codebase                 Cleanup local codebase files and redundant scripts
    validate                 Validate cleanup script functionality

EXAMPLES:
    $0 052                    # Cleanup stack named "052"
    $0 --mode efs "test-*"    # Cleanup EFS matching pattern "test-*"
    $0 --mode failed-deployments  # Cleanup failed deployment EFS file systems
    $0 --mode specific --efs --instances  # Cleanup specific resource types
    $0 --force 052            # Force cleanup without confirmation
    $0 --mode codebase        # Cleanup local codebase files and redundant scripts
    $0 --mode validate        # Validate cleanup script functionality
    $0 --dry-run --verbose 052 # Preview cleanup with detailed output

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--mode)
                CLEANUP_MODE="$2"
                shift 2
                ;;
            -r|--region)
                export AWS_REGION="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            --instances)
                CLEANUP_INSTANCES=true
                shift
                ;;
            --efs)
                CLEANUP_EFS=true
                shift
                ;;
            --iam)
                CLEANUP_IAM=true
                shift
                ;;
            --network)
                CLEANUP_NETWORK=true
                shift
                ;;
            --monitoring)
                CLEANUP_MONITORING=true
                shift
                ;;
            --storage)
                CLEANUP_STORAGE=true
                shift
                ;;
            --codebase)
                CLEANUP_CODEBASE=true
                shift
                ;;
            -*)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [ -z "$STACK_NAME" ]; then
                    STACK_NAME="$1"
                else
                    error "Multiple stack names provided. Only one stack name allowed."
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Set default cleanup types based on mode
    if [ "$CLEANUP_MODE" = "stack" ] && [ -n "$STACK_NAME" ]; then
        CLEANUP_INSTANCES=true
        CLEANUP_EFS=true
        CLEANUP_IAM=true
        CLEANUP_NETWORK=true
        CLEANUP_MONITORING=true
        CLEANUP_STORAGE=true
    elif [ "$CLEANUP_MODE" = "all" ]; then
        CLEANUP_INSTANCES=true
        CLEANUP_EFS=true
        CLEANUP_IAM=true
        CLEANUP_NETWORK=true
        CLEANUP_MONITORING=true
        CLEANUP_STORAGE=true
    elif [ "$CLEANUP_MODE" = "codebase" ]; then
        CLEANUP_CODEBASE=true
    fi
}

# Confirm cleanup operation
confirm_cleanup() {
    if [ "$FORCE" = true ]; then
        return 0
    fi
    
    echo ""
    echo "🗑️  CONFIRMATION REQUIRED"
    echo "=========================="
    echo "Stack Name: $STACK_NAME"
    echo "Mode: $CLEANUP_MODE"
    echo "Dry Run: $DRY_RUN"
    echo ""
    echo "Resource types to cleanup:"
    [ "$CLEANUP_INSTANCES" = true ] && echo "  ✅ EC2 Instances and related resources"
    [ "$CLEANUP_EFS" = true ] && echo "  ✅ EFS File Systems and mount targets"
    [ "$CLEANUP_IAM" = true ] && echo "  ✅ IAM Roles, policies, and instance profiles"
    [ "$CLEANUP_NETWORK" = true ] && echo "  ✅ Network resources (VPC, SG, ALB)"
    [ "$CLEANUP_MONITORING" = true ] && echo "  ✅ Monitoring resources (CloudWatch)"
    [ "$CLEANUP_STORAGE" = true ] && echo "  ✅ Storage resources (EBS, snapshots)"
    [ "$CLEANUP_CODEBASE" = true ] && echo "  ✅ Local codebase files"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        echo "This is a DRY RUN - no resources will be deleted."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        info "Cleanup cancelled"
        exit 0
    fi
}

# Print cleanup summary
print_summary() {
    echo ""
    echo "📊 CLEANUP SUMMARY"
    echo "=================="
    echo "Stack Name: $STACK_NAME"
    echo "Mode: $CLEANUP_MODE"
    echo "Dry Run: $DRY_RUN"
    echo ""
    echo "Resources processed:"
    echo "  ✅ Deleted: $RESOURCES_DELETED"
    echo "  ⏭️  Skipped: $RESOURCES_SKIPPED"
    echo "  ❌ Failed: $RESOURCES_FAILED"
    echo ""
    
    if [ $RESOURCES_FAILED -eq 0 ]; then
        success "Cleanup completed successfully!"
    else
        warning "Cleanup completed with $RESOURCES_FAILED failures"
    fi
}

# =============================================================================
# AWS RESOURCE CLEANUP FUNCTIONS
# =============================================================================

# Cleanup EC2 instances
cleanup_ec2_instances() {
    step "Cleaning up EC2 instances..."
    
    if [ -z "$STACK_NAME" ]; then
        info "No stack name provided, skipping instance cleanup"
        return 0
    fi
    
    # Find instances by stack name
    local instance_ids
    instance_ids=$(aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:StackName,Values=$STACK_NAME" "Name=instance-state-name,Values=running,stopped,stopping" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$instance_ids" ]; then
        log "Found instances to cleanup: $instance_ids"
        
        for instance_id in $instance_ids; do
            if [ "$DRY_RUN" = true ]; then
                info "Would terminate instance: $instance_id"
                increment_counter "deleted"
            else
                if aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids "$instance_id" >/dev/null 2>&1; then
                    success "Terminated instance: $instance_id"
                    increment_counter "deleted"
                else
                    error "Failed to terminate instance: $instance_id"
                    increment_counter "failed"
                fi
            fi
        done
    else
        info "No instances found for cleanup"
    fi
    
    # Cleanup spot instance requests
    local spot_request_ids
    spot_request_ids=$(aws ec2 describe-spot-instance-requests \
        --region "$AWS_REGION" \
        --filters "Name=tag:StackName,Values=$STACK_NAME" "Name=state,Values=open,active" \
        --query 'SpotInstanceRequests[].SpotInstanceRequestId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$spot_request_ids" ]; then
        log "Found spot instance requests to cleanup: $spot_request_ids"
        
        for request_id in $spot_request_ids; do
            if [ "$DRY_RUN" = true ]; then
                info "Would cancel spot request: $request_id"
                increment_counter "deleted"
            else
                if aws ec2 cancel-spot-instance-requests --region "$AWS_REGION" --spot-instance-request-ids "$request_id" >/dev/null 2>&1; then
                    success "Cancelled spot request: $request_id"
                    increment_counter "deleted"
                else
                    error "Failed to cancel spot request: $request_id"
                    increment_counter "failed"
                fi
            fi
        done
    else
        info "No spot instance requests found for cleanup"
    fi
}

# Cleanup EFS resources
cleanup_efs_resources() {
    step "Cleaning up EFS resources..."
    
    # Handle different cleanup modes
    case "$CLEANUP_MODE" in
        "efs")
            # Pattern-based EFS cleanup
            if [ -n "$STACK_NAME" ]; then
                cleanup_efs_by_pattern "$STACK_NAME"
            else
                info "No pattern provided for EFS cleanup"
                return 0
            fi
            ;;
        "failed-deployments")
            # Cleanup specific failed deployment EFS file systems
            cleanup_failed_deployment_efs
            ;;
        *)
            # Stack-based EFS cleanup
            if [ -z "$STACK_NAME" ]; then
                info "No stack name provided, skipping EFS cleanup"
                return 0
            fi
            
            # Find EFS file systems by stack name
            local efs_ids
            efs_ids=$(aws efs describe-file-systems \
                --region "$AWS_REGION" \
                --query "FileSystems[?contains(Tags[?Key=='StackName'].Value, '$STACK_NAME')].FileSystemId" \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$efs_ids" ]; then
                log "Found EFS file systems to cleanup: $efs_ids"
                
                for efs_id in $efs_ids; do
                    cleanup_single_efs "$efs_id"
                done
            else
                info "No EFS file systems found for cleanup"
            fi
            ;;
    esac
}

# Cleanup EFS file systems by pattern
cleanup_efs_by_pattern() {
    local pattern="$1"
    step "Cleaning up EFS file systems matching pattern: $pattern"
    
    # Find EFS file systems by name pattern
    local efs_list
    efs_list=$(aws efs describe-file-systems \
        --region "$AWS_REGION" \
        --query "FileSystems[?contains(Name, '$pattern')].{ID:FileSystemId,Name:Name,State:LifeCycleState}" \
        --output table 2>/dev/null || echo "")
    
    if [ -n "$efs_list" ]; then
        log "Found EFS file systems matching pattern '$pattern':"
        echo "$efs_list"
        
        # Get EFS IDs for deletion
        local efs_ids
        efs_ids=$(aws efs describe-file-systems \
            --region "$AWS_REGION" \
            --query "FileSystems[?contains(Name, '$pattern')].FileSystemId" \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$efs_ids" ]; then
            for efs_id in $efs_ids; do
                cleanup_single_efs "$efs_id"
            done
        fi
    else
        info "No EFS file systems found matching pattern: $pattern"
    fi
}

# Cleanup specific failed deployment EFS file systems
cleanup_failed_deployment_efs() {
    step "Cleaning up failed deployment EFS file systems..."
    
    # Specific EFS file systems from failed deployments (051-efs through 059-efs)
    local failed_efs_systems=(
        "fs-0e713d7f70c5c28e5"  # 051-efs
        "fs-016b6b42fe4e1251d"  # 052-efs
        "fs-081412d661c7359b6"  # 053-efs
        "fs-08b9502f5bcb7db98"  # 054-efs
        "fs-043c227f27b0a57c5"  # 055-efs
        "fs-0e50ce2a955e271a1"  # 056-efs
        "fs-09b78c8e0b3439f73"  # 057-efs
        "fs-05e2980141f1c4cf5"  # 058-efs
        "fs-0cb64b1f87cbda05f"  # 059-efs
    )
    
    log "Checking for failed deployment EFS file systems..."
    
    local existing_count=0
    for fs_id in "${failed_efs_systems[@]}"; do
        if check_efs_exists "$fs_id"; then
            log "Found existing EFS file system: $fs_id"
            ((existing_count++))
        fi
    done
    
    if [ "$existing_count" -eq 0 ]; then
        info "No failed deployment EFS file systems found to delete"
        return 0
    fi
    
    log "Found $existing_count failed deployment EFS file system(s) to delete"
    
    # Show current EFS file systems
    if [ "$VERBOSE" = true ]; then
        log "Current EFS file systems:"
        aws efs describe-file-systems \
            --region "$AWS_REGION" \
            --query 'FileSystems[].{ID:FileSystemId,Name:Name,State:LifeCycleState}' \
            --output table
    fi
    
    # Delete each EFS file system
    for fs_id in "${failed_efs_systems[@]}"; do
        if check_efs_exists "$fs_id"; then
            cleanup_single_efs "$fs_id"
        else
            info "Skipping $fs_id - already deleted or does not exist"
            increment_counter "skipped"
        fi
    done
    
    # Show remaining EFS file systems
    if [ "$VERBOSE" = true ]; then
        log "Remaining EFS file systems:"
        aws efs describe-file-systems \
            --region "$AWS_REGION" \
            --query 'FileSystems[].{ID:FileSystemId,Name:Name,State:LifeCycleState}' \
            --output table
    fi
}

# Check if EFS file system exists
check_efs_exists() {
    local fs_id="$1"
    
    if aws efs describe-file-systems \
        --file-system-ids "$fs_id" \
        --region "$AWS_REGION" \
        --query 'FileSystems[0].FileSystemId' \
        --output text 2>/dev/null | grep -q "$fs_id"; then
        return 0
    else
        return 1
    fi
}

# Cleanup single EFS file system
cleanup_single_efs() {
    local efs_id="$1"
    
    if [ "$DRY_RUN" = true ]; then
        info "Would cleanup EFS file system: $efs_id"
        increment_counter "deleted"
        return 0
    fi
    
    # Get mount targets
    local mount_target_ids
    mount_target_ids=$(aws efs describe-mount-targets \
        --region "$AWS_REGION" \
        --file-system-id "$efs_id" \
        --query 'MountTargets[].MountTargetId' \
        --output text 2>/dev/null || echo "")
    
    # Delete mount targets first
    if [ -n "$mount_target_ids" ]; then
        log "Deleting mount targets for EFS $efs_id: $mount_target_ids"
        
        for mount_target_id in $mount_target_ids; do
            if aws efs delete-mount-target --region "$AWS_REGION" --mount-target-id "$mount_target_id" >/dev/null 2>&1; then
                success "Deleted mount target: $mount_target_id"
                increment_counter "deleted"
            else
                error "Failed to delete mount target: $mount_target_id"
                increment_counter "failed"
            fi
            
            # Wait for mount target to be deleted
            log "Waiting for mount target deletion to complete..."
            aws efs describe-mount-targets \
                --region "$AWS_REGION" \
                --file-system-id "$efs_id" \
                --mount-target-ids "$mount_target_id" >/dev/null 2>&1 || true
        done
    fi
    
    # Delete the file system
    if aws efs delete-file-system --region "$AWS_REGION" --file-system-id "$efs_id" >/dev/null 2>&1; then
        success "Deleted EFS file system: $efs_id"
        increment_counter "deleted"
    else
        error "Failed to delete EFS file system: $efs_id"
        increment_counter "failed"
    fi
}

# Cleanup network resources
cleanup_network_resources() {
    step "Cleaning up network resources..."
    
    if [ -z "$STACK_NAME" ]; then
        info "No stack name provided, skipping network cleanup"
        return 0
    fi
    
    # Cleanup security groups
    local security_group_ids
    security_group_ids=$(aws ec2 describe-security-groups \
        --region "$AWS_REGION" \
        --filters "Name=group-name,Values=*$STACK_NAME*" \
        --query 'SecurityGroups[].GroupId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$security_group_ids" ]; then
        log "Found security groups to cleanup: $security_group_ids"
        
        for sg_id in $security_group_ids; do
            if [ "$DRY_RUN" = true ]; then
                info "Would delete security group: $sg_id"
                increment_counter "deleted"
            else
                if aws ec2 delete-security-group --region "$AWS_REGION" --group-id "$sg_id" >/dev/null 2>&1; then
                    success "Deleted security group: $sg_id"
                    increment_counter "deleted"
                else
                    error "Failed to delete security group: $sg_id"
                    increment_counter "failed"
                fi
            fi
        done
    else
        info "No security groups found for cleanup"
    fi
    
    # Cleanup load balancers
    cleanup_load_balancers
    
    # Cleanup CloudFront distributions
    cleanup_cloudfront_distributions
}

# Cleanup load balancers
cleanup_load_balancers() {
    local load_balancer_arns
    load_balancer_arns=$(aws elbv2 describe-load-balancers \
        --region "$AWS_REGION" \
        --query "LoadBalancers[?contains(LoadBalancerName, '$STACK_NAME')].LoadBalancerArn" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$load_balancer_arns" ]; then
        log "Found load balancers to cleanup: $load_balancer_arns"
        
        for lb_arn in $load_balancer_arns; do
            if [ "$DRY_RUN" = true ]; then
                info "Would delete load balancer: $lb_arn"
                increment_counter "deleted"
            else
                if aws elbv2 delete-load-balancer --region "$AWS_REGION" --load-balancer-arn "$lb_arn" >/dev/null 2>&1; then
                    success "Deleted load balancer: $lb_arn"
                    increment_counter "deleted"
                else
                    error "Failed to delete load balancer: $lb_arn"
                    increment_counter "failed"
                fi
            fi
        done
    else
        info "No load balancers found for cleanup"
    fi
}

# Cleanup CloudFront distributions
cleanup_cloudfront_distributions() {
    local distribution_ids
    distribution_ids=$(aws cloudfront list-distributions \
        --query "DistributionList.Items[?contains(Comment, '$STACK_NAME')].Id" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$distribution_ids" ]; then
        log "Found CloudFront distributions to cleanup: $distribution_ids"
        
        for dist_id in $distribution_ids; do
            if [ "$DRY_RUN" = true ]; then
                info "Would delete CloudFront distribution: $dist_id"
                increment_counter "deleted"
            else
                # Disable distribution first
                aws cloudfront get-distribution-config --id "$dist_id" >/dev/null 2>&1 && {
                    aws cloudfront update-distribution --id "$dist_id" --distribution-config file:///tmp/dist-config.json >/dev/null 2>&1 || true
                }
                
                if aws cloudfront delete-distribution --id "$dist_id" --if-match "$(aws cloudfront get-distribution-config --id "$dist_id" --query 'ETag' --output text)" >/dev/null 2>&1; then
                    success "Deleted CloudFront distribution: $dist_id"
                    increment_counter "deleted"
                else
                    error "Failed to delete CloudFront distribution: $dist_id"
                    increment_counter "failed"
                fi
            fi
        done
    else
        info "No CloudFront distributions found for cleanup"
    fi
}

# Cleanup monitoring resources
cleanup_monitoring_resources() {
    step "Cleaning up monitoring resources..."
    
    if [ -z "$STACK_NAME" ]; then
        info "No stack name provided, skipping monitoring cleanup"
        return 0
    fi
    
    # Cleanup CloudWatch alarms
    local alarm_names
    alarm_names=$(aws cloudwatch describe-alarms \
        --region "$AWS_REGION" \
        --query "MetricAlarms[?contains(AlarmName, '$STACK_NAME')].AlarmName" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$alarm_names" ]; then
        log "Found CloudWatch alarms to cleanup: $alarm_names"
        
        for alarm_name in $alarm_names; do
            if [ "$DRY_RUN" = true ]; then
                info "Would delete CloudWatch alarm: $alarm_name"
                increment_counter "deleted"
            else
                if aws cloudwatch delete-alarms --region "$AWS_REGION" --alarm-names "$alarm_name" >/dev/null 2>&1; then
                    success "Deleted CloudWatch alarm: $alarm_name"
                    increment_counter "deleted"
                else
                    error "Failed to delete CloudWatch alarm: $alarm_name"
                    increment_counter "failed"
                fi
            fi
        done
    else
        info "No CloudWatch alarms found for cleanup"
    fi
    
    # Cleanup CloudWatch log groups
    local log_group_names
    log_group_names=$(aws logs describe-log-groups \
        --region "$AWS_REGION" \
        --query "logGroups[?contains(logGroupName, '$STACK_NAME')].logGroupName" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$log_group_names" ]; then
        log "Found CloudWatch log groups to cleanup: $log_group_names"
        
        for log_group_name in $log_group_names; do
            if [ "$DRY_RUN" = true ]; then
                info "Would delete CloudWatch log group: $log_group_name"
                increment_counter "deleted"
            else
                if aws logs delete-log-group --region "$AWS_REGION" --log-group-name "$log_group_name" >/dev/null 2>&1; then
                    success "Deleted CloudWatch log group: $log_group_name"
                    increment_counter "deleted"
                else
                    error "Failed to delete CloudWatch log group: $log_group_name"
                    increment_counter "failed"
                fi
            fi
        done
    else
        info "No CloudWatch log groups found for cleanup"
    fi
}

# Cleanup IAM resources
cleanup_iam_resources() {
    step "Cleaning up IAM resources..."
    
    if [ -z "$STACK_NAME" ]; then
        info "No stack name provided, skipping IAM cleanup"
        return 0
    fi
    
    local role_name="${STACK_NAME}-role"
    local profile_name
    
    # Determine profile name based on stack naming convention
    if [[ "${STACK_NAME}" =~ ^[0-9] ]]; then
        clean_name=$(echo "${STACK_NAME}" | sed 's/[^a-zA-Z0-9]//g')
        profile_name="app-${clean_name}-profile"
    else
        profile_name="${STACK_NAME}-instance-profile"
    fi
    
    # Cleanup instance profile first (remove role from profile)
    if aws iam get-instance-profile --instance-profile-name "$profile_name" >/dev/null 2>&1; then
        log "Found instance profile: $profile_name"
        
        if [ "$DRY_RUN" = true ]; then
            info "Would remove role from instance profile: $profile_name"
            info "Would delete instance profile: $profile_name"
            increment_counter "deleted"
        else
            # Remove role from instance profile
            if aws iam remove-role-from-instance-profile \
                --instance-profile-name "$profile_name" \
                --role-name "$role_name" >/dev/null 2>&1; then
                success "Removed role from instance profile: $profile_name"
            else
                warning "Failed to remove role from instance profile (may not exist): $profile_name"
            fi
            
            # Delete instance profile
            if aws iam delete-instance-profile --instance-profile-name "$profile_name" >/dev/null 2>&1; then
                success "Deleted instance profile: $profile_name"
                increment_counter "deleted"
            else
                error "Failed to delete instance profile: $profile_name"
                increment_counter "failed"
            fi
        fi
    else
        info "No instance profile found: $profile_name"
    fi
    
    # Cleanup IAM role
    if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
        log "Found IAM role: $role_name"
        
        if [ "$DRY_RUN" = true ]; then
            info "Would cleanup IAM role: $role_name"
            increment_counter "deleted"
        else
            # Delete inline policies
            local inline_policies
            inline_policies=$(aws iam list-role-policies --role-name "$role_name" --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
            
            for policy_name in $inline_policies; do
                if [ -n "$policy_name" ] && [ "$policy_name" != "None" ]; then
                    if aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" >/dev/null 2>&1; then
                        success "Deleted inline policy: $policy_name"
                    else
                        warning "Failed to delete inline policy: $policy_name"
                    fi
                fi
            done
            
            # Detach managed policies
            local managed_policies
            managed_policies=$(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
            
            for policy_arn in $managed_policies; do
                if [ -n "$policy_arn" ] && [ "$policy_arn" != "None" ]; then
                    if aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" >/dev/null 2>&1; then
                        success "Detached managed policy: $policy_arn"
                    else
                        warning "Failed to detach managed policy: $policy_arn"
                    fi
                fi
            done
            
            # Delete the role
            if aws iam delete-role --role-name "$role_name" >/dev/null 2>&1; then
                success "Deleted IAM role: $role_name"
                increment_counter "deleted"
            else
                error "Failed to delete IAM role: $role_name"
                increment_counter "failed"
            fi
        fi
    else
        info "No IAM role found: $role_name"
    fi
}

# Cleanup storage resources
cleanup_storage_resources() {
    step "Cleaning up storage resources..."
    
    if [ -z "$STACK_NAME" ]; then
        info "No stack name provided, skipping storage cleanup"
        return 0
    fi
    
    # Cleanup EBS volumes
    local volume_ids
    volume_ids=$(aws ec2 describe-volumes \
        --region "$AWS_REGION" \
        --filters "Name=tag:StackName,Values=$STACK_NAME" "Name=status,Values=available" \
        --query 'Volumes[].VolumeId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$volume_ids" ]; then
        log "Found EBS volumes to cleanup: $volume_ids"
        
        for volume_id in $volume_ids; do
            if [ "$DRY_RUN" = true ]; then
                info "Would delete EBS volume: $volume_id"
                increment_counter "deleted"
            else
                if aws ec2 delete-volume --region "$AWS_REGION" --volume-id "$volume_id" >/dev/null 2>&1; then
                    success "Deleted EBS volume: $volume_id"
                    increment_counter "deleted"
                else
                    error "Failed to delete EBS volume: $volume_id"
                    increment_counter "failed"
                fi
            fi
        done
    else
        info "No EBS volumes found for cleanup"
    fi
    
    # Cleanup snapshots
    local snapshot_ids
    snapshot_ids=$(aws ec2 describe-snapshots \
        --region "$AWS_REGION" \
        --owner-ids self \
        --filters "Name=tag:StackName,Values=$STACK_NAME" \
        --query 'Snapshots[].SnapshotId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$snapshot_ids" ]; then
        log "Found snapshots to cleanup: $snapshot_ids"
        
        for snapshot_id in $snapshot_ids; do
            if [ "$DRY_RUN" = true ]; then
                info "Would delete snapshot: $snapshot_id"
                increment_counter "deleted"
            else
                if aws ec2 delete-snapshot --region "$AWS_REGION" --snapshot-id "$snapshot_id" >/dev/null 2>&1; then
                    success "Deleted snapshot: $snapshot_id"
                    increment_counter "deleted"
                else
                    error "Failed to delete snapshot: $snapshot_id"
                    increment_counter "failed"
                fi
            fi
        done
    else
        info "No snapshots found for cleanup"
    fi
}

# =============================================================================
# CODEBASE CLEANUP FUNCTIONS
# =============================================================================

# Cleanup local codebase files
cleanup_codebase_files() {
    step "Cleaning up local codebase files..."
    
    local removed_count=0
    
    # Cleanup backup files
    log "Cleaning up backup files..."
    find "$PROJECT_ROOT" -name "*.backup" -o -name "*.backup-*" -o -name "*.bak" -o -name "*~" | while read -r file; do
        if [ -f "$file" ]; then
            if [ "$DRY_RUN" = true ]; then
                info "Would remove backup file: $file"
                ((removed_count++))
            else
                if rm "$file"; then
                    success "Removed backup file: $file"
                    ((removed_count++))
                    increment_counter "deleted"
                else
                    error "Failed to remove backup file: $file"
                    increment_counter "failed"
                fi
            fi
        fi
    done
    
    # Cleanup system files
    log "Cleaning up system files..."
    find "$PROJECT_ROOT" -name ".DS_Store" -o -name "Thumbs.db" -o -name "*.swp" -o -name "*.swo" | while read -r file; do
        if [ -f "$file" ]; then
            if [ "$DRY_RUN" = true ]; then
                info "Would remove system file: $file"
                ((removed_count++))
            else
                if rm "$file"; then
                    success "Removed system file: $file"
                    ((removed_count++))
                    increment_counter "deleted"
                else
                    error "Failed to remove system file: $file"
                    increment_counter "failed"
                fi
            fi
        fi
    done
    
    # Cleanup temporary test files
    log "Cleaning up temporary test files..."
    find "$PROJECT_ROOT" -name "test-*.sh" -path "*/scripts/*" | grep -v "test-cleanup-integration.sh" | grep -v "test-cleanup-consolidated.sh" | while read -r file; do
        if [ -f "$file" ]; then
            if [ "$DRY_RUN" = true ]; then
                info "Would remove test file: $file"
                ((removed_count++))
            else
                if rm "$file"; then
                    success "Removed test file: $file"
                    ((removed_count++))
                    increment_counter "deleted"
                else
                    error "Failed to remove test file: $file"
                    increment_counter "failed"
                fi
            fi
        fi
    done
    
    # Cleanup redundant cleanup scripts (from consolidate-cleanup.sh functionality)
    log "Cleaning up redundant cleanup scripts..."
    local redundant_cleanup_files=(
        "cleanup-unified.sh"
        "cleanup-comparison.sh"
        "cleanup-codebase.sh"
        "quick-cleanup-test.sh"
        "test-cleanup-integration.sh"
        "test-cleanup-unified.sh"
        "test-cleanup-017.sh"
        "test-cleanup-iam.sh"
        "test-full-iam-cleanup.sh"
        "test-inline-policy-cleanup.sh"
    )
    
    for file in "${redundant_cleanup_files[@]}"; do
        local file_path="$SCRIPT_DIR/$file"
        # Also check in tests directory for test files
        local test_file_path="$PROJECT_ROOT/tests/$file"
        
        for path in "$file_path" "$test_file_path"; do
            if [ -f "$path" ]; then
                if [ "$DRY_RUN" = true ]; then
                    info "Would remove redundant cleanup script: $path"
                    ((removed_count++))
                else
                    if rm "$path"; then
                        success "Removed redundant cleanup script: $path"
                        ((removed_count++))
                        increment_counter "deleted"
                    else
                        error "Failed to remove redundant cleanup script: $path"
                        increment_counter "failed"
                    fi
                fi
            fi
        done
    done
    
    success "Codebase cleanup completed. Removed $removed_count files."
}

# Comprehensive test validation function (from test-cleanup-consolidated.sh)
validate_cleanup_script() {
    step "Validating cleanup script functionality..."
    
    local validation_errors=0
    
    # Check script basics
    if [ ! -f "$SCRIPT_DIR/cleanup-consolidated.sh" ]; then
        error "Consolidated cleanup script not found!"
        ((validation_errors++))
    fi
    
    if [ ! -x "$SCRIPT_DIR/cleanup-consolidated.sh" ]; then
        error "Consolidated cleanup script is not executable!"
        ((validation_errors++))
    fi
    
    # Check bash syntax
    if ! bash -n "$SCRIPT_DIR/cleanup-consolidated.sh" 2>/dev/null; then
        error "Bash syntax errors found in cleanup script!"
        ((validation_errors++))
    fi
    
    # Check required functions are defined
    local required_functions=(
        "show_usage"
        "parse_arguments"
        "confirm_cleanup"
        "increment_counter"
        "print_summary"
        "cleanup_ec2_instances"
        "cleanup_efs_resources"
        "cleanup_single_efs"
        "cleanup_network_resources"
        "cleanup_load_balancers"
        "cleanup_cloudfront_distributions"
        "cleanup_monitoring_resources"
        "cleanup_iam_resources"
        "cleanup_storage_resources"
        "cleanup_codebase_files"
        "validate_cleanup_script"
        "main"
    )
    
    for func in "${required_functions[@]}"; do
        if ! grep -q "^${func}()" "$SCRIPT_DIR/cleanup-consolidated.sh"; then
            error "Required function $func not found in cleanup script!"
            ((validation_errors++))
        fi
    done
    
    # Check library sourcing
    if ! grep -q 'source.*error-handling.sh' "$SCRIPT_DIR/cleanup-consolidated.sh"; then
        error "Error handling library not sourced!"
        ((validation_errors++))
    fi
    
    if ! grep -q 'source.*aws-deployment-common.sh' "$SCRIPT_DIR/cleanup-consolidated.sh"; then
        error "AWS deployment common library not sourced!"
        ((validation_errors++))
    fi
    
    # Test help functionality
    if ! "$SCRIPT_DIR/cleanup-consolidated.sh" --help >/dev/null 2>&1; then
        error "Help functionality not working!"
        ((validation_errors++))
    fi
    
    # Test dry-run functionality
    if ! "$SCRIPT_DIR/cleanup-consolidated.sh" --dry-run --force test-stack >/dev/null 2>&1; then
        error "Dry-run functionality not working!"
        ((validation_errors++))
    fi
    
    if [ $validation_errors -eq 0 ]; then
        success "Cleanup script validation passed! All $((${#required_functions[@]} + 4)) checks successful."
        return 0
    else
        error "Cleanup script validation failed with $validation_errors errors!"
        return 1
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo "🗑️  CONSOLIDATED AWS RESOURCE CLEANUP"
    echo "====================================="
    
    # Parse arguments
    parse_arguments "$@"
    
    # Validate arguments
    if [ "$CLEANUP_MODE" = "stack" ] && [ -z "$STACK_NAME" ]; then
        error "Stack name is required for stack mode"
        show_usage
        exit 1
    fi
    
    if [ "$CLEANUP_MODE" = "efs" ] && [ -z "$STACK_NAME" ]; then
        error "Pattern is required for efs mode (use STACK_NAME as pattern)"
        show_usage
        exit 1
    fi
    
    # Skip confirmation for validation mode
    if [ "$CLEANUP_MODE" = "validate" ]; then
        FORCE=true
    fi
    
    # Show configuration
    if [ "$QUIET" != true ]; then
        info "Configuration:"
        info "  Stack Name: $STACK_NAME"
        info "  Mode: $CLEANUP_MODE"
        info "  Region: $AWS_REGION"
        info "  Dry Run: $DRY_RUN"
        info "  Force: $FORCE"
        info "  Verbose: $VERBOSE"
    fi
    
    # Confirm cleanup unless force is enabled
    confirm_cleanup
    
    # Execute cleanup based on mode and resource types
    case "$CLEANUP_MODE" in
        "failed-deployments")
            # Special mode for failed deployment EFS cleanup
            cleanup_efs_resources
            ;;
        "efs")
            # EFS pattern-based cleanup
            cleanup_efs_resources
            ;;
        "codebase")
            # Codebase cleanup only
            cleanup_codebase_files
            ;;
        "validate")
            # Validate cleanup script functionality
            validate_cleanup_script
            ;;
        "all")
            # Cleanup all resources
            cleanup_ec2_instances
            cleanup_efs_resources
            cleanup_network_resources
            cleanup_monitoring_resources
            cleanup_iam_resources
            cleanup_storage_resources
            cleanup_codebase_files
            ;;
        "specific")
            # Cleanup specific resource types based on flags
            if [ "$CLEANUP_INSTANCES" = true ]; then
                cleanup_ec2_instances
            fi
            
            if [ "$CLEANUP_EFS" = true ]; then
                cleanup_efs_resources
            fi
            
            if [ "$CLEANUP_NETWORK" = true ]; then
                cleanup_network_resources
            fi
            
            if [ "$CLEANUP_MONITORING" = true ]; then
                cleanup_monitoring_resources
            fi
            
            if [ "$CLEANUP_IAM" = true ]; then
                cleanup_iam_resources
            fi
            
            if [ "$CLEANUP_STORAGE" = true ]; then
                cleanup_storage_resources
            fi
            
            if [ "$CLEANUP_CODEBASE" = true ]; then
                cleanup_codebase_files
            fi
            ;;
        *)
            # Default stack-based cleanup
            if [ "$CLEANUP_INSTANCES" = true ]; then
                cleanup_ec2_instances
            fi
            
            if [ "$CLEANUP_EFS" = true ]; then
                cleanup_efs_resources
            fi
            
            if [ "$CLEANUP_NETWORK" = true ]; then
                cleanup_network_resources
            fi
            
            if [ "$CLEANUP_MONITORING" = true ]; then
                cleanup_monitoring_resources
            fi
            
            if [ "$CLEANUP_IAM" = true ]; then
                cleanup_iam_resources
            fi
            
            if [ "$CLEANUP_STORAGE" = true ]; then
                cleanup_storage_resources
            fi
            
            if [ "$CLEANUP_CODEBASE" = true ]; then
                cleanup_codebase_files
            fi
            ;;
    esac
    
    # Print summary
    print_summary
}

# Run main function
main "$@" 