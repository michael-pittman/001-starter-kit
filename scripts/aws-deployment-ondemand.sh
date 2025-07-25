#!/bin/bash

# =============================================================================
# GeuseMaker - On-Demand AWS Deployment
# =============================================================================
# This script uses ONLY on-demand instances to completely avoid spot limits
# Features: 100% reliable deployment, no spot instance complications
# Target: g4dn.xlarge with NVIDIA T4 GPU using NVIDIA GPU-Optimized AMI
# AMI Product ID: 676eed8d-dcf5-4784-87d7-0de463205c17
# Benefits: Pre-installed NVIDIA drivers, Docker GPU runtime, CUDA toolkit
# Cost: Higher but guaranteed availability
# =============================================================================

set -euo pipefail

# =============================================================================
# CLEANUP ON FAILURE HANDLER
# =============================================================================

# Global flag to track if cleanup should run
CLEANUP_ON_FAILURE="${CLEANUP_ON_FAILURE:-true}"
RESOURCES_CREATED=false
STACK_NAME=""

cleanup_on_failure() {
    local exit_code=$?
    if [ "$CLEANUP_ON_FAILURE" = "true" ] && [ "$RESOURCES_CREATED" = "true" ] && [ $exit_code -ne 0 ] && [ -n "$STACK_NAME" ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        error "🚨 Deployment failed! Running automatic cleanup for stack: $STACK_NAME"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Get script directory
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local project_root="$(cd "$script_dir/.." && pwd)"
        
        # Use cleanup script if available
        if [ -f "$project_root/cleanup-stack.sh" ]; then
            log "Using cleanup script to remove resources..."
            "$project_root/cleanup-stack.sh" "$STACK_NAME" || true
        else
            log "Running manual cleanup..."
            # Basic manual cleanup
            aws ec2 describe-instances --filters "Name=tag:Stack,Values=$STACK_NAME" --query 'Reservations[].Instances[].[InstanceId]' --output text | while read -r instance_id; do
                if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
                    aws ec2 terminate-instances --instance-ids "$instance_id" --region "${AWS_REGION:-us-east-1}" || true
                    log "Terminated instance: $instance_id"
                fi
            done
        fi
        
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        warning "💡 To disable automatic cleanup, set CLEANUP_ON_FAILURE=false"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
}

# Register cleanup handler
trap cleanup_on_failure EXIT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_TYPE="${INSTANCE_TYPE:-g4dn.xlarge}"
KEY_NAME="${KEY_NAME:-GeuseMaker-ondemand-key}"
STACK_NAME="${STACK_NAME:-GeuseMaker-ondemand}"
PROJECT_NAME="${PROJECT_NAME:-GeuseMaker}"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" >&2
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}" >&2
}

info() {
    echo -e "${CYAN}[INFO] $1${NC}" >&2
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Please install AWS CLI first."
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        error "Docker not found. Please install Docker first."
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        error "Docker Compose not found. Please install Docker Compose first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check jq for JSON processing
    if ! command -v jq &> /dev/null; then
        warning "jq not found. Installing jq for JSON processing..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            brew install jq || {
                error "Failed to install jq. Please install it manually."
                exit 1
            }
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo apt-get update && sudo apt-get install -y jq || {
                error "Failed to install jq. Please install it manually."
                exit 1
            }
        fi
    fi
    
    success "Prerequisites check completed"
}

get_single_availability_zone() {
    aws ec2 describe-availability-zones \
        --region "$AWS_REGION" \
        --query 'AvailabilityZones[?State==`available`].ZoneName' \
        --output text | awk '{print $1}'
}

get_all_availability_zones() {
    aws ec2 describe-availability-zones \
        --region "$AWS_REGION" \
        --query 'AvailabilityZones[?State==`available`].ZoneName' \
        --output text
}

get_subnet_for_az() {
    local AZ="$1"
    aws ec2 describe-subnets \
        --filters "Name=availability-zone,Values=$AZ" "Name=default-for-az,Values=true" \
        --region "$AWS_REGION" \
        --query 'Subnets[0].SubnetId' \
        --output text
}

# Add SSM fetch function
fetch_ssm_params() {
    log "Fetching parameters from AWS SSM..."
    
    # List of parameters to fetch
    params=(
        "/aibuildkit/n8n/COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE"
        "/aibuildkit/n8n/CORS_ALLOWED_ORIGINS"
        "/aibuildkit/n8n/CORS_ENABLE"
        "/aibuildkit/n8n/ENCRYPTION_KEY"
        "/aibuildkit/n8n/USER_MANAGEMENT_JWT_SECRET"
        "/aibuildkit/OPENAI_API_KEY"
        "/aibuildkit/POSTGRES_DB"
        "/aibuildkit/POSTGRES_PASSWORD"
        "/aibuildkit/POSTGRES_USER"
        "/aibuildkit/WEBHOOK_URL"
        "/aibuildkit/n8n_id"
    )
    
    # Fetch parameters in batch
    SSM_PARAMS=$(aws ssm get-parameters --names "${params[@]}" --with-decryption --region "$AWS_REGION" --query "Parameters" --output json)
    
    # Export as environment variables
    export N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/n8n/COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE") | .Value')
    export N8N_CORS_ALLOWED_ORIGINS=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/n8n/CORS_ALLOWED_ORIGINS") | .Value')
    export N8N_CORS_ENABLE=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/n8n/CORS_ENABLE") | .Value')
    export N8N_ENCRYPTION_KEY=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/n8n/ENCRYPTION_KEY") | .Value')
    export N8N_USER_MANAGEMENT_JWT_SECRET=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/n8n/USER_MANAGEMENT_JWT_SECRET") | .Value')
    export OPENAI_API_KEY=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/OPENAI_API_KEY") | .Value')
    export POSTGRES_DB=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/POSTGRES_DB") | .Value')
    export POSTGRES_PASSWORD=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/POSTGRES_PASSWORD") | .Value')
    export POSTGRES_USER=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/POSTGRES_USER") | .Value')
    export WEBHOOK_URL=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/WEBHOOK_URL") | .Value')
    export N8N_ID=$(echo "$SSM_PARAMS" | jq -r '.[] | select(.Name=="/aibuildkit/n8n_id") | .Value')
    
    success "Fetched parameters from SSM"
}

# =============================================================================
# INFRASTRUCTURE SETUP
# =============================================================================

create_key_pair() {
    log "Setting up SSH key pair..."
    
    if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$AWS_REGION" &> /dev/null; then
        warning "Key pair $KEY_NAME already exists"
        return 0
    fi
    
    # Create key pair
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --region "$AWS_REGION" \
        --query 'KeyMaterial' \
        --output text > "${KEY_NAME}.pem"
    
    chmod 600 "${KEY_NAME}.pem"
    success "Created SSH key pair: ${KEY_NAME}.pem"
}

