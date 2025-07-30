#!/usr/bin/env bash
# =============================================================================
# AMI Selection Module
# Enhanced AMI selection, validation, and caching
# =============================================================================

# Prevent multiple sourcing
[ -n "${_COMPUTE_AMI_SH_LOADED:-}" ] && return 0
_COMPUTE_AMI_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/core.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/../core/variables.sh"
source "${SCRIPT_DIR}/../core/logging.sh"

# =============================================================================
# AMI PATTERNS
# =============================================================================

# Define AMI name patterns
declare -r NVIDIA_GPU_PATTERN="Deep Learning Base OSS Nvidia Driver GPU AMI (Ubuntu 22.04)*"
declare -r NVIDIA_FALLBACK_PATTERN="Deep Learning OSS Nvidia Driver AMI GPU *"
declare -r UBUNTU_PATTERN="ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
declare -r UBUNTU_ARM_PATTERN="ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"

# AMI owners
declare -r CANONICAL_OWNER="099720109477"  # Canonical
declare -r AMAZON_OWNER="amazon"           # Amazon
declare -r DEBIAN_OWNER="136693071363"     # Debian
declare -r ROCKY_OWNER="792107900819"      # Rocky Linux
declare -r ALMA_OWNER="764336703387"       # AlmaLinux

# OS-specific AMI patterns
declare -A OS_AMI_PATTERNS=(
    ["ubuntu:20.04"]="ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"
    ["ubuntu:22.04"]="ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
    ["ubuntu:24.04"]="ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*"
    ["debian:11"]="debian-11-amd64-*"
    ["debian:12"]="debian-12-amd64-*"
    ["amazonlinux:2"]="amzn2-ami-hvm-*-x86_64-gp2"
    ["amazonlinux:2023"]="al2023-ami-*-x86_64"
    ["rocky:8"]="Rocky-8-*-x86_64"
    ["rocky:9"]="Rocky-9-*-x86_64"
    ["almalinux:8"]="AlmaLinux-8-*-x86_64"
    ["almalinux:9"]="AlmaLinux-9-*-x86_64"
)

# OS owners mapping
declare -A OS_OWNERS=(
    ["ubuntu"]="$CANONICAL_OWNER"
    ["debian"]="$DEBIAN_OWNER"
    ["amazonlinux"]="$AMAZON_OWNER"
    ["rocky"]="$ROCKY_OWNER"
    ["almalinux"]="$ALMA_OWNER"
)

# =============================================================================
# AMI SELECTION
# =============================================================================

# Get AMI for instance type
get_ami_for_instance() {
    local instance_type="$1"
    local region="${2:-$AWS_REGION}"
    
    case "$instance_type" in
        g4dn.*|g5.*|p3.*|p4d.*)
            # GPU instances - need NVIDIA drivers
            get_nvidia_gpu_ami "$region"
            ;;
        g5g.*)
            # ARM GPU instances
            get_nvidia_gpu_ami "$region" "arm64"
            ;;
        t3.*|m5.*|c5.*)
            # Standard x86 instances
            get_ubuntu_ami "$region"
            ;;
        t4g.*|m6g.*|c6g.*)
            # ARM instances
            get_ubuntu_ami "$region" "arm64"
            ;;
        *)
            throw_error $ERROR_INVALID_ARGUMENT "Unknown instance type: $instance_type"
            ;;
    esac
}

# Get NVIDIA GPU-optimized AMI
get_nvidia_gpu_ami() {
    local region="$1"
    local architecture="${2:-x86_64}"
    
    echo "Searching for NVIDIA GPU AMI in region: $region" >&2
    
    # Try primary pattern
    local ami_id
    ami_id=$(search_ami "$NVIDIA_GPU_PATTERN" "$AMAZON_OWNER" "$region" "$architecture")
    
    if [ -z "$ami_id" ] || [ "$ami_id" = "None" ]; then
        echo "Primary GPU AMI not found, trying fallback pattern..." >&2
        ami_id=$(search_ami "$NVIDIA_FALLBACK_PATTERN" "$AMAZON_OWNER" "$region" "$architecture")
    fi
    
    if [ -z "$ami_id" ] || [ "$ami_id" = "None" ]; then
        # Final fallback - use Ubuntu and install drivers
        echo "WARNING: No NVIDIA GPU AMI found, using Ubuntu base" >&2
        echo "NOTE: NVIDIA drivers will need to be installed manually" >&2
        ami_id=$(get_ubuntu_ami "$region" "$architecture")
    fi
    
    validate_ami "$ami_id" "$region"
    echo "$ami_id"
}

