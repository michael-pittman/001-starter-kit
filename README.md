# GeuseMaker AWS Deployment System

A modular, reusable AWS infrastructure deployment system with uniform coding standards and comprehensive error handling.

## 🚀 Features

- **Modular Architecture**: Plug-and-play deployment modules for different infrastructure components
- **Uniform Coding Standards**: Consistent naming conventions, error handling, and logging across all scripts
- **Comprehensive Rollback**: Automatic resource cleanup on deployment failures
- **Multi-Environment Support**: Development, staging, and production environments
- **Cost Optimization**: Spot instance support for cost-effective deployments
- **Security First**: Built-in security groups and IAM best practices
- **Monitoring Ready**: Integrated logging and health monitoring
- **Unified Maintenance**: Consolidated maintenance suite for all operations

## 📋 Prerequisites

- **Bash**: Works with any bash version
  - macOS: Works with system bash
  - Linux: Compatible with all distributions
- **AWS CLI v2**: Configured with appropriate credentials
- **jq**: JSON processing utility
- **Docker**: For containerized deployments (optional)

## 🏗️ Architecture

```
GeuseMaker/
├── deploy.sh                 # Main deployment orchestrator
├── lib/
│   ├── modules/              # Consolidated modular architecture
│   │   ├── core/            # Core utilities with 7 components
│   │   ├── infrastructure/  # AWS infrastructure with 7 unified modules
│   │   ├── compute/         # EC2 operations with spot optimization
│   │   ├── application/     # Application deployment and AI services
│   │   ├── deployment/      # Orchestration and state management
│   │   ├── monitoring/      # Health checks and metrics
│   │   ├── errors/          # Structured error handling
│   │   ├── config/          # Configuration management
│   │   ├── instances/       # Instance lifecycle management
│   │   ├── cleanup/         # Resource cleanup and recovery
│   │   └── maintenance/     # Unified maintenance operations
│   └── utils/               # Shared utilities
├── config/                  # Configuration files
├── deployments/             # Deployment state and logs
└── Makefile                 # Build automation
```

## 🚀 Quick Start

### 1. Setup Environment

```bash
# Clone the repository
git clone <repository-url>
cd GeuseMaker

# Install dependencies
make install

# Setup AWS configuration
make setup ENV=dev
```

### 2. Deploy Infrastructure

```bash
# Deploy spot instance (cost-optimized, single AZ with EFS)
make deploy-spot STACK_NAME=my-dev-stack

# Deploy with ALB (load balancer, spot instances, CDN, and EFS in single AZ)
make deploy-alb STACK_NAME=my-prod-stack

# Deploy with CDN (CloudFront CDN with ALB and EFS in single AZ)
make deploy-cdn STACK_NAME=my-prod-stack

# Deploy complete stack (all features in single AZ)
make deploy-full STACK_NAME=my-prod-stack
```

**Note**: All deployment types now include EFS for persistent storage and are optimized for single AZ deployments to reduce costs while maintaining reliability.

### 3. Check Status

```bash
# View deployment status
make status ENV=dev STACK_NAME=my-dev-stack

# Check health
make health ENV=dev STACK_NAME=my-stack

# View logs
make logs ENV=dev STACK_NAME=my-stack
```

### 4. Cleanup

```bash
# Destroy all resources
make destroy ENV=dev STACK_NAME=my-dev-stack
```

### 5. Maintenance Operations

The unified maintenance suite provides all maintenance operations through a single interface:

```bash
# Fix deployment issues
make maintenance-fix STACK_NAME=my-stack

# Clean up resources
make maintenance-cleanup STACK_NAME=my-stack

# Create backup
make maintenance-backup TYPE=full

# Health check
make maintenance-health STACK_NAME=my-stack

# Update Docker images
make maintenance-update ENV=production
```

See [Maintenance Suite Guide](docs/maintenance-suite-guide.md) for complete documentation.

## 📖 Usage

### Command Line Interface

The main deployment script supports various deployment types:

```bash
# Basic usage
./deploy.sh --[deployment-type] --env [environment] --stack-name [name]

# Examples
./deploy.sh --spot --env dev --stack-name my-stack
./deploy.sh --alb --env staging --stack-name my-stack
./deploy.sh --cdn --env prod --stack-name my-stack
./deploy.sh --full --env prod --stack-name my-stack
```

### Deployment Types

