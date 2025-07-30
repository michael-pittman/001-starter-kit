#!/bin/bash

# User Acceptance Testing - Interactive Deployment Experience
# Tests user-friendly deployment interfaces and workflows

set -euo pipefail

# Colors for better UX
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/lib/modules/core/logging.sh"

# Interactive deployment wizard
deployment_wizard() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           GeuseMaker Deployment Wizard v2.0                ║${NC}"
    echo -e "${BLUE}║                                                            ║${NC}"
    echo -e "${BLUE}║  Welcome! This wizard will guide you through deploying     ║${NC}"
    echo -e "${BLUE}║  your AI infrastructure stack on AWS.                      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Stack name
    echo -e "${GREEN}Step 1: Stack Name${NC}"
    echo "Enter a name for your deployment (e.g., dev-stack, prod-ai):"
    read -p "> " STACK_NAME
    
    # Validate stack name
    if [[ ! "$STACK_NAME" =~ ^[a-zA-Z][a-zA-Z0-9-]{0,127}$ ]]; then
        echo -e "${RED}✗ Invalid stack name. Use only letters, numbers, and hyphens.${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Stack name: $STACK_NAME${NC}"
    echo ""
    
    # Environment type
    echo -e "${GREEN}Step 2: Environment Type${NC}"
    echo "Select your environment:"
    echo "  1) Development (cost-optimized, single AZ)"
    echo "  2) Staging (balanced performance, optional multi-AZ)"
    echo "  3) Production (high availability, multi-AZ, CDN)"
    read -p "Choice [1-3]: " ENV_CHOICE
    
    case $ENV_CHOICE in
        1)
            ENV_TYPE="development"
            DEPLOYMENT_FLAGS="--spot"
            echo -e "${GREEN}✓ Development environment selected${NC}"
            ;;
        2)
            ENV_TYPE="staging"
            DEPLOYMENT_FLAGS="--spot --alb"
            echo -e "${GREEN}✓ Staging environment selected${NC}"
            ;;
        3)
            ENV_TYPE="production"
            DEPLOYMENT_FLAGS="--spot --alb --cloudfront --multi-az"
            echo -e "${GREEN}✓ Production environment selected${NC}"
            ;;
        *)
            echo -e "${RED}✗ Invalid choice${NC}"
            return 1
            ;;
    esac
    echo ""
    
    # Instance type selection with recommendations
    echo -e "${GREEN}Step 3: Instance Type${NC}"
    echo "Select GPU instance type for AI workloads:"
    echo ""
    echo "  1) g4dn.xlarge  - 1 GPU, 16GB, $0.21/hr spot (Recommended for dev)"
    echo "  2) g4dn.2xlarge - 1 GPU, 32GB, $0.30/hr spot"
    echo "  3) g5.xlarge    - 1 GPU, 24GB, $0.18/hr spot (Best value)"
    echo "  4) g5.2xlarge   - 1 GPU, 32GB, $0.25/hr spot"
    echo "  5) Custom       - Enter your own instance type"
    echo ""
    echo -e "${YELLOW}💡 Tip: g5.xlarge offers best price/performance for most workloads${NC}"
    read -p "Choice [1-5]: " INSTANCE_CHOICE
    
    case $INSTANCE_CHOICE in
        1) INSTANCE_TYPE="g4dn.xlarge" ;;
        2) INSTANCE_TYPE="g4dn.2xlarge" ;;
        3) INSTANCE_TYPE="g5.xlarge" ;;
        4) INSTANCE_TYPE="g5.2xlarge" ;;
        5)
            read -p "Enter instance type: " INSTANCE_TYPE
            ;;
        *)
            echo -e "${RED}✗ Invalid choice${NC}"
            return 1
            ;;
    esac
    
    echo -e "${GREEN}✓ Instance type: $INSTANCE_TYPE${NC}"
    echo ""
    
    # Region selection with latency info
    echo -e "${GREEN}Step 4: AWS Region${NC}"
    echo "Select deployment region:"
    echo ""
    echo "  1) us-west-2     - Oregon (lowest cost, good GPU availability)"
    echo "  2) us-east-1     - Virginia (lowest latency for East Coast)"
    echo "  3) eu-west-1     - Ireland (EU compliance)"
    echo "  4) ap-southeast-1 - Singapore (Asia-Pacific)"
    echo "  5) Current region - $(aws configure get region 2>/dev/null || echo "not set")"
    read -p "Choice [1-5]: " REGION_CHOICE
    
    case $REGION_CHOICE in
        1) AWS_REGION="us-west-2" ;;
        2) AWS_REGION="us-east-1" ;;
        3) AWS_REGION="eu-west-1" ;;
        4) AWS_REGION="ap-southeast-1" ;;
        5) AWS_REGION="$(aws configure get region)" ;;
        *)
            echo -e "${RED}✗ Invalid choice${NC}"
            return 1
            ;;
    esac
    
    echo -e "${GREEN}✓ Region: $AWS_REGION${NC}"
    echo ""
    
    # Cost estimation
    echo -e "${GREEN}Step 5: Cost Estimation${NC}"
    echo "Calculating estimated costs..."
    sleep 1
    
    # Simple cost calculation
    SPOT_PRICE="0.21"  # Default for g4dn.xlarge
    case $INSTANCE_TYPE in
        g4dn.2xlarge) SPOT_PRICE="0.30" ;;
        g5.xlarge) SPOT_PRICE="0.18" ;;
        g5.2xlarge) SPOT_PRICE="0.25" ;;
    esac
    
    HOURLY_COST=$SPOT_PRICE
    DAILY_COST=$(awk "BEGIN {printf \"%.2f\", $HOURLY_COST * 24}")
    MONTHLY_COST=$(awk "BEGIN {printf \"%.2f\", $DAILY_COST * 30}")
    SAVINGS=$(awk "BEGIN {printf \"%.0f\", 70}")
    
    echo -e "${BLUE}┌─────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│       Estimated Costs (Spot)        │${NC}"
    echo -e "${BLUE}├─────────────────────────────────────┤${NC}"
    echo -e "${BLUE}│ Hourly:   \$${HOURLY_COST}/hr                   │${NC}"
    echo -e "${BLUE}│ Daily:    \$${DAILY_COST}/day                  │${NC}"
    echo -e "${BLUE}│ Monthly:  \$${MONTHLY_COST}/month              │${NC}"
    echo -e "${BLUE}│                                     │${NC}"
    echo -e "${BLUE}│ ${GREEN}Savings:  ${SAVINGS}% vs on-demand${NC}       ${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────┘${NC}"
    echo ""
    
    # Additional features
    echo -e "${GREEN}Step 6: Additional Features${NC}"
    echo "Would you like to enable any additional features?"
    echo ""
    
    read -p "Enable automated backups? [y/N]: " ENABLE_BACKUPS
    read -p "Enable monitoring dashboard? [y/N]: " ENABLE_MONITORING
    read -p "Enable auto-scaling? [y/N]: " ENABLE_AUTOSCALING
    
    # Deployment summary
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                    Deployment Summary                          ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "Stack Name:        ${GREEN}$STACK_NAME${NC}"
    echo -e "Environment:       ${GREEN}$ENV_TYPE${NC}"
    echo -e "Instance Type:     ${GREEN}$INSTANCE_TYPE${NC}"
    echo -e "Region:           ${GREEN}$AWS_REGION${NC}"
    echo -e "Estimated Cost:   ${GREEN}\$${MONTHLY_COST}/month${NC}"
    echo -e "Features:         ${GREEN}$DEPLOYMENT_FLAGS${NC}"
    
    [[ "$ENABLE_BACKUPS" == "y" ]] && echo -e "                  ${GREEN}✓ Automated Backups${NC}"
    [[ "$ENABLE_MONITORING" == "y" ]] && echo -e "                  ${GREEN}✓ Monitoring Dashboard${NC}"
    [[ "$ENABLE_AUTOSCALING" == "y" ]] && echo -e "                  ${GREEN}✓ Auto-scaling${NC}"
    
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Final confirmation
    echo -e "${YELLOW}Ready to deploy?${NC}"
    read -p "Deploy now? [y/N]: " CONFIRM_DEPLOY
    
    if [[ "$CONFIRM_DEPLOY" == "y" ]]; then
        echo ""
        echo -e "${GREEN}🚀 Starting deployment...${NC}"
        echo ""
        
        # Show deployment command
        echo "Executing: AWS_REGION=$AWS_REGION ./scripts/aws-deployment-modular.sh $DEPLOYMENT_FLAGS --instance-type $INSTANCE_TYPE $STACK_NAME"
        
        # In real deployment, this would execute the actual command
        # For UAT, we just simulate
        echo ""
        echo -e "${YELLOW}[UAT Mode: Simulating deployment]${NC}"
        
        # Simulate progress
        show_deployment_progress
        
        echo ""
        echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
        echo ""
        echo "Next steps:"
        echo "  1. Check deployment status: make status STACK_NAME=$STACK_NAME"
        echo "  2. View application logs: make logs STACK_NAME=$STACK_NAME"
        echo "  3. Access services:"
        echo "     - n8n: http://your-alb-url:5678"
        echo "     - Ollama: http://your-alb-url:11434"
        echo ""
    else
        echo -e "${YELLOW}Deployment cancelled.${NC}"
    fi
}

