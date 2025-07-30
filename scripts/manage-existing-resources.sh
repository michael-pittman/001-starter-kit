#!/usr/bin/env bash
# =============================================================================
# Existing Resources Management Script
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source common functions
source "${PROJECT_ROOT}/lib/utils/cli.sh"
source "${PROJECT_ROOT}/lib/modules/infrastructure/existing-resources.sh"

# =============================================================================
# USAGE AND HELP
# =============================================================================

show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Manage existing AWS resources for deployment reuse.

COMMANDS:
    discover    Auto-discover existing resources
    validate    Validate existing resources
    map         Map resources to deployment variables
    list        List configured existing resources
    test        Test resource connectivity and permissions
    help        Show this help message

OPTIONS:
    -e, --environment ENV    Environment name (dev, staging, prod)
    -s, --stack-name NAME    Stack name
    -c, --config-file FILE   Configuration file path
    -v, --verbose           Enable verbose output
    -d, --dry-run          Show what would be done without making changes

EXAMPLES:
    # Discover existing resources for dev environment
    $0 discover -e dev -s GeuseMaker-dev
    
    # Validate existing resources
    $0 validate -e dev -s GeuseMaker-dev
    
    # Test resource connectivity
    $0 test -e dev -s GeuseMaker-dev
    
    # List configured resources
    $0 list -e dev

EOF
}

# =============================================================================
# COMMAND FUNCTIONS
# =============================================================================

cmd_discover() {
    local environment="$1"
    local stack_name="$2"
    
    echo "🔍 Discovering existing resources for stack: $stack_name"
    
    # Load configuration
    load_existing_resources_config "$environment"
    
    # Discover resources
    local discovered_resources
    discovered_resources=$(discover_existing_resources "$stack_name" "$environment")
    
    if [[ -z "$discovered_resources" || "$discovered_resources" == "{}" ]]; then
        echo "❌ No existing resources discovered"
        return 1
    fi
    
    echo "✅ Discovered resources:"
    echo "$discovered_resources" | jq '.'
    
    # Save to configuration file
    local config_file="config/environments/${environment}.yml"
    echo "💾 Saving discovered resources to: $config_file"
    
    # Backup existing config
    cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Update configuration
    yq eval ".existing_resources.resources = $discovered_resources" -i "$config_file"
    
    echo "✅ Discovery completed successfully"
}

cmd_validate() {
    local environment="$1"
    local stack_name="$2"
    
    echo "🔍 Validating existing resources for stack: $stack_name"
    
    # Load configuration
    load_existing_resources_config "$environment"
    
    # Get resources configuration
    local config_file="config/environments/${environment}.yml"
    local resources_config
    resources_config=$(yq eval '.existing_resources.resources' -o=json "$config_file" 2>/dev/null)
    
    if [[ -z "$resources_config" || "$resources_config" == "null" ]]; then
        echo "❌ No existing resources configuration found"
        return 1
    fi
    
    # Validate VPC
    local vpc_id
    vpc_id=$(echo "$resources_config" | jq -r '.vpc.id // empty')
    if [[ -n "$vpc_id" ]]; then
        echo "🔍 Validating VPC: $vpc_id"
        if validate_existing_vpc "$vpc_id"; then
            echo "✅ VPC validation passed"
        else
            echo "❌ VPC validation failed"
            return 1
        fi
    fi
    
    # Validate subnets
    local public_subnet_ids
    public_subnet_ids=$(echo "$resources_config" | jq -r '.subnets.public.ids // [] | join(",")')
    if [[ -n "$public_subnet_ids" && -n "$vpc_id" ]]; then
        echo "🔍 Validating public subnets: $public_subnet_ids"
        if validate_existing_subnets "$public_subnet_ids" "$vpc_id" "public"; then
            echo "✅ Public subnet validation passed"
        else
            echo "❌ Public subnet validation failed"
            return 1
        fi
    fi
    
    local private_subnet_ids
    private_subnet_ids=$(echo "$resources_config" | jq -r '.subnets.private.ids // [] | join(",")')
    if [[ -n "$private_subnet_ids" && -n "$vpc_id" ]]; then
        echo "🔍 Validating private subnets: $private_subnet_ids"
        if validate_existing_subnets "$private_subnet_ids" "$vpc_id" "private"; then
            echo "✅ Private subnet validation passed"
        else
            echo "❌ Private subnet validation failed"
            return 1
        fi
    fi
    
    # Validate security groups
    local security_group_ids
    security_group_ids=$(echo "$resources_config" | jq -r '.security_groups | to_entries[] | .value.id // empty' | grep -v '^$' | tr '\n' ',')
    if [[ -n "$security_group_ids" && -n "$vpc_id" ]]; then
        echo "🔍 Validating security groups: $security_group_ids"
        if validate_existing_security_groups "$security_group_ids" "$vpc_id"; then
            echo "✅ Security group validation passed"
        else
            echo "❌ Security group validation failed"
            return 1
        fi
    fi
    
    echo "✅ All resource validations passed"
}

