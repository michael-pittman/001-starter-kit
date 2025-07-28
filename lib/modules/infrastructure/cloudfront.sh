#!/bin/bash
# =============================================================================
# CloudFront CDN Infrastructure Module
# Manages CloudFront distributions for ALB and direct origins
# =============================================================================

# Prevent multiple sourcing
[ -n "${_CLOUDFRONT_SH_LOADED:-}" ] && return 0
_CLOUDFRONT_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"

# =============================================================================
# CLOUDFRONT DISTRIBUTION MANAGEMENT
# =============================================================================

# Create CloudFront distribution for ALB
create_cloudfront_distribution() {
    local stack_name="${1:-$STACK_NAME}"
    local origin_domain="$2"  # ALB DNS or custom domain
    local origin_type="${3:-alb}"  # alb, s3, custom
    local enable_compression="${4:-true}"
    local price_class="${5:-PriceClass_100}"  # PriceClass_100, PriceClass_200, PriceClass_All
    
    with_error_context "create_cloudfront_distribution" \
        _create_cloudfront_distribution_impl "$stack_name" "$origin_domain" "$origin_type" "$enable_compression" "$price_class"
}

_create_cloudfront_distribution_impl() {
    local stack_name="$1"
    local origin_domain="$2"
    local origin_type="$3"
    local enable_compression="$4"
    local price_class="$5"
    
    echo "Creating CloudFront distribution for: $stack_name (origin: $origin_domain)" >&2
    
    # Validate inputs
    if [ -z "$origin_domain" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "Origin domain is required"
    fi
    
    # Check if distribution already exists
    local existing_dist
    existing_dist=$(aws cloudfront list-distributions \
        --query "DistributionList.Items[?Comment=='${stack_name}-cdn'].Id | [0]" \
        --output text 2>/dev/null || true)
    
    if [ -n "$existing_dist" ] && [ "$existing_dist" != "None" ] && [ "$existing_dist" != "null" ]; then
        echo "CloudFront distribution already exists: $existing_dist" >&2
        echo "$existing_dist"
        return 0
    fi
    
    # Build origin configuration based on type
    local origin_config
    case "$origin_type" in
        alb)
            origin_config=$(cat <<EOF
{
    "Id": "${stack_name}-origin",
    "DomainName": "${origin_domain}",
    "CustomOriginConfig": {
        "HTTPPort": 80,
        "HTTPSPort": 443,
        "OriginProtocolPolicy": "http-only",
        "OriginSslProtocols": {
            "Quantity": 4,
            "Items": ["TLSv1", "TLSv1.1", "TLSv1.2", "SSLv3"]
        },
        "OriginReadTimeout": 60,
        "OriginKeepaliveTimeout": 5
    },
    "CustomHeaders": {
        "Quantity": 1,
        "Items": [{
            "HeaderName": "X-Forwarded-Host",
            "HeaderValue": "${stack_name}.cloudfront.net"
        }]
    }
}
EOF
)
            ;;
        s3)
            origin_config=$(cat <<EOF
{
    "Id": "${stack_name}-origin",
    "DomainName": "${origin_domain}",
    "S3OriginConfig": {
        "OriginAccessIdentity": ""
    }
}
EOF
)
            ;;
        custom)
            origin_config=$(cat <<EOF
{
    "Id": "${stack_name}-origin",
    "DomainName": "${origin_domain}",
    "CustomOriginConfig": {
        "HTTPPort": 80,
        "HTTPSPort": 443,
        "OriginProtocolPolicy": "https-only",
        "OriginSslProtocols": {
            "Quantity": 2,
            "Items": ["TLSv1.2", "TLSv1.3"]
        }
    }
}
EOF
)
            ;;
    esac
    
    # Build cache behaviors for AI services
    local cache_behaviors=$(build_ai_service_cache_behaviors "$stack_name")
    
    # Create distribution configuration
    local dist_config=$(cat <<EOF
{
    "CallerReference": "${stack_name}-$(date +%s)",
    "Comment": "${stack_name}-cdn",
    "Enabled": true,
    "Origins": {
        "Quantity": 1,
        "Items": [$origin_config]
    },
    "DefaultRootObject": "",
    "DefaultCacheBehavior": {
        "TargetOriginId": "${stack_name}-origin",
        "ViewerProtocolPolicy": "redirect-to-https",
        "AllowedMethods": {
            "Quantity": 7,
            "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
            "CachedMethods": {
                "Quantity": 2,
                "Items": ["GET", "HEAD"]
            }
        },
        "ForwardedValues": {
            "QueryString": true,
            "Cookies": { "Forward": "all" },
            "Headers": {
                "Quantity": 3,
                "Items": ["Host", "Origin", "Access-Control-Request-Headers"]
            }
        },
        "TrustedSigners": {
            "Enabled": false,
            "Quantity": 0
        },
        "MinTTL": 0,
        "DefaultTTL": 0,
        "MaxTTL": 31536000,
        "Compress": $enable_compression
    },
    "CacheBehaviors": $cache_behaviors,
    "CustomErrorResponses": {
        "Quantity": 2,
        "Items": [
            {
                "ErrorCode": 403,
                "ResponsePagePath": "",
                "ResponseCode": "",
                "ErrorCachingMinTTL": 10
            },
            {
                "ErrorCode": 404,
                "ResponsePagePath": "",
                "ResponseCode": "",
                "ErrorCachingMinTTL": 10
            }
        ]
    },
    "PriceClass": "$price_class",
    "WebACLId": ""
}
EOF
)
    
    # Create distribution
    local dist_output
    dist_output=$(aws cloudfront create-distribution \
        --distribution-config "$dist_config" \
        --output json) || {
        throw_error $ERROR_AWS_API "Failed to create CloudFront distribution"
    }
    
    local dist_id
    dist_id=$(echo "$dist_output" | jq -r '.Distribution.Id')
    
    # Add tags
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text)
    
    aws cloudfront tag-resource \
        --resource "arn:aws:cloudfront::${account_id}:distribution/${dist_id}" \
        --tags "Items=$(tags_to_cloudfront_format "$(generate_tags "$stack_name" '{"Service": "CloudFront", "Type": "CDN"}')")" || true
    
    # Register distribution
    register_resource "cloudfront_distributions" "$dist_id" \
        "{\"domain\": \"$(echo "$dist_output" | jq -r '.Distribution.DomainName')\", \"comment\": \"${stack_name}-cdn\"}"
    
    echo "CloudFront distribution created: $dist_id" >&2
    echo "$dist_id"
}

