# Architecture Guide

## Overview

GeuseMaker uses a modular architecture designed for maintainability, scalability, and cost optimization. The system is built with bash 3.x compatibility for macOS development while supporting advanced Linux features in production.

## System Architecture

### High-Level Components

```
┌─────────────────────────────────────────────────────────────┐
│                        User Interface                        │
│              (CLI / Make commands / Scripts)                 │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────┴───────────────────────────────────┐
│                   Orchestration Layer                        │
│     (aws-deployment-v2-simple.sh / aws-deployment-modular.sh)│
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────┴───────────────────────────────────┐
│                     Module System                            │
│  ┌──────────┬──────────┬──────────┬──────────┬──────────┐ │
│  │   Core   │  Infra   │ Compute  │   App    │  Errors  │ │
│  │ Modules  │ Modules  │ Modules  │ Modules  │ Modules  │ │
│  └──────────┴──────────┴──────────┴──────────┴──────────┘ │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────┴───────────────────────────────────┐
│                    AWS Infrastructure                        │
│  ┌──────────┬──────────┬──────────┬──────────┬──────────┐ │
│  │   VPC    │    EC2   │   EFS    │   ALB    │    IAM   │ │
│  └──────────┴──────────┴──────────┴──────────┴──────────┘ │
└─────────────────────────┬───────────────────────────────────┘
                          │
┌─────────────────────────┴───────────────────────────────────┐
│                    Container Platform                        │
│  ┌──────────┬──────────┬──────────┬──────────┬──────────┐ │
│  │   n8n    │  Ollama  │  Qdrant  │ Crawl4AI │ PostgreSQL│ │
│  └──────────┴──────────┴──────────┴──────────┴──────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Module System

The codebase is organized into 23 specialized modules:

### Core Modules (`/lib/modules/core/`)

**variables.sh**
- Variable sanitization and validation
- Type-safe variable management
- Bash 3.x compatible implementation

**registry.sh**
- Resource lifecycle tracking
- Dependency management
- Cleanup orchestration

**errors.sh**
- Base error handling functions
- Context wrapping for errors

### Infrastructure Modules (`/lib/modules/infrastructure/`)

**vpc.sh**
- Multi-AZ VPC creation
- Public/private subnet management
- Internet/NAT Gateway setup

**security.sh**
- Security group management
- Least-privilege port access
- Service-specific rules

**iam.sh**
- IAM roles and policies
- Instance profiles
- Service-linked roles

**efs.sh**
- Encrypted file system creation
- Multi-AZ mount targets
- Service-specific access points

**alb.sh**
- Application Load Balancer
- Target group management
- CloudFront integration

### Compute Modules (`/lib/modules/compute/`)

**provisioner.sh**
- EC2 instance provisioning
- Retry logic with exponential backoff
- Cross-region failover

**spot_optimizer.sh**
- Spot pricing analysis
- Instance type selection
- Cost optimization strategies

### Application Modules (`/lib/modules/application/`)

**docker_manager.sh**
- Docker installation and setup
- NVIDIA runtime configuration
- Container orchestration

**service_config.sh**
- Docker Compose generation
- Environment configuration
- Resource allocation

**ai_services.sh**
- Ollama model deployment
- n8n workflow setup
- Qdrant vector database
- Crawl4AI configuration

**health_monitor.sh**
- Service health checks
- Performance monitoring
- Alert management

### Error Handling (`/lib/modules/errors/`)

**error_types.sh**
- Structured error definitions
- Recovery strategies
- Error categorization

## Design Patterns

### 1. Single Responsibility

Each module has one clear purpose:
```bash
# Good: Focused module
/lib/modules/infrastructure/vpc.sh  # Only VPC management

# Bad: Mixed concerns
/lib/aws-deployment-unified.sh  # Everything in one file
```

### 2. Error Context Wrapping

All modules wrap errors with context:
```bash
wrap_error_context "vpc_creation" "stack=$STACK_NAME" \
    create_vpc_internal "$@"
```

### 3. Bash Compatibility

Supports both bash 3.x and 4.x:
```bash
# Avoid bash 4.x only features
declare -A array        # OK
declare -g -A array     # Not OK (no -g in bash 3.x)
```

### 4. Resource Registry

All resources tracked for cleanup:
```bash
register_resource "vpc-123" "vpc" "" \
    "aws ec2 delete-vpc --vpc-id vpc-123"
