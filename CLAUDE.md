# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**GeuseMaker** is an enterprise-ready AWS deployment system with AI infrastructure capabilities:
- **70% cost savings** via intelligent spot instance optimization
- **Multi-architecture support** (Intel x86_64 and ARM64 Graviton2)
- **AI Stack**: n8n workflows + Ollama (DeepSeek-R1:8B, Qwen2.5-VL:7B) + Qdrant + Crawl4AI
- **Enterprise features**: Multi-AZ, ALB, CloudFront CDN, EFS persistence, comprehensive monitoring
- **Works with any bash version**

## Essential Commands

### Deployment
```bash
# Basic deployment commands
make deploy-spot STACK_NAME=dev-stack    # Deploy spot instance (70% cost savings)
make deploy-alb STACK_NAME=prod-stack    # Deploy with Application Load Balancer
make deploy-full STACK_NAME=prod-stack   # Deploy complete stack (VPC+EC2+ALB+CDN)
make destroy STACK_NAME=stack-name       # Destroy all resources

# Advanced modular deployment
./scripts/aws-deployment-modular.sh --spot --multi-az stack-name              # Spot with multi-AZ
./scripts/aws-deployment-modular.sh --spot --alb --cloudfront prod-stack      # Full production
./archive/legacy/aws-deployment-v2-simple.sh dev-stack                        # Simple development (legacy)
```

### Testing & Validation
```bash
# Run tests (MANDATORY before deployment)
make test                                      # Run all tests (unit, integration, security, performance)
./tools/test-runner.sh unit                    # Unit tests only
./tools/test-runner.sh integration             # Integration tests
./tools/test-runner.sh security                # Security validation
./tools/test-runner.sh --report                # Generate HTML test report

# Test categories available: unit, integration, security, performance, deployment, smoke, config, maintenance

# Specific test files
./tests/test-modular-v2.sh                     # Test modular deployment system
./tests/test-deployment-flow.sh                # Test deployment workflow
./tests/run-deployment-tests.sh                # Run all deployment tests

# Validation & checks
make lint                                      # Run shellcheck on all scripts
make security                                  # Run security scans
make validate                                  # Validate configuration
./scripts/check-quotas.sh                      # Check AWS service quotas
./scripts/validate-environment.sh              # Environment validation
```

### Development & Debugging
```bash
# Local testing (no AWS costs)
./archive/demos/simple-demo.sh                       # Test spot selection logic locally
./archive/demos/test-intelligent-selection.sh        # Comprehensive local testing

# Monitoring & troubleshooting  
make status STACK_NAME=stack                   # Show deployment status
make logs STACK_NAME=stack                     # View application logs
make health STACK_NAME=stack                   # Check deployment health
./scripts/health-check-advanced.sh STACK_NAME  # Advanced health diagnostics
./scripts/fix-deployment-issues.sh STACK REGION # Fix common issues
```

### Maintenance Operations
```bash
# Unified maintenance suite operations
make maintenance-fix STACK_NAME=my-stack       # Fix deployment issues
make maintenance-cleanup STACK_NAME=my-stack   # Clean up resources
make maintenance-backup TYPE=full              # Create backup
make maintenance-health STACK_NAME=my-stack    # Run health checks
make maintenance-update ENV=production         # Update Docker images
```

## High-Level Architecture

### Core Components
The project uses a modular architecture with 10 major functional modules:

```
lib/modules/
├── core/           # Variables, logging, validation, resource registry (7 components)
├── infrastructure/ # VPC, security, IAM, EFS, ALB, CloudFront (7 unified modules)
├── compute/        # EC2 provisioning, spot optimization, AMI selection  
├── application/    # Docker, AI services, health monitoring
├── deployment/     # Orchestration, state management, rollback
├── monitoring/     # Health checks, metrics collection
├── errors/         # Structured error handling with recovery
├── config/         # Configuration management
├── instances/      # Instance lifecycle management
└── cleanup/        # Resource cleanup and failure recovery
```

### Deployment Architecture

**Primary Scripts**:
- `aws-deployment-modular.sh` - Enterprise deployment with full features
- `aws-deployment-v2-simple.sh` - Simple deployment for development (archived)

**Modern Library Loading Pattern** (NEW):
```bash
# New unified library loader
source "$SCRIPT_DIR/../lib/utils/library-loader.sh" || {
    echo "Error: Failed to load library loader" >&2
    exit 1
}

# Initialize script with required modules
initialize_script "script-name.sh" \
    "config/variables" \
    "core/registry" \
    "core/errors"

# Load additional libraries
safe_source "aws-cli-v2.sh" true "AWS CLI v2 enhancements"
```

**Legacy Library Loading Pattern** (still supported):
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

