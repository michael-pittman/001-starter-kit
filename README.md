# 🚀 GeuseMaker - AI Stack on AWS in Minutes

**Deploy a complete AI infrastructure (n8n + Ollama + Qdrant + Crawl4AI) on AWS with one command.**

[![Deploy Time](https://img.shields.io/badge/Deploy%20Time-5%20minutes-brightgreen)]()
[![Cost](https://img.shields.io/badge/Cost-~%240.50%2Fhour-blue)]()
[![AWS](https://img.shields.io/badge/AWS-Ready-orange)]()

## 🎯 What You Get

- **n8n**: Workflow automation platform
- **Ollama**: Local LLM inference (DeepSeek-R1:8B, Qwen2.5-VL:7B)
- **Qdrant**: Vector database for embeddings
- **Crawl4AI**: Web scraping service
- **70% Cost Savings**: Via intelligent spot instance optimization
- **One-Command Deploy**: From zero to running AI stack in 5 minutes
- **Auto-Recovery**: Self-healing deployments with rollback
- **Production Ready**: Multi-AZ, ALB, CloudFront CDN options

## 🏃 Quick Deploy (5 minutes)

```bash
# 1. Clone and setup (1 minute)
git clone https://github.com/yourusername/geusemaker.git
cd geusemaker
./scripts/setup-configuration.sh  # Interactive setup wizard

# 2. Deploy (3-5 minutes)
make deploy-spot  # That's it! ☕
```

📖 **[See Full Quick Start Guide →](QUICKSTART.md)**

## 📋 Prerequisites

- AWS Account with EC2 permissions
- AWS CLI v2 configured (`aws configure`)
- SSH key pair in your AWS region
- bash and jq (pre-installed on macOS/Linux)

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

## 🎯 Deployment Options

### Development (Cheapest - $0.50/hr)
```bash
make deploy-spot STACK_NAME=dev-ai
```
- Single g4dn.xlarge spot instance
- All AI services enabled
- Auto-cleanup on failure

### Staging (Production-like - $2-3/hr)
```bash
make deploy-alb STACK_NAME=staging-ai
```
- Application Load Balancer
- Spot with on-demand fallback
- EFS persistent storage

### Production (Full Features - $5-10/hr)
```bash
make deploy-full STACK_NAME=prod-ai
```
- Multi-AZ deployment
- ALB + CloudFront CDN
- Automated backups
- Full monitoring

## 📊 Post-Deployment

```bash
# Check status
make status STACK_NAME=my-ai

# View service URLs
make info STACK_NAME=my-ai

# SSH access
make ssh STACK_NAME=my-ai

# Cleanup
make destroy STACK_NAME=my-ai
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

## Using Existing Resources

The GeuseMaker deployment system supports reusing existing AWS resources instead of creating new ones. This is useful when you have pre-existing infrastructure that you want to leverage for your deployment.

### Configuration

You can specify existing resources in your environment configuration file (`config/environments/dev.yml`):

```yaml
existing_resources:
  enabled: true
  validation_mode: lenient  # strict, lenient, skip
  auto_discovery: true
  
  reuse_policy:
    vpc: true
    subnets: true
    security_groups: true
    efs: false  # Create new EFS
    alb: true
    cloudfront: false  # Create new CloudFront
    
  resources:
    vpc:
      id: "vpc-12345678"
    subnets:
      public:
        ids: ["subnet-12345678", "subnet-87654321"]
      private:
        ids: ["subnet-abcdef12", "subnet-21fedcba"]
    security_groups:
      alb:
        id: "sg-12345678"
      ec2:
        id: "sg-87654321"
    alb:
      load_balancer_arn: "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/GeuseMaker-dev-alb/1234567890123456"
```

### CLI Management

Use the existing resources management script to discover, validate, and manage existing resources:

```bash
# Discover existing resources
./scripts/manage-existing-resources.sh discover -e dev -s GeuseMaker-dev

# Validate existing resources
./scripts/manage-existing-resources.sh validate -e dev -s GeuseMaker-dev

# Test resource connectivity
./scripts/manage-existing-resources.sh test -e dev -s GeuseMaker-dev

# List configured resources
./scripts/manage-existing-resources.sh list -e dev
```

### Makefile Integration

The existing resources feature is fully integrated with the Makefile for easy deployment:

```bash
# Discover existing resources
make existing-resources-discover ENV=dev STACK_NAME=my-stack

# Validate existing resources
make existing-resources-validate ENV=dev STACK_NAME=my-stack

# Test resource connectivity
make existing-resources-test ENV=dev STACK_NAME=my-stack

# List configured resources
make existing-resources-list ENV=dev

# Deploy with existing VPC
make deploy-with-vpc ENV=dev STACK_NAME=my-stack VPC_ID=vpc-12345678

# Deploy with multiple existing resources
make deploy-existing ENV=dev STACK_NAME=my-stack \
    VPC_ID=vpc-12345678 \
    EFS_ID=fs-87654321 \
    ALB_ARN=arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/my-alb/1234567890123456

# Deploy with auto-discovered resources
make deploy-auto-discover ENV=dev STACK_NAME=my-stack

# Deploy with existing resources (with validation)
make deploy-existing-validate ENV=dev STACK_NAME=my-stack
```

#### Available Makefile Targets

| Target | Description | Variables |
|--------|-------------|-----------|
| `existing-resources-discover` | Discover existing AWS resources | `ENV`, `STACK_NAME` |
| `existing-resources-validate` | Validate existing AWS resources | `ENV`, `STACK_NAME` |
| `existing-resources-test` | Test existing resources connectivity | `ENV`, `STACK_NAME` |
| `existing-resources-list` | List configured existing resources | `ENV` |
| `existing-resources-map` | Map existing resources to variables | `ENV`, `STACK_NAME` |
| `deploy-with-vpc` | Deploy using existing VPC | `ENV`, `STACK_NAME`, `VPC_ID` |
| `deploy-existing` | Deploy using existing resources | `ENV`, `STACK_NAME`, `VPC_ID`, `EFS_ID`, `ALB_ARN`, `CLOUDFRONT_ID` |
| `deploy-auto-discover` | Deploy with auto-discovered resources | `ENV`, `STACK_NAME` |
| `deploy-existing-validate` | Deploy with existing resources (validated) | `ENV`, `STACK_NAME` |

### Auto-Discovery

The system can automatically discover existing resources based on naming patterns:

- VPC: `{project_name}-{environment}-vpc`
- Subnets: `{project_name}-{environment}-{type}-subnet-*`
- Security Groups: `{project_name}-{environment}-{type}-sg`
- ALB: `{project_name}-{environment}-alb`
- EFS: `{project_name}-{environment}-efs`
- CloudFront: `{project_name}-{environment}-cdn`

### Validation Modes

- **strict**: Validates all resources and fails if any are invalid
- **lenient**: Validates resources but continues with warnings for issues
- **skip**: Skips validation entirely (not recommended for production)

### Benefits

- **Cost Savings**: Reuse existing infrastructure instead of creating new resources
- **Faster Deployments**: Skip resource creation for existing components
- **Environment Consistency**: Use the same infrastructure across deployments
- **Migration Support**: Gradually migrate to the deployment system
- **Disaster Recovery**: Leverage existing backup and recovery infrastructure

### Use Cases

- **Development Environments**: Reuse existing VPC and networking
- **Staging Deployments**: Use production-like infrastructure
- **Migration Projects**: Gradually adopt the deployment system
- **Multi-Environment**: Share infrastructure between environments
- **Cost Optimization**: Minimize resource creation and costs

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