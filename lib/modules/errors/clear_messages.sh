#!/usr/bin/env bash
# =============================================================================
# Clear Error Messages Module
# Provides user-friendly, actionable error messages with recovery guidance
# Part of Story 5.3 Task 3 implementation
# =============================================================================

set -euo pipefail

# Prevent multiple sourcing
[ -n "${_CLEAR_MESSAGES_SH_LOADED:-}" ] && return 0
_CLEAR_MESSAGES_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../core/errors.sh"

# Ensure error category constants are available
ERROR_CAT_UNKNOWN="${ERROR_CAT_UNKNOWN:-unknown}"

# =============================================================================
# ERROR MESSAGE FORMAT DEFINITIONS
# =============================================================================

# Message clarity levels
readonly MSG_CLARITY_TECHNICAL=0
readonly MSG_CLARITY_STANDARD=1
readonly MSG_CLARITY_USER_FRIENDLY=2

# Default message clarity level
export ERROR_MESSAGE_CLARITY="${ERROR_MESSAGE_CLARITY:-$MSG_CLARITY_USER_FRIENDLY}"

# Message components
readonly MSG_COMPONENT_WHAT="what"
readonly MSG_COMPONENT_WHY="why"
readonly MSG_COMPONENT_HOW="how"
readonly MSG_COMPONENT_EXAMPLE="example"

# =============================================================================
# ERROR MESSAGE TEMPLATES
# =============================================================================

# Define clear message templates for common errors
declare -gA CLEAR_ERROR_MESSAGES=(
    ["EC2_INSUFFICIENT_CAPACITY"]="what:Unable to launch EC2 instance|why:AWS doesn't have enough capacity for the requested instance type in this region|how:Try a different instance type (e.g., g5.xlarge instead of g4dn.xlarge) or switch to another region|example:aws ec2 run-instances --instance-type g5.xlarge --region us-west-2"
    
    ["EC2_INSTANCE_LIMIT_EXCEEDED"]="what:Cannot create more EC2 instances|why:You've reached your AWS account limit for this instance type|how:Request a limit increase through AWS Support or terminate unused instances|example:Visit AWS Service Quotas console to request increase"
    
    ["EC2_SPOT_BID_TOO_LOW"]="what:Spot instance request failed|why:Your bid price is lower than the current market price|how:Increase your bid price or use on-demand instances|example:Current price: \$0.50/hr, your bid: \$0.30/hr - try bidding \$0.55/hr"
    
    ["NETWORK_VPC_NOT_FOUND"]="what:Cannot find the specified VPC|why:The VPC ID doesn't exist or you don't have access to it|how:Check the VPC ID in AWS console or create a new VPC|example:aws ec2 describe-vpcs --region us-east-1"
    
    ["AUTH_INVALID_CREDENTIALS"]="what:AWS authentication failed|why:Your AWS credentials are invalid, expired, or not configured|how:Run 'aws configure' to set up your credentials|example:aws configure (then enter your Access Key ID and Secret Access Key)"
    
    ["AUTH_INSUFFICIENT_PERMISSIONS"]="what:Permission denied for AWS operation|why:Your IAM user/role doesn't have the required permissions|how:Ask your AWS administrator to grant the necessary permissions|example:Add 'ec2:RunInstances' permission to your IAM policy"
    
    ["CONFIG_MISSING_PARAMETER"]="what:Required configuration is missing|why:A mandatory parameter wasn't provided|how:Add the missing parameter to your command or configuration file|example:export STACK_NAME='my-stack' or add --stack-name parameter"
    
    ["DEPENDENCY_NOT_READY"]="what:A required service isn't ready|why:The service needs more time to start or has failed|how:Wait a few moments and retry, or check the service status|example:Check service health: make health-check STACK_NAME=my-stack"
    
    ["TIMEOUT_OPERATION"]="what:Operation took too long to complete|why:Network issues, service delays, or resource constraints|how:Retry the operation or increase the timeout value|example:Set longer timeout: export AWS_CLI_TIMEOUT=300"
    
    ["DOCKER_DAEMON_NOT_RUNNING"]="what:Cannot connect to Docker|why:Docker service is not running on your system|how:Start Docker Desktop or run 'sudo systemctl start docker'|example:macOS: Open Docker Desktop app, Linux: sudo systemctl start docker"
    
    ["DISK_SPACE_INSUFFICIENT"]="what:Not enough disk space|why:Your system is running low on storage|how:Free up space by removing unused files or Docker images|example:docker system prune -a or rm -rf /tmp/*"
    
    ["NETWORK_CONNECTION_FAILED"]="what:Cannot connect to remote service|why:Network connectivity issues or firewall blocking|how:Check your internet connection and firewall settings|example:ping google.com or check security group rules"
)

