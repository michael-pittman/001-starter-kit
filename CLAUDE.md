# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**GeuseMaker** is an enterprise-ready AI infrastructure platform featuring:
- **70% cost savings** through intelligent spot instance management
- **Multi-architecture support** (Intel x86_64 and ARM64 Graviton2) 
- **AI Stack**: n8n workflows + Ollama (DeepSeek-R1:8B, Qwen2.5-VL:7B) + Qdrant + Crawl4AI
- **Enterprise features**: Auto-scaling, CloudFront CDN, EFS persistence, comprehensive monitoring

## Git Context & Workflow

**Current Branch**: `main` (default)
**Repository State**: Clean modular architecture with root directory cleanup completed
**Recent Major Changes**: Complete modular deployment system, bash 3.x compatibility, comprehensive error handling

### Commit Workflow
- Run tests before committing: `make test`
- Run linting: `make lint` 
- Security validation: `make security-check`
- Check git status to see modified files

### Claude Code Agent Integration  
Specialized agents available for complex tasks:
- **ec2-provisioning-specialist**: EC2 launch failures, spot capacity, AMI availability, service quotas
- **aws-deployment-debugger**: Deployment failures, infrastructure problems
- **spot-instance-optimizer**: Cost optimization, spot pricing analysis
- **security-validator**: Pre-production security validation
- **test-runner-specialist**: Comprehensive testing orchestration
- **bash-script-validator**: Script validation for macOS/Linux compatibility

## Essential Commands

### Testing and Validation
```bash
make test                          # Run all tests (MANDATORY before deployment)
make lint                          # Run shellcheck on all scripts
make security-check                # Security validation
./tools/test-runner.sh unit        # Run specific test category
./tools/test-runner.sh --report    # Generate HTML test report
```

### Core Deployment Commands

| Command | Description | Use Case |
|---------|-------------|----------|
| `make deploy-simple STACK_NAME=dev` | Bash 3.x compatible development | Quick testing, local development |
| `make deploy-spot STACK_NAME=prod` | Cost-optimized production | 70% cost savings with spot instances |
| `make deploy-enterprise STACK_NAME=prod` | Enterprise multi-AZ with ALB | High-availability production |
| `make destroy STACK_NAME=stack` | Clean resource removal | Cleanup after testing |

### Advanced Modular Deployment
```bash
# Enterprise deployment with all features  
./scripts/aws-deployment-modular.sh --multi-az --private-subnets --nat-gateway --alb --spot production-stack

# Cost-optimized deployment with intelligent fallback
./scripts/aws-deployment-modular.sh --spot --multi-az stack-name

# Simple development deployment (bash 3.x compatible)
./scripts/aws-deployment-v2-simple.sh dev-stack
```

### Development Without AWS Costs
```bash
./scripts/simple-demo.sh           # Test spot selection logic locally
./scripts/test-intelligent-selection.sh  # Comprehensive local testing
./tests/test-modular-v2.sh        # Test modular system
```

## High-Level Architecture

### Core Design Principles
- **Modular Architecture**: 23 specialized modules with single responsibility
- **Cross-Platform Compatibility**: bash 3.x (macOS) + bash 4.x+ (Linux)
- **Intelligent Cost Optimization**: 70% savings via spot instances and cross-region analysis
- **Enterprise Ready**: Multi-AZ, ALB, CloudFront, comprehensive monitoring

### Modular System Structure
```
/lib/modules/
├── core/              # Variable management, resource registry, base errors
├── infrastructure/    # VPC, security groups, IAM, EFS, ALB modules
├── compute/           # EC2 provisioning, spot optimization, AMI selection
├── application/       # Docker, AI services, health monitoring
├── compatibility/     # Legacy function wrappers
├── cleanup/           # Resource cleanup and failure recovery
└── errors/           # Structured error handling with recovery strategies
```

### Deployment Script Architecture
**Key Pattern**: All deployment scripts must source libraries in this exact order:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/lib/aws-deployment-common.sh"  # Logging, prerequisites
source "$PROJECT_ROOT/lib/error-handling.sh"        # Error handling, cleanup
```

**Primary Orchestrators**:
1. **aws-deployment-v2-simple.sh**: Bash 3.x compatible, core features for development
2. **aws-deployment-modular.sh**: Enterprise features (multi-AZ, ALB, CloudFront, spot optimization)

### AI Services Stack
```
Port Allocation:
├── 5678:  n8n (workflow automation)
├── 11434: Ollama (LLM inference - DeepSeek-R1:8B, Qwen2.5-VL:7B)
├── 6333:  Qdrant (vector database)
├── 11235: Crawl4AI (web scraping)
└── 5432:  PostgreSQL (persistence)
```

### Resource Allocation Strategy (g4dn.xlarge)
- **CPU**: 85% target utilization across 4 vCPUs
- **Memory**: 16GB total (Ollama: 6GB, PostgreSQL/Qdrant: 2GB each)
- **GPU**: T4 16GB (Ollama: ~13.6GB, system reserve: ~2.4GB)

## Critical Implementation Patterns

### Bash 3.x Compatibility (MANDATORY)
```bash
# WRONG - bash 4.x only
declare -g -A MY_ARRAY
declare -A ASSOC_ARRAY