# Get Ubuntu AMI
get_ubuntu_ami() {
    local region="$1"
    local architecture="${2:-x86_64}"
    
    echo "Searching for Ubuntu 22.04 AMI in region: $region" >&2
    
    local pattern="$UBUNTU_PATTERN"
    [ "$architecture" = "arm64" ] && pattern="$UBUNTU_ARM_PATTERN"
    
    local ami_id
    ami_id=$(search_ami "$pattern" "$CANONICAL_OWNER" "$region" "$architecture")
    
    if [ -z "$ami_id" ] || [ "$ami_id" = "None" ]; then
        throw_error $ERROR_RESOURCE_NOT_FOUND "No Ubuntu AMI found in region $region"
    fi
    
    validate_ami "$ami_id" "$region"
    echo "$ami_id"
}

# Search for AMI
search_ami() {
    local name_pattern="$1"
    local owner="$2"
    local region="$3"
    local architecture="${4:-x86_64}"
    
    aws ec2 describe-images \
        --region "$region" \
        --owners "$owner" \
        --filters \
            "Name=name,Values=$name_pattern" \
            "Name=state,Values=available" \
            "Name=architecture,Values=$architecture" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --output text 2>/dev/null
}

# Validate AMI exists and is available
validate_ami() {
    local ami_id="$1"
    local region="$2"
    
    if [ -z "$ami_id" ] || [ "$ami_id" = "None" ]; then
        throw_error $ERROR_RESOURCE_NOT_FOUND "Invalid AMI ID: $ami_id"
    fi
    
    # Verify AMI exists
    local state
    state=$(aws ec2 describe-images \
        --region "$region" \
        --image-ids "$ami_id" \
        --query 'Images[0].State' \
        --output text 2>/dev/null) || {
        throw_error $ERROR_AWS_API "Failed to describe AMI: $ami_id"
    }
    
    if [ "$state" != "available" ]; then
        throw_error $ERROR_INVALID_ARGUMENT "AMI $ami_id is not available (state: $state)"
    fi
    
    echo "AMI validated: $ami_id (state: $state)" >&2
}

# =============================================================================
# AMI CACHING
# =============================================================================

# Cache file for AMI lookups
AMI_CACHE_FILE="${AMI_CACHE_FILE:-/tmp/geusemaker-ami-cache.json}"
AMI_CACHE_TTL="${AMI_CACHE_TTL:-3600}"  # 1 hour

# Global AMI cache for batch operations
declare -gA AMI_BATCH_CACHE 2>/dev/null || true

# Initialize AMI cache
init_ami_cache() {
    if [ ! -f "$AMI_CACHE_FILE" ]; then
        echo '{}' > "$AMI_CACHE_FILE"
    fi
}

# Get cached AMI
get_cached_ami() {
    local cache_key="$1"
    
    init_ami_cache
    
    # Check if cache entry exists and is not expired
    local cache_entry
    cache_entry=$(jq -r --arg key "$cache_key" '.[$key] // empty' "$AMI_CACHE_FILE")
    
    if [ -n "$cache_entry" ]; then
        local cached_time=$(echo "$cache_entry" | jq -r '.timestamp')
        local cached_ami=$(echo "$cache_entry" | jq -r '.ami_id')
        local current_time=$(date +%s)
        
        if [ $((current_time - cached_time)) -lt "$AMI_CACHE_TTL" ]; then
            echo "Using cached AMI: $cached_ami" >&2
            echo "$cached_ami"
            return 0
        fi
    fi
    
    return 1
}