create_security_group() {
    log "Creating security group..."
    
    # Check if security group exists
    SG_ID=$(aws ec2 describe-security-groups \
        --group-names "${STACK_NAME}-sg" \
        --region "$AWS_REGION" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$SG_ID" != "None" ]]; then
        warning "Security group already exists: $SG_ID"
        echo "$SG_ID"
        return 0
    fi
    
    # Get VPC ID
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --region "$AWS_REGION" \
        --query 'Vpcs[0].VpcId' \
        --output text)
    
    # Create security group
    SG_ID=$(aws ec2 create-security-group \
        --group-name "${STACK_NAME}-sg" \
        --description "Security group for GeuseMaker (On-Demand)" \
        --vpc-id "$VPC_ID" \
        --region "$AWS_REGION" \
        --query 'GroupId' \
        --output text)
    
    # Add rules
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION"
    
    # n8n
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 5678 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION"
    
    # Ollama
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 11434 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION"
    
    # Crawl4AI
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 11235 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION"
    
    # Qdrant
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 6333 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION"
    
    # ALB ports
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION"
    
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 \
        --region "$AWS_REGION"
    
    # NFS for EFS
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --protocol tcp \
        --port 2049 \
        --source-group "$SG_ID" \
        --region "$AWS_REGION"
    
    success "Created security group: $SG_ID"
    echo "$SG_ID"
}

create_efs() {
    local SG_ID="$1"
    log "Setting up EFS (Elastic File System)..."
    
    # Check if EFS already exists by searching through all file systems
    EFS_LIST=$(aws efs describe-file-systems \
        --region "$AWS_REGION" \
        --query 'FileSystems[].FileSystemId' \
        --output text 2>/dev/null || echo "")
    
    # Check each EFS to see if it has our tag
    for EFS_ID in $EFS_LIST; do
        if [[ -n "$EFS_ID" && "$EFS_ID" != "None" ]]; then
            EFS_TAGS=$(aws efs list-tags-for-resource \
                --resource-id "$EFS_ID" \
                --region "$AWS_REGION" \
                --query "Tags[?Key=='Name'].Value" \
                --output text 2>/dev/null || echo "")
            
            if [[ "$EFS_TAGS" == "${STACK_NAME}-efs" ]]; then
                warning "EFS already exists: $EFS_ID"
                # Get EFS DNS name
                EFS_DNS="${EFS_ID}.efs.${AWS_REGION}.amazonaws.com"
                export EFS_ID
                echo "$EFS_DNS"
                return 0
            fi
        fi
    done
    
    # Create EFS
    EFS_ID=$(aws efs create-file-system \
        --creation-token "${STACK_NAME}-efs-$(date +%s)" \
        --performance-mode generalPurpose \
        --throughput-mode provisioned \
        --provisioned-throughput-in-mibps 100 \
        --encrypted \
        --region "$AWS_REGION" \
        --query 'FileSystemId' \
        --output text)
    
    # Tag EFS
    aws efs create-tags \
        --file-system-id "$EFS_ID" \
        --tags Key=Name,Value="${STACK_NAME}-efs" Key=Project,Value="$PROJECT_NAME" \
        --region "$AWS_REGION"
    
    # Wait for EFS to be available
    log "Waiting for EFS to become available..."
    while true; do
        EFS_STATE=$(aws efs describe-file-systems \
            --file-system-id "$EFS_ID" \
            --region "$AWS_REGION" \
            --query 'FileSystems[0].LifeCycleState' \
            --output text 2>/dev/null || echo "")
        
        if [[ "$EFS_STATE" == "available" ]]; then
            log "EFS is now available"
            break
        elif [[ "$EFS_STATE" == "creating" ]]; then
            log "EFS is still creating... waiting 10 seconds"
            sleep 10
        else
            warning "EFS state: $EFS_STATE"
            sleep 10
        fi
    done
    
    # Get EFS DNS name
    EFS_DNS="${EFS_ID}.efs.${AWS_REGION}.amazonaws.com"
    # Export EFS_ID for cleanup function
    export EFS_ID
    success "Created EFS: $EFS_ID (DNS: $EFS_DNS)"
    echo "$EFS_DNS"
}

create_efs_mount_target() {
    local SG_ID="$1"
    local INSTANCE_AZ="$2"
    
    if [[ -z "$EFS_ID" ]]; then
        error "EFS_ID not set. Cannot create mount target."
        return 1
    fi
    
    log "Creating EFS mount target in $INSTANCE_AZ (where instance is running)..."
    
    # Check if mount target already exists in this AZ
    EXISTING_MT=$(aws efs describe-mount-targets \
        --file-system-id "$EFS_ID" \
        --region "$AWS_REGION" \
        --query "MountTargets[?AvailabilityZoneName=='$INSTANCE_AZ'].MountTargetId" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$EXISTING_MT" && "$EXISTING_MT" != "None" ]]; then
        warning "EFS mount target already exists in $INSTANCE_AZ: $EXISTING_MT"
        return 0
    fi
    
    # Get subnet ID for the instance AZ
    SUBNET_ID=$(get_subnet_for_az "$INSTANCE_AZ")
    
    if [[ "$SUBNET_ID" != "None" && -n "$SUBNET_ID" ]]; then
        aws efs create-mount-target \
            --file-system-id "$EFS_ID" \
            --subnet-id "$SUBNET_ID" \
            --security-groups "$SG_ID" \
            --region "$AWS_REGION" || {
            warning "Mount target creation failed in $INSTANCE_AZ, but continuing..."
            return 0
        }
        success "Created EFS mount target in $INSTANCE_AZ"
    else
        error "No suitable subnet found in $INSTANCE_AZ"
        return 1
    fi
}

# Create main target group for n8n
create_target_group() {
    local SG_ID="$1"
    local INSTANCE_ID="$2"
    
    log "Creating target group for n8n..."
    
    # Get VPC ID
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region "$AWS_REGION")
    
    TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
        --name "${STACK_NAME}-n8n-tg" \
        --protocol HTTP \
        --port 5678 \
        --vpc-id "$VPC_ID" \
        --health-check-protocol HTTP \
        --health-check-port 5678 \
        --health-check-path /healthz \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 10 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 2 \
        --target-type instance \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    
    # Register instance to target group
    aws elbv2 register-targets \
        --target-group-arn "$TARGET_GROUP_ARN" \
        --targets Id="$INSTANCE_ID" Port=5678 \
        --region "$AWS_REGION"
    
    success "Created n8n target group: $TARGET_GROUP_ARN"
    echo "$TARGET_GROUP_ARN"
}

