#!/bin/bash
# Unity Interactive Tutorial: First Deployment
# This tutorial guides you through your first Unity deployment

set -euo pipefail

# Colors for interactive output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Tutorial functions
print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_step() {
    echo -e "${GREEN}▶${NC} $1"
}

print_info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

wait_for_enter() {
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read -r
}

# Main tutorial
main() {
    clear
    print_header "Welcome to Unity - First Deployment Tutorial"
    
    echo "This interactive tutorial will guide you through:"
    echo "1. Initializing Unity"
    echo "2. Configuring your environment"
    echo "3. Deploying your first stack"
    echo "4. Verifying the deployment"
    echo "5. Cleaning up resources"
    
    wait_for_enter
    
    # Step 1: Check Prerequisites
    print_header "Step 1: Checking Prerequisites"
    
    print_step "Checking Unity installation..."
    if [[ -f "./scripts/unity-cli.sh" ]]; then
        print_success "Unity CLI found"
    else
        print_error "Unity CLI not found. Please ensure you're in the Unity directory."
        exit 1
    fi
    
    print_step "Checking AWS credentials..."
    if aws sts get-caller-identity &>/dev/null; then
        print_success "AWS credentials configured"
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        print_info "Using AWS Account: $ACCOUNT_ID"
    else
        print_error "AWS credentials not configured. Please run 'aws configure'"
        exit 1
    fi
    
    wait_for_enter
    
    # Step 2: Initialize Unity
    print_header "Step 2: Initializing Unity System"
    
    print_step "Initializing Unity core components..."
    echo -e "${YELLOW}Running: ./scripts/unity-cli.sh init${NC}"
    
    # Simulate initialization
    echo "✓ Unity core initialized"
    echo "✓ Service registry created"
    echo "✓ Event bus started"
    echo "✓ Configuration loaded"
    
    print_success "Unity initialization complete!"
    
    wait_for_enter
    
    # Step 3: Configure Environment
    print_header "Step 3: Configuring Your Environment"
    
    print_step "Let's set up your deployment configuration..."
    
    # Get user input
    echo -n "AWS Region [us-east-1]: "
    read -r AWS_REGION
    AWS_REGION=${AWS_REGION:-us-east-1}
    
    echo -n "Environment name [development]: "
    read -r ENVIRONMENT
    ENVIRONMENT=${ENVIRONMENT:-development}
    
    echo -n "Enable spot instances? [Y/n]: "
    read -r ENABLE_SPOT
    ENABLE_SPOT=${ENABLE_SPOT:-Y}
    
    echo -n "Your email for alerts: "
    read -r ALERT_EMAIL
    
    print_info "Configuration summary:"
    echo "  Region: $AWS_REGION"
    echo "  Environment: $ENVIRONMENT"
    echo "  Spot Instances: $ENABLE_SPOT"
    echo "  Alert Email: $ALERT_EMAIL"
    
    wait_for_enter
    
    # Step 4: Deploy First Stack
    print_header "Step 4: Deploying Your First Stack"
    
    STACK_NAME="unity-tutorial-$(date +%s)"
    print_step "Deploying stack: $STACK_NAME"
    
    echo -e "${YELLOW}Running: ./scripts/unity-cli.sh deploy $STACK_NAME --instance-type t3.micro --simple${NC}"
    
    # Simulate deployment progress
    echo ""
    for stage in "Creating VPC" "Setting up security groups" "Launching EC2 instance" "Configuring application" "Running health checks"; do
        echo -n "  $stage"
        for i in {1..3}; do
            sleep 0.5
            echo -n "."
        done
        echo " ✓"
    done
    
    print_success "Deployment completed successfully!"
    
    # Show deployment info
    print_info "Stack Information:"
    echo "  Stack Name: $STACK_NAME"
    echo "  Instance Type: t3.micro"
    echo "  Public IP: 54.123.45.67 (example)"
    echo "  Application URL: http://54.123.45.67:5678"
    
    wait_for_enter
    
    # Step 5: Verify Deployment
    print_header "Step 5: Verifying Your Deployment"
    
    print_step "Let's check the deployment status..."
    
    echo -e "${YELLOW}Running: ./scripts/unity-cli.sh status $STACK_NAME${NC}"
    echo ""
    echo "Stack Status: RUNNING"
    echo "Health Check: HEALTHY"
    echo "Uptime: 2 minutes"
    
    print_step "View application logs..."
    echo -e "${YELLOW}Running: ./scripts/unity-cli.sh logs $STACK_NAME --tail 5${NC}"
    echo ""
    echo "[2024-01-15 10:00:00] INFO: Application started successfully"
    echo "[2024-01-15 10:00:05] INFO: Health check endpoint ready"
    echo "[2024-01-15 10:00:10] INFO: Connected to database"
    echo "[2024-01-15 10:00:15] INFO: All services operational"
    echo "[2024-01-15 10:00:20] INFO: Ready to accept requests"
    
    print_success "Deployment verified and healthy!"
    
    wait_for_enter
    
    # Step 6: Explore Unity Features
    print_header "Step 6: Exploring Unity Features"
    
    print_info "Now that your stack is running, try these commands:"
    echo ""
    echo "  # Monitor your deployment"
    echo "  ./scripts/unity-cli.sh monitor $STACK_NAME --follow"
    echo ""
    echo "  # View detailed information"
    echo "  ./scripts/unity-cli.sh info $STACK_NAME --detailed"
    echo ""
    echo "  # Check costs"
    echo "  ./scripts/unity-cli.sh cost analyze --stack $STACK_NAME"
    echo ""
    echo "  # Scale your deployment"
    echo "  ./scripts/unity-cli.sh scale $STACK_NAME --instances 2"
    
    wait_for_enter
    
    # Step 7: Cleanup
    print_header "Step 7: Cleaning Up Resources"
    
    print_step "To avoid charges, let's destroy the tutorial stack..."
    
    echo -n "Do you want to destroy the stack now? [Y/n]: "
    read -r DESTROY_CONFIRM
    DESTROY_CONFIRM=${DESTROY_CONFIRM:-Y}
    
    if [[ "$DESTROY_CONFIRM" =~ ^[Yy] ]]; then
        echo -e "${YELLOW}Running: ./scripts/unity-cli.sh destroy $STACK_NAME${NC}"
        echo ""
        echo -n "Destroying resources"
        for i in {1..5}; do
            sleep 0.5
            echo -n "."
        done
        echo " ✓"
        
        print_success "Stack destroyed successfully!"
    else
        print_info "Remember to destroy the stack later with:"
        echo "  ./scripts/unity-cli.sh destroy $STACK_NAME"
    fi
    
    # Tutorial Complete
    print_header "Tutorial Complete! 🎉"
    
    echo "Congratulations! You've successfully:"
    echo "✓ Initialized Unity"
    echo "✓ Configured your environment"
    echo "✓ Deployed your first stack"
    echo "✓ Verified the deployment"
    echo "✓ Learned basic Unity commands"
    
    echo -e "\n${GREEN}Next Steps:${NC}"
    echo "1. Explore the Unity documentation: docs/unity/"
    echo "2. Try the AWS deployment tutorial: ./examples/unity/aws-deployment/production-deploy.sh"
    echo "3. Learn about plugins: ./examples/unity/plugin-development/create-plugin.sh"
    echo "4. Join the Unity community: #unity on Slack"
    
    echo -e "\n${BLUE}Thank you for trying Unity!${NC}"
}

# Run the tutorial
main "$@"