# Recovery action templates
declare -gA RECOVERY_ACTIONS=(
    ["retry"]="Try running the command again - temporary issues often resolve themselves"
    ["fallback"]="The system will automatically try an alternative approach"
    ["manual"]="Manual intervention required - please follow the suggested steps"
    ["abort"]="Operation cannot continue - resolve the issue before retrying"
    ["skip"]="This step will be skipped - may affect functionality"
)

# =============================================================================
# MESSAGE FORMATTING FUNCTIONS
# =============================================================================

# Format error message with clarity
format_clear_error_message() {
    local error_code="$1"
    local context="${2:-}"
    local technical_details="${3:-}"
    
    # Get message template
    local template="${CLEAR_ERROR_MESSAGES[$error_code]:-}"
    if [[ -z "$template" ]]; then
        # Fallback to generic message
        echo "Error: $error_code occurred${context:+ in $context}"
        return
    fi
    
    # Parse template components
    local what why how example
    IFS='|' read -r what why how example <<< "$template"
    
    what="${what#what:}"
    why="${why#why:}"
    how="${how#how:}"
    example="${example#example:}"
    
    # Substitute context values if provided
    if [[ -n "$context" ]]; then
        what="${what//\{context\}/$context}"
        why="${why//\{context\}/$context}"
        how="${how//\{context\}/$context}"
        example="${example//\{context\}/$context}"
    fi
    
    # Build formatted message based on clarity level
    local message=""
    case "$ERROR_MESSAGE_CLARITY" in
        $MSG_CLARITY_TECHNICAL)
            message="[$error_code] $what${technical_details:+ - $technical_details}"
            ;;
        $MSG_CLARITY_STANDARD)
            message="❌ $what\n   Why: $why\n   Fix: $how"
            ;;
        $MSG_CLARITY_USER_FRIENDLY)
            message="❌ What happened: $what\n\n📋 Why this occurred: $why\n\n💡 How to fix: $how\n\n📝 Example: $example"
            ;;
    esac
    
    echo -e "$message"
}

# Get recovery suggestion with user-friendly formatting
get_clear_recovery_suggestion() {
    local recovery_strategy="$1"
    local error_code="${2:-}"
    
    local base_suggestion="${RECOVERY_ACTIONS[$recovery_strategy]:-Please check the error details and try again}"
    
    # Add specific suggestions based on error code
    local specific_suggestion=""
    case "$error_code" in
        *"CAPACITY"*)
            specific_suggestion="\n💡 Tip: AWS capacity varies by region and time - try different regions or wait 5-10 minutes"
            ;;
        *"AUTH"*)
            specific_suggestion="\n🔐 Security tip: Never share your AWS credentials. Store them securely using 'aws configure'"
            ;;
        *"NETWORK"*)
            specific_suggestion="\n🌐 Network tip: Check if you're behind a corporate firewall or VPN"
            ;;
        *"DOCKER"*)
            specific_suggestion="\n🐳 Docker tip: Make sure Docker Desktop is running and you have enough disk space"
            ;;
    esac
    
    echo -e "$base_suggestion$specific_suggestion"
}

