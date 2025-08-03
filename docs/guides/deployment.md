# Deployment Guide

> Complete guide for deploying GeuseMaker AI infrastructure on AWS

## Overview

GeuseMaker uses the Unity event-driven deployment system for all operations. This guide covers deployment options, configurations, and best practices.

## Quick Start

### Unity Deployment (Recommended)

```bash
# Deploy spot instance (70% cost savings)
./deploy.sh spot dev-stack

# Deploy with Application Load Balancer
./deploy.sh alb prod-stack

# Deploy with CloudFront CDN
./deploy.sh cdn prod-stack

# Deploy complete infrastructure
./deploy.sh full prod-stack
```

### Legacy Makefile Support

```bash
# Legacy commands (redirects to Unity)
./unity deploy spot my-stack
./unity deploy alb my-stack
./unity deploy full my-stack
```

## Deployment Types

| Type | Components | Use Case | Cost |
|------|------------|----------|------|
| `spot` | VPC, EC2 (spot) | Development | ~$0.50/hr |
| `alb` | VPC, EC2, ALB | Staging | ~$2-3/hr |
| `cdn` | CloudFront CDN | Production edge | ~$1-2/hr |
| `full` | VPC, EC2, ALB, CDN | Production | ~$5-10/hr |

## Prerequisites

- AWS Account with EC2 permissions
- AWS CLI v2 configured (`aws configure`)
- SSH key pair in your AWS region
- bash and jq (pre-installed on macOS/Linux)

## Environment Configuration

### Unity Configuration

Unity uses `config/unity.yml` as the primary configuration:

```yaml
unity:
  deployment:
    types: [spot, alb, cdn, full]
    environments: [dev, staging, prod]
    defaults:
      instance_type: g4dn.xlarge
      region: us-east-1
```

### Environment-Specific Settings

Create environment-specific configurations:

```bash
config/
├── unity.yml          # Main Unity configuration
├── dev/
│   ├── variables.json
│   └── deployment.json
├── staging/
└── prod/
```

## Advanced Deployment Options

### Using Existing Resources

Deploy with existing AWS infrastructure:

```bash
# Discover existing resources
./scripts/unity-cli.sh discover-resources dev-stack

# Deploy with existing VPC
./deploy.sh spot dev-stack --vpc-id vpc-12345678

# Deploy with multiple existing resources
./deploy.sh full prod-stack \
  --vpc-id vpc-12345678 \
  --efs-id fs-87654321 \
  --alb-arn arn:aws:elasticloadbalancing:...
```

### Multi-AZ Deployment

```bash
# Production deployment with multi-AZ
./deploy.sh full prod-stack \
  --multi-az \
  --availability-zones us-east-1a,us-east-1b,us-east-1c
```

## Monitoring Deployment

### Real-time Monitoring

```bash
# Monitor deployment progress
./scripts/unity-cli.sh monitor my-stack

# Check deployment status
./scripts/unity-cli.sh status my-stack

# View service health
./scripts/unity-cli.sh service health
```

### Post-Deployment Verification

```bash
# Check all services
./unity status my-stack

# View service URLs
./unity info my-stack

# SSH access
./unity ssh my-stack
```

## Troubleshooting

### Common Issues

1. **AWS Credentials Not Configured**
   ```bash
   aws configure
   # Or use profiles
   aws configure --profile dev
   ```

2. **Insufficient Permissions**
   - Ensure EC2, VPC, IAM permissions
   - Check service quotas

3. **Deployment Failures**
   ```bash
   # Enable debug mode
   export DEBUG=1
   ./deploy.sh spot my-stack
   ```

### Recovery and Rollback

```bash
# Automatic rollback on failure
./deploy.sh spot my-stack --auto-rollback

# Manual rollback
./scripts/unity-cli.sh rollback my-stack

# Force cleanup
./deploy.sh destroy my-stack --force
```

## Best Practices

### Security

- Use least privilege IAM policies
- Enable VPC Flow Logs
- Configure security groups restrictively
- Use private subnets for EC2 instances

### Cost Optimization

- Use spot instances for development (70% savings)
- Monitor CloudWatch metrics
- Set up billing alerts
- Clean up unused resources

### Performance

- Choose appropriate instance types
- Use EFS for persistent storage
- Configure auto-scaling policies
- Monitor application metrics

## Next Steps

- [Troubleshooting Guide](troubleshooting.md)
- [Architecture Overview](architecture.md)
- [Unity Documentation](../unity/)
- [API Reference](../reference/api/)

---

For more information, see the [Unity Operations Guide](../unity/core/unity-operations.md).