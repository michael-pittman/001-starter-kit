# Unity Services

This directory contains the core Unity services that provide unified interfaces for various system operations.

## Available Services

### 1. Unity AWS Service (`unity-aws-service.sh`)

A unified interface for all AWS operations that consolidates:
- EC2 operations (spot instances, on-demand, autoscaling)
- VPC management and intelligent CIDR allocation
- ALB (Application Load Balancer) operations
- CloudFront CDN management
- EFS file system operations
- Cost optimization engine (70% savings via spot instances)
- Quota checking and limits system
- API caching for efficiency

**Key Features:**
- Single interface for all AWS operations
- Resource lifecycle management with tracking
- Built-in cost optimization
- Automatic quota checking
- Cross-platform bash 3/4 compatibility
- Event bus integration ready

**Usage:**
```bash
source lib/unity/services/unity-aws-service.sh
init_unity_aws_service "my-deployment"
instance_id=$(unity_aws launch g4dn.xlarge spot my-stack)
```

## Service Architecture

All Unity services follow these patterns:

1. **Initialization**: Each service has an `init_*` function
2. **Resource Tracking**: Services track resources they create
3. **Event Integration**: Services emit events when event bus is available
4. **Error Handling**: Consistent error handling with recovery
5. **Caching**: Built-in caching for expensive operations
6. **CLI Interface**: Each service provides a CLI command

## Creating New Services

To create a new Unity service:

1. Create a new file: `unity-<service-name>-service.sh`
2. Follow the structure of existing services
3. Include initialization, resource tracking, and CLI interface
4. Emit events for major operations
5. Add comprehensive error handling
6. Document in this README

## Integration

Unity services can be used standalone or integrated with the Unity framework:

**Standalone:**
```bash
source lib/unity/services/unity-aws-service.sh
unity_aws launch t3.medium on-demand test
```

**With Unity Framework:**
```bash
./scripts/unity-cli.sh aws launch t3.medium on-demand test
```

## Future Services

Planned Unity services:
- `unity-docker-service.sh` - Docker and container operations
- `unity-monitoring-service.sh` - Unified monitoring and alerting
- `unity-config-service.sh` - Configuration management
- `unity-deployment-service.sh` - Deployment orchestration