# Cache AMI lookup
cache_ami() {
    local cache_key="$1"
    local ami_id="$2"
    
    init_ami_cache
    
    local temp_file=$(mktemp)
    jq --arg key "$cache_key" \
       --arg ami "$ami_id" \
       --arg ts "$(date +%s)" \
       '.[$key] = {ami_id: $ami, timestamp: ($ts | tonumber)}' \
       "$AMI_CACHE_FILE" > "$temp_file" && \
    mv "$temp_file" "$AMI_CACHE_FILE"
}

# =============================================================================
# CROSS-REGION AMI SEARCH
# =============================================================================

# Find best AMI across regions
find_best_ami_across_regions() {
    local instance_type="$1"
    local preferred_regions=("${@:2}")
    
    # Default region list if none provided
    if [ ${#preferred_regions[@]} -eq 0 ]; then
        preferred_regions=(
            "us-east-1"
            "us-west-2"
            "eu-west-1"
            "ap-southeast-1"
        )
    fi
    
    echo "Searching for AMI across regions..." >&2
    
    for region in "${preferred_regions[@]}"; do
        echo "Checking region: $region" >&2
        
        local ami_id
        ami_id=$(get_ami_for_instance "$instance_type" "$region" 2>/dev/null) || continue
        
        if [ -n "$ami_id" ] && [ "$ami_id" != "None" ]; then
            echo "Found AMI in region $region: $ami_id" >&2
            cat <<EOF
{
    "region": "$region",
    "ami_id": "$ami_id"
}
EOF
            return 0
        fi
    done
    
    throw_error $ERROR_RESOURCE_NOT_FOUND "No suitable AMI found in any region"
}

# =============================================================================
# AMI INFORMATION
# =============================================================================

# Get AMI details
get_ami_details() {
    local ami_id="$1"
    local region="${2:-$AWS_REGION}"
    
    aws ec2 describe-images \
        --region "$region" \
        --image-ids "$ami_id" \
        --query 'Images[0].{
            Name: Name,
            Description: Description,
            Architecture: Architecture,
            VirtualizationType: VirtualizationType,
            RootDeviceType: RootDeviceType,
            BlockDeviceMappings: BlockDeviceMappings,
            CreationDate: CreationDate,
            OwnerId: OwnerId,
            State: State
        }' \
        --output json
}

# Check if AMI has GPU support
ami_has_gpu_support() {
    local ami_id="$1"
    local region="${2:-$AWS_REGION}"
    
    local ami_name
    ami_name=$(aws ec2 describe-images \
        --region "$region" \
        --image-ids "$ami_id" \
        --query 'Images[0].Name' \
        --output text 2>/dev/null)
    
    # Check if name contains GPU-related keywords
    if [[ "$ami_name" =~ (GPU|NVIDIA|CUDA|Deep Learning) ]]; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# OS-SPECIFIC AMI SELECTION
# =============================================================================

# Get AMI for specific OS and version
get_ami_for_os() {
    local os_id="$1"
    local os_version="$2"
    local region="${3:-$AWS_REGION}"
    local architecture="${4:-x86_64}"
    
    local os_key="${os_id}:${os_version}"
    local pattern="${OS_AMI_PATTERNS[$os_key]:-}"
    local owner="${OS_OWNERS[$os_id]:-}"
    
    if [ -z "$pattern" ]; then
        echo "WARNING: No AMI pattern found for $os_key, using generic search" >&2
        get_generic_ami_for_os "$os_id" "$region" "$architecture"
        return
    fi
    
    if [ -z "$owner" ]; then
        echo "WARNING: No owner found for $os_id, using generic search" >&2
        get_generic_ami_for_os "$os_id" "$region" "$architecture"
        return
    fi
    
    echo "Searching for $os_key AMI in region: $region" >&2
    
    local ami_id
    ami_id=$(search_ami "$pattern" "$owner" "$region" "$architecture")
    
    if [ -z "$ami_id" ] || [ "$ami_id" = "None" ]; then
        echo "WARNING: No AMI found for $os_key, trying generic search" >&2
        get_generic_ami_for_os "$os_id" "$region" "$architecture"
        return
    fi
    
    validate_ami "$ami_id" "$region"
    echo "$ami_id"
}

# Generic AMI search for OS family
get_generic_ami_for_os() {
    local os_id="$1"
    local region="$2"
    local architecture="${3:-x86_64}"
    
    echo "Performing generic AMI search for: $os_id" >&2
    
    case "$os_id" in
        ubuntu*)
            get_ubuntu_ami "$region" "$architecture"
            ;;
        debian*)
            search_ami "debian-*-amd64-*" "$DEBIAN_OWNER" "$region" "$architecture" || \
            search_ami "debian*" "$DEBIAN_OWNER" "$region" "$architecture"
            ;;
        amazonlinux*|amzn*)
            search_ami "amzn2-ami-hvm-*" "$AMAZON_OWNER" "$region" "$architecture" || \
            search_ami "al2023-ami-*" "$AMAZON_OWNER" "$region" "$architecture"
            ;;
        rocky*)
            search_ami "Rocky-*-x86_64" "$ROCKY_OWNER" "$region" "$architecture"
            ;;
        almalinux*|alma*)
            search_ami "AlmaLinux-*-x86_64" "$ALMA_OWNER" "$region" "$architecture"
            ;;
        centos*)
            # CentOS images are often in marketplace or community AMIs
            search_ami "CentOS*" "125523088429" "$region" "$architecture" || \
            search_ami "CentOS*" "679593333241" "$region" "$architecture"
            ;;
        *)
            echo "ERROR: Unsupported OS for generic search: $os_id" >&2
            return 1
            ;;
    esac
}