# Add qdrant target group creation
create_qdrant_target_group() {
    local SG_ID="$1"
    local INSTANCE_ID="$2"
    
    log "Creating target group for qdrant..."
    
    # Get VPC ID
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region "$AWS_REGION")
    
    QDRANT_TG_ARN=$(aws elbv2 create-target-group \
        --name "${STACK_NAME}-qdrant-tg" \
        --protocol HTTP \
        --port 6333 \
        --vpc-id "$VPC_ID" \
        --health-check-protocol HTTP \
        --health-check-port 6333 \
        --health-check-path /healthz \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 10 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 2 \
        --target-type instance \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    
    # Register instance to qdrant target group
    aws elbv2 register-targets \
        --target-group-arn "$QDRANT_TG_ARN" \
        --targets Id="$INSTANCE_ID" Port=6333 \
        --region "$AWS_REGION"
    
    success "Created qdrant target group: $QDRANT_TG_ARN"
    echo "$QDRANT_TG_ARN"
}

# =============================================================================
# NVIDIA GPU-OPTIMIZED AMI MANAGEMENT
# =============================================================================

get_nvidia_gpu_optimized_ami() {
    log "Looking for NVIDIA GPU-Optimized AMI (Product ID: 676eed8d-dcf5-4784-87d7-0de463205c17)..."
    
    # Search for NVIDIA GPU-Optimized AMI using the specific product ID
    AMI_ID=$(aws ec2 describe-images \
        --owners 679593333241 \
        --filters \
            "Name=name,Values=*NVIDIA GPU-Optimized AMI*" \
            "Name=state,Values=available" \
            "Name=architecture,Values=x86_64" \
            "Name=virtualization-type,Values=hvm" \
        --region "$AWS_REGION" \
        --query 'Images[?contains(Description, `676eed8d-dcf5-4784-87d7-0de463205c17`)] | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text 2>/dev/null || echo "None")
    
    # Fallback: Search by name pattern for NVIDIA GPU-Optimized AMI
    if [[ "$AMI_ID" == "None" || -z "$AMI_ID" ]]; then
        log "Searching for NVIDIA GPU-Optimized AMI by name pattern..."
        AMI_ID=$(aws ec2 describe-images \
            --owners 679593333241 \
            --filters \
                "Name=name,Values=*NVIDIA*GPU*Optimized*AMI*" \
                "Name=state,Values=available" \
                "Name=architecture,Values=x86_64" \
                "Name=virtualization-type,Values=hvm" \
            --region "$AWS_REGION" \
            --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
            --output text 2>/dev/null || echo "None")
    fi
    
    # Additional fallback: Search AWS Marketplace for NVIDIA AMI
    if [[ "$AMI_ID" == "None" || -z "$AMI_ID" ]]; then
        log "Searching AWS Marketplace for NVIDIA GPU-Optimized AMI..."
        AMI_ID=$(aws ec2 describe-images \
            --owners aws-marketplace \
            --filters \
                "Name=name,Values=*NVIDIA*GPU*" \
                "Name=state,Values=available" \
                "Name=architecture,Values=x86_64" \
                "Name=virtualization-type,Values=hvm" \
            --region "$AWS_REGION" \
            --query 'Images[?contains(Name, `GPU`) && contains(Name, `NVIDIA`)] | sort_by(@, &CreationDate) | [-1].ImageId' \
            --output text 2>/dev/null || echo "None")
    fi
    
    if [[ "$AMI_ID" == "None" || -z "$AMI_ID" ]]; then
        error "NVIDIA GPU-Optimized AMI not found in region $AWS_REGION"
        error "Required AMI Product ID: 676eed8d-dcf5-4784-87d7-0de463205c17"
        error "This deployment requires the NVIDIA GPU-Optimized AMI which includes:"
        error "  - Pre-installed NVIDIA drivers"
        error "  - Docker with NVIDIA container runtime"
        error "  - CUDA toolkit and libraries"
        error "  - Optimized GPU configurations"
        error ""
        error "Possible solutions:"
        error "  1. Subscribe to NVIDIA GPU-Optimized AMI in AWS Marketplace"
        error "  2. Check if the AMI is available in region $AWS_REGION"
        error "  3. Verify AWS account permissions for marketplace AMIs"
        error "  4. Try a different AWS region where the AMI is available"
        return 1
    fi
    
    # Get AMI details for verification
    AMI_INFO=$(aws ec2 describe-images \
        --image-ids "$AMI_ID" \
        --region "$AWS_REGION" \
        --query 'Images[0].{Name:Name,Description:Description,OwnerId:OwnerId,CreationDate:CreationDate}' \
        --output json)
    
    AMI_NAME=$(echo "$AMI_INFO" | jq -r '.Name')
    AMI_DESCRIPTION=$(echo "$AMI_INFO" | jq -r '.Description')
    AMI_OWNER=$(echo "$AMI_INFO" | jq -r '.OwnerId')
    AMI_DATE=$(echo "$AMI_INFO" | jq -r '.CreationDate')
    
    success "Found NVIDIA GPU-Optimized AMI: $AMI_ID"
    info "AMI Name: $AMI_NAME"
    info "AMI Description: $AMI_DESCRIPTION"
    info "AMI Owner: $AMI_OWNER"
    info "Creation Date: $AMI_DATE"
    
    # Verify this is actually a NVIDIA GPU-optimized AMI
    if [[ ! "$AMI_NAME" == *"NVIDIA"* ]] && [[ ! "$AMI_DESCRIPTION" == *"NVIDIA"* ]]; then
        warning "Selected AMI may not be the official NVIDIA GPU-Optimized AMI"
        warning "Please verify this is the correct AMI for GPU workloads"
    fi
    
    echo "$AMI_ID"
}

create_iam_role() {
    log "Creating IAM role for EC2 instances..."
    
    # Check if role exists
    if aws iam get-role --role-name "${STACK_NAME}-role" &> /dev/null; then
        warning "IAM role already exists"
        return 0
    fi
    
    # Create trust policy
    cat > trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

    # Create role
    aws iam create-role \
        --role-name "${STACK_NAME}-role" \
        --assume-role-policy-document file://trust-policy.json || {
        warning "Role ${STACK_NAME}-role may already exist, continuing..."
    }
    
    # Attach essential policies
    aws iam attach-role-policy \
        --role-name "${STACK_NAME}-role" \
        --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy || {
        warning "CloudWatchAgentServerPolicy may already be attached, continuing..."
    }
    
    aws iam attach-role-policy \
        --role-name "${STACK_NAME}-role" \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore || {
        warning "AmazonSSMManagedInstanceCore may already be attached, continuing..."
    }
    
    # Create custom policy for EFS and AWS service access
    cat > custom-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "elasticfilesystem:DescribeFileSystems",
                "elasticfilesystem:DescribeMountTargets", 
                "ec2:Describe*",
                "cloudwatch:PutMetricData",
                "ssm:GetParameter",
                "ssm:GetParameters",
                "ssm:GetParametersByPath"
            ],
            "Resource": "*"
        }
    ]
}
EOF

    aws iam create-policy \
        --policy-name "${STACK_NAME}-custom-policy" \
        --policy-document file://custom-policy.json || true
    
    aws iam attach-role-policy \
        --role-name "${STACK_NAME}-role" \
        --policy-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/${STACK_NAME}-custom-policy" || {
        warning "Custom policy may already be attached, continuing..."
    }
    
    # Create instance profile (ensure name starts with letter for AWS compliance)
    local profile_name
    if [[ "${STACK_NAME}" =~ ^[0-9] ]]; then
        local clean_name=$(echo "${STACK_NAME}" | sed 's/[^a-zA-Z0-9]//g')
        profile_name="app-${clean_name}-profile"
    else
        profile_name="${STACK_NAME}-instance-profile"
    fi
    
    aws iam create-instance-profile --instance-profile-name "$profile_name" || true
    aws iam add-role-to-instance-profile \
        --instance-profile-name "$profile_name" \
        --role-name "${STACK_NAME}-role" || true
    
    # Wait for IAM propagation
    log "Waiting for IAM role propagation..."
    sleep 30
    
    success "Created IAM role and instance profile"
}