# Build cache behaviors for AI services
build_ai_service_cache_behaviors() {
    local stack_name="$1"
    
    # Define path patterns for different services
    cat <<EOF
{
    "Quantity": 4,
    "Items": [
        {
            "PathPattern": "/n8n/*",
            "TargetOriginId": "${stack_name}-origin",
            "ViewerProtocolPolicy": "redirect-to-https",
            "AllowedMethods": {
                "Quantity": 7,
                "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
                "CachedMethods": {
                    "Quantity": 2,
                    "Items": ["GET", "HEAD"]
                }
            },
            "ForwardedValues": {
                "QueryString": true,
                "Cookies": { "Forward": "all" },
                "Headers": { "Quantity": 1, "Items": ["*"] }
            },
            "TrustedSigners": { "Enabled": false, "Quantity": 0 },
            "MinTTL": 0,
            "DefaultTTL": 0,
            "MaxTTL": 0,
            "Compress": false
        },
        {
            "PathPattern": "/api/*",
            "TargetOriginId": "${stack_name}-origin",
            "ViewerProtocolPolicy": "redirect-to-https",
            "AllowedMethods": {
                "Quantity": 7,
                "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
                "CachedMethods": {
                    "Quantity": 2,
                    "Items": ["GET", "HEAD"]
                }
            },
            "ForwardedValues": {
                "QueryString": true,
                "Cookies": { "Forward": "none" },
                "Headers": { "Quantity": 3, "Items": ["Authorization", "Content-Type", "Accept"] }
            },
            "TrustedSigners": { "Enabled": false, "Quantity": 0 },
            "MinTTL": 0,
            "DefaultTTL": 300,
            "MaxTTL": 3600,
            "Compress": true
        },
        {
            "PathPattern": "/static/*",
            "TargetOriginId": "${stack_name}-origin",
            "ViewerProtocolPolicy": "redirect-to-https",
            "AllowedMethods": {
                "Quantity": 3,
                "Items": ["GET", "HEAD", "OPTIONS"],
                "CachedMethods": {
                    "Quantity": 2,
                    "Items": ["GET", "HEAD"]
                }
            },
            "ForwardedValues": {
                "QueryString": false,
                "Cookies": { "Forward": "none" },
                "Headers": { "Quantity": 0 }
            },
            "TrustedSigners": { "Enabled": false, "Quantity": 0 },
            "MinTTL": 0,
            "DefaultTTL": 86400,
            "MaxTTL": 31536000,
            "Compress": true
        },
        {
            "PathPattern": "/ws/*",
            "TargetOriginId": "${stack_name}-origin",
            "ViewerProtocolPolicy": "redirect-to-https",
            "AllowedMethods": {
                "Quantity": 7,
                "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
                "CachedMethods": {
                    "Quantity": 2,
                    "Items": ["GET", "HEAD"]
                }
            },
            "ForwardedValues": {
                "QueryString": true,
                "Cookies": { "Forward": "all" },
                "Headers": { "Quantity": 1, "Items": ["*"] }
            },
            "TrustedSigners": { "Enabled": false, "Quantity": 0 },
            "MinTTL": 0,
            "DefaultTTL": 0,
            "MaxTTL": 0,
            "Compress": false
        }
    ]
}
EOF
}