# Simulate deployment progress
show_deployment_progress() {
    local steps=(
        "Creating VPC and networking..."
        "Setting up security groups..."
        "Launching EC2 instance..."
        "Configuring storage (EFS)..."
        "Installing Docker and dependencies..."
        "Deploying AI services..."
        "Configuring load balancer..."
        "Running health checks..."
    )
    
    for step in "${steps[@]}"; do
        echo -ne "${step}"
        # Simulate progress dots
        for i in {1..3}; do
            sleep 0.5
            echo -n "."
        done
        echo -e " ${GREEN}✓${NC}"
    done
}

# Quick deployment mode
quick_deploy() {
    echo -e "${BLUE}GeuseMaker Quick Deploy${NC}"
    echo ""
    
    # Use sensible defaults
    STACK_NAME="quick-deploy-$(date +%s)"
    
    echo "This will deploy a development stack with:"
    echo "  • Stack name: $STACK_NAME"
    echo "  • Instance: g5.xlarge (best value)"
    echo "  • Region: $(aws configure get region || echo "us-west-2")"
    echo "  • Features: Spot instance (70% savings)"
    echo ""
    
    read -p "Continue? [y/N]: " CONFIRM
    
    if [[ "$CONFIRM" == "y" ]]; then
        echo -e "${GREEN}🚀 Deploying...${NC}"
        show_deployment_progress
        echo -e "${GREEN}✅ Quick deployment completed!${NC}"
    fi
}