launch_on_demand_instance() {
    local SG_ID="$1"
    local EFS_DNS="$2"
    
    log "Launching on-demand instance (NO SPOT INSTANCES) with NVIDIA GPU-Optimized AMI..."
    
    # Get NVIDIA GPU-Optimized AMI
    AMI_ID=$(get_nvidia_gpu_optimized_ami)
    if [[ $? -ne 0 ]]; then
        error "Failed to find NVIDIA GPU-Optimized AMI"
        return 1
    fi
    
    # Create user data script optimized for NVIDIA GPU-Optimized AMI
    cat > user-data-ondemand.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Log all output for debugging
exec > >(tee /var/log/user-data.log) 2>&1

echo "=== NVIDIA GPU-Optimized AMI Setup Start ==="
echo "Timestamp: $(date)"
echo "AMI should include pre-installed NVIDIA drivers and Docker GPU support"

# Update system packages
echo "Updating system packages..."
apt-get update && apt-get upgrade -y

# Verify NVIDIA drivers are pre-installed
echo "=== Checking Pre-installed NVIDIA Components ==="
if command -v nvidia-smi &> /dev/null; then
    echo "✓ NVIDIA drivers found:"
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv
else
    echo "✗ NVIDIA drivers not found - this may not be the correct AMI"
    exit 1
fi

# Verify Docker is pre-installed
if command -v docker &> /dev/null; then
    echo "✓ Docker found:"
    docker --version
    # Add ubuntu user to docker group
    usermod -aG docker ubuntu
else
    echo "Docker not found, installing..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    usermod -aG docker ubuntu
    rm get-docker.sh
fi

# Verify Docker Compose is available
if command -v docker-compose &> /dev/null; then
    echo "✓ Docker Compose found:"
    docker-compose --version
else
    echo "Installing Docker Compose..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Verify NVIDIA Container Runtime
echo "=== Checking NVIDIA Container Runtime ==="
if docker info | grep -q nvidia; then
    echo "✓ NVIDIA Container Runtime is configured"
else
    echo "Configuring NVIDIA Container Runtime..."
    # Install nvidia-container-toolkit if not present
    if ! command -v nvidia-ctk &> /dev/null; then
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
        curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
        apt-get update && apt-get install -y nvidia-container-toolkit
    fi
    
    # Configure Docker daemon for GPU
    cat > /etc/docker/daemon.json << 'EODAEMON'
{
    "default-runtime": "nvidia",
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    }
}
EODAEMON
    
    systemctl restart docker
fi

# Test GPU access in Docker
echo "=== Testing GPU Access in Docker ==="
if docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu20.04 nvidia-smi; then
    echo "✓ GPU access in Docker containers verified"
else
    echo "✗ GPU access in Docker containers failed"
    exit 1
fi

# Install additional tools
echo "Installing additional tools..."
apt-get install -y jq curl wget git htop nvtop awscli nfs-common tree

# Install CloudWatch agent
echo "Installing CloudWatch agent..."
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb
rm amazon-cloudwatch-agent.deb

# Ensure Docker service is running and enabled
systemctl enable docker
systemctl start docker

# Create mount point for EFS
mkdir -p /mnt/efs

# Create GPU monitoring script
cat > /usr/local/bin/gpu-check.sh << 'EOGPU'
#!/bin/bash
echo "=== GPU Status Check ==="
echo "Date: $(date)"
echo "NVIDIA Driver Version:"
nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits
echo "GPU Info:"
nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,temperature.gpu,power.draw --format=csv
echo "Docker GPU Test:"
docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu20.04 nvidia-smi -L
EOGPU

chmod +x /usr/local/bin/gpu-check.sh

# Run initial GPU check
echo "=== Running Initial GPU Check ==="
/usr/local/bin/gpu-check.sh

# Signal that setup is complete
echo "=== NVIDIA GPU-Optimized AMI Setup Complete ==="
echo "Timestamp: $(date)"
touch /tmp/user-data-complete

EOF
    
    info "Using NVIDIA GPU-Optimized AMI: $AMI_ID"
    
    # Encode user data
    if [[ "$OSTYPE" == "darwin"* ]]; then
        USER_DATA=$(base64 -i user-data-ondemand.sh | tr -d '\n')
    else
        USER_DATA=$(base64 -w 0 user-data-ondemand.sh)
    fi
    
    # Launch ON-DEMAND instance (no spot)
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SG_ID" \
        --user-data "$USER_DATA" \
        --iam-instance-profile Name="$(if [[ "${STACK_NAME}" =~ ^[0-9] ]]; then echo "app-$(echo "${STACK_NAME}" | sed 's/[^a-zA-Z0-9]//g')-profile"; else echo "${STACK_NAME}-instance-profile"; fi)" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${STACK_NAME}-gpu-instance},{Key=Project,Value=$PROJECT_NAME},{Key=Type,Value=OnDemand},{Key=CostOptimized,Value=false}]" \
        --region "$AWS_REGION" \
        --query 'Instances[0].InstanceId' \
        --output text)
    
    if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then
        error "Failed to launch on-demand instance"
        return 1
    fi
    
    # Wait for instance to be running
    log "Waiting for on-demand instance to be running..."
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$AWS_REGION"
    
    # Get public IP and AZ
    INSTANCE_INFO=$(aws ec2 describe-instances \
        --instance-ids "$INSTANCE_ID" \
        --region "$AWS_REGION" \
        --query 'Reservations[0].Instances[0].{PublicIp:PublicIpAddress,AZ:Placement.AvailabilityZone}' \
        --output json)
    
    PUBLIC_IP=$(echo "$INSTANCE_INFO" | jq -r '.PublicIp')
    ACTUAL_AZ=$(echo "$INSTANCE_INFO" | jq -r '.AZ')
    
    success "On-demand instance launched: $INSTANCE_ID (IP: $PUBLIC_IP) in AZ: $ACTUAL_AZ"
    echo "$INSTANCE_ID:$PUBLIC_IP:$ACTUAL_AZ"
}

