# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git Context & Workflow

**Current Branch**: `GeuseMaker` (feature branch)  
**Main Branch**: `main` (for pull requests)  
**Recent Changes**: Modular deployment architecture, enhanced test runner, specialized agent integration

### Branch Workflow
- Work on feature branch `GeuseMaker`
- Create PRs against `main` branch
- Always run tests before committing: `make test`
- Check git status with: `git status` to see current modified files

### Claude Code Agent Integration
The project includes specialized Claude Code agents for automated assistance:
- **ec2-provisioning-specialist**: Handles EC2 launch failures, spot instance capacity issues, AMI availability problems, and service quota limits
- **aws-deployment-debugger**: Debugs deployment failures, spot instance issues, and infrastructure problems
- **spot-instance-optimizer**: Optimizes AWS spot instance deployments for cost savings and handles spot instance interruptions
- **security-validator**: Performs security validation and compliance checking before production
- **test-runner-specialist**: Orchestrates comprehensive testing workflows before deployments

## Project Overview

GeuseMaker is an enterprise-ready AI infrastructure platform for GPU-optimized AWS deployment featuring:
- **70% cost savings** through intelligent spot instance management and cross-region analysis
- **Multi-architecture support** (Intel x86_64 and ARM64 Graviton2) with intelligent GPU selection
- **AI Stack**: n8n workflows + Ollama (DeepSeek-R1:8B, Qwen2.5-VL:7B) + Qdrant + Crawl4AI
- **Enterprise features**: Auto-scaling, CloudFront CDN, EFS persistence, comprehensive monitoring

## Essential Commands

### Build, Test, and Validate
```bash
# Core quality checks
make lint                           # Run shellcheck on all shell scripts
make test                          # Run all tests (MANDATORY before deployment)
make security-check                # Security validation
./scripts/security-validation.sh   # Direct security checks

# Test specific components without AWS costs
./scripts/simple-demo.sh           # Test intelligent selection logic
./tools/test-runner.sh unit        # Run unit tests only
./tools/test-runner.sh security    # Run security tests only
./tools/test-runner.sh --report    # Generate HTML test report
```

### Deployment Commands
```bash
# Basic deployment workflow
make setup                         # Initial setup with security
make deploy-simple STACK_NAME=dev  # Quick development deployment
make health-check STACK_NAME=dev   # Verify services
make destroy STACK_NAME=dev        # Clean up resources

# Advanced deployment options
make deploy-spot STACK_NAME=prod   # Cost-optimized spot instances
make deploy-spot-cdn STACK_NAME=prod # Spot + CloudFront CDN
./scripts/aws-deployment-modular.sh [OPTIONS] STACK_NAME  # New modular deployment
```

### Testing Without AWS Costs
```bash
# Critical for development - test logic without creating resources
./scripts/simple-demo.sh                    # Basic intelligent selection
./scripts/test-intelligent-selection.sh     # Comprehensive testing
./tests/test-docker-config.sh              # Docker configuration
./tests/test-modular-system.sh             # Modular architecture tests
```

## High-Level Architecture

### Modular Deployment System (NEW)
The project is transitioning to a cleaner modular architecture in `/lib/modules/`:

```
/lib/modules/
├── core/           # Registry (resource tracking) + Error handling
├── config/         # Centralized variable management with validation
├── infrastructure/ # VPC and security group creation
├── instances/      # AMI selection and instance launching
├── deployment/     # User data generation for instance configuration
├── monitoring/     # Health checks and status monitoring
└── cleanup/        # Resource cleanup and failure recovery
```

**Key Pattern**: Each module is self-contained with a single responsibility, making the codebase more maintainable and testable.

### Deployment Script Architecture
All deployment scripts follow this mandatory pattern:

```bash
# ALWAYS start deployment scripts with:
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Required libraries in order:
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"  # Logging, prerequisites
source "$PROJECT_ROOT/lib/error-handling.sh"        # Error handling, cleanup
```

**Library Functions**:
- `aws-deployment-common.sh`: `log()`, `error()`, `success()`, `check_common_prerequisites()`
- `error-handling.sh`: Cleanup on failure, error trapping
- `spot-instance.sh`: Spot pricing, instance selection
- `aws-config.sh`: Configuration defaults

### Testing Framework
Shell-based testing with comprehensive coverage:

```
Test Categories:
- unit: Function-level tests (security validation, utilities)
- integration: Component interaction (deployment workflow, Docker)
- security: Vulnerability scans (bandit, safety, trivy if available)
- performance: Load tests and benchmarks
- deployment: Script validation, Terraform checks
- smoke: Quick CI/CD validation
- config: Configuration management tests

Test Reports: ./test-reports/
- test-summary.html (human-readable)
- test-results.json (CI/CD integration)
```