```

## Deployment Patterns

### Simple Deployment

```
User → aws-deployment-v2-simple.sh
         ├→ Core modules (variables, registry)
         ├→ Basic infrastructure (default VPC)
         ├→ Compute provisioning
         └→ Application deployment
```

### Enterprise Deployment

```
User → aws-deployment-modular.sh
         ├→ All core modules
         ├→ Full infrastructure modules
         │   ├→ Multi-AZ VPC
         │   ├→ Private subnets + NAT
         │   ├→ ALB + target groups
         │   └→ EFS with access points
         ├→ Compute with spot optimization
         └→ Full application stack
```

## Service Architecture

### Container Services

```yaml
Services:
  n8n:
    Port: 5678
    CPU: 0.4 vCPUs
    Memory: 1.5GB
    Purpose: Workflow automation
    
  ollama:
    Port: 11434
    CPU: 2.0 vCPUs
    Memory: 6GB
    GPU: 13.6GB
    Models:
      - deepseek-r1:8b
      - qwen2.5-vl:7b
    
  qdrant:
    Port: 6333
    CPU: 0.4 vCPUs
    Memory: 2GB
    Purpose: Vector database
    
  crawl4ai:
    Port: 11235
    CPU: 0.4 vCPUs
    Memory: 1.5GB
    Purpose: Web scraping
    
  postgresql:
    Port: 5432
    CPU: 0.4 vCPUs
    Memory: 2GB
    Purpose: Data persistence
```

### Resource Allocation (g4dn.xlarge)

```
Total Resources:
  CPU: 4 vCPUs (85% target = 3.4 vCPUs)
  Memory: 16GB
  GPU: T4 16GB

Allocation:
  System overhead: 15% (0.6 vCPUs, 2.4GB)
  Services: 85% (3.4 vCPUs, 13.6GB)
```

## Security Architecture

### Network Security

```
Internet → CloudFront (optional)
             │
             ↓
         ALB (public subnet)
             │
             ↓
     EC2 (private subnet)
             │
             ↓
     EFS (private subnet)
```

### IAM Permissions

Least-privilege model:
- EC2 instance role with specific permissions
- No hardcoded credentials
- Parameter Store for secrets
- Service-linked roles for AWS services

### Data Security

- EFS encryption at rest
- TLS for service communication
- Secrets in Parameter Store
- No sensitive data in logs

## Scaling Architecture

### Horizontal Scaling

```
ALB → Target Group
         ├→ Instance 1 (services)
         ├→ Instance 2 (services)
         └→ Instance 3 (services)
         
Shared: EFS (models, data)
```

### Vertical Scaling

Instance type progression:
- Development: t3.micro (no GPU)
- Small: g4dn.xlarge (T4 GPU)
- Medium: g4dn.2xlarge (T4 GPU)
- Large: g5.xlarge (A10G GPU)
- XLarge: g5.2xlarge (A10G GPU)

## Cost Optimization

### Spot Instance Strategy

1. **Primary**: Preferred instance in preferred region
2. **Fallback Types**: Alternative instances same region
3. **Fallback Regions**: Same instance other regions
4. **Last Resort**: Any available GPU instance

### Resource Optimization

- Spot instances: 70% savings
- EFS lifecycle policies: Archive after 30 days
- Intelligent instance selection
- Automatic cleanup on failure

## Monitoring Architecture

### Health Checks

```
CloudWatch → Instance metrics
              ├→ CPU, Memory, Disk
              ├→ GPU utilization
              └→ Custom metrics

ALB → Target health
       ├→ /health endpoints
       └→ Service availability

Application → Service monitoring
               ├→ Response times
               ├→ Error rates
               └→ Queue depths
```

### Logging

Centralized logging:
- CloudWatch Logs for system logs
- Docker logs for services
- Application logs to EFS
- Error tracking with context

## Development Workflow

### Local Testing

```bash
# Test without AWS
./scripts/simple-demo.sh

# Validate modules
./tests/test-modular-v2.sh

# Check specific module
bash -n lib/modules/core/variables.sh
```

### CI/CD Integration

```yaml
Pipeline:
  - Lint: make lint
  - Test: make test
  - Security: make security-check
  - Deploy: make deploy-spot
  - Validate: make health-check
```

## Best Practices

1. **Always use modules** - Don't add to monolithic scripts
2. **Test locally first** - Use simple-demo.sh
3. **Handle errors gracefully** - Use error_types.sh
4. **Track resources** - Register for cleanup
5. **Document changes** - Update CLAUDE.md