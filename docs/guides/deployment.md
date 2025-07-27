# Deployment Guide

This guide covers all deployment methods for the GeuseMaker AI infrastructure platform using the modular deployment system.

## Prerequisites

- AWS Account with appropriate permissions
- AWS CLI configured (`aws configure`)
- Docker installed locally
- Make installed
- Bash 3.x+ (macOS) or 4.x+ (Linux)

## Quick Start

```bash
# Initial setup
make setup

# Deploy development environment
make deploy-simple STACK_NAME=dev

# Deploy production with spot instances
make deploy-spot STACK_NAME=prod
```

## Deployment Methods

### 1. Simple Development Deployment

For quick development environments with minimal configuration:

```bash
make deploy-simple STACK_NAME=my-dev
# or
./scripts/aws-deployment-v2-simple.sh my-dev
```

**Features:**
- Single EC2 instance
- Basic networking (default VPC)
- All AI services on one instance
- No load balancer or CDN
- Cost: ~$0.10-0.20/hour

### 2. Production Spot Instance Deployment

For cost-optimized production environments:

```bash
make deploy-spot STACK_NAME=prod
# or
./scripts/aws-deployment-modular.sh --spot prod
```

**Features:**
- Spot instances (70% cost savings)
- Intelligent cross-region failover
- Auto-recovery from interruptions
- EFS for persistent storage
- Cost: ~$0.05-0.10/hour

### 3. Enterprise Multi-AZ Deployment

For high-availability production environments:

```bash
./scripts/aws-deployment-modular.sh \
  --multi-az \
  --private-subnets \
  --nat-gateway \
  --alb \
  --spot \
  STACK_NAME
```

**Features:**
- Multi-AZ deployment
- Private subnets with NAT Gateway
- Application Load Balancer
- CloudFront CDN option
- Auto-scaling ready
- Cost: ~$0.20-0.40/hour

## Configuration Options

### Instance Types

Default: `g4dn.xlarge` (4 vCPUs, 16GB RAM, T4 GPU)

```bash
# Specify custom instance type
./scripts/aws-deployment-modular.sh -t g5.xlarge prod

# Available GPU instances:
# - g4dn.xlarge: T4 GPU, best value
# - g4dn.2xlarge: T4 GPU, more CPU
# - g5.xlarge: A10G GPU, better performance
# - g5.2xlarge: A10G GPU, maximum performance
```

### Regions

Default: `us-east-1`

```bash
# Deploy to specific region
./scripts/aws-deployment-modular.sh -r us-west-2 prod

# Automatic fallback regions:
# us-east-1 → us-east-2 → us-west-2
# eu-west-1 → eu-west-2 → eu-central-1
```

### Advanced Options

```bash
# All available options
./scripts/aws-deployment-modular.sh \
  --instance-type g4dn.xlarge \    # EC2 instance type
  --region us-east-1 \              # AWS region
  --spot \                          # Use spot instances
  --multi-az \                      # Multi-AZ deployment
  --private-subnets \               # Use private subnets
  --nat-gateway \                   # Create NAT Gateway
  --alb \                          # Create Load Balancer
  --no-efs \                       # Skip EFS creation
  --environment production \        # Environment tag
  --skip-validation \              # Skip pre-checks
  STACK_NAME
```

## Service Access

After deployment, access your services:

```bash
# Get instance IP
make status STACK_NAME=prod

# Service URLs (replace YOUR_IP):
# n8n:      http://YOUR_IP:5678
# Ollama:   http://YOUR_IP:11434
# Qdrant:   http://YOUR_IP:6333
# Crawl4AI: http://YOUR_IP:11235
```

## Security Configuration

### Parameter Store Setup

```bash
# Setup required secrets
./scripts/setup-parameter-store.sh

# Required parameters:
# /aibuildkit/OPENAI_API_KEY
# /aibuildkit/n8n/ENCRYPTION_KEY
# /aibuildkit/POSTGRES_PASSWORD
# /aibuildkit/WEBHOOK_URL
```

### Security Groups

The deployment automatically configures:
- SSH access (port 22) from your IP
- Service ports only from ALB (if enabled)
- Outbound HTTPS for updates
- Inter-service communication

## Monitoring and Health Checks

```bash
# Basic health check
make health-check STACK_NAME=prod

# Advanced diagnostics
make health-check-advanced STACK_NAME=prod

# View logs
ssh -i ~/.ssh/aibuildkit-prod.pem ubuntu@YOUR_IP
docker compose logs -f
```

## Cost Optimization

### Spot Instance Strategies

1. **Automatic Failover**: System tries multiple instance types and regions
2. **Price Caching**: Reduces API calls and speeds deployment
3. **Intelligent Selection**: Chooses optimal price/performance ratio

### Cost Estimates

| Deployment Type | Hourly Cost | Monthly Cost |
|----------------|-------------|--------------|
| Simple (on-demand) | $0.52 | $380 |
| Spot (single AZ) | $0.15 | $110 |
| Enterprise (multi-AZ) | $0.40 | $290 |

## Troubleshooting

### Common Issues

1. **Spot capacity unavailable**
   - System automatically tries fallback regions
   - Check CloudWatch for capacity events

2. **Services not starting**
   - Check disk space: `df -h`
   - View logs: `docker compose logs`

3. **GPU not detected**
   - Verify instance type supports GPU
   - Check NVIDIA drivers: `nvidia-smi`

### Debug Commands

```bash
# Check deployment status
./scripts/check-instance-status.sh STACK_NAME

# Fix deployment issues
./scripts/fix-deployment-issues.sh STACK_NAME REGION

# Validate environment
./scripts/validate-environment.sh
```

## Cleanup

```bash
# Destroy all resources
make destroy STACK_NAME=prod

# Cleanup failed deployments
./scripts/cleanup-consolidated.sh --stack STACK_NAME
```

## Next Steps

- [Architecture Guide](architecture.md) - Understand the system design
- [Testing Guide](testing.md) - Test your deployment
- [Troubleshooting Guide](troubleshooting.md) - Resolve common issues