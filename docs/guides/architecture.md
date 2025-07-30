# Architecture Guide

## Overview

GeuseMaker uses a modular architecture designed for maintainability, scalability, and cost optimization. The system is compatible with bash 3.x+ for broad compatibility while providing enhanced features through our consolidated module system.

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

The codebase has been consolidated from 23 specialized modules into 8 major functional groups for better maintainability:

### Core Module (`/lib/modules/core/`)

**Consolidated Components:**
- **variables.sh** - Variable sanitization, validation, and persistence
- **logging.sh** - Structured logging with multiple levels
- **errors.sh** - Base error handling and context wrapping
- **validation.sh** - Input validation and type checking
- **registry.sh** - Resource lifecycle tracking and cleanup orchestration
- **dependency-groups.sh** - Library dependency management
- **instance-utils.sh** - Common instance utility functions

**Key Features:**
- Bash 3.x+ compatible with automatic enhancement for bash 4.0+
- Type-safe variable management
- Centralized resource tracking
- Enhanced error context preservation

### Infrastructure Module (`/lib/modules/infrastructure/`)

**Consolidated Components:**
- **vpc.sh** - Multi-AZ VPC creation, subnet management, gateways
- **ec2.sh** - EC2 instance management and configuration
- **security.sh** - Security groups with least-privilege access
- **iam.sh** - IAM roles, policies, and instance profiles
- **efs.sh** - Encrypted file systems with multi-AZ mount targets
- **alb.sh** - Application Load Balancer and target groups
- **cloudfront.sh** - CDN distribution management

**Key Features:**
- Unified infrastructure provisioning
- Consistent error handling across components
- Resource registration for cleanup
- CloudFormation integration support

### Compute Module (`/lib/modules/compute/`)

**Consolidated Components:**
- **ami.sh** - AMI selection based on architecture and region
- **spot_optimizer.sh** - Spot pricing analysis and optimization
- **provisioner.sh** - Instance provisioning with retry logic
- **autoscaling.sh** - Auto-scaling group management
- **launch.sh** - Launch template creation and management
- **lifecycle.sh** - Instance lifecycle management
- **security.sh** - Compute-specific security configuration

**Key Features:**
- Intelligent instance selection with fallback strategies
- Cross-region failover capabilities
- 70% cost savings through spot optimization
- GPU instance support (T4, A10G)
- Comprehensive error recovery

### Application Module (`/lib/modules/application/`)

**Consolidated Components:**
- **base.sh** - Base application utilities and common functions
- **docker_manager.sh** - Docker installation, NVIDIA runtime setup
- **service_config.sh** - Docker Compose generation, resource allocation
- **ai_services.sh** - AI stack deployment (Ollama, n8n, Qdrant, Crawl4AI)
- **health_monitor.sh** - Service health checks and monitoring

**Key Features:**
- Unified application deployment
- GPU-optimized container configuration
- Automated health monitoring
- Service dependency management
- Resource allocation optimization

### Deployment Module (`/lib/modules/deployment/`)

**Consolidated Components:**
- **orchestrator.sh** - Main deployment workflow coordination
- **state.sh** - Deployment state management and persistence
- **rollback.sh** - Rollback mechanisms and recovery
- **userdata.sh** - EC2 user data script generation

**Key Features:**
- Stateful deployment tracking
- Atomic rollback capabilities
- Progress tracking and reporting
- User data automation for EC2

### Monitoring Module (`/lib/modules/monitoring/`)

**Components:**
- **health.sh** - Comprehensive health checks
- **metrics.sh** - Performance metrics collection

**Key Features:**
- Real-time health monitoring
- CloudWatch integration
- Custom metric collection
- Alert management

### Errors Module (`/lib/modules/errors/`)

**Components:**
- **error_types.sh** - Structured error definitions
- **clear_messages.sh** - User-friendly error messages

**Key Features:**
- Categorized error types
- Recovery strategy recommendations
- Clear, actionable error messages
- Context preservation

### Cleanup Module (`/lib/modules/cleanup/`)

**Component:**
- **resources.sh** - Resource cleanup orchestration

**Key Features:**
- Safe resource deletion
- Dependency-aware cleanup
- Failed deployment recovery
- Orphaned resource identification

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

### 3. Bash Compatibility and Modernization

Compatible with bash 3.x+ with automatic enhancements when bash 4.0+ is available:
```bash
# Modern bash patterns (auto-enabled when available)
declare -A CONFIG_CACHE              # Associative arrays
declare -n config_ref="CONFIG_CACHE" # Nameref variables
config_ref["key"]="value"            # Enhanced array operations

# Comprehensive error handling
declare -A ERROR_REGISTRY
ERROR_REGISTRY["EC2_INSUFFICIENT_CAPACITY"]="retry_with_fallback"
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
./archive/demos/simple-demo.sh

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
2. **Test locally first** - Use archive/demos/simple-demo.sh
3. **Handle errors gracefully** - Use error_types.sh
4. **Track resources** - Register for cleanup
5. **Document changes** - Update CLAUDE.md