# Help system with examples
show_interactive_help() {
    clear
    echo -e "${BLUE}GeuseMaker Help System${NC}"
    echo ""
    echo "Available deployment modes:"
    echo ""
    echo -e "${GREEN}1. Wizard Mode${NC} (Recommended for first-time users)"
    echo "   Interactive step-by-step deployment guide"
    echo "   Example: ./deploy.sh wizard"
    echo ""
    echo -e "${GREEN}2. Quick Deploy${NC} (For developers)"
    echo "   Deploy with sensible defaults in one command"
    echo "   Example: ./deploy.sh quick"
    echo ""
    echo -e "${GREEN}3. Advanced Mode${NC} (For DevOps)"
    echo "   Full control with command-line options"
    echo "   Example: ./deploy.sh --spot --alb --multi-az prod-stack"
    echo ""
    echo "Common tasks:"
    echo "  • Check costs:    ./deploy.sh estimate"
    echo "  • View status:    ./deploy.sh status STACK_NAME"
    echo "  • Get help:       ./deploy.sh help"
    echo ""
    echo -e "${YELLOW}💡 Tip: Use 'wizard' mode for your first deployment${NC}"
}

# Cost calculator
cost_calculator() {
    echo -e "${BLUE}GeuseMaker Cost Calculator${NC}"
    echo ""
    echo "Enter your requirements:"
    
    read -p "Number of instances [1]: " NUM_INSTANCES
    NUM_INSTANCES=${NUM_INSTANCES:-1}
    
    read -p "Hours per day [24]: " HOURS_PER_DAY
    HOURS_PER_DAY=${HOURS_PER_DAY:-24}
    
    read -p "Days per month [30]: " DAYS_PER_MONTH
    DAYS_PER_MONTH=${DAYS_PER_MONTH:-30}
    
    echo ""
    echo "Instance type costs (spot prices):"
    echo ""
    
    # Calculate costs for each instance type
    declare -A SPOT_PRICES=(
        ["g4dn.xlarge"]="0.21"
        ["g4dn.2xlarge"]="0.30"
        ["g5.xlarge"]="0.18"
        ["g5.2xlarge"]="0.25"
    )
    
    for instance in "${!SPOT_PRICES[@]}"; do
        price="${SPOT_PRICES[$instance]}"
        monthly=$(awk "BEGIN {printf \"%.2f\", $price * $HOURS_PER_DAY * $DAYS_PER_MONTH * $NUM_INSTANCES}")
        ondemand=$(awk "BEGIN {printf \"%.2f\", $monthly / 0.3}")  # Assume 70% savings
        savings=$(awk "BEGIN {printf \"%.2f\", $ondemand - $monthly}")
        
        echo "$instance:"
        echo "  Spot:      \$$monthly/month"
        echo "  On-demand: \$$ondemand/month"
        echo "  Savings:   \$$savings/month (70%)"
        echo ""
    done
}