# Find compatible AMI for current system
find_compatible_ami() {
    local region="${1:-$AWS_REGION}"
    local architecture="${2:-x86_64}"
    local prefer_gpu="${3:-false}"
    
    # Detect current OS if not already done
    if [ -z "${OS_ID:-}" ]; then
        detect_os >/dev/null 2>&1
    fi
    
    local os_id="${OS_ID:-ubuntu}"
    local os_version="${OS_VERSION:-22.04}"
    
    echo "Finding compatible AMI for current system: $os_id $os_version" >&2
    
    # If GPU preference, try GPU-optimized AMI first
    if [ "$prefer_gpu" = "true" ]; then
        local gpu_ami
        gpu_ami=$(get_nvidia_gpu_ami "$region" "$architecture" 2>/dev/null || echo "")
        if [ -n "$gpu_ami" ] && [ "$gpu_ami" != "None" ]; then
            echo "$gpu_ami"
            return 0
        fi
    fi
    
    # Try OS-specific AMI
    local os_ami
    os_ami=$(get_ami_for_os "$os_id" "$os_version" "$region" "$architecture" 2>/dev/null || echo "")
    if [ -n "$os_ami" ] && [ "$os_ami" != "None" ]; then
        echo "$os_ami"
        return 0
    fi
    
    # Fallback to Ubuntu LTS
    echo "WARNING: Using Ubuntu 22.04 LTS as fallback" >&2
    get_ubuntu_ami "$region" "$architecture"
}