# =============================================================================
# ENHANCED ERROR LOGGING WITH CLEAR MESSAGES
# =============================================================================

# Log error with clear, actionable message
log_clear_error() {
    local error_code="$1"
    local context="${2:-}"
    local exit_code="${3:-1}"
    local technical_details="${4:-}"
    local recovery_strategy="${5:-$RECOVERY_ABORT}"
    
    # Format the clear message
    local clear_message
    clear_message=$(format_clear_error_message "$error_code" "$context" "$technical_details")
    
    # Get recovery suggestion
    local recovery_suggestion
    recovery_suggestion=$(get_clear_recovery_suggestion "$recovery_strategy" "$error_code")
    
    # Use color codes for better visibility
    local color_code="${RED}"
    case "$recovery_strategy" in
        "$RECOVERY_RETRY") color_code="${YELLOW}" ;;
        "$RECOVERY_FALLBACK") color_code="${BLUE}" ;;
        "$RECOVERY_SKIP") color_code="${CYAN}" ;;
    esac
    
    # Output formatted error
    echo -e "\n${color_code}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo -e "$clear_message" >&2
    echo -e "\n🔧 Recovery: $recovery_suggestion" >&2
    echo -e "${color_code}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n" >&2
    
    # Log to structured error system if available
    if command -v log_structured_error >/dev/null 2>&1; then
        # Determine error category from error code
        local error_category="$ERROR_CAT_UNKNOWN"
        case "$error_code" in
            *"EC2"*) error_category="$ERROR_CAT_CAPACITY" ;;
            *"NETWORK"*) error_category="$ERROR_CAT_NETWORK" ;;
            *"AUTH"*) error_category="$ERROR_CAT_AUTHENTICATION" ;;
            *"CONFIG"*) error_category="$ERROR_CAT_CONFIGURATION" ;;
            *"TIMEOUT"*) error_category="$ERROR_CAT_TIMEOUT" ;;
            *"DEPENDENCY"*) error_category="$ERROR_CAT_DEPENDENCY" ;;
        esac
        
        log_structured_error "$error_code" "$clear_message" "$error_category" \
            "$ERROR_SEVERITY_ERROR" "$context" "$recovery_strategy"
    fi
    
    return "$exit_code"
}

# =============================================================================
# PREDEFINED CLEAR ERROR FUNCTIONS
# =============================================================================

# EC2 errors with clear messages
error_ec2_insufficient_capacity_clear() {
    local instance_type="$1"
    local region="$2"
    log_clear_error "EC2_INSUFFICIENT_CAPACITY" \
        "$instance_type in $region" \
        1 \
        "Instance type: $instance_type, Region: $region" \
        "$RECOVERY_FALLBACK"
}

error_ec2_instance_limit_clear() {
    local instance_type="$1"
    log_clear_error "EC2_INSTANCE_LIMIT_EXCEEDED" \
        "$instance_type" \
        1 \
        "Current limit reached for $instance_type" \
        "$RECOVERY_MANUAL"
}

# Network errors with clear messages
error_network_vpc_not_found_clear() {
    local vpc_id="$1"
    log_clear_error "NETWORK_VPC_NOT_FOUND" \
        "$vpc_id" \
        1 \
        "VPC ID: $vpc_id" \
        "$RECOVERY_MANUAL"
}

# Authentication errors with clear messages
error_auth_invalid_credentials_clear() {
    local service="$1"
    log_clear_error "AUTH_INVALID_CREDENTIALS" \
        "$service" \
        1 \
        "Service: $service" \
        "$RECOVERY_MANUAL"
}

error_auth_insufficient_permissions_clear() {
    local action="$1"
    local resource="$2"
    log_clear_error "AUTH_INSUFFICIENT_PERMISSIONS" \
        "$action on $resource" \
        1 \
        "Action: $action, Resource: $resource" \
        "$RECOVERY_MANUAL"
}