# =============================================================================
# CLOUDFRONT UTILITIES
# =============================================================================

# Get CloudFront distribution info
get_cloudfront_distribution_info() {
    local dist_id="$1"
    
    aws cloudfront get-distribution \
        --id "$dist_id" \
        --query 'Distribution.{Id:Id,DomainName:DomainName,Status:Status,Enabled:DistributionConfig.Enabled}' \
        --output json
}

# Wait for CloudFront distribution to be deployed
wait_for_cloudfront_deployment() {
    local dist_id="$1"
    local max_wait="${2:-1800}"  # 30 minutes default
    
    echo "Waiting for CloudFront distribution to deploy (this may take 15-20 minutes)..." >&2
    
    local start_time=$(date +%s)
    local status="InProgress"
    
    while [ "$status" = "InProgress" ]; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -gt $max_wait ]; then
            throw_error $ERROR_TIMEOUT "CloudFront deployment timed out after ${max_wait}s"
        fi
        
        status=$(aws cloudfront get-distribution \
            --id "$dist_id" \
            --query 'Distribution.Status' \
            --output text)
        
        if [ "$status" = "Deployed" ]; then
            echo "CloudFront distribution deployed successfully" >&2
            return 0
        fi
        
        echo -n "." >&2
        sleep 30
    done
}

# Enable/disable CloudFront distribution
toggle_cloudfront_distribution() {
    local dist_id="$1"
    local enabled="${2:-true}"
    
    echo "Setting CloudFront distribution enabled=$enabled" >&2
    
    # Get current config and ETag
    local dist_data
    dist_data=$(aws cloudfront get-distribution-config --id "$dist_id" --output json)
    
    local etag
    etag=$(echo "$dist_data" | jq -r '.ETag')
    
    # Update enabled status
    local config
    config=$(echo "$dist_data" | jq ".DistributionConfig.Enabled = $enabled | .DistributionConfig")
    
    # Update distribution
    aws cloudfront update-distribution \
        --id "$dist_id" \
        --if-match "$etag" \
        --distribution-config "$config" \
        --query 'Distribution.Id' \
        --output text
}