cmd_map() {
    local environment="$1"
    local stack_name="$2"
    
    echo "🗺️  Mapping existing resources for stack: $stack_name"
    
    # Load configuration
    load_existing_resources_config "$environment"
    
    # Get resources configuration
    local config_file="config/environments/${environment}.yml"
    local resources_config
    resources_config=$(yq eval '.existing_resources.resources' -o=json "$config_file" 2>/dev/null)
    
    if [[ -z "$resources_config" || "$resources_config" == "null" ]]; then
        echo "❌ No existing resources configuration found"
        return 1
    fi
    
    # Map resources
    map_existing_resources "$resources_config" "$stack_name"
    
    echo "✅ Resource mapping completed"
}

cmd_list() {
    local environment="$1"
    
    echo "📋 Listing configured existing resources for environment: $environment"
    
    local config_file="config/environments/${environment}.yml"
    
    if [[ ! -f "$config_file" ]]; then
        echo "❌ Configuration file not found: $config_file"
        return 1
    fi
    
    # Extract and display existing resources configuration
    local resources_config
    resources_config=$(yq eval '.existing_resources' "$config_file" 2>/dev/null)
    
    if [[ -z "$resources_config" || "$resources_config" == "null" ]]; then
        echo "❌ No existing resources configuration found"
        return 1
    fi
    
    # Check if the output is valid JSON before trying to format it
    if echo "$resources_config" | jq . >/dev/null 2>&1; then
        echo "Configuration:"
        echo "$resources_config" | jq '.'
    else
        echo "Configuration (raw):"
        echo "$resources_config"
    fi
}

cmd_test() {
    local environment="$1"
    local stack_name="$2"
    
    echo "🧪 Testing existing resources connectivity for stack: $stack_name"
    
    # Load configuration
    load_existing_resources_config "$environment"
    
    # Test AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        echo "❌ AWS credentials not configured or invalid"
        return 1
    fi
    
    echo "✅ AWS credentials valid"
    
    # Test resource access
    local config_file="config/environments/${environment}.yml"
    local resources_config
    resources_config=$(yq eval '.existing_resources.resources' -o=json "$config_file" 2>/dev/null)
    
    if [[ -n "$resources_config" && "$resources_config" != "null" ]]; then
        # Test VPC access
        local vpc_id
        vpc_id=$(echo "$resources_config" | jq -r '.vpc.id // empty')
        if [[ -n "$vpc_id" ]]; then
            if aws ec2 describe-vpcs --vpc-ids "$vpc_id" >/dev/null 2>&1; then
                echo "✅ VPC access: $vpc_id"
            else
                echo "❌ VPC access failed: $vpc_id"
                return 1
            fi
        fi
        
        # Test EFS access
        local efs_id
        efs_id=$(echo "$resources_config" | jq -r '.efs.file_system_id // empty')
        if [[ -n "$efs_id" ]]; then
            if aws efs describe-file-systems --file-system-id "$efs_id" >/dev/null 2>&1; then
                echo "✅ EFS access: $efs_id"
            else
                echo "❌ EFS access failed: $efs_id"
                return 1
            fi
        fi
        
        # Test ALB access
        local alb_arn
        alb_arn=$(echo "$resources_config" | jq -r '.alb.load_balancer_arn // empty')
        if [[ -n "$alb_arn" ]]; then
            if aws elbv2 describe-load-balancers --load-balancer-arns "$alb_arn" >/dev/null 2>&1; then
                echo "✅ ALB access: $alb_arn"
            else
                echo "❌ ALB access failed: $alb_arn"
                return 1
            fi
        fi
    fi
    
    echo "✅ All connectivity tests passed"
}

# =============================================================================
# MAIN SCRIPT LOGIC
# =============================================================================

main() {
    local command=""
    local environment=""
    local stack_name=""
    local config_file=""
    local verbose=false
    local dry_run=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            discover|validate|map|list|test|help)
                command="$1"
                shift
                ;;
            -e|--environment)
                environment="$2"
                shift 2
                ;;
            -s|--stack-name)
                stack_name="$2"
                shift 2
                ;;
            -c|--config-file)
                config_file="$2"
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set default environment if not specified
    if [[ -z "$environment" ]]; then
        environment="${ENVIRONMENT:-dev}"
    fi
    
    # Set default stack name if not specified
    if [[ -z "$stack_name" ]]; then
        stack_name="${STACK_NAME:-GeuseMaker-${environment}}"
    fi
    
    # Show help if no command specified
    if [[ -z "$command" ]]; then
        show_usage
        exit 1
    fi
    
    # Execute command
    case "$command" in
        discover)
            cmd_discover "$environment" "$stack_name"
            ;;
        validate)
            cmd_validate "$environment" "$stack_name"
            ;;
        map)
            cmd_map "$environment" "$stack_name"
            ;;
        list)
            cmd_list "$environment"
            ;;
        test)
            cmd_test "$environment" "$stack_name"
            ;;
        help)
            show_usage
            ;;
        *)
            echo "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi