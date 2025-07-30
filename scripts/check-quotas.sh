#!/usr/bin/env bash

# Quick quota and pricing check script
# Usage: ./scripts/check-quotas.sh [instance-type] [region]

set -euo pipefail

# Standard library loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load the library loader
source "$PROJECT_ROOT/lib/utils/library-loader.sh"

# Initialize script with required modules
initialize_script "check-quotas.sh" "core/variables" "core/logging"

# Configuration
INSTANCE_TYPE="${1:-g4dn.xlarge}"
AWS_REGION="${2:-us-east-1}"

echo -e "${CYAN}========================================${NC}"
echo -e "${GREEN}  Quick AWS Quota & Pricing Check      ${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "${BLUE}Instance Type: $INSTANCE_TYPE${NC}"
echo -e "${BLUE}Region: $AWS_REGION${NC}"
echo ""

# Check AWS CLI and credentials
if ! command -v aws &> /dev/null; then
    error "AWS CLI not found. Please install AWS CLI first."
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

# Check service quotas
log "Checking service quotas..."

# Check G and VT Spot Instance Requests (GPU instances)
GPU_SPOT_QUOTA=$(aws service-quotas get-service-quota \
    --service-code ec2 \
    --quota-code L-34B43A08 \
    --region "$AWS_REGION" \
    --query 'Quota.Value' \
    --output text 2>/dev/null || echo "N/A")

# Check Standard Spot Instance Requests
STANDARD_SPOT_QUOTA=$(aws service-quotas get-service-quota \
    --service-code ec2 \
    --quota-code L-3819A6DF \
    --region "$AWS_REGION" \
    --query 'Quota.Value' \
    --output text 2>/dev/null || echo "N/A")

# Get instance type vCPU count
VCPU_COUNT=$(aws ec2 describe-instance-types \
    --instance-types "$INSTANCE_TYPE" \
    --region "$AWS_REGION" \
    --query 'InstanceTypes[0].VCpuInfo.DefaultVCpus' \
    --output text 2>/dev/null || echo "N/A")

echo -e "${CYAN}Service Quota Results:${NC}"
echo -e "  Instance Type: $INSTANCE_TYPE (${VCPU_COUNT} vCPUs)"
echo -e "  GPU Spot Quota: $GPU_SPOT_QUOTA vCPUs"
echo -e "  Standard Spot Quota: $STANDARD_SPOT_QUOTA vCPUs"

# Check if GPU quota is sufficient
if [[ "$GPU_SPOT_QUOTA" != "N/A" && "$VCPU_COUNT" != "N/A" ]]; then
    if (( $(echo "$VCPU_COUNT > $GPU_SPOT_QUOTA" | bc -l 2>/dev/null || echo "0") )); then
        error "❌ INSUFFICIENT GPU SPOT QUOTA"
        error "  Required: $VCPU_COUNT vCPUs"
        error "  Available: $GPU_SPOT_QUOTA vCPUs"
        echo ""
        error "🔧 TO FIX: Request quota increase for 'All G and VT Spot Instance Requests'"
        error "📋 Link: https://console.aws.amazon.com/servicequotas/home/services/ec2/quotas/L-34B43A08"
        QUOTA_OK=false
    else
        success "✓ GPU spot quota sufficient ($VCPU_COUNT ≤ $GPU_SPOT_QUOTA vCPUs)"
        QUOTA_OK=true
    fi
else
    warning "⚠️  Could not verify quotas"
    QUOTA_OK=false
fi

echo ""

# Check instance type availability
log "Checking instance type availability..."
AVAILABLE_AZS=$(aws ec2 describe-instance-type-offerings \
    --location-type availability-zone \
    --filters "Name=instance-type,Values=$INSTANCE_TYPE" \
    --region "$AWS_REGION" \
    --query 'InstanceTypeOfferings[].Location' \
    --output text 2>/dev/null || echo "")

if [[ -n "$AVAILABLE_AZS" && "$AVAILABLE_AZS" != "None" ]]; then
    success "✓ $INSTANCE_TYPE available in AZs: $AVAILABLE_AZS"
else
    error "❌ $INSTANCE_TYPE not available in region $AWS_REGION"
    exit 1
fi

echo ""

# Check current spot pricing
log "Checking current spot pricing..."
SPOT_PRICES=$(aws ec2 describe-spot-price-history \
    --instance-types "$INSTANCE_TYPE" \
    --product-descriptions "Linux/UNIX" \
    --max-items 10 \
    --region "$AWS_REGION" \
    --query 'SpotPriceHistory[0:5].[AvailabilityZone,SpotPrice,Timestamp]' \
    --output table 2>/dev/null || echo "")

if [[ -n "$SPOT_PRICES" && "$SPOT_PRICES" != *"None"* ]]; then
    info "Recent spot prices for $INSTANCE_TYPE:"
    echo "$SPOT_PRICES"
    
    # Get lowest price
    LOWEST_PRICE=$(aws ec2 describe-spot-price-history \
        --instance-types "$INSTANCE_TYPE" \
        --product-descriptions "Linux/UNIX" \
        --max-items 20 \
        --region "$AWS_REGION" \
        --query 'SpotPriceHistory | min_by(@, &SpotPrice).SpotPrice' \
        --output text 2>/dev/null || echo "N/A")
    
    if [[ "$LOWEST_PRICE" != "N/A" ]]; then
        info "Lowest current price: \$$LOWEST_PRICE/hour"
    fi
else
    warning "⚠️  Could not retrieve spot pricing data"
fi

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${GREEN}         Summary                        ${NC}"
echo -e "${CYAN}========================================${NC}"

if [[ "$QUOTA_OK" == "true" ]]; then
    success "✅ Ready to deploy! Quotas are sufficient."
else
    error "❌ Not ready to deploy. Please fix quota issues first."
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Request quota increase for GPU spot instances"
    echo "2. Wait for approval (usually 24-48 hours)"
    echo "3. Run this check again: ./scripts/check-quotas.sh"
fi 