# CORRECT - bash 3.x compatible
declare -A MY_ARRAY  # No -g flag
# Or use regular arrays for simple lookups
```

### Variable Sanitization
All AWS resource names must be sanitized:
```bash
# Problem: efs-id=fs-abc123 causes "not a valid identifier" error
# Solution: Use sanitize_variable_name() from variables.sh module
sanitized=$(echo "$var" | sed 's/[^a-zA-Z0-9_]/_/g')
```

### Error Handling Pattern
```bash
# Use structured error types
source "$LIB_DIR/modules/errors/error_types.sh"
error_ec2_insufficient_capacity "$instance_type" "$region"

# Check recovery strategy
if should_retry_error "EC2_INSUFFICIENT_CAPACITY" 3; then
    # Retry with exponential backoff
fi
```

### AWS API Rate Limiting
- Cache spot prices for 1 hour (individual) or 30 minutes (batch)
- Use 2-second delays between region API calls
- Fallback prices: g4dn.xlarge ($0.21/hr), g5.xlarge ($0.18/hr)

### Security Parameters (SSM)
```
/aibuildkit/OPENAI_API_KEY
/aibuildkit/n8n/ENCRYPTION_KEY
/aibuildkit/POSTGRES_PASSWORD
/aibuildkit/WEBHOOK_URL
```

## Comprehensive Testing Framework

### Test Categories and Commands
```bash
# Run all tests (MANDATORY before deployment)
make test

# Test specific categories  
./tools/test-runner.sh unit           # Module-level testing
./tools/test-runner.sh integration    # Component interactions
./tools/test-runner.sh security       # Security validation
./tools/test-runner.sh performance    # Load tests and benchmarks
./tools/test-runner.sh deployment     # Script validation
./tools/test-runner.sh smoke          # Quick CI/CD validation
./tools/test-runner.sh config         # Configuration management tests

# Generate reports
./tools/test-runner.sh --report       # HTML test report
```

### Key Test Files by Category
- **Core System**: `test-modular-v2.sh`, `test-infrastructure-modules.sh`
- **Deployment**: `test-deployment-flow.sh`, `final-validation.sh`
- **Local Testing**: `simple-demo.sh`, `test-intelligent-selection.sh`
- **Module Testing**: `test-modular-system.sh`

**Reports**: Generated in `./test-reports/` as `test-summary.html` (human-readable) and `test-results.json` (CI/CD integration)

## Common Issues and Solutions

- **Disk space exhaustion**: `./scripts/fix-deployment-issues.sh STACK REGION`
- **EFS mount failures**: `./scripts/setup-parameter-store.sh validate`
- **Spot capacity issues**: Use ec2-provisioning-specialist agent
- **Variable errors**: Check sanitization in variables.sh module

## n8n Workflow Development

When working with n8n workflows:
1. Pre-validate: `validate_node_minimal()` → `validate_node_operation()`
2. Build workflow with validated configs
3. Post-validate: `validate_workflow()` → `validate_workflow_connections()`
4. Deploy using `n8n_update_partial_workflow()` for 80-90% token savings

Remember: ANY node can be an AI tool, not just those with usableAsTool=true.

## Development Rules Integration

### AWS Architecture (.cursor/rules/aws.mdc)
The project follows AWS Well-Architected Framework with 6 pillars:
1. **Operational Excellence**: Automated deployment, comprehensive monitoring
2. **Security**: Least privilege IAM, encryption by default, Parameter Store for secrets
3. **Reliability**: Multi-AZ deployments, spot instance failover strategies
4. **Performance**: GPU optimization (T4 16GB), intelligent instance selection
5. **Cost Optimization**: 70% savings via spot instances, cross-region analysis
6. **Sustainability**: ARM64 Graviton2 support, efficient resource allocation

**Service Selection Order**: Serverless → Containers → Kubernetes → VMs

### n8n Workflow Development (.cursor/rules/n8n-mcp.mdc)
Critical validation pattern for n8n workflows:
1. **Pre-Validation**: `validate_node_minimal()` → `validate_node_operation()`
2. **Build**: Create workflow with validated configurations  
3. **Post-Validation**: `validate_workflow()` → `validate_workflow_connections()`
4. **Deploy**: Use `n8n_update_partial_workflow()` for 80-90% token savings

**Key Insight**: ANY node can be an AI tool (not just usableAsTool=true)

## Project Structure Reference

### Root Directory (Clean)
```
GeuseMaker/
├── CLAUDE.md                          # This file - AI assistant guidance
├── LICENSE                            # MIT license
├── Makefile                           # Development automation (45+ commands)
├── README.md                          # Project documentation
├── docker-compose.gpu-optimized.yml   # Main service composition
└── docker-compose.test.yml           # Test environment
```

### Organized Directories
- `assets/` - Project assets and demo files
- `config/` - Configuration management with environment-specific configs
- `docs/guides/` - Comprehensive documentation (deployment, architecture, testing, troubleshooting)
- `lib/modules/` - 23 specialized modules for modular deployment
- `scripts/` - Primary deployment and management scripts
- `tests/` - Comprehensive test suite with categories
- `tools/` - Development and monitoring utilities