# List available AMIs for OS
list_amis_for_os() {
    local os_id="$1"
    local region="${2:-$AWS_REGION}"
    local max_results="${3:-10}"
    
    local owner="${OS_OWNERS[$os_id]:-}"
    if [ -z "$owner" ]; then
        echo "ERROR: Unknown OS for AMI listing: $os_id" >&2
        return 1
    fi
    
    echo "Listing AMIs for $os_id in $region:" >&2
    
    # Search for OS-specific patterns
    case "$os_id" in
        ubuntu)
            aws ec2 describe-images \
                --region "$region" \
                --owners "$owner" \
                --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-*-server-*" \
                          "Name=state,Values=available" \
                --query "sort_by(Images, &CreationDate)[-$max_results:].{ImageId: ImageId, Name: Name, CreationDate: CreationDate}" \
                --output table
            ;;
        debian)
            aws ec2 describe-images \
                --region "$region" \
                --owners "$owner" \
                --filters "Name=name,Values=debian-*" \
                          "Name=state,Values=available" \
                --query "sort_by(Images, &CreationDate)[-$max_results:].{ImageId: ImageId, Name: Name, CreationDate: CreationDate}" \
                --output table
            ;;
        amazonlinux)
            aws ec2 describe-images \
                --region "$region" \
                --owners "$owner" \
                --filters "Name=name,Values=amzn*-ami-*" \
                          "Name=state,Values=available" \
                --query "sort_by(Images, &CreationDate)[-$max_results:].{ImageId: ImageId, Name: Name, CreationDate: CreationDate}" \
                --output table
            ;;
        *)
            echo "AMI listing not implemented for: $os_id" >&2
            return 1
            ;;
    esac
}

# Validate OS compatibility with AMI
validate_os_ami_compatibility() {
    local ami_id="$1"
    local target_os_id="$2"
    local region="${3:-$AWS_REGION}"
    
    echo "Validating OS compatibility for AMI: $ami_id" >&2
    
    # Get AMI details
    local ami_name
    ami_name=$(aws ec2 describe-images \
        --region "$region" \
        --image-ids "$ami_id" \
        --query 'Images[0].Name' \
        --output text 2>/dev/null)
    
    if [ -z "$ami_name" ] || [ "$ami_name" = "None" ]; then
        echo "ERROR: Could not retrieve AMI name for: $ami_id" >&2
        return 1
    fi
    
    echo "AMI name: $ami_name" >&2
    
    # Check OS compatibility
    case "$target_os_id" in
        ubuntu*)
            if [[ "$ami_name" =~ ubuntu ]]; then
                echo "✓ Ubuntu AMI confirmed" >&2
                return 0
            fi
            ;;
        debian*)
            if [[ "$ami_name" =~ debian ]]; then
                echo "✓ Debian AMI confirmed" >&2
                return 0
            fi
            ;;
        amazonlinux*|amzn*)
            if [[ "$ami_name" =~ (amzn|amazon) ]]; then
                echo "✓ Amazon Linux AMI confirmed" >&2
                return 0
            fi
            ;;
        rocky*)
            if [[ "$ami_name" =~ [Rr]ocky ]]; then
                echo "✓ Rocky Linux AMI confirmed" >&2
                return 0
            fi
            ;;
        almalinux*|alma*)
            if [[ "$ami_name" =~ [Aa]lma ]]; then
                echo "✓ AlmaLinux AMI confirmed" >&2
                return 0
            fi
            ;;
    esac
    
    echo "WARNING: AMI may not be compatible with target OS: $target_os_id" >&2
    return 1
}

# =============================================================================
# AMI BATCH OPERATIONS
# =============================================================================

