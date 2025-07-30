#!/usr/bin/env bash
# =============================================================================
# CloudFront Infrastructure Module
# Uniform CloudFront distribution creation and management
# =============================================================================

# Prevent multiple sourcing
[ -n "${_INFRASTRUCTURE_CLOUDFRONT_SH_LOADED:-}" ] && return 0
_INFRASTRUCTURE_CLOUDFRONT_SH_LOADED=1

# =============================================================================
# CLOUDFRONT CONFIGURATION
# =============================================================================

# CloudFront configuration defaults
CLOUDFRONT_DEFAULT_PRICE_CLASS="PriceClass_100"
CLOUDFRONT_DEFAULT_HTTP_VERSION="http2"
CLOUDFRONT_DEFAULT_IPV6_ENABLED=true
CLOUDFRONT_DEFAULT_COMPRESS=true
CLOUDFRONT_DEFAULT_DEFAULT_ROOT_OBJECT="index.html"
CLOUDFRONT_DEFAULT_ERROR_PAGE_PATH="/error.html"

# Cache behavior defaults
CACHE_BEHAVIOR_DEFAULT_VIEWER_PROTOCOL_POLICY="redirect-to-https"
CACHE_BEHAVIOR_DEFAULT_ALLOWED_METHODS="GET,HEAD,OPTIONS,PUT,POST,PATCH,DELETE"
CACHE_BEHAVIOR_DEFAULT_CACHED_METHODS="GET,HEAD"
CACHE_BEHAVIOR_DEFAULT_TTL=86400
CACHE_BEHAVIOR_DEFAULT_MIN_TTL=0
CACHE_BEHAVIOR_DEFAULT_MAX_TTL=31536000

# =============================================================================
# CLOUDFRONT VALIDATION FUNCTIONS
# =============================================================================

# Validate existing CloudFront distribution
validate_existing_cloudfront() {
    local distribution_id="$1"
    
    log_info "Validating existing CloudFront distribution: $distribution_id" "CLOUDFRONT"
    
    if [[ -z "$distribution_id" ]]; then
        log_error "Distribution ID is required for validation" "CLOUDFRONT"
        return 1
    fi
    
    # Check if distribution exists
    local distribution_info
    distribution_info=$(aws cloudfront get-distribution \
        --id "$distribution_id" \
        --output json 2>/dev/null)
    
    if [[ $? -ne 0 ]]; then
        log_error "CloudFront distribution not found or inaccessible: $distribution_id" "CLOUDFRONT"
        return 1
    fi
    
    # Validate distribution state
    local distribution_status
    distribution_status=$(echo "$distribution_info" | jq -r '.Distribution.Status')
    if [[ "$distribution_status" != "Deployed" ]]; then
        log_error "CloudFront distribution is not in deployed state: $distribution_status" "CLOUDFRONT"
        return 1
    fi
    
    # Validate distribution is enabled
    local distribution_enabled
    distribution_enabled=$(echo "$distribution_info" | jq -r '.Distribution.DistributionConfig.Enabled')
    if [[ "$distribution_enabled" != "true" ]]; then
        log_error "CloudFront distribution is not enabled" "CLOUDFRONT"
        return 1
    fi
    
    log_info "CloudFront distribution validation successful: $distribution_id" "CLOUDFRONT"
    return 0
}

# =============================================================================
# CLOUDFRONT CREATION FUNCTIONS
# =============================================================================