| Type | Description | Components |
|------|-------------|------------|
| `spot` | Cost-optimized EC2 spot instance | VPC, Security Groups, EC2 |
| `alb` | Application Load Balancer | VPC, Security Groups, ALB, Target Groups |
| `cdn` | CloudFront CDN | CloudFront Distribution |
| `full` | Complete infrastructure | VPC, EC2, ALB, CloudFront |

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ENV` | Environment name (dev/staging/prod) | `dev` |
| `PROFILE` | AWS profile to use | `$ENV` |
| `REGION` | AWS region | `us-east-1` |
| `STACK_NAME` | Stack name | `geusemaker-$ENV` |

## 🔧 Configuration

### Environment Configuration

Create environment-specific configuration files in `config/`:

```bash
config/
├── dev/
│   ├── variables.json
│   └── deployment.json
├── staging/
│   ├── variables.json
│   └── deployment.json
└── prod/
    ├── variables.json
    └── deployment.json
```

### Variable Store

The system uses a centralized variable store for managing deployment state:

```json
{
  "stack_name": "my-stack",
  "deployment_type": "full",
  "vpc_id": "vpc-12345678",
  "ec2_instance_id": "i-12345678",
  "alb_arn": "arn:aws:elasticloadbalancing:...",
  "cloudfront_distribution_id": "E1234567890ABCD"
}
```

## 🏗️ Module System

The GeuseMaker system has been consolidated into 10 major functional modules for better maintainability:

### Core Module (`lib/modules/core/`)
Provides essential utilities and shared functionality:
- **variables.sh** - Variable sanitization, validation, and persistence
- **logging.sh** - Structured logging with multiple levels
- **errors.sh** - Base error handling and context wrapping
- **validation.sh** - Input validation and type checking
- **registry.sh** - Resource lifecycle tracking and cleanup
- **dependency-groups.sh** - Library dependency management
- **instance-utils.sh** - Common instance utility functions

### Infrastructure Module (`lib/modules/infrastructure/`)
Manages AWS infrastructure resources:
- **vpc.sh** - Multi-AZ VPC creation, subnet management, gateways
- **ec2.sh** - EC2 instance management and configuration
- **security.sh** - Security groups with least-privilege access
- **iam.sh** - IAM roles, policies, and instance profiles
- **efs.sh** - Encrypted file systems with multi-AZ mount targets
- **alb.sh** - Application Load Balancer and target groups
- **cloudfront.sh** - CDN distribution management

### Compute Module (`lib/modules/compute/`)
Handles EC2 compute operations with intelligent instance selection:
- **ami.sh** - AMI selection based on architecture and region
- **spot_optimizer.sh** - Spot pricing analysis (70% cost savings)
- **provisioner.sh** - Instance provisioning with retry logic
- **autoscaling.sh** - Auto-scaling group management
- **launch.sh** - Launch template creation
- **lifecycle.sh** - Instance lifecycle management
- **security.sh** - Compute-specific security configuration

### Application Module (`lib/modules/application/`)
Manages application deployment and AI services:
- **base.sh** - Base application utilities
- **docker_manager.sh** - Docker installation, NVIDIA runtime setup
- **service_config.sh** - Docker Compose generation
- **ai_services.sh** - AI stack (n8n, Ollama, Qdrant, Crawl4AI)
- **health_monitor.sh** - Service health checks and monitoring

### Deployment Module (`lib/modules/deployment/`)
Orchestrates the deployment process:
- **orchestrator.sh** - Main deployment workflow coordination
- **state.sh** - Deployment state management and persistence
- **rollback.sh** - Rollback mechanisms and recovery
- **userdata.sh** - EC2 user data script generation

### Monitoring Module (`lib/modules/monitoring/`)
Provides health checks and metrics:
- **health.sh** - Comprehensive health checks
- **metrics.sh** - Performance metrics collection

### Errors Module (`lib/modules/errors/`)
Structured error handling with clear messages:
- **error_types.sh** - Error type definitions and categorization
- **clear_messages.sh** - User-friendly error messages

### Config Module (`lib/modules/config/`)
Manages configuration and environment settings:
- **variables.sh** - Environment variable management
- **settings.sh** - Application settings and defaults

### Instances Module (`lib/modules/instances/`)
Handles instance lifecycle and management:
- **ami.sh** - AMI management and selection
- **failsafe-recovery.sh** - Instance recovery mechanisms
- **launch.sh** - Instance launch configuration
- **lifecycle.sh** - Instance lifecycle management

### Cleanup Module (`lib/modules/cleanup/`)
Manages resource cleanup and recovery:
- **resources.sh** - Safe resource deletion with dependency checking

## 🔒 Security

### Security Groups

The system automatically creates and configures security groups:

- **ALB Security Group**: HTTP (80), HTTPS (443)
- **EC2 Security Group**: SSH (22), HTTP (80), HTTPS (443)

### IAM Best Practices

- Least privilege access
- Role-based permissions
- Secure credential management

### Network Security

- Private subnets for EC2 instances
- Public subnets for load balancers
- NAT gateways for outbound internet access

## 📊 Monitoring and Logging

### Health Checks

```bash
# Check deployment health
make health ENV=dev STACK_NAME=my-stack