# Create ALB
create_alb() {
    local SG_ID="$1"
    local TARGET_GROUP_ARN="$2"
    local QDRANT_TG_ARN="$3"
    
    log "Creating Application Load Balancer..."
    
    # Check if ALB exists
    ALB_ARN=$(aws elbv2 describe-load-balancers \
        --names "${STACK_NAME}-alb" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$ALB_ARN" != "None" ]]; then
        warning "ALB already exists: $ALB_ARN"
        ALB_DNS=$(aws elbv2 describe-load-balancers \
            --load-balancer-arns "$ALB_ARN" \
            --region "$AWS_REGION" \
            --query 'LoadBalancers[0].DNSName' \
            --output text)
        echo "$ALB_DNS"
        return 0
    fi
    
    # Get subnets
    SUBNET_IDS=$(aws ec2 describe-subnets \
        --filters "Name=default-for-az,Values=true" \
        --region "$AWS_REGION" \
        --query 'Subnets[].SubnetId' \
        --output text)
    
    # Create ALB
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "${STACK_NAME}-alb" \
        --type application \
        --scheme internet-facing \
        --subnets $SUBNET_IDS \
        --security-groups "$SG_ID" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text)
    
    # Create listener
    LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$TARGET_GROUP_ARN" \
        --region "$AWS_REGION" \
        --query 'Listeners[0].ListenerArn' \
        --output text)
    
    # Add host-header rule for qdrant
    aws elbv2 create-rule \
        --listener-arn "$LISTENER_ARN" \
        --priority 10 \
        --conditions Field=host-header,Values=qdrant.geuse.io \
        --actions Type=forward,TargetGroupArn="$QDRANT_TG_ARN" \
        --region "$AWS_REGION"
    
    # Get ALB DNS
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    success "Created ALB: $ALB_DNS"
    echo "$ALB_DNS"
}

# CloudFront setup
setup_cloudfront() {
    local ALB_DNS="$1"
    log "Setting up CloudFront distribution with subdomains..."
    
    # Create origin access identity
    OAI_ID=$(aws cloudfront create-cloud-front-origin-access-identity --cloud-front-origin-access-identity-config CallerReference="$(date +%s)" Comment="GeuseMaker OAI" --query 'CloudFrontOriginAccessIdentity.Id' --output text)
    
    # Create distribution with multiple aliases and behaviors
    DISTRIBUTION_ID=$(aws cloudfront create-distribution --distribution-config '{
        "CallerReference": "'"$(date +%s)"'",
        "Comment": "GeuseMaker Distribution with subdomains (On-Demand)",
        "Enabled": true,
        "Origins": {
            "Quantity": 1,
            "Items": [{
                "Id": "ALBOrigin",
                "DomainName": "'"$ALB_DNS"'",
                "CustomOriginConfig": {
                    "HTTPPort": 80,
                    "HTTPSPort": 443,
                    "OriginProtocolPolicy": "http-only",
                    "OriginSslProtocols": {"Quantity": 1, "Items": ["TLSv1.2"]},
                    "OriginReadTimeout": 30,
                    "OriginKeepaliveTimeout": 5
                }
            }]
        },
        "DefaultCacheBehavior": {
            "TargetOriginId": "ALBOrigin",
            "ViewerProtocolPolicy": "redirect-to-https",
            "AllowedMethods": {"Quantity": 7, "Items": ["HEAD", "DELETE", "POST", "GET", "OPTIONS", "PUT", "PATCH"], "CachedMethods": {"Quantity": 3, "Items": ["HEAD", "GET", "OPTIONS"]}},
            "Compress": true,
            "ForwardedValues": {
                "QueryString": true,
                "Cookies": {"Forward": "all"},
                "Headers": {"Quantity": 1, "Items": ["*"]},
                "QueryStringCacheKeys": {"Quantity": 0}
            },
            "MinTTL": 0,
            "DefaultTTL": 0,
            "MaxTTL": 0
        },
        "CacheBehaviors": {
            "Quantity": 1,
            "Items": [{
                "PathPattern": "*",
                "TargetOriginId": "ALBOrigin",
                "ViewerProtocolPolicy": "redirect-to-https",
                "AllowedMethods": {"Quantity": 7, "Items": ["HEAD", "DELETE", "POST", "GET", "OPTIONS", "PUT", "PATCH"], "CachedMethods": {"Quantity": 3, "Items": ["HEAD", "GET", "OPTIONS"]}},
                "Compress": true,
                "ForwardedValues": {
                    "QueryString": true,
                    "Cookies": {"Forward": "all"},
                    "Headers": {"Quantity": 2, "Items": ["Host", "*"]}
                },
                "MinTTL": 0,
                "DefaultTTL": 0,
                "MaxTTL": 0
            }]
        },
        "ViewerCertificate": {
            "CloudFrontDefaultCertificate": true
        },
        "Aliases": {
            "Quantity": 2,
            "Items": ["n8n.geuse.io", "qdrant.geuse.io"]
        }
    }' --query 'Distribution.Id' --output text)
    
    # Wait for distribution to deploy
    aws cloudfront wait distribution-deployed --id "$DISTRIBUTION_ID"
    
    DISTRIBUTION_DOMAIN=$(aws cloudfront get-distribution --id "$DISTRIBUTION_ID" --query 'Distribution.DomainName' --output text)
    
    success "CloudFront distribution created: $DISTRIBUTION_DOMAIN"
    echo "Update DNS: Point n8n.geuse.io and qdrant.geuse.io CNAMEs to $DISTRIBUTION_DOMAIN"
    
    export DISTRIBUTION_DOMAIN
}

# =============================================================================
# APPLICATION DEPLOYMENT
# =============================================================================

wait_for_instance_ready() {
    local PUBLIC_IP="$1"
    
    log "Waiting for instance to be ready for SSH..."
    
    for i in {1..30}; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "${KEY_NAME}.pem" "ubuntu@$PUBLIC_IP" "test -f /tmp/user-data-complete" &> /dev/null; then
            success "Instance is ready!"
            return 0
        fi
        info "Attempt $i/30: Instance not ready yet, waiting 30 seconds..."
        sleep 30
    done
    
    error "Instance failed to become ready after 15 minutes"
    return 1
}