# Create CloudFront distribution
create_cloudfront_distribution() {
    local stack_name="$1"
    local origin_domain="$2"
    local origin_id="${3:-}"
    local certificate_arn="${4:-}"
    local custom_domain="${5:-}"
    
    # Check for existing CloudFront distribution from environment or variable store
    local existing_distribution_id="${EXISTING_CLOUDFRONT_ID:-}"
    if [[ -z "$existing_distribution_id" ]]; then
        existing_distribution_id=$(get_variable "CLOUDFRONT_DISTRIBUTION_ID" "$VARIABLE_SCOPE_STACK")
    fi
    
    if [[ -n "$existing_distribution_id" ]]; then
        log_info "Using existing CloudFront distribution: $existing_distribution_id" "CLOUDFRONT"
        
        # Validate existing distribution
        if ! validate_existing_cloudfront "$existing_distribution_id"; then
            log_error "Existing CloudFront validation failed: $existing_distribution_id" "CLOUDFRONT"
            return 1
        fi
        
        # Register existing distribution
        register_resource "cloudfront_distributions" "$existing_distribution_id" "existing"
        
        # Extract distribution details
        local distribution_info
        distribution_info=$(aws cloudfront get-distribution \
            --id "$existing_distribution_id" \
            --query 'Distribution' \
            --output json)
        
        local distribution_domain
        distribution_domain=$(echo "$distribution_info" | jq -r '.DomainName')
        
        # Set variables for downstream use
        set_variable "CLOUDFRONT_DISTRIBUTION_DOMAIN" "$distribution_domain" "$VARIABLE_SCOPE_STACK"
        
        echo "$existing_distribution_id"
        return 0
    fi
    
    log_info "Creating CloudFront distribution for stack: $stack_name" "CLOUDFRONT"
    
    # Generate distribution name
    local distribution_name
    distribution_name=$(generate_resource_name "cloudfront" "$stack_name")
    
    # Validate distribution name
    if ! validate_resource_name "$distribution_name" "cloudfront"; then
        return 1
    fi
    
    # Validate origin domain
    if [[ -z "$origin_domain" ]]; then
        log_error "Origin domain is required for CloudFront distribution" "CLOUDFRONT"
        return 1
    fi
    
    # Set default origin ID if not provided
    if [[ -z "$origin_id" ]]; then
        origin_id="$origin_domain"
    fi
    
    # Create distribution configuration
    local distribution_config
    distribution_config=$(create_distribution_config "$distribution_name" "$origin_domain" "$origin_id" "$certificate_arn" "$custom_domain")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create distribution configuration" "CLOUDFRONT"
        return 1
    fi
    
    # Create CloudFront distribution
    local distribution_output
    distribution_output=$(aws cloudfront create-distribution \
        --distribution-config "$distribution_config" \
        --output json \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create CloudFront distribution: $distribution_output" "CLOUDFRONT"
        return 1
    fi
    
    # Extract distribution ID and domain name
    local distribution_id
    distribution_id=$(echo "$distribution_output" | jq -r '.Distribution.Id')
    
    local distribution_domain
    distribution_domain=$(echo "$distribution_output" | jq -r '.Distribution.DomainName')
    
    # Store distribution information
    set_variable "CLOUDFRONT_DISTRIBUTION_ID" "$distribution_id" "$VARIABLE_SCOPE_STACK"
    set_variable "CLOUDFRONT_DISTRIBUTION_DOMAIN" "$distribution_domain" "$VARIABLE_SCOPE_STACK"
    
    # Register new distribution
    register_resource "cloudfront_distributions" "$distribution_id" "created"
    
    # Wait for distribution to be deployed
    log_info "Waiting for CloudFront distribution to be deployed: $distribution_id" "CLOUDFRONT"
    if ! wait_for_distribution_deployed "$distribution_id"; then
        log_error "CloudFront distribution failed to deploy" "CLOUDFRONT"
        return 1
    fi
    
    log_info "CloudFront distribution created successfully: $distribution_id" "CLOUDFRONT"
    echo "$distribution_id"
    return 0
}

# Create distribution configuration
create_distribution_config() {
    local distribution_name="$1"
    local origin_domain="$2"
    local origin_id="$3"
    local certificate_arn="$4"
    local custom_domain="$5"
    
    log_info "Creating distribution configuration for: $distribution_name" "CLOUDFRONT"
    
    # Create origin configuration
    local origin_config
    origin_config=$(create_origin_config "$origin_domain" "$origin_id")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Create default cache behavior
    local cache_behavior_config
    cache_behavior_config=$(create_default_cache_behavior "$origin_id")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Create custom error responses
    local error_responses_config
    error_responses_config=$(create_error_responses_config)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Build distribution configuration
    local distribution_config
    distribution_config=$(cat <<EOF
{
    "CallerReference": "$(date +%s)",
    "Comment": "CloudFront distribution for $distribution_name",
    "DefaultRootObject": "$CLOUDFRONT_DEFAULT_DEFAULT_ROOT_OBJECT",
    "Origins": {
        "Quantity": 1,
        "Items": [$origin_config]
    },
    "DefaultCacheBehavior": $cache_behavior_config,
    "CacheBehaviors": {
        "Quantity": 0,
        "Items": []
    },
    "CustomErrorResponses": $error_responses_config,
    "Logging": {
        "Enabled": false,
        "IncludeCookies": false,
        "Bucket": "",
        "Prefix": ""
    },
    "PriceClass": "$CLOUDFRONT_DEFAULT_PRICE_CLASS",
    "Enabled": true,
    "ViewerCertificate": $(create_viewer_certificate_config "$certificate_arn" "$custom_domain"),
    "Restrictions": {
        "GeoRestriction": {
            "RestrictionType": "none",
            "Quantity": 0,
            "Items": []
        }
    },
    "WebACLId": "",
    "HttpVersion": "$CLOUDFRONT_DEFAULT_HTTP_VERSION",
    "IsIPV6Enabled": $CLOUDFRONT_DEFAULT_IPV6_ENABLED,
    "DefaultRootObject": "$CLOUDFRONT_DEFAULT_DEFAULT_ROOT_OBJECT",
    "Compress": $CLOUDFRONT_DEFAULT_COMPRESS
}
EOF
)
    
    log_info "Distribution configuration created successfully" "CLOUDFRONT"
    echo "$distribution_config"
    return 0
}

# Create origin configuration
create_origin_config() {
    local origin_domain="$1"
    local origin_id="$2"
    
    log_info "Creating origin configuration for domain: $origin_domain" "CLOUDFRONT"
    
    # Determine origin protocol based on domain
    local origin_protocol="https-only"
    if [[ "$origin_domain" =~ ^http:// ]]; then
        origin_protocol="http-only"
    fi
    
    # Remove protocol from domain for origin
    local clean_domain
    clean_domain=$(echo "$origin_domain" | sed 's|^https\?://||')
    
    local origin_config
    origin_config=$(cat <<EOF
{
    "Id": "$origin_id",
    "DomainName": "$clean_domain",
    "OriginPath": "",
    "CustomHeaders": {
        "Quantity": 0,
        "Items": []
    },
    "S3OriginConfig": null,
    "CustomOriginConfig": {
        "HTTPPort": 80,
        "HTTPSPort": 443,
        "OriginProtocolPolicy": "$origin_protocol",
        "OriginSslProtocols": {
            "Quantity": 1,
            "Items": ["TLSv1.2"]
        },
        "OriginReadTimeout": 30,
        "OriginKeepaliveTimeout": 5
    },
    "ConnectionAttempts": 3,
    "ConnectionTimeout": 10,
    "OriginShield": {
        "Enabled": false
    }
}
EOF
)
    
    log_info "Origin configuration created successfully" "CLOUDFRONT"
    echo "$origin_config"
    return 0
}

# Create default cache behavior
create_default_cache_behavior() {
    local origin_id="$1"
    
    log_info "Creating default cache behavior for origin: $origin_id" "CLOUDFRONT"
    
    local cache_behavior_config
    cache_behavior_config=$(cat <<EOF
{
    "TargetOriginId": "$origin_id",
    "ViewerProtocolPolicy": "$CACHE_BEHAVIOR_DEFAULT_VIEWER_PROTOCOL_POLICY",
    "TrustedSigners": {
        "Enabled": false,
        "Quantity": 0,
        "Items": []
    },
    "TrustedKeyGroups": {
        "Enabled": false,
        "Quantity": 0,
        "Items": []
    },
    "ViewerCertificate": {
        "CloudFrontDefaultCertificate": true,
        "MinimumProtocolVersion": "TLSv1",
        "CertificateSource": "cloudfront"
    },
    "MinTTL": $CACHE_BEHAVIOR_DEFAULT_MIN_TTL,
    "DefaultTTL": $CACHE_BEHAVIOR_DEFAULT_TTL,
    "MaxTTL": $CACHE_BEHAVIOR_DEFAULT_MAX_TTL,
    "Compress": $CLOUDFRONT_DEFAULT_COMPRESS,
    "SmoothStreaming": false,
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
        "Cookies": {
            "Forward": "all"
        },
        "Headers": {
            "Quantity": 0,
            "Items": []
        },
        "QueryStringCacheKeys": {
            "Quantity": 0,
            "Items": []
        }
    },
    "LambdaFunctionAssociations": {
        "Quantity": 0,
        "Items": []
    },
    "FunctionAssociations": {
        "Quantity": 0,
        "Items": []
    },
    "FieldLevelEncryptionId": ""
}
EOF
)
    
    log_info "Default cache behavior created successfully" "CLOUDFRONT"
    echo "$cache_behavior_config"
    return 0
}

# Create error responses configuration
create_error_responses_config() {
    log_info "Creating error responses configuration" "CLOUDFRONT"
    
    local error_responses_config
    error_responses_config=$(cat <<EOF
{
    "Quantity": 2,
    "Items": [
        {
            "ErrorCode": 403,
            "ResponsePagePath": "$CLOUDFRONT_DEFAULT_ERROR_PAGE_PATH",
            "ResponseCode": "403",
            "ErrorCachingMinTTL": 300
        },
        {
            "ErrorCode": 404,
            "ResponsePagePath": "$CLOUDFRONT_DEFAULT_ERROR_PAGE_PATH",
            "ResponseCode": "404",
            "ErrorCachingMinTTL": 300
        }
    ]
}
EOF
)
    
    log_info "Error responses configuration created successfully" "CLOUDFRONT"
    echo "$error_responses_config"
    return 0
}

# Create viewer certificate configuration
create_viewer_certificate_config() {
    local certificate_arn="$1"
    local custom_domain="$2"
    
    log_info "Creating viewer certificate configuration" "CLOUDFRONT"
    
    if [[ -n "$certificate_arn" && -n "$custom_domain" ]]; then
        # Use custom certificate
        local viewer_cert_config
        viewer_cert_config=$(cat <<EOF
{
    "ACMCertificateArn": "$certificate_arn",
    "SSLSupportMethod": "sni-only",
    "MinimumProtocolVersion": "TLSv1.2_2021",
    "Certificate": "$certificate_arn",
    "CertificateSource": "acm",
    "CloudFrontDefaultCertificate": false,
    "IAMCertificateId": ""
}
EOF
)
    else
        # Use CloudFront default certificate
        local viewer_cert_config
        viewer_cert_config=$(cat <<EOF
{
    "CloudFrontDefaultCertificate": true,
    "MinimumProtocolVersion": "TLSv1",
    "CertificateSource": "cloudfront"
}
EOF
)
    fi
    
    log_info "Viewer certificate configuration created successfully" "CLOUDFRONT"
    echo "$viewer_cert_config"
    return 0
}

# =============================================================================
# CLOUDFRONT MANAGEMENT FUNCTIONS
# =============================================================================

# Wait for distribution to be deployed
wait_for_distribution_deployed() {
    local distribution_id="$1"
    local timeout="${2:-1800}"  # 30 minutes default
    
    log_info "Waiting for CloudFront distribution to be deployed: $distribution_id" "CLOUDFRONT"
    
    local start_time
    start_time=$(date +%s)
    
    while true; do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout ]]; then
            log_error "Timeout waiting for CloudFront distribution to be deployed" "CLOUDFRONT"
            return 1
        fi
        
        # Get distribution status
        local distribution_status
        distribution_status=$(aws cloudfront get-distribution \
            --id "$distribution_id" \
            --query 'Distribution.Status' \
            --output text \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE" 2>/dev/null)
        
        if [[ $? -eq 0 && "$distribution_status" == "Deployed" ]]; then
            log_info "CloudFront distribution deployed successfully" "CLOUDFRONT"
            return 0
        fi
        
        log_info "Waiting for CloudFront distribution to be deployed... (status: $distribution_status)" "CLOUDFRONT"
        sleep 30
    done
}

# Invalidate CloudFront cache
invalidate_cloudfront_cache() {
    local distribution_id="$1"
    local paths="${2:-/*}"
    
    log_info "Invalidating CloudFront cache for distribution: $distribution_id" "CLOUDFRONT"
    
    # Validate distribution ID
    if [[ -z "$distribution_id" ]]; then
        log_error "Distribution ID is required for cache invalidation" "CLOUDFRONT"
        return 1
    fi
    
    # Create invalidation
    local invalidation_output
    invalidation_output=$(aws cloudfront create-invalidation \
        --distribution-id "$distribution_id" \
        --paths "$paths" \
        --output json \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create CloudFront invalidation: $invalidation_output" "CLOUDFRONT"
        return 1
    fi
    
    local invalidation_id
    invalidation_id=$(echo "$invalidation_output" | jq -r '.Invalidation.Id')
    
    log_info "CloudFront invalidation created successfully: $invalidation_id" "CLOUDFRONT"
    echo "$invalidation_id"
    return 0
}

# Wait for invalidation to complete
wait_for_invalidation_complete() {
    local distribution_id="$1"
    local invalidation_id="$2"
    local timeout="${3:-1800}"  # 30 minutes default
    
    log_info "Waiting for CloudFront invalidation to complete: $invalidation_id" "CLOUDFRONT"
    
    local start_time
    start_time=$(date +%s)
    
    while true; do
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout ]]; then
            log_error "Timeout waiting for CloudFront invalidation to complete" "CLOUDFRONT"
            return 1
        fi
        
        # Get invalidation status
        local invalidation_status
        invalidation_status=$(aws cloudfront get-invalidation \
            --distribution-id "$distribution_id" \
            --id "$invalidation_id" \
            --query 'Invalidation.Status' \
            --output text \
            --region "$AWS_REGION" \
            --profile "$AWS_PROFILE" 2>/dev/null)
        
        if [[ $? -eq 0 && "$invalidation_status" == "Completed" ]]; then
            log_info "CloudFront invalidation completed successfully" "CLOUDFRONT"
            return 0
        fi
        
        log_info "Waiting for CloudFront invalidation to complete... (status: $invalidation_status)" "CLOUDFRONT"
        sleep 30
    done
}

