# Deployment Guide

This guide covers all deployment methods for the GeuseMaker AI infrastructure platform using the modular deployment system.

## Prerequisites

- AWS Account with appropriate permissions
- AWS CLI v2 configured (`aws configure`)
- Docker installed locally
- Make installed
- Bash 3.x+ (compatible with all major systems)

## Quick Start

```bash
# Initial setup
make setup

# Deploy development environment
make deploy-spot ENV=dev STACK_NAME=dev

# Deploy production with spot instances
make deploy-spot ENV=prod STACK_NAME=prod
```

## Deployment Methods

### 1. Spot Instance Deployment (Recommended)

For cost-optimized environments with automatic failover:

```bash
# Development deployment
make deploy-spot ENV=dev STACK_NAME=my-dev

# Production deployment
make deploy-spot ENV=prod STACK_NAME=my-prod

# Or use direct script
./deploy.sh --spot --env dev --stack-name my-stack
```

**Features:**
- Spot instances (70% cost savings)
- Intelligent cross-region failover
- Auto-recovery from interruptions
- EFS for persistent storage
- Cost: ~$0.05-0.10/hour

### 2. ALB Deployment (Load Balancer)

For environments requiring load balancing:

```bash
# Deploy with ALB
make deploy-alb ENV=staging STACK_NAME=my-stack

# Or use direct script
./deploy.sh --alb --env staging --stack-name my-stack
```

**Features:**
- Application Load Balancer
- Health checks and auto-scaling ready
- SSL termination support
- Cost: ~$0.15-0.25/hour

### 3. CDN Deployment (CloudFront)

For global content distribution:

```bash
# Deploy with CDN
make deploy-cdn ENV=prod STACK_NAME=my-stack

# Or use direct script
./deploy.sh --cdn --env prod --stack-name my-stack
```

**Features:**
- CloudFront CDN distribution
- Global edge locations
- Caching optimization
- Cost: ~$0.10-0.20/hour

### 4. Full Stack Deployment

For complete infrastructure with all components:

```bash
# Deploy complete stack
make deploy-full ENV=prod STACK_NAME=my-stack

# Or use direct script
./deploy.sh --full --env prod --stack-name my-stack
```

**Features:**
- VPC with public/private subnets
- EC2 instances with spot optimization
- Application Load Balancer
- CloudFront CDN
- Auto-scaling ready
- Cost: ~$0.20-0.40/hour

## Configuration Options

### Instance Types

Default: `g4dn.xlarge` (4 vCPUs, 16GB RAM, T4 GPU)

```bash
# Specify custom instance type via environment variable
export EC2_INSTANCE_TYPE=g5.xlarge
make deploy-spot ENV=dev STACK_NAME=my-stack

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
export AWS_REGION=us-west-2
make deploy-spot ENV=dev STACK_NAME=my-stack

# Automatic fallback regions:
# us-east-1 → us-east-2 → us-west-2
# eu-west-1 → eu-west-2 → eu-central-1
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ENV` | Environment name (dev/staging/prod) | `dev` |
| `PROFILE` | AWS profile to use | `$ENV` |
| `REGION` | AWS region | `us-east-1` |
| `STACK_NAME` | Stack name | `geusemaker-$ENV` |
| `EC2_INSTANCE_TYPE` | EC2 instance type | `g4dn.xlarge` |
| `VPC_CIDR` | VPC CIDR block | `10.0.0.0/16` |

## Service Access

After deployment, access your services:

```bash
# Get instance IP and service URLs
make status ENV=dev STACK_NAME=my-stack

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
./archive/legacy/setup-parameter-store.sh

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
make health ENV=dev STACK_NAME=my-stack

# Advanced diagnostics
./lib/modules/monitoring/health.sh --stack-name my-stack

# View logs
make logs ENV=dev STACK_NAME=my-stack
```

## Cost Optimization

### Spot Instance Strategies

1. **Automatic Failover**: System tries multiple instance types and regions
2. **Price Caching**: Reduces API calls and speeds deployment
3. **Intelligent Selection**: Chooses optimal price/performance ratio

### Cost Estimates

| Deployment Type | Hourly Cost | Monthly Cost |
|----------------|-------------|--------------|
| Spot (single AZ) | $0.15 | $110 |
| ALB (with spot) | $0.25 | $180 |
| CDN (with spot) | $0.20 | $145 |
| Full Stack | $0.40 | $290 |

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
make status ENV=dev STACK_NAME=my-stack

# Run diagnostics
make troubleshoot ENV=dev STACK_NAME=my-stack

# Validate environment
./scripts/validate-environment.sh
```

## Cleanup

```bash
# Destroy all resources
make destroy ENV=dev STACK_NAME=my-stack

# Cleanup failed deployments
./lib/modules/cleanup/resources.sh --stack-name my-stack
```

## Next Steps

- [Architecture Guide](architecture.md) - Understand the system design
- [Testing Guide](testing.md) - Test your deployment
- [Troubleshooting Guide](troubleshooting.md) - Resolve common issues