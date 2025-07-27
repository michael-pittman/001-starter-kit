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
    default_tg_arn=$(echo "$target_groups_json" | jq -r '.[] | select(.service == "n8n") | .target_group_arn')\n    \n    if [ -z "$default_tg_arn" ] || [ "$default_tg_arn" = "null" ]; then\n        default_tg_arn=$(echo "$target_groups_json" | jq -r '.[0].target_group_arn')\n    fi\n    \n    # Create HTTP listener\n    local listener_arn\n    listener_arn=$(aws elbv2 create-listener \\\n        --load-balancer-arn "$alb_arn" \\\n        --protocol HTTP \\\n        --port 80 \\\n        --default-actions Type=forward,TargetGroupArn="$default_tg_arn" \\\n        --query 'Listeners[0].ListenerArn' \\\n        --output text) || {\n        throw_error $ERROR_AWS_API "Failed to create HTTP listener"\n    }\n    \n    # Create listener rules for different services\n    create_listener_rules "$listener_arn" "$target_groups_json"\n    \n    echo "$listener_arn"\n}\n\n# Create HTTPS listener\ncreate_https_listener() {\n    local alb_arn="$1"\n    local target_groups_json="$2"\n    local certificate_arn="$3"\n    \n    # Get default target group (n8n)\n    local default_tg_arn\n    default_tg_arn=$(echo "$target_groups_json" | jq -r '.[] | select(.service == "n8n") | .target_group_arn')\n    \n    if [ -z "$default_tg_arn" ] || [ "$default_tg_arn" = "null" ]; then\n        default_tg_arn=$(echo "$target_groups_json" | jq -r '.[0].target_group_arn')\n    fi\n    \n    # Create HTTPS listener\n    local listener_arn\n    listener_arn=$(aws elbv2 create-listener \\\n        --load-balancer-arn "$alb_arn" \\\n        --protocol HTTPS \\\n        --port 443 \\\n        --certificates CertificateArn="$certificate_arn" \\\n        --default-actions Type=forward,TargetGroupArn="$default_tg_arn" \\\n        --query 'Listeners[0].ListenerArn' \\\n        --output text) || {\n        return 1\n    }\n    \n    # Create listener rules for different services\n    create_listener_rules "$listener_arn" "$target_groups_json"\n    \n    echo "$listener_arn"\n}\n\n# Create listener rules for path-based routing\ncreate_listener_rules() {\n    local listener_arn="$1"\n    local target_groups_json="$2"\n    \n    echo "Creating listener rules for path-based routing" >&2\n    \n    # Create rules for each service\n    echo "$target_groups_json" | jq -c '.[]' | while read -r service_obj; do\n        local service_name\n        service_name=$(echo "$service_obj" | jq -r '.service')\n        local tg_arn\n        tg_arn=$(echo "$service_obj" | jq -r '.target_group_arn')\n        \n        # Skip default service (n8n)\n        [ "$service_name" = "n8n" ] && continue\n        \n        # Create rule for service path\n        local rule_priority\n        case "$service_name" in\n            "ollama") rule_priority=100 ;;\n            "qdrant") rule_priority=200 ;;\n            "crawl4ai") rule_priority=300 ;;\n            *) rule_priority=400 ;;\n        esac\n        \n        aws elbv2 create-rule \\\n            --listener-arn "$listener_arn" \\\n            --priority "$rule_priority" \\\n            --conditions Field=path-pattern,Values="/${service_name}/*" \\\n            --actions Type=forward,TargetGroupArn="$tg_arn" || {\n            echo "WARNING: Failed to create rule for $service_name" >&2\n        }\n        \n        echo "Created listener rule for $service_name" >&2\n    done\n}\n\n# =============================================================================\n# CLOUDFRONT DISTRIBUTION\n# =============================================================================\n\n# Create CloudFront distribution for ALB\ncreate_cloudfront_distribution() {\n    local alb_dns_name="$1"\n    local stack_name="${2:-$STACK_NAME}"\n    local enable_waf="${3:-false}"\n    \n    with_error_context "create_cloudfront_distribution" \\\n        _create_cloudfront_distribution_impl "$alb_dns_name" "$stack_name" "$enable_waf"\n}\n\n_create_cloudfront_distribution_impl() {\n    local alb_dns_name="$1"\n    local stack_name="$2"\n    local enable_waf="$3"\n    \n    echo "Creating CloudFront distribution for: $alb_dns_name" >&2\n    \n    # Create distribution configuration\n    local distribution_config\n    distribution_config=$(create_cloudfront_config "$alb_dns_name" "$stack_name" "$enable_waf")\n    \n    # Create CloudFront distribution\n    local distribution_id\n    distribution_id=$(aws cloudfront create-distribution \\\n        --distribution-config "$distribution_config" \\\n        --query 'Distribution.Id' \\\n        --output text) || {\n        throw_error $ERROR_AWS_API "Failed to create CloudFront distribution"\n    }\n    \n    echo "CloudFront distribution created: $distribution_id" >&2\n    echo "NOTE: Distribution deployment may take 15-20 minutes" >&2\n    \n    # Register distribution\n    register_resource "cloudfront_distributions" "$distribution_id" \\\n        "{\"alb_dns\": \"$alb_dns_name\", \"stack\": \"$stack_name\"}"\n    \n    echo "$distribution_id"\n}\n\n# Create CloudFront distribution configuration\ncreate_cloudfront_config() {\n    local alb_dns_name="$1"\n    local stack_name="$2"\n    local enable_waf="$3"\n    \n    local caller_reference\n    caller_reference="$stack_name-$(date +%s)"\n    \n    local config\n    config=$(cat <<EOF\n{\n    "CallerReference": "$caller_reference",\n    "Comment": "CloudFront distribution for $stack_name ALB",\n    "DefaultCacheBehavior": {\n        "TargetOriginId": "$stack_name-alb-origin",\n        "ViewerProtocolPolicy": "redirect-to-https",\n        "MinTTL": 0,\n        "ForwardedValues": {\n            "QueryString": true,\n            "Cookies": {\n                "Forward": "all"\n            },\n            "Headers": {\n                "Quantity": 1,\n                "Items": ["*"]\n            }\n        },\n        "TrustedSigners": {\n            "Enabled": false,\n            "Quantity": 0\n        }\n    },\n    "Origins": {\n        "Quantity": 1,\n        "Items": [\n            {\n                "Id": "$stack_name-alb-origin",\n                "DomainName": "$alb_dns_name",\n                "CustomOriginConfig": {\n                    "HTTPPort": 80,\n                    "HTTPSPort": 443,\n                    "OriginProtocolPolicy": "http-only"\n                }\n            }\n        ]\n    },\n    "Enabled": true,\n    "PriceClass": "PriceClass_100"\nEOF\n)\n    \n    # Add WAF if enabled\n    if [ "$enable_waf" = "true" ]; then\n        # Note: WAF integration would require additional setup\n        echo "WARNING: WAF integration not implemented yet" >&2\n    fi\n    \n    echo "$config"\n}\n\n# Get CloudFront distribution domain name\nget_cloudfront_domain_name() {\n    local distribution_id="$1"\n    \n    aws cloudfront get-distribution \\\n        --id "$distribution_id" \\\n        --query 'Distribution.DomainName' \\\n        --output text\n}\n\n# =============================================================================\n# ALB ORCHESTRATION\n# =============================================================================\n\n# Setup complete ALB infrastructure\nsetup_alb_infrastructure() {\n    local stack_name="${1:-$STACK_NAME}"\n    local subnets_json="$2"\n    local security_group_id="$3"\n    local vpc_id="$4"\n    local instance_id="${5:-}"\n    local enable_cloudfront="${6:-false}"\n    \n    echo "Setting up ALB infrastructure for: $stack_name" >&2\n    \n    # Create ALB\n    local alb_arn\n    alb_arn=$(create_application_load_balancer "$stack_name" "$subnets_json" "$security_group_id") || return 1\n    echo "ALB created: $alb_arn" >&2\n    \n    # Create target groups for AI services\n    local target_groups_json\n    target_groups_json=$(create_ai_service_target_groups "$stack_name" "$vpc_id") || return 1\n    echo "Target groups created" >&2\n    \n    # Create listeners\n    local listeners_json\n    listeners_json=$(create_alb_listeners "$alb_arn" "$target_groups_json") || return 1\n    echo "Listeners created" >&2\n    \n    # Register instance with target groups if provided\n    if [ -n "$instance_id" ]; then\n        echo "Registering instance with target groups..." >&2\n        echo "$target_groups_json" | jq -c '.[]' | while read -r service_obj; do\n            local tg_arn port\n            tg_arn=$(echo "$service_obj" | jq -r '.target_group_arn')\n            port=$(echo "$service_obj" | jq -r '.port')\n            \n            register_target "$tg_arn" "$instance_id" "$port" || {\n                echo "WARNING: Failed to register instance with target group" >&2\n            }\n        done\n    fi\n    \n    # Get ALB DNS name\n    local alb_dns\n    alb_dns=$(get_alb_dns_name "$alb_arn")\n    \n    # Create CloudFront distribution if enabled\n    local cloudfront_id=""\n    local cloudfront_domain=""\n    if [ "$enable_cloudfront" = "true" ]; then\n        echo "Creating CloudFront distribution..." >&2\n        cloudfront_id=$(create_cloudfront_distribution "$alb_dns" "$stack_name") || {\n            echo "WARNING: Failed to create CloudFront distribution" >&2\n        }\n        \n        if [ -n "$cloudfront_id" ]; then\n            cloudfront_domain=$(get_cloudfront_domain_name "$cloudfront_id")\n        fi\n    fi\n    \n    # Return ALB information\n    cat <<EOF\n{\n    "alb_arn": "$alb_arn",\n    "alb_dns": "$alb_dns",\n    "target_groups": $target_groups_json,\n    "listeners": $listeners_json,\n    "cloudfront_id": "$cloudfront_id",\n    "cloudfront_domain": "$cloudfront_domain"\n}\nEOF\n}\n\n# =============================================================================\n# CLEANUP FUNCTIONS\n# =============================================================================\n\n# Comprehensive ALB cleanup\ncleanup_alb_comprehensive() {\n    local stack_name="${1:-$STACK_NAME}"\n    \n    echo "Starting comprehensive ALB cleanup for: $stack_name" >&2\n    \n    # Delete CloudFront distributions\n    cleanup_cloudfront_distributions "$stack_name"\n    \n    # Delete ALBs\n    cleanup_load_balancers "$stack_name"\n    \n    # Delete target groups\n    cleanup_target_groups "$stack_name"\n    \n    echo "ALB cleanup completed" >&2\n}\n\n# Cleanup CloudFront distributions\ncleanup_cloudfront_distributions() {\n    local stack_name="$1"\n    \n    echo "Cleaning up CloudFront distributions..." >&2\n    \n    # Note: CloudFront cleanup is complex and requires disabling before deletion\n    # This is a simplified approach\n    local distributions\n    distributions=$(aws cloudfront list-distributions \\\n        --query "DistributionList.Items[?Comment && contains(Comment, '$stack_name')].Id" \\\n        --output text 2>/dev/null || echo "")\n    \n    for dist_id in $distributions; do\n        if [ -n "$dist_id" ] && [ "$dist_id" != "None" ]; then\n            echo "WARNING: CloudFront distribution $dist_id requires manual cleanup" >&2\n            echo "Run: aws cloudfront delete-distribution --id $dist_id --if-match ETAG" >&2\n        fi\n    done\n}\n\n# Cleanup load balancers\ncleanup_load_balancers() {\n    local stack_name="$1"\n    \n    echo "Cleaning up load balancers..." >&2\n    \n    local alb_arns\n    alb_arns=$(aws elbv2 describe-load-balancers \\\n        --query "LoadBalancers[?LoadBalancerName && contains(LoadBalancerName, '$stack_name')].LoadBalancerArn" \\\n        --output text 2>/dev/null || echo "")\n    \n    for alb_arn in $alb_arns; do\n        if [ -n "$alb_arn" ] && [ "$alb_arn" != "None" ]; then\n            aws elbv2 delete-load-balancer --load-balancer-arn "$alb_arn" || true\n            echo "Deleted load balancer: $alb_arn" >&2\n        fi\n    done\n}\n\n# Cleanup target groups\ncleanup_target_groups() {\n    local stack_name="$1"\n    \n    echo "Cleaning up target groups..." >&2\n    \n    local tg_arns\n    tg_arns=$(aws elbv2 describe-target-groups \\\n        --query "TargetGroups[?TargetGroupName && contains(TargetGroupName, '$stack_name')].TargetGroupArn" \\\n        --output text 2>/dev/null || echo "")\n    \n    for tg_arn in $tg_arns; do\n        if [ -n "$tg_arn" ] && [ "$tg_arn" != "None" ]; then\n            aws elbv2 delete-target-group --target-group-arn "$tg_arn" || true\n            echo "Deleted target group: $tg_arn" >&2\n        fi\n    done\n}