# =============================================================================
# CLOUDFRONT UTILITY FUNCTIONS
# =============================================================================

# Get CloudFront distribution information
get_cloudfront_distribution_info() {
    local distribution_id="$1"
    
    log_info "Getting CloudFront distribution information: $distribution_id" "CLOUDFRONT"
    
    local distribution_info
    distribution_info=$(aws cloudfront get-distribution \
        --id "$distribution_id" \
        --output json \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get CloudFront distribution information: $distribution_info" "CLOUDFRONT"
        return 1
    fi
    
    echo "$distribution_info"
    return 0
}

# List CloudFront distributions
list_cloudfront_distributions() {
    log_info "Listing CloudFront distributions" "CLOUDFRONT"
    
    local distributions
    distributions=$(aws cloudfront list-distributions \
        --output json \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to list CloudFront distributions: $distributions" "CLOUDFRONT"
        return 1
    fi
    
    echo "$distributions"
    return 0
}

# Get CloudFront distribution domain
get_cloudfront_domain() {
    local distribution_id="$1"
    
    log_info "Getting CloudFront distribution domain: $distribution_id" "CLOUDFRONT"
    
    local distribution_info
    distribution_info=$(get_cloudfront_distribution_info "$distribution_id")
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    local domain_name
    domain_name=$(echo "$distribution_info" | jq -r '.Distribution.DomainName')
    
    if [[ -z "$domain_name" || "$domain_name" == "null" ]]; then
        log_error "Failed to extract domain name from distribution info" "CLOUDFRONT"
        return 1
    fi
    
    log_info "CloudFront distribution domain: $domain_name" "CLOUDFRONT"
    echo "$domain_name"
    return 0
}

# =============================================================================
# CLOUDFRONT CLEANUP FUNCTIONS
# =============================================================================

# Delete CloudFront distribution
delete_cloudfront_distribution() {
    local distribution_id="$1"
    
    log_info "Deleting CloudFront distribution: $distribution_id" "CLOUDFRONT"
    
    # Validate distribution ID
    if [[ -z "$distribution_id" ]]; then
        log_error "Distribution ID is required for deletion" "CLOUDFRONT"
        return 1
    fi
    
    # Get current distribution configuration
    local distribution_info
    distribution_info=$(get_cloudfront_distribution_info "$distribution_id")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get distribution info for deletion" "CLOUDFRONT"
        return 1
    fi
    
    # Extract ETag and configuration
    local etag
    etag=$(echo "$distribution_info" | jq -r '.ETag')
    
    local distribution_config
    distribution_config=$(echo "$distribution_info" | jq '.Distribution.DistributionConfig')
    
    # Disable the distribution
    local disabled_config
    disabled_config=$(echo "$distribution_config" | jq '.Enabled = false')
    
    # Update distribution to disable it
    local update_output
    update_output=$(aws cloudfront update-distribution \
        --id "$distribution_id" \
        --distribution-config "$disabled_config" \
        --if-match "$etag" \
        --output json \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to disable CloudFront distribution: $update_output" "CLOUDFRONT"
        return 1
    fi
    
    # Wait for distribution to be deployed
    log_info "Waiting for CloudFront distribution to be disabled" "CLOUDFRONT"
    if ! wait_for_distribution_deployed "$distribution_id"; then
        log_error "Failed to disable CloudFront distribution" "CLOUDFRONT"
        return 1
    fi
    
    # Get new ETag for deletion
    local new_distribution_info
    new_distribution_info=$(get_cloudfront_distribution_info "$distribution_id")
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get updated distribution info for deletion" "CLOUDFRONT"
        return 1
    fi
    
    local new_etag
    new_etag=$(echo "$new_distribution_info" | jq -r '.ETag')
    
    # Delete the distribution
    local delete_output
    delete_output=$(aws cloudfront delete-distribution \
        --id "$distribution_id" \
        --if-match "$new_etag" \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to delete CloudFront distribution: $delete_output" "CLOUDFRONT"
        return 1
    fi
    
    log_info "CloudFront distribution deleted successfully: $distribution_id" "CLOUDFRONT"
    return 0
}

# =============================================================================
# CLOUDFRONT MONITORING FUNCTIONS
# =============================================================================

# Get CloudFront metrics
get_cloudfront_metrics() {
    local distribution_id="$1"
    local metric_name="$2"
    local start_time="$3"
    local end_time="$4"
    local period="${5:-300}"
    
    log_info "Getting CloudFront metrics for distribution: $distribution_id" "CLOUDFRONT"
    
    # Validate parameters
    if [[ -z "$distribution_id" || -z "$metric_name" || -z "$start_time" || -z "$end_time" ]]; then
        log_error "Distribution ID, metric name, start time, and end time are required" "CLOUDFRONT"
        return 1
    fi
    
    # Get metrics from CloudWatch
    local metrics_output
    metrics_output=$(aws cloudwatch get-metric-statistics \
        --namespace "AWS/CloudFront" \
        --metric-name "$metric_name" \
        --dimensions "Name=DistributionId,Value=$distribution_id" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --period "$period" \
        --statistics Average \
        --output json \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to get CloudFront metrics: $metrics_output" "CLOUDFRONT"
        return 1
    fi
    
    echo "$metrics_output"
    return 0
}

# Get CloudFront access logs
get_cloudfront_access_logs() {
    local distribution_id="$1"
    local log_bucket="$2"
    local log_prefix="$3"
    local date="${4:-$(date +%Y-%m-%d)}"
    
    log_info "Getting CloudFront access logs for distribution: $distribution_id" "CLOUDFRONT"
    
    # Validate parameters
    if [[ -z "$distribution_id" || -z "$log_bucket" ]]; then
        log_error "Distribution ID and log bucket are required" "CLOUDFRONT"
        return 1
    fi
    
    # Set default log prefix if not provided
    if [[ -z "$log_prefix" ]]; then
        log_prefix="$distribution_id"
    fi
    
    # List log files
    local log_files
    log_files=$(aws s3 ls "s3://$log_bucket/$log_prefix/$date/" \
        --recursive \
        --output json \
        --region "$AWS_REGION" \
        --profile "$AWS_PROFILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to list CloudFront access logs: $log_files" "CLOUDFRONT"
        return 1
    fi
    
    echo "$log_files"
    return 0
}