# =============================================================================
# CLOUDFRONT + ALB INTEGRATION
# =============================================================================

# Setup CloudFront for ALB with AI services
setup_cloudfront_for_alb() {
    local stack_name="${1:-$STACK_NAME}"
    local alb_dns="$2"
    local enable_waf="${3:-false}"
    
    echo "Setting up CloudFront distribution for ALB: $alb_dns" >&2
    
    # Create CloudFront distribution
    local dist_id
    dist_id=$(create_cloudfront_distribution "$stack_name" "$alb_dns" "alb" "true" "PriceClass_100") || return 1
    
    # Get distribution info
    local dist_info
    dist_info=$(get_cloudfront_distribution_info "$dist_id")
    
    local domain_name
    domain_name=$(echo "$dist_info" | jq -r '.DomainName')
    
    # Wait for initial deployment
    wait_for_cloudfront_deployment "$dist_id" 300  # Wait up to 5 minutes for initial status
    
    # Return distribution information
    cat <<EOF
{
    "distribution_id": "$dist_id",
    "domain_name": "$domain_name",
    "url": "https://$domain_name",
    "status": "deploying"
}
EOF
}

# =============================================================================
# CLOUDFRONT INVALIDATION
# =============================================================================

# Create CloudFront invalidation
create_cloudfront_invalidation() {
    local dist_id="$1"
    local paths="${2:-/*}"  # Default to invalidate everything
    
    echo "Creating CloudFront invalidation for: $dist_id" >&2
    
    # Create invalidation
    local invalidation_id
    invalidation_id=$(aws cloudfront create-invalidation \
        --distribution-id "$dist_id" \
        --paths "$paths" \
        --query 'Invalidation.Id' \
        --output text)
    
    echo "Invalidation created: $invalidation_id" >&2
    echo "$invalidation_id"
}

# =============================================================================
# CLEANUP FUNCTIONS
# =============================================================================

# Cleanup CloudFront distributions
cleanup_cloudfront_distributions() {
    local stack_name="${1:-$STACK_NAME}"
    
    echo "Cleaning up CloudFront distributions for: $stack_name" >&2
    
    # Find distributions by comment
    local dist_ids
    dist_ids=$(aws cloudfront list-distributions \
        --query "DistributionList.Items[?Comment=='${stack_name}-cdn'].Id" \
        --output text 2>/dev/null || echo "")
    
    for dist_id in $dist_ids; do
        if [ -n "$dist_id" ] && [ "$dist_id" != "None" ]; then
            echo "Disabling CloudFront distribution: $dist_id" >&2
            
            # First disable the distribution
            toggle_cloudfront_distribution "$dist_id" "false" || true
            
            # Wait for distribution to be deployed (disabled state)
            wait_for_cloudfront_deployment "$dist_id" 600 || true
            
            # Get ETag for deletion
            local etag
            etag=$(aws cloudfront get-distribution-config \
                --id "$dist_id" \
                --query 'ETag' \
                --output text)
            
            # Delete distribution
            aws cloudfront delete-distribution \
                --id "$dist_id" \
                --if-match "$etag" || true
            
            echo "Deleted CloudFront distribution: $dist_id" >&2
        fi
    done
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Convert tags to CloudFront format
tags_to_cloudfront_format() {
    local tags_json="$1"
    
    echo "$tags_json" | jq -c '[.[] | {Key: .Key, Value: .Value}]'
}

# Export functions
export -f create_cloudfront_distribution
export -f get_cloudfront_distribution_info
export -f wait_for_cloudfront_deployment
export -f setup_cloudfront_for_alb
export -f create_cloudfront_invalidation
export -f cleanup_cloudfront_distributions