deploy_application() {
    local PUBLIC_IP="$1"
    local EFS_DNS="$2"
    local INSTANCE_ID="$3"
    
    log "Deploying GeuseMaker application with SSM parameters..."
    
    # Fetch SSM params with error handling
    fetch_ssm_params || { error "Failed to fetch SSM parameters"; return 1; }
    
    # Create deployment script using SSM vars
    cat > deploy-app-ondemand.sh << EOF
#!/bin/bash
set -euo pipefail

echo "Starting GeuseMaker deployment on on-demand instance..."

# Mount EFS
sudo mkdir -p /mnt/efs
sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc $EFS_DNS:/ /mnt/efs
echo "$EFS_DNS:/ /mnt/efs nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc,_netdev 0 0" | sudo tee -a /etc/fstab

# Clone repository
git clone https://github.com/michael-pittman/001-starter-kit.git /home/ubuntu/GeuseMaker || true
cd /home/ubuntu/GeuseMaker

# Create .env from SSM parameters
cat > .env << 'EOFENV'
POSTGRES_DB=$POSTGRES_DB
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
N8N_USER_MANAGEMENT_JWT_SECRET=$N8N_USER_MANAGEMENT_JWT_SECRET
N8N_HOST=0.0.0.0
N8N_PORT=5678
WEBHOOK_URL=$WEBHOOK_URL
EFS_DNS=$EFS_DNS
INSTANCE_ID=$INSTANCE_ID
INSTANCE_TYPE=$INSTANCE_TYPE
AWS_DEFAULT_REGION=$AWS_REGION
OPENAI_API_KEY=$OPENAI_API_KEY
N8N_CORS_ENABLE=$N8N_CORS_ENABLE
N8N_CORS_ALLOWED_ORIGINS=$N8N_CORS_ALLOWED_ORIGINS
N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=$N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE
N8N_ID=$N8N_ID
EOFENV

# Start GPU-optimized services
export EFS_DNS=$EFS_DNS
sudo -E docker-compose -f docker-compose.gpu-optimized.yml up -d

echo "Deployment completed on on-demand instance!"
EOF

    # Copy application files and deploy
    log "Copying application files..."
    
    # Copy the entire repository
    rsync -avz --exclude '.git' --exclude 'node_modules' --exclude '*.log' \
        -e "ssh -o StrictHostKeyChecking=no -i ${KEY_NAME}.pem" \
        ./ "ubuntu@$PUBLIC_IP:/home/ubuntu/GeuseMaker/"
    
    # Run deployment
    log "Running deployment script..."
    ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" "ubuntu@$PUBLIC_IP" \
        "chmod +x /home/ubuntu/GeuseMaker/deploy-app-ondemand.sh && /home/ubuntu/GeuseMaker/deploy-app-ondemand.sh"
    
    success "Application deployment completed!"
}

setup_monitoring() {
    local PUBLIC_IP="$1"
    
    log "Setting up monitoring and cost optimization..."
    
    # Copy monitoring scripts
    scp -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" \
        "scripts/cost-optimization.py" \
        "ubuntu@$PUBLIC_IP:/home/ubuntu/cost-optimization.py" 2>/dev/null || {
        warning "cost-optimization.py not found, skipping monitoring setup"
        return 0
    }
    
    # Install monitoring script
    ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" "ubuntu@$PUBLIC_IP" << 'EOF'
# Install Python dependencies
sudo apt-get install -y python3-pip
pip3 install boto3 schedule requests nvidia-ml-py3 psutil

# Create systemd service for cost optimization
sudo cat > /etc/systemd/system/cost-optimization.service << 'EOFSERVICE'
[Unit]
Description=GeuseMaker Cost Optimization (On-Demand)
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu
ExecStart=/usr/bin/python3 /home/ubuntu/cost-optimization.py --action schedule
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOFSERVICE

# Start cost optimization service
sudo systemctl daemon-reload
sudo systemctl enable cost-optimization.service
sudo systemctl start cost-optimization.service

echo "Monitoring setup completed!"
EOF

    success "Monitoring and cost optimization setup completed!"
}

# =============================================================================
# VALIDATION AND HEALTH CHECKS
# =============================================================================

validate_deployment() {
    local PUBLIC_IP="$1"
    
    log "Validating deployment..."
    
    # Wait with backoff
    sleep 120
    
    local endpoints=(
        "http://$PUBLIC_IP:5678/healthz:n8n"
        "http://$PUBLIC_IP:11434/api/tags:Ollama"
        "http://$PUBLIC_IP:6333/healthz:Qdrant"
        "http://$PUBLIC_IP:11235/health:Crawl4AI"
    )
    
    for endpoint_info in "${endpoints[@]}"; do
        IFS=':' read -r url service <<< "$endpoint_info"
        
        log "Testing $service at $url..."
        local retry=0
        local max_retries=10
        local backoff=30
        while [ $retry -lt $max_retries ]; do
            if curl -f -s "$url" > /dev/null 2>&1; then
                success "$service is healthy"
                break
            fi
            retry=$((retry+1))
            info "Attempt $retry/$max_retries: $service not ready, waiting ${backoff}s..."
            sleep $backoff
            backoff=$((backoff * 2))  # Exponential backoff
        done
        if [ $retry -eq $max_retries ]; then
            error "$service failed health check after $max_retries attempts"
        fi
    done
    
    success "Deployment validation completed!"
}