# Main menu
main_menu() {
    while true; do
        clear
        echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║        GeuseMaker UAT Interactive Test             ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "Select a test scenario:"
        echo ""
        echo "  1) Deployment Wizard        - Step-by-step deployment"
        echo "  2) Quick Deploy            - One-click deployment"
        echo "  3) Cost Calculator         - Estimate your costs"
        echo "  4) Interactive Help        - Learn about features"
        echo "  5) Error Simulation        - Test error handling"
        echo "  6) Exit"
        echo ""
        read -p "Choice [1-6]: " choice
        
        case $choice in
            1) deployment_wizard ;;
            2) quick_deploy ;;
            3) cost_calculator ;;
            4) show_interactive_help ;;
            5) simulate_errors ;;
            6) exit 0 ;;
            *) echo -e "${RED}Invalid choice${NC}" ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Error simulation for UAT
simulate_errors() {
    echo -e "${BLUE}Error Handling Test${NC}"
    echo ""
    echo "Simulating common deployment errors..."
    echo ""
    
    # Simulate spot capacity error
    echo -e "${RED}ERROR: InsufficientSpotCapacity${NC}"
    echo "No g4dn.xlarge spot capacity in us-west-2a"
    echo ""
    echo -e "${YELLOW}SUGGESTION:${NC}"
    echo "  • Try different availability zones"
    echo "  • Use alternative instance: g5.xlarge"
    echo "  • Enable multi-AZ deployment"
    echo ""
    echo "Would you like to:"
    echo "  1) Retry with g5.xlarge"
    echo "  2) Try different region"
    echo "  3) Use on-demand pricing"
    read -p "Choice [1-3]: " error_choice
    
    echo ""
    echo -e "${GREEN}✓ Retrying with suggested fix...${NC}"
    sleep 2
    echo -e "${GREEN}✓ Deployment successful with g5.xlarge${NC}"
}

# Run appropriate mode based on arguments
case "${1:-menu}" in
    wizard)
        deployment_wizard
        ;;
    quick)
        quick_deploy
        ;;
    help)
        show_interactive_help
        ;;
    cost)
        cost_calculator
        ;;
    menu|*)
        main_menu
        ;;
esac