# =============================================================================
# MESSAGE CLARITY TESTING
# =============================================================================

# Test message clarity score
test_message_clarity() {
    local message="$1"
    local score=0
    local max_score=10
    
    # Check for user-friendly language (avoid jargon)
    if [[ ! "$message" =~ (API|SDK|CLI|daemon|socket|errno) ]]; then
        ((score += 2))
    fi
    
    # Check for actionable guidance
    if [[ "$message" =~ (Try|Check|Run|Visit|Set|Add) ]]; then
        ((score += 2))
    fi
    
    # Check for examples
    if [[ "$message" =~ (example:|e\.g\.|for instance) ]]; then
        ((score += 2))
    fi
    
    # Check for explanation of why
    if [[ "$message" =~ (because|due to|caused by|Why) ]]; then
        ((score += 2))
    fi
    
    # Check for appropriate length (not too short, not too long)
    local word_count
    word_count=$(echo "$message" | wc -w)
    if [[ $word_count -ge 10 && $word_count -le 100 ]]; then
        ((score += 2))
    fi
    
    echo "$score/$max_score"
}

# =============================================================================
# USER EXPERIENCE ENHANCEMENTS
# =============================================================================

# Show progress indication for long operations
show_error_context_progress() {
    local operation="$1"
    local step="${2:-1}"
    local total="${3:-1}"
    
    if [[ "$ERROR_MESSAGE_CLARITY" == "$MSG_CLARITY_USER_FRIENDLY" ]]; then
        echo -e "\n📍 Step $step of $total: $operation" >&2
    fi
}

# Provide helpful context before operations that might fail
provide_operation_context() {
    local operation="$1"
    local likelihood="${2:-low}"  # low, medium, high
    
    if [[ "$ERROR_MESSAGE_CLARITY" == "$MSG_CLARITY_USER_FRIENDLY" ]]; then
        case "$likelihood" in
            "high")
                echo -e "\n⚠️  This operation might fail due to common issues. Don't worry, we'll guide you through any problems." >&2
                ;;
            "medium")
                echo -e "\n📌 Starting: $operation" >&2
                ;;
        esac
    fi
}

# =============================================================================
# INTERACTIVE ERROR RESOLUTION
# =============================================================================

# Offer interactive resolution for errors
offer_interactive_resolution() {
    local error_code="$1"
    local recovery_strategy="$2"
    
    if [[ "$ERROR_MESSAGE_CLARITY" != "$MSG_CLARITY_USER_FRIENDLY" ]]; then
        return 0
    fi
    
    case "$recovery_strategy" in
        "$RECOVERY_RETRY")
            echo -e "\n🔄 Would you like to retry this operation? (y/n): " >&2
            ;;
        "$RECOVERY_MANUAL")
            echo -e "\n📚 Would you like to see detailed troubleshooting steps? (y/n): " >&2
            ;;
        "$RECOVERY_FALLBACK")
            echo -e "\n🔀 The system can try an alternative approach. Continue? (y/n): " >&2
            ;;
    esac
}

# =============================================================================
# ERROR MESSAGE LOCALIZATION SUPPORT
# =============================================================================

# Get localized error message (stub for future implementation)
get_localized_error_message() {
    local error_code="$1"
    local language="${ERROR_MESSAGE_LANGUAGE:-en}"
    
    # For now, just return the English message
    # Future: implement message catalogs for different languages
    format_clear_error_message "$error_code"
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f format_clear_error_message
export -f get_clear_recovery_suggestion
export -f log_clear_error
export -f error_ec2_insufficient_capacity_clear
export -f error_ec2_instance_limit_clear
export -f error_network_vpc_not_found_clear
export -f error_auth_invalid_credentials_clear
export -f error_auth_insufficient_permissions_clear
export -f test_message_clarity
export -f show_error_context_progress
export -f provide_operation_context
export -f offer_interactive_resolution
export -f get_localized_error_message