display_results() {
    local PUBLIC_IP="$1"
    local INSTANCE_ID="$2"
    local EFS_DNS="$3"
    local INSTANCE_AZ="$4"
    
    echo ""
    echo -e "${CYAN}=================================${NC}"
    echo -e "${GREEN}   AI STARTER KIT DEPLOYED!    ${NC}"
    echo -e "${CYAN}=================================${NC}"
    echo ""
    echo -e "${BLUE}Instance Information:${NC}"
    echo -e "  Instance ID: ${YELLOW}$INSTANCE_ID${NC}"
    echo -e "  Public IP: ${YELLOW}$PUBLIC_IP${NC}"
    echo -e "  Instance Type: ${YELLOW}$INSTANCE_TYPE${NC}"
    echo -e "  Availability Zone: ${YELLOW}$INSTANCE_AZ${NC}"
    echo -e "  EFS DNS: ${YELLOW}$EFS_DNS${NC}"
    echo -e "  Billing: ${YELLOW}On-Demand (No Spot Instances)${NC}"
    echo -e "  AMI: ${YELLOW}NVIDIA GPU-Optimized AMI${NC}"
    echo -e "  GPU Drivers: ${GREEN}Pre-installed & Optimized${NC}"
    echo ""
    echo -e "${BLUE}Service URLs:${NC}"
    echo -e "  ${GREEN}n8n Workflow Editor:${NC}     http://$PUBLIC_IP:5678"
    echo -e "  ${GREEN}Crawl4AI Web Scraper:${NC}    http://$PUBLIC_IP:11235"
    echo -e "  ${GREEN}Qdrant Vector Database:${NC}  http://$PUBLIC_IP:6333"
    echo -e "  ${GREEN}Ollama AI Models:${NC}        http://$PUBLIC_IP:11434"
    echo ""
    echo -e "${BLUE}SSH Access:${NC}"
    echo -e "  ssh -i ${KEY_NAME}.pem ubuntu@$PUBLIC_IP"
    echo ""
    echo -e "${BLUE}NVIDIA GPU-Optimized AMI Benefits:${NC}"
    echo -e "  ${GREEN}✓${NC} Pre-installed NVIDIA drivers (latest stable)"
    echo -e "  ${GREEN}✓${NC} Docker with NVIDIA container runtime pre-configured"
    echo -e "  ${GREEN}✓${NC} CUDA toolkit and libraries optimized for AWS GPU instances"
    echo -e "  ${GREEN}✓${NC} Faster deployment (no driver compilation time)"
    echo -e "  ${GREEN}✓${NC} AWS-tested and validated GPU software stack"
    echo ""
    echo -e "${BLUE}Next Steps:${NC}"
    echo -e "  1. Wait 5-10 minutes for all services to fully start"
    echo -e "  2. Access n8n at http://$PUBLIC_IP:5678 to set up workflows"
    echo -e "  3. Check GPU status: ssh to instance and run '/usr/local/bin/gpu-check.sh'"
    echo -e "  4. Check service logs: ssh to instance and run 'docker-compose logs'"
    echo -e "  5. Configure API keys in .env file for enhanced features"
    echo ""
    echo -e "${YELLOW}Cost Information:${NC}"
    echo -e "  - On-demand g4dn.xlarge: ~$0.75/hour (~$18/day)"
    echo -e "  - 100% reliable availability (no spot interruptions)"
    echo -e "  - No spot instance limits or complications"
    echo -e "  - ${RED}Remember to terminate when not in use!${NC}"
    echo ""
    echo -e "${GREEN}Advantages of On-Demand Deployment:${NC}"
    echo -e "  ✅ No spot instance count limits"
    echo -e "  ✅ Guaranteed availability"
    echo -e "  ✅ Instant launch"
    echo -e "  ✅ Predictable costs"
    echo -e "  ✅ Full infrastructure included (EFS, ALB, CloudFront)"
    echo -e "  ✅ NVIDIA GPU-Optimized AMI for best performance"
    echo ""
    echo -e "${YELLOW}Instance Details:${NC}"
    echo -e "  - Single on-demand instance deployment"
    echo -e "  - Deployed in $INSTANCE_AZ"
    echo -e "  - NVIDIA GPU-Optimized AMI (Product ID: 676eed8d-dcf5-4784-87d7-0de463205c17)"
    echo -e "  - Pre-optimized NVIDIA drivers and GPU software stack"
    echo -e "  - CloudWatch monitoring enabled"
    echo -e "  - EFS shared storage available"
    echo -e "  - SSM management access"
    echo -e "  - GPU status monitoring script installed at /usr/local/bin/gpu-check.sh"
    echo ""
}

# =============================================================================
# CLEANUP FUNCTION
# =============================================================================

cleanup_on_error() {
    error "Deployment failed. Cleaning up resources..."
    
    # Terminate instance first
    if [ ! -z "${INSTANCE_ID:-}" ]; then
        log "Terminating instance $INSTANCE_ID..."
        aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" || true
        aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" --region "$AWS_REGION" || true
    fi
    
    # Delete CloudWatch alarms (if any were created)
    log "Deleting CloudWatch alarms..."
    aws cloudwatch delete-alarms \
        --alarm-names "${STACK_NAME}-high-gpu-utilization" "${STACK_NAME}-low-gpu-utilization" \
        --region "$AWS_REGION" 2>/dev/null || true
    
    # Delete CloudFront distribution (takes longest, do early)
    if [ ! -z "${DISTRIBUTION_ID:-}" ]; then
        log "Disabling and deleting CloudFront distribution..."
        # Disable first
        ETAG=$(aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --query ETag --output text 2>/dev/null) || true
        if [ ! -z "$ETAG" ] && [ "$ETAG" != "None" ]; then
            CONFIG=$(aws cloudfront get-distribution-config --id "$DISTRIBUTION_ID" --query DistributionConfig --output json 2>/dev/null) || true
            if [ ! -z "$CONFIG" ]; then
                echo "$CONFIG" | jq '.Enabled = false' > disabled-config.json 2>/dev/null || true
                aws cloudfront update-distribution --id "$DISTRIBUTION_ID" --distribution-config file://disabled-config.json --if-match "$ETAG" 2>/dev/null || true
                aws cloudfront wait distribution-deployed --id "$DISTRIBUTION_ID" 2>/dev/null || true
                NEW_ETAG=$(aws cloudfront get-distribution --id "$DISTRIBUTION_ID" --query ETag --output text 2>/dev/null) || true
                aws cloudfront delete-distribution --id "$DISTRIBUTION_ID" --if-match "$NEW_ETAG" 2>/dev/null || true
            fi
        fi
    fi
    
    # Wait for ALB dependencies to clear, then delete ALB
    if [ ! -z "${ALB_ARN:-}" ]; then
        log "Deleting Application Load Balancer..."
        sleep 30  # Wait for connections to clear
        aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" --region "$AWS_REGION" || true
        # Wait for ALB to be deleted before deleting target groups
        sleep 60
    fi
    
    # Delete target groups after ALB is gone
    if [ ! -z "${TARGET_GROUP_ARN:-}" ]; then
        log "Deleting n8n target group..."
        aws elbv2 delete-target-group --target-group-arn "$TARGET_GROUP_ARN" --region "$AWS_REGION" || true
    fi
    if [ ! -z "${QDRANT_TG_ARN:-}" ]; then
        log "Deleting qdrant target group..."
        aws elbv2 delete-target-group --target-group-arn "$QDRANT_TG_ARN" --region "$AWS_REGION" || true
    fi
    
    # Delete EFS mount targets and file system
    if [ ! -z "${EFS_ID:-}" ]; then
        log "Deleting EFS mount targets and file system..."
        MOUNT_TARGETS=$(aws efs describe-mount-targets --file-system-id "$EFS_ID" --query 'MountTargets[].MountTargetId' --output text --region "$AWS_REGION" 2>/dev/null) || true
        for MT in $MOUNT_TARGETS; do
            if [ ! -z "$MT" ] && [ "$MT" != "None" ]; then
                aws efs delete-mount-target --mount-target-id "$MT" --region "$AWS_REGION" || true
            fi
        done
        sleep 30  # Wait for mount targets to be deleted
        aws efs delete-file-system --file-system-id "$EFS_ID" --region "$AWS_REGION" || true
    fi
    
    # Delete security group (wait for all dependencies to clear)
    if [ ! -z "${SG_ID:-}" ]; then
        log "Deleting security group..."
        # Wait longer for EFS mount targets and other dependencies to fully detach
        sleep 60
        # Retry security group deletion with better error handling
        local retry_count=0
        while [ $retry_count -lt 3 ]; do
            if aws ec2 delete-security-group --group-id "$SG_ID" --region "$AWS_REGION" 2>/dev/null; then
                success "Security group deleted"
                break
            else
                retry_count=$((retry_count + 1))
                warning "Security group deletion attempt $retry_count failed, waiting 30s..."
                sleep 30
            fi
        done
        if [ $retry_count -eq 3 ]; then
            warning "Security group $SG_ID could not be deleted due to dependencies. Please delete manually."
        fi
    fi
    
    # Delete IAM resources
    log "Cleaning up IAM resources..."
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || ""
    # Clean up instance profile (handle numeric stack names)
    local profile_name
    if [[ "${STACK_NAME}" =~ ^[0-9] ]]; then
        local clean_name=$(echo "${STACK_NAME}" | sed 's/[^a-zA-Z0-9]//g')
        profile_name="app-${clean_name}-profile"
    else
        profile_name="${STACK_NAME}-instance-profile"
    fi
    
    aws iam remove-role-from-instance-profile --instance-profile-name "$profile_name" --role-name "${STACK_NAME}-role" 2>/dev/null || true
    aws iam delete-instance-profile --instance-profile-name "$profile_name" 2>/dev/null || true
    aws iam detach-role-policy --role-name "${STACK_NAME}-role" --policy-arn "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" 2>/dev/null || true
    aws iam detach-role-policy --role-name "${STACK_NAME}-role" --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" 2>/dev/null || true
    if [ ! -z "$ACCOUNT_ID" ]; then
        aws iam detach-role-policy --role-name "${STACK_NAME}-role" --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${STACK_NAME}-custom-policy" 2>/dev/null || true
        aws iam delete-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${STACK_NAME}-custom-policy" 2>/dev/null || true
    fi
    aws iam delete-role --role-name "${STACK_NAME}-role" 2>/dev/null || true
    
    # Delete key pair and local files
    log "Deleting key pair and temporary files..."
    aws ec2 delete-key-pair --key-name "$KEY_NAME" --region "$AWS_REGION" || true
    rm -f "${KEY_NAME}.pem" user-data-ondemand.sh trust-policy.json custom-policy.json deploy-app-ondemand.sh disabled-config.json
    
    warning "Cleanup completed. Please verify in AWS console that all resources are deleted."
}