# Monitor continuously
./deploy.sh --monitor --env dev --stack-name my-stack
```

### Logging

All operations are logged with structured format:

```
[2024-01-15T10:30:00Z] [INFO] [VPC] Creating VPC for stack: my-stack
[2024-01-15T10:30:05Z] [INFO] [VPC] VPC created successfully: vpc-12345678
```

### Metrics

- CloudWatch metrics for all resources
- Custom metrics for application health
- Cost tracking and optimization

## 🛠️ Development

### Adding New Modules

1. Create module file in appropriate directory:
   ```bash
   lib/modules/infrastructure/new-module.sh
   ```

2. Follow naming conventions:
   ```bash
   # Module header
   #!/bin/bash
   # =============================================================================
   # New Module
   # Description
   # =============================================================================
   
   # Prevent multiple sourcing
   [ -n "${_INFRASTRUCTURE_NEW_MODULE_SH_LOADED:-}" ] && return 0
   _INFRASTRUCTURE_NEW_MODULE_SH_LOADED=1
   ```

3. Implement functions with uniform error handling:
   ```bash
   create_new_resource() {
       local stack_name="$1"
       
       log_info "Creating new resource for stack: $stack_name" "NEW_MODULE"
       
       # Implementation with error handling
       if ! aws_command; then
           log_error "Failed to create resource" "NEW_MODULE"
           return 1
       fi
       
       log_info "Resource created successfully" "NEW_MODULE"
       return 0
   }
   ```

### Testing

```bash
# Run all tests (unit, integration, security, performance)
make test

# Run specific test types
make test-unit          # Unit tests only
make test-integration   # Integration tests

# Run comprehensive test suite with reporting
./tools/test-runner.sh --report

# Run specific test categories
./tools/test-runner.sh unit integration security

# Run linting
make lint

# Run security scans
make security
```

### Core Scripts

- **`scripts/aws-deployment-modular.sh`** - Main deployment orchestrator with modular architecture
- **`deploy.sh`** - Makefile entry point for deployment operations
- **`tools/test-runner.sh`** - Comprehensive test runner with 8 test categories

### Archive Structure

Non-essential files have been organized into the `archive/` directory:
```
archive/
├── reports/        # Historical reports and analysis documents
├── summaries/      # Epic and story completion summaries
├── test-results/   # Previous test execution results
├── validation-reports/  # Validation and assessment documents
└── legacy/         # Deprecated scripts and configurations
```

## 🔄 CI/CD Integration

### GitHub Actions Example

```yaml
name: Deploy
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      
      - name: Deploy to staging
        run: |
          make deploy-staging
      
      - name: Run health checks
        run: |
          make health ENV=staging
```

## 🚨 Troubleshooting

### Common Issues

1. **Shell Compatibility**
   ```bash
   # Scripts work with any bash version
   # No specific version requirements
   ```

2. **AWS Credentials Not Configured**
   ```bash
   # Configure AWS CLI
   aws configure
   
   # Or use profiles
   aws configure --profile dev
   ```

3. **Insufficient AWS Quotas**
   ```bash
   # Check quotas
   aws service-quotas list-service-quotas --service-code ec2
   
   # Request quota increase if needed
   ```

### Debug Mode

```bash
# Enable debug mode
export DEBUG=1
./deploy.sh --spot --env dev --stack-name my-stack

# Or use make target
make debug ENV=dev STACK_NAME=my-stack
```

### Logs and Diagnostics

```bash
# View deployment logs
make logs ENV=dev STACK_NAME=my-stack

# Run diagnostics
make troubleshoot ENV=dev STACK_NAME=my-stack
```

## 📚 Documentation

- [Deployment Guide](docs/guides/deployment.md)
- [Architecture Overview](docs/architecture.md)
- [Module Development](docs/module-architecture.md)
- [Troubleshooting](docs/guides/troubleshooting.md)
- [API Reference](docs/reference/api/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Follow coding standards
4. Add tests for new functionality
5. Submit a pull request

### Coding Standards

- Use uniform naming conventions
- Implement comprehensive error handling
- Add logging for all operations
- Follow bash best practices
- Include documentation for new modules

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/your-repo/issues)
- **Documentation**: [Wiki](https://github.com/your-repo/wiki)
- **Discussions**: [GitHub Discussions](https://github.com/your-repo/discussions)

## 🔄 Changelog

### Version 2.0.0
- Complete modular architecture redesign
- Uniform coding standards implementation
- Comprehensive error handling and rollback
- Multi-environment support
- Enhanced security features
- Consolidated module structure (10 modules)

### Version 1.x
- Initial implementation
- Basic deployment functionality
- Limited modularity

---

**Built with ❤️ for reliable, scalable AWS infrastructure deployment.**