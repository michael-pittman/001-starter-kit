#!/bin/bash
# =============================================================================
# Application Load Balancer Infrastructure Module
# Manages ALB, target groups, and CloudFront distributions
# =============================================================================

# Prevent multiple sourcing
[ -n "${_ALB_SH_LOADED:-}" ] && return 0
_ALB_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"

# =============================================================================
# APPLICATION LOAD BALANCER MANAGEMENT
# =============================================================================

# Create Application Load Balancer
create_application_load_balancer() {
    local stack_name="${1:-$STACK_NAME}"
    local subnets_json="$2"  # JSON array of subnet objects
    local security_group_id="$3"
    local scheme="${4:-internet-facing}"  # internet-facing or internal
    
    with_error_context "create_application_load_balancer" \
        _create_application_load_balancer_impl "$stack_name" "$subnets_json" "$security_group_id" "$scheme"
}

_create_application_load_balancer_impl() {
    local stack_name="$1"
    local subnets_json="$2"
    local security_group_id="$3"
    local scheme="$4"
    
    echo "Creating Application Load Balancer for: $stack_name" >&2
    
    # Check if ALB already exists
    local existing_alb
    existing_alb=$(aws elbv2 describe-load-balancers \
        --query "LoadBalancers[?LoadBalancerName=='${stack_name}-alb'].LoadBalancerArn | [0]" \
        --output text 2>/dev/null | grep -v "None" || true)
    
    if [ -n "$existing_alb" ]; then
        echo "ALB already exists: $existing_alb" >&2
        echo "$existing_alb"
        return 0
    fi
    
    # Extract subnet IDs
    local subnet_ids
    subnet_ids=($(echo "$subnets_json" | jq -r '.[].id'))
    
    if [ ${#subnet_ids[@]} -lt 2 ]; then
        throw_error $ERROR_INVALID_ARGUMENT "ALB requires at least 2 subnets in different AZs"
    fi
    
    # Create ALB
    local alb_arn
    alb_arn=$(aws elbv2 create-load-balancer \
        --name "${stack_name}-alb" \
        --subnets "${subnet_ids[@]}" \
        --security-groups "$security_group_id" \
        --scheme "$scheme" \
        --type application \
        --ip-address-type ipv4 \
        --tags "$(tags_to_cli_format "$(generate_tags "$stack_name" '{"Service": "ALB"}')")" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text) || {
        throw_error $ERROR_AWS_API "Failed to create Application Load Balancer"
    }
    
    # Wait for ALB to be active
    echo "Waiting for ALB to become active..." >&2
    aws elbv2 wait load-balancer-active --load-balancer-arns "$alb_arn" || {
        throw_error $ERROR_TIMEOUT "ALB did not become active"
    }
    
    # Register ALB
    register_resource "load_balancers" "$alb_arn" \
        "{\"name\": \"${stack_name}-alb\", \"scheme\": \"$scheme\", \"type\": \"application\"}"
    
    echo "$alb_arn"
}

# Get ALB DNS name
get_alb_dns_name() {
    local alb_arn="$1"
    
    aws elbv2 describe-load-balancers \
        --load-balancer-arns "$alb_arn" \
        --query 'LoadBalancers[0].DNSName' \
        --output text
}

# =============================================================================
# TARGET GROUP MANAGEMENT
# =============================================================================

# Create target group for specific service
create_target_group() {
    local stack_name="${1:-$STACK_NAME}"
    local service_name="$2"  # n8n, ollama, qdrant, etc.
    local port="$3"
    local vpc_id="$4"
    local health_check_path="${5:-/}"
    local protocol="${6:-HTTP}"
    
    with_error_context "create_target_group" \
        _create_target_group_impl "$stack_name" "$service_name" "$port" "$vpc_id" "$health_check_path" "$protocol"
}

_create_target_group_impl() {
    local stack_name="$1"
    local service_name="$2"
    local port="$3"
    local vpc_id="$4"
    local health_check_path="$5"
    local protocol="$6"
    
    local tg_name="${stack_name}-${service_name}-tg"
    
    echo "Creating target group: $tg_name" >&2
    
    # Check if target group already exists
    local existing_tg
    existing_tg=$(aws elbv2 describe-target-groups \
        --names "$tg_name" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null | grep -v "None" || true)
    
    if [ -n "$existing_tg" ]; then
        echo "Target group already exists: $existing_tg" >&2
        echo "$existing_tg"
        return 0
    fi
    
    # Create target group
    local tg_arn
    tg_arn=$(aws elbv2 create-target-group \
        --name "$tg_name" \
        --protocol "$protocol" \
        --port "$port" \
        --vpc-id "$vpc_id" \
        --target-type instance \
        --health-check-enabled \
        --health-check-protocol "$protocol" \
        --health-check-port "$port" \
        --health-check-path "$health_check_path" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --tags "$(tags_to_cli_format "$(generate_tags "$stack_name" "{\"Service\": \"$service_name\"}")")" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text) || {
        throw_error $ERROR_AWS_API "Failed to create target group"
    }
    
    # Register target group
    register_resource "target_groups" "$tg_arn" \
        "{\"name\": \"$tg_name\", \"service\": \"$service_name\", \"port\": $port}"
    
    echo "$tg_arn"
}

# Register instance with target group
register_target() {
    local target_group_arn="$1"
    local instance_id="$2"
    local port="${3:-80}"
    
    echo "Registering instance $instance_id with target group" >&2
    
    aws elbv2 register-targets \
        --target-group-arn "$target_group_arn" \
        --targets "Id=$instance_id,Port=$port" || {
        throw_error $ERROR_AWS_API "Failed to register target"
    }
    
    # Wait for target to be healthy
    echo "Waiting for target to become healthy..." >&2
    aws elbv2 wait target-in-service \
        --target-group-arn "$target_group_arn" \
        --targets "Id=$instance_id,Port=$port" || {
        echo "WARNING: Target did not become healthy within timeout" >&2
    }
}

# Create multiple target groups for AI services
create_ai_service_target_groups() {
    local stack_name="${1:-$STACK_NAME}"
    local vpc_id="$2"
    
    echo "Creating target groups for AI services" >&2
    
    # Define services with their ports and health check paths
    local services=(
        "n8n:5678:/healthz"
        "ollama:11434:/api/tags"
        "qdrant:6333:/health"
        "crawl4ai:11235:/health"
    )
    
    local target_groups_json="[]"
    
    for service_def in "${services[@]}"; do
        local service_name port health_path
        IFS=':' read -r service_name port health_path <<< "$service_def"
        
        local tg_arn
        tg_arn=$(create_target_group "$stack_name" "$service_name" "$port" "$vpc_id" "$health_path") || {
            echo "WARNING: Failed to create target group for $service_name" >&2
            continue
        }
        
        # Add to JSON array
        local tg_info
        tg_info=$(cat <<EOF
{
    "service": "$service_name",
    "port": $port,
    "target_group_arn": "$tg_arn",
    "health_path": "$health_path"
}
EOF
)
        target_groups_json=$(echo "$target_groups_json" | jq ". += [$tg_info]")
        
        echo "Created target group for $service_name: $tg_arn" >&2
    done
    
    echo "$target_groups_json"
}

# =============================================================================
# LISTENER MANAGEMENT
# =============================================================================

# Create ALB listener with rules
create_alb_listeners() {
    local alb_arn="$1"
    local target_groups_json="$2"
    local enable_https="${3:-false}"
    local certificate_arn="${4:-}"
    
    echo "Creating ALB listeners" >&2
    
    # Create HTTP listener
    local http_listener_arn
    http_listener_arn=$(create_http_listener "$alb_arn" "$target_groups_json") || {
        throw_error $ERROR_AWS_API "Failed to create HTTP listener"
    }
    
    # Create HTTPS listener if enabled
    local https_listener_arn=""
    if [ "$enable_https" = "true" ] && [ -n "$certificate_arn" ]; then
        https_listener_arn=$(create_https_listener "$alb_arn" "$target_groups_json" "$certificate_arn") || {
            echo "WARNING: Failed to create HTTPS listener" >&2
        }
    fi
    
    # Return listener information
    cat <<EOF
{
    "http_listener_arn": "$http_listener_arn",
    "https_listener_arn": "$https_listener_arn"
}
EOF
}

# Create HTTP listener
create_http_listener() {
    local alb_arn="$1"
    local target_groups_json="$2"
    
    # Get default target group (n8n)
    local default_tg_arn
    default_tg_arn=$(echo "$target_groups_json" | jq -r '.[] | select(.service == "n8n") | .target_group_arn')
    
    if [ -z "$default_tg_arn" ] || [ "$default_tg_arn" = "null" ]; then
        default_tg_arn=$(echo "$target_groups_json" | jq -r '.[0].target_group_arn')
    fi
    
    # Create HTTP listener
    local listener_arn
    listener_arn=$(aws elbv2 create-listener \
        --load-balancer-arn "$alb_arn" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$default_tg_arn" \
        --query 'Listeners[0].ListenerArn' \
        --output text) || {
        throw_error $ERROR_AWS_API "Failed to create HTTP listener"
    }
    
    # Create listener rules for different services
    create_listener_rules "$listener_arn" "$target_groups_json"
    
    echo "$listener_arn"
}

# Create HTTPS listener
create_https_listener() {
    local alb_arn="$1"
    local target_groups_json="$2"
    local certificate_arn="$3"
    
    # Get default target group (n8n)
    local default_tg_arn
    default_tg_arn=$(echo "$target_groups_json" | jq -r '.[] | select(.service == "n8n") | .target_group_arn')
    
    if [ -z "$default_tg_arn" ] || [ "$default_tg_arn" = "null" ]; then
        default_tg_arn=$(echo "$target_groups_json" | jq -r '.[0].target_group_arn')
    fi
    
    # Create HTTPS listener
    local listener_arn
    listener_arn=$(aws elbv2 create-listener \
        --load-balancer-arn "$alb_arn" \
        --protocol HTTPS \
        --port 443 \
        --certificates CertificateArn="$certificate_arn" \
        --default-actions Type=forward,TargetGroupArn="$default_tg_arn" \
        --query 'Listeners[0].ListenerArn' \
        --output text) || {
        throw_error $ERROR_AWS_API "Failed to create HTTPS listener"
    }
    
    # Create listener rules for different services
    create_listener_rules "$listener_arn" "$target_groups_json"
    
    echo "$listener_arn"
}

# Create listener rules for path-based routing
create_listener_rules() {
    local listener_arn="$1"
    local target_groups_json="$2"
    
    # Create rules for each service (skip n8n as it's default)
    local priority=100
    echo "$target_groups_json" | jq -c '.[]' | while read -r service_obj; do
        local service_name port target_group_arn
        service_name=$(echo "$service_obj" | jq -r '.service')
        port=$(echo "$service_obj" | jq -r '.port')
        target_group_arn=$(echo "$service_obj" | jq -r '.target_group_arn')
        
        # Skip n8n as it's the default
        [ "$service_name" = "n8n" ] && continue
        
        # Create path-based rule
        local path_pattern="/${service_name}*"
        
        aws elbv2 create-rule \
            --listener-arn "$listener_arn" \
            --priority "$priority" \
            --conditions "Field=path-pattern,Values=$path_pattern" \
            --actions "Type=forward,TargetGroupArn=$target_group_arn" || {
            echo "WARNING: Failed to create rule for $service_name" >&2
        }
        
        priority=$((priority + 10))
    done
}

# =============================================================================
# MAIN ALB INFRASTRUCTURE SETUP
# =============================================================================

# Setup comprehensive ALB infrastructure
setup_alb_infrastructure() {
    local stack_name="${1:-$STACK_NAME}"
    local subnets_json="$2"  # JSON array of subnet objects
    local security_group_id="$3"
    local vpc_id="$4"
    local enable_https="${5:-false}"
    local certificate_arn="${6:-}"
    
    echo "Setting up ALB infrastructure for: $stack_name" >&2
    
    # Validate inputs
    if [ -z "$subnets_json" ] || [ -z "$security_group_id" ] || [ -z "$vpc_id" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "setup_alb_infrastructure requires subnets_json, security_group_id, and vpc_id"
    fi
    
    # Create Application Load Balancer
    local alb_arn
    alb_arn=$(create_application_load_balancer "$stack_name" "$subnets_json" "$security_group_id") || return 1
    echo "ALB created: $alb_arn" >&2
    
    # Get ALB DNS name
    local alb_dns
    alb_dns=$(get_alb_dns_name "$alb_arn")
    echo "ALB DNS: $alb_dns" >&2
    
    # Create target groups for AI services
    local target_groups_json
    target_groups_json=$(create_ai_service_target_groups "$stack_name" "$vpc_id") || return 1
    echo "Target groups created" >&2
    
    # Create listeners
    local listeners_info
    listeners_info=$(create_alb_listeners "$alb_arn" "$target_groups_json" "$enable_https" "$certificate_arn") || return 1
    echo "Listeners created" >&2
    
    # Return ALB information
    cat <<EOF
{
    "alb_arn": "$alb_arn",
    "alb_dns": "$alb_dns",
    "target_groups": $target_groups_json,
    "listeners": $listeners_info
}
EOF
}

# =============================================================================
# ALB UTILITIES
# =============================================================================

# Get ALB health status
get_alb_health_status() {
    local alb_arn="$1"
    
    # Get all target groups for this ALB
    local target_groups
    target_groups=$(aws elbv2 describe-target-groups \
        --load-balancer-arn "$alb_arn" \
        --query 'TargetGroups[*].TargetGroupArn' \
        --output text)
    
    # Check health of each target group
    for tg_arn in $target_groups; do
        local health_status
        health_status=$(aws elbv2 describe-target-health \
            --target-group-arn "$tg_arn" \
            --query 'TargetHealthDescriptions[*].{Target:Target.Id,Health:TargetHealth.State}' \
            --output json)
        
        echo "Target Group: $tg_arn"
        echo "$health_status" | jq -r '.[] | "\(.Target): \(.Health)"'
        echo ""
    done
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

# Cleanup ALB infrastructure
cleanup_alb_infrastructure() {
    local stack_name="${1:-$STACK_NAME}"
    
    echo "Cleaning up ALB infrastructure for: $stack_name" >&2
    
    # Get ALB ARN
    local alb_arn
    alb_arn=$(aws elbv2 describe-load-balancers \
        --query "LoadBalancers[?LoadBalancerName=='${stack_name}-alb'].LoadBalancerArn | [0]" \
        --output text 2>/dev/null | grep -v "None" || true)
    
    if [ -n "$alb_arn" ]; then
        # Delete listeners first
        local listeners
        listeners=$(aws elbv2 describe-listeners \
            --load-balancer-arn "$alb_arn" \
            --query 'Listeners[*].ListenerArn' \
            --output text 2>/dev/null || echo "")
        
        for listener_arn in $listeners; do
            if [ -n "$listener_arn" ] && [ "$listener_arn" != "None" ]; then
                aws elbv2 delete-listener --listener-arn "$listener_arn" || true
                echo "Deleted listener: $listener_arn" >&2
            fi
        done
        
        # Delete target groups
        local target_groups
        target_groups=$(aws elbv2 describe-target-groups \
            --load-balancer-arn "$alb_arn" \
            --query 'TargetGroups[*].TargetGroupArn' \
            --output text 2>/dev/null || echo "")
        
        for tg_arn in $target_groups; do
            if [ -n "$tg_arn" ] && [ "$tg_arn" != "None" ]; then
                aws elbv2 delete-target-group --target-group-arn "$tg_arn" || true
                echo "Deleted target group: $tg_arn" >&2
            fi
        done
        
        # Delete ALB
        aws elbv2 delete-load-balancer --load-balancer-arn "$alb_arn" || true
        echo "Deleted ALB: $alb_arn" >&2
    fi
    
    echo "ALB cleanup completed" >&2
}