### Service Architecture
```
AWS Infrastructure:
├── EC2 Instance (g4dn.xlarge or similar)
│   ├── Docker Services
│   │   ├── n8n (port 5678) - Workflow automation
│   │   ├── Ollama (port 11434) - LLM inference
│   │   ├── Qdrant (port 6333) - Vector database
│   │   ├── Crawl4AI (port 11235) - Web scraping
│   │   └── PostgreSQL (port 5432) - Data persistence
│   └── GPU Resources (NVIDIA T4 16GB)
├── EFS - Shared persistent storage
├── ALB - Load balancing (optional)
└── CloudFront - CDN (optional)
```

## Critical Development Patterns

### macOS Bash Compatibility
The project supports bash 3.x (macOS default) and 4.x+ (Linux):
- **No associative arrays** - Uses function-based lookups
- **Array syntax** - Uses `"${array[@]}"` compatible syntax
- **Variable safety** - All variables initialized to prevent `-u` errors

### AWS API Rate Limiting
Intelligent pricing with caching to avoid rate limits:
- 1-hour cache for individual pricing, 30-minute for batch data
- Fallback pricing: g4dn.xlarge ($0.21/hr), g5g.xlarge ($0.18/hr)
- Maximum 1 API call per region with 2-second delays
- Batch requests for all instance types vs individual calls

### Security Configuration
Required AWS SSM Parameters:
```
/aibuildkit/OPENAI_API_KEY      # OpenAI API key
/aibuildkit/n8n/ENCRYPTION_KEY  # n8n encryption
/aibuildkit/POSTGRES_PASSWORD   # Database password
/aibuildkit/WEBHOOK_URL         # Webhook base URL
```

### Resource Allocation (g4dn.xlarge)
```
CPU (4 vCPUs, 85% target):
- ollama: 2.0 vCPUs (50%)
- postgres: 0.4 vCPUs (10%)
- n8n/qdrant/crawl4ai: 0.4 vCPUs each
- monitoring: 0.3 vCPUs

Memory (16GB total):
- ollama: 6GB (37.5%)
- postgres/qdrant: 2GB each
- n8n/crawl4ai: 1.5GB each

GPU (T4 16GB):
- ollama: ~13.6GB (85%)
- system: ~2.4GB reserve
```

## Development Rules from Cursor IDE

### AWS Architecture (.cursor/rules/aws.mdc)
- **Well-Architected Framework**: 6 pillars (Operational Excellence, Security, Reliability, Performance, Cost, Sustainability)
- **Service Selection**: Serverless-first → Containers → Kubernetes → VMs
- **Database Matrix**: Aurora for high-performance relational, DynamoDB for NoSQL scale
- **Architecture by Scale**: Single account (startup) → Multi-account (mid) → Multi-region (enterprise)

### n8n Workflow Development (.cursor/rules/n8n-mcp.mdc)
Critical validation pattern for n8n workflows:
1. Pre-Validation: `validate_node_minimal()` → `validate_node_operation()`
2. Build: Create workflow with validated configurations
3. Post-Validation: `validate_workflow()` → `validate_workflow_connections()`
4. Deploy: Use `n8n_update_partial_workflow()` for 80-90% token savings

**Key Insight**: ANY node can be an AI tool (not just usableAsTool=true)

## Troubleshooting Quick Reference

### Common Issues
- **Disk space exhaustion**: Run `./scripts/fix-deployment-issues.sh STACK REGION`
- **EFS not mounting**: Check Parameter Store setup with `./scripts/setup-parameter-store.sh validate`
- **Spot capacity issues**: Use `ec2-provisioning-specialist` agent for cross-region analysis
- **Services failing**: Check disk space first, then environment variables

### Debug Commands
```bash
# Check services
docker compose -f docker-compose.gpu-optimized.yml ps
docker compose -f docker-compose.gpu-optimized.yml logs ollama

# Monitor resources
nvidia-smi                    # GPU usage
df -h                        # Disk space
du -sh /var/lib/docker      # Docker space

# AWS validation
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running"
./scripts/setup-parameter-store.sh list
```

## File Location Quick Reference

```
/lib/                        # Core libraries (source in all scripts)
├── aws-deployment-common.sh # Logging, prerequisites
├── error-handling.sh        # Error handling, cleanup
├── modules/                 # NEW modular components
│   ├── core/               # Registry, errors
│   ├── config/             # Variable management
│   └── ...                 # Other modules

/scripts/                    # Main deployment scripts
├── aws-deployment-unified.sh    # Main orchestrator
├── aws-deployment-modular.sh    # NEW modular deployment
├── simple-demo.sh              # Test without AWS costs
└── fix-deployment-issues.sh    # Deployment troubleshooting

/tests/                      # Testing framework
├── test-*.sh               # Individual test scripts
└── test-modular-system.sh  # NEW modular architecture tests

/tools/                      # Development tools
└── test-runner.sh          # Test orchestration

/.cursor/rules/              # IDE development rules
├── aws.mdc                 # AWS best practices
└── n8n-mcp.mdc            # n8n workflow patterns
```