# Get AMIs for multiple instance types
get_amis_for_instance_types() {
    local region="${1:-$AWS_REGION}"
    shift
    local instance_types=("$@")
    
    if [ ${#instance_types[@]} -eq 0 ]; then
        log_error "No instance types provided" "AMI"
        return 1
    fi
    
    log_info "Getting AMIs for ${#instance_types[@]} instance types" "AMI"
    
    local results=()
    for instance_type in "${instance_types[@]}"; do
        local ami_id
        ami_id=$(get_ami_for_instance "$instance_type" "$region" 2>/dev/null || echo "")
        
        if [ -n "$ami_id" ] && [ "$ami_id" != "None" ]; then
            results+=("{\"instance_type\": \"$instance_type\", \"ami_id\": \"$ami_id\"}")
        else
            results+=("{\"instance_type\": \"$instance_type\", \"ami_id\": null, \"error\": \"Not found\"}")
        fi
    done
    
    # Return as JSON array
    printf '[%s]' "$(IFS=,; echo "${results[*]}")"
}

# Validate multiple AMIs in parallel
validate_amis_batch() {
    local region="${1:-$AWS_REGION}"
    shift
    local ami_ids=("$@")
    
    if [ ${#ami_ids[@]} -eq 0 ]; then
        log_error "No AMI IDs provided" "AMI"
        return 1
    fi
    
    log_info "Validating ${#ami_ids[@]} AMIs in parallel" "AMI"
    
    # Query all AMIs at once
    local ami_data
    ami_data=$(aws ec2 describe-images \
        --region "$region" \
        --image-ids "${ami_ids[@]}" \
        --query 'Images[].{ImageId: ImageId, State: State, Name: Name}' \
        --output json 2>/dev/null || echo "[]")
    
    # Process results
    local valid_count=0
    local invalid_count=0
    
    for ami_id in "${ami_ids[@]}"; do
        local ami_info
        ami_info=$(echo "$ami_data" | jq -r --arg id "$ami_id" '.[] | select(.ImageId == $id)')
        
        if [ -n "$ami_info" ]; then
            local state
            state=$(echo "$ami_info" | jq -r '.State')
            
            if [ "$state" = "available" ]; then
                ((valid_count++))
                log_info "✓ AMI $ami_id is valid" "AMI"
            else
                ((invalid_count++))
                log_warn "✗ AMI $ami_id is not available (state: $state)" "AMI"
            fi
        else
            ((invalid_count++))
            log_error "✗ AMI $ami_id not found" "AMI"
        fi
    done
    
    log_info "Validation complete: $valid_count valid, $invalid_count invalid" "AMI"
    
    [ $invalid_count -eq 0 ]
}

# =============================================================================
# AMI RECOMMENDATIONS
# =============================================================================

# Get recommended AMI based on workload type
get_recommended_ami() {
    local workload_type="$1"
    local region="${2:-$AWS_REGION}"
    local architecture="${3:-x86_64}"
    
    log_info "Getting recommended AMI for workload: $workload_type" "AMI"
    
    case "$workload_type" in
        "ai"|"ml"|"deep-learning")
            # Deep Learning workloads - need NVIDIA drivers
            get_nvidia_gpu_ami "$region" "$architecture"
            ;;
        "web"|"api"|"microservice")
            # Web services - standard Ubuntu
            get_ubuntu_ami "$region" "$architecture"
            ;;
        "database"|"cache")
            # Database workloads - Amazon Linux for performance
            search_ami "amzn2-ami-hvm-*-x86_64-gp2" "$AMAZON_OWNER" "$region" "$architecture"
            ;;
        "container"|"kubernetes"|"docker")
            # Container workloads - ECS optimized
            search_ami "amzn2-ami-ecs-hvm-*-x86_64-ebs" "$AMAZON_OWNER" "$region" "$architecture"
            ;;
        "hpc"|"compute")
            # HPC workloads - optimized for compute
            search_ami "amzn2-ami-hvm-*-x86_64-gp2" "$AMAZON_OWNER" "$region" "$architecture"
            ;;
        *)
            # Default to Ubuntu LTS
            get_ubuntu_ami "$region" "$architecture"
            ;;
    esac
}

# =============================================================================
# AMI COST OPTIMIZATION
# =============================================================================

# Get most cost-effective AMI for instance type
get_cost_optimized_ami() {
    local instance_type="$1"
    local region="${2:-$AWS_REGION}"
    
    # For GPU instances, check if we can use a base AMI and install drivers
    if is_gpu_instance "$instance_type"; then
        log_info "Checking cost optimization for GPU instance" "AMI"
        
        # Compare GPU AMI vs base AMI + driver installation time
        local gpu_ami
        local base_ami
        
        gpu_ami=$(get_nvidia_gpu_ami "$region" 2>/dev/null || echo "")
        base_ami=$(get_ubuntu_ami "$region" 2>/dev/null || echo "")
        
        if [ -n "$gpu_ami" ] && [ -n "$base_ami" ]; then
            cat <<EOF
{
    "recommended": "$gpu_ami",
    "alternative": "$base_ami",
    "note": "GPU AMI recommended for immediate use. Base AMI requires ~10min driver installation.",
    "savings": "Using base AMI saves ~5-10% on first-hour costs due to faster boot time"
}
EOF
        else
            echo "$gpu_ami"
        fi
    else
        # For non-GPU instances, use standard selection
        get_ami_for_instance "$instance_type" "$region"
    fi
}