load_library() {
    local library="$1"
    local library_path="${LIB_DIR}/${library}"
    [ ! -f "$library_path" ] && { echo "ERROR: Required library not found: $library_path" >&2; exit 1; }
    source "$library_path" || { echo "ERROR: Failed to source library: $library_path" >&2; exit 1; }
}
```

### AI Services Stack (Docker Compose)
- **n8n** (5678): Workflow automation platform
- **Ollama** (11434): LLM serving (DeepSeek-R1:8B, Qwen2.5-VL:7B)
- **Qdrant** (6333): Vector database for embeddings
- **Crawl4AI** (11235): Web scraping service
- **PostgreSQL** (5432): Persistent storage

## Critical Implementation Patterns

### Bash Compatibility
All deployment scripts work with any bash version. The project includes comprehensive bash compatibility through:
- Associative array emulation for bash 3.x
- Version detection and automatic fallbacks
- Cross-platform compatibility (macOS, Linux)

### Common Patterns

**Variable Sanitization**:
```bash
# AWS resource names must be sanitized
sanitized=$(echo "$var" | sed 's/[^a-zA-Z0-9_]/_/g')
```

**Error Handling**:
```bash
source "$LIB_DIR/modules/core/errors.sh"
error_ec2_insufficient_capacity "$instance_type" "$region"
```

**AWS Rate Limiting**:
- Cache spot prices: 1hr (individual), 30min (batch)
- 2-second delays between region API calls
- Fallback prices: g4dn.xlarge ($0.21/hr), g5.xlarge ($0.18/hr)

### Security Parameters (SSM)
- `/aibuildkit/OPENAI_API_KEY`
- `/aibuildkit/n8n/ENCRYPTION_KEY`
- `/aibuildkit/POSTGRES_PASSWORD`
- `/aibuildkit/WEBHOOK_URL`

## Common Troubleshooting

| Issue | Solution |
|-------|----------|
| Disk space exhaustion | `./scripts/fix-deployment-issues.sh STACK REGION` |
| EFS mount failures | `./archive/legacy/setup-parameter-store.sh validate` |
| Spot capacity issues | Use `ec2-provisioning-specialist` agent |
| Variable errors | Check sanitization in `variables.sh` module |
| AWS quota limits | `./scripts/check-quotas.sh REGION` |
| Health check failures | `./scripts/health-check-advanced.sh STACK_NAME` |

## Key Architecture Insights

### AWS Well-Architected Framework Implementation
1. **Operational Excellence**: Automated deployment, comprehensive monitoring
2. **Security**: Least privilege IAM, encryption by default, Parameter Store
3. **Reliability**: Multi-AZ deployments, spot instance failover
4. **Performance**: GPU optimization (T4 16GB), intelligent instance selection
5. **Cost Optimization**: 70% savings via spot instances
6. **Sustainability**: ARM64 Graviton2 support

### n8n Workflow Development Pattern
1. Pre-validate: `validate_node_minimal()` → `validate_node_operation()`
2. Build workflow with validated configurations
3. Post-validate: `validate_workflow()` → `validate_workflow_connections()`
4. Deploy using `n8n_update_partial_workflow()` for token savings

**Remember**: ANY node can be an AI tool in n8n workflows.

## Advanced Features

### Associative Arrays
The project uses comprehensive associative arrays for:
- **Spot Pricing**: Dynamic price caching and analysis
- **Configuration**: Type-safe environment overrides
- **Resource Management**: Lifecycle tracking and dependencies
- **Test Framework**: Parallel execution and reporting
- **Deployment State**: Multi-phase orchestration

Key libraries:
- `/lib/associative-arrays.sh` - Utility functions
- `/lib/spot-instance.sh` - Pricing optimization
- `/lib/config-management.sh` - Configuration inheritance
- `/lib/deployment-state-manager.sh` - State orchestration

### Claude Code Agents
Use specialized agents for complex tasks:
- **ec2-provisioning-specialist**: EC2 and spot instance issues
- **aws-deployment-debugger**: Deployment failures
- **spot-instance-optimizer**: Cost optimization
- **security-validator**: Pre-production validation
- **test-runner-specialist**: Test orchestration
- **bash-script-validator**: Script validation
- **aws-cost-optimizer**: Cost analysis

### BMad Slash Commands
Available in `.claude/commands/BMad/`:
- Agents: `/analyst`, `/architect`, `/dev`, `/pm`, `/po`, `/qa`, `/sm`, `/ux-expert`
- Tasks: `/create-doc`, `/review-story`, `/execute-checklist`, `/create-next-story`
- Advanced: `/brownfield-create-epic`, `/facilitate-brainstorming-session`, `/advanced-elicitation`

### Maintenance Suite
The project includes a comprehensive maintenance suite (`/lib/modules/maintenance/maintenance-suite.sh`):
- **Fix Operations**: Automated deployment issue resolution
- **Cleanup Operations**: Safe resource cleanup with dependency checks
- **Backup/Restore**: Full and incremental backup capabilities
- **Health Monitoring**: Proactive health checks with auto-fix
- **Update Operations**: Docker image and component updates
- **Optimization**: Performance tuning and resource optimization

Access via Makefile targets: `make maintenance-*`

### Performance Optimization
The project includes performance optimization modules:
- **AWS API Caching**: Reduces API calls and improves response times
- **Parallel Execution**: Concurrent operations for faster deployments
- **Performance Monitoring**: Track operation timings and bottlenecks
- **Connection Pooling**: Reuse AWS connections for efficiency

Key module: `/lib/modules/performance/`