# =============================================================================
# MAIN DEPLOYMENT FLOW
# =============================================================================

main() {
    echo -e "${CYAN}"
    cat << 'EOF'
 _____ _____   _____ _             _            _   _ _ _   
|  _  |     | |   __| |_ ___ ___ _| |_ ___ ___  | | | |_| |_ 
|     |-   -| |__   |  _| .'|  _|  _| -_|  _|  | |_| | |  _|
|__|__|_____| |_____|_| |__,|_| |_| |___|_|    |___|_|_|_|  
                                                           
EOF
    echo -e "${NC}"
    echo -e "${BLUE}On-Demand AWS Deployment (100% Spot-Free)${NC}"
    echo -e "${BLUE}Reliable | No Limits | Guaranteed Availability${NC}"
    echo ""
    
    # Set error trap
    trap cleanup_on_error ERR
    
    # Run deployment steps
    check_prerequisites
    
    log "Starting on-demand AWS deployment (no spot instances)..."
    
    # Mark that we're starting to create resources
    RESOURCES_CREATED=true
    
    create_key_pair
    create_iam_role
    
    SG_ID=$(create_security_group)
    EFS_DNS=$(create_efs "$SG_ID")
    
    # Launch on-demand instance
    INSTANCE_INFO=$(launch_on_demand_instance "$SG_ID" "$EFS_DNS")
    INSTANCE_ID=$(echo "$INSTANCE_INFO" | cut -d: -f1)
    PUBLIC_IP=$(echo "$INSTANCE_INFO" | cut -d: -f2)
    INSTANCE_AZ=$(echo "$INSTANCE_INFO" | cut -d: -f3)

    # Now create EFS mount target in the AZ where instance was actually launched
    create_efs_mount_target "$SG_ID" "$INSTANCE_AZ"

    TARGET_GROUP_ARN=$(create_target_group "$SG_ID" "$INSTANCE_ID")
    QDRANT_TG_ARN=$(create_qdrant_target_group "$SG_ID" "$INSTANCE_ID")
    ALB_DNS=$(create_alb "$SG_ID" "$TARGET_GROUP_ARN" "$QDRANT_TG_ARN")
    
    setup_cloudfront "$ALB_DNS"
    
    wait_for_instance_ready "$PUBLIC_IP"
    deploy_application "$PUBLIC_IP" "$EFS_DNS" "$INSTANCE_ID"
    setup_monitoring "$PUBLIC_IP"
    validate_deployment "$PUBLIC_IP"
    
    display_results "$PUBLIC_IP" "$INSTANCE_ID" "$EFS_DNS" "$INSTANCE_AZ"
    
    # Clean up temporary files
    rm -f user-data-ondemand.sh trust-policy.json custom-policy.json deploy-app-ondemand.sh
    
    success "GeuseMaker deployment completed successfully!"
}

# =============================================================================
# COMMAND LINE INTERFACE
# =============================================================================

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "On-Demand Instance Deployment (No Spot Instances)"
    echo "=================================================="
    echo ""
    echo "This script deploys the AI starter kit using the NVIDIA GPU-Optimized AMI"
    echo "Product ID: 676eed8d-dcf5-4784-87d7-0de463205c17"
    echo ""
    echo "Requirements:"
    echo "  - AWS account with NVIDIA GPU-Optimized AMI subscription"
    echo "  - Valid AWS credentials configured"
    echo "  - Docker and AWS CLI installed"
    echo ""
    echo "Options:"
    echo "  --region REGION         AWS region (default: us-east-1)"
    echo "  --instance-type TYPE    Instance type (default: g4dn.xlarge)"
    echo "  --key-name NAME         SSH key name (default: GeuseMaker-ondemand-key)"
    echo "  --stack-name NAME       Stack name (default: GeuseMaker-ondemand)"
    echo "  --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with defaults"
    echo "  $0 --region us-west-2                # Deploy in different region"
    echo "  $0 --instance-type g4dn.2xlarge      # Use larger instance"
    echo ""
    echo "Benefits of On-Demand Deployment:"
    echo "  • No spot instance count limits"
    echo "  • Guaranteed availability" 
    echo "  • Instant launch"
    echo "  • Predictable costs"
    echo "  • Full infrastructure (EFS, ALB, CloudFront)"
    echo "  • NVIDIA GPU-Optimized AMI for best performance"
    echo ""
    echo "Cost: ~$0.75/hour (~$18/day) for g4dn.xlarge on-demand"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --instance-type)
            INSTANCE_TYPE="$2"
            shift 2
            ;;
        --key-name)
            KEY_NAME="$2"
            shift 2
            ;;
        --stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Run main function
main "$@" 