# =============================================================================
# AMI METADATA ENRICHMENT
# =============================================================================

# Get detailed AMI information with recommendations
get_ami_details_enriched() {
    local ami_id="$1"
    local region="${2:-$AWS_REGION}"
    
    local ami_details
    ami_details=$(get_ami_details "$ami_id" "$region")
    
    if [ -z "$ami_details" ] || [ "$ami_details" = "null" ]; then
        log_error "Failed to get AMI details" "AMI"
        return 1
    fi
    
    # Enrich with additional information
    local name
    local has_gpu_support
    local estimated_boot_time
    local recommended_instance_types=()
    
    name=$(echo "$ami_details" | jq -r '.Name')
    
    # Check GPU support
    if ami_has_gpu_support "$ami_id" "$region"; then
        has_gpu_support="true"
        recommended_instance_types+=("g4dn.xlarge" "g5.xlarge" "p3.2xlarge")
        estimated_boot_time="2-3 minutes"
    else
        has_gpu_support="false"
        recommended_instance_types+=("t3.medium" "t3.large" "m5.large")
        estimated_boot_time="1-2 minutes"
    fi
    
    # Add enriched data
    echo "$ami_details" | jq \
        --arg gpu "$has_gpu_support" \
        --arg boot "$estimated_boot_time" \
        --argjson types "$(printf '%s\n' "${recommended_instance_types[@]}" | jq -R . | jq -s .)" \
        '. + {
            "gpu_support": $gpu,
            "estimated_boot_time": $boot,
            "recommended_instance_types": $types
        }'
}

# =============================================================================
# AMI MIGRATION HELPERS
# =============================================================================

# Copy AMI to another region
copy_ami_to_region() {
    local source_ami_id="$1"
    local source_region="$2"
    local target_region="$3"
    local name_suffix="${4:-copy}"
    
    log_info "Copying AMI $source_ami_id from $source_region to $target_region" "AMI"
    
    # Get source AMI details
    local ami_name
    ami_name=$(aws ec2 describe-images \
        --region "$source_region" \
        --image-ids "$source_ami_id" \
        --query 'Images[0].Name' \
        --output text 2>/dev/null)
    
    if [ -z "$ami_name" ] || [ "$ami_name" = "None" ]; then
        log_error "Source AMI not found: $source_ami_id" "AMI"
        return 1
    fi
    
    # Copy AMI
    local new_ami_id
    new_ami_id=$(aws ec2 copy-image \
        --source-region "$source_region" \
        --source-image-id "$source_ami_id" \
        --region "$target_region" \
        --name "${ami_name}-${name_suffix}" \
        --description "Copied from $source_region" \
        --query 'ImageId' \
        --output text 2>/dev/null)
    
    if [ -z "$new_ami_id" ] || [ "$new_ami_id" = "None" ]; then
        log_error "Failed to copy AMI" "AMI"
        return 1
    fi
    
    log_info "AMI copy initiated: $new_ami_id (this may take several minutes)" "AMI"
    echo "$new_ami_id"
    
    # Optionally wait for copy to complete
    if [ "${WAIT_FOR_AMI_COPY:-false}" = "true" ]; then
        log_info "Waiting for AMI copy to complete..." "AMI"
        aws ec2 wait image-available \
            --region "$target_region" \
            --image-ids "$new_ami_id" 2>/dev/null || {
            log_error "Timeout waiting for AMI copy" "AMI"
            return 1
        }
        log_info "AMI copy completed successfully" "AMI"
    fi
}