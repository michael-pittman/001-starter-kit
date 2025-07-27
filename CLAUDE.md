# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git Context & Workflow

**Current Branch**: `main` (default)
**Recent Major Changes**: Complete modular deployment architecture with 23 modules, bash 3.x compatibility, comprehensive error handling

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

### Deployment Commands
```bash
# Quick development deployment
make deploy-simple STACK_NAME=dev

# Production deployment with spot instances
make deploy-spot STACK_NAME=prod

# Advanced modular deployment
./scripts/aws-deployment-modular.sh --multi-az --alb STACK_NAME

# Cleanup resources
make destroy STACK_NAME=dev
```

### Development Without AWS Costs
```bash
./scripts/simple-demo.sh           # Test spot selection logic locally
./scripts/test-intelligent-selection.sh  # Comprehensive local testing
./tests/test-modular-v2.sh        # Test modular system
```

## High-Level Architecture

### Modular System Structure
The codebase uses a modular architecture with 23 specialized modules:

```
/lib/modules/
├── core/              # Variable management, resource registry, base errors
├── infrastructure/    # VPC, security groups, IAM, EFS, ALB modules
├── compute/           # EC2 provisioning, spot optimization
├── application/       # Docker, AI services, health monitoring
├── compatibility/     # Legacy function wrappers
└── errors/           # Structured error handling with recovery strategies
```

**Key Design Pattern**: Each module is self-contained with single responsibility. All modules follow bash 3.x compatibility for macOS support.

### Deployment Script Hierarchy

1. **aws-deployment-v2-simple.sh**: Bash 3.x compatible orchestrator with core features
2. **aws-deployment-modular.sh**: Enterprise features (multi-AZ, ALB, CloudFront)
3. **aws-deployment-unified.sh**: Original monolithic script (legacy)

All scripts must source these in order:
```bash
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"  # Logging functions
source "$PROJECT_ROOT/lib/error-handling.sh"        # Error trapping
```

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

## Testing Framework

Categories: unit, integration, security, performance, deployment, smoke, config

Key test files:
- `test-modular-v2.sh`: Core module functionality
- `test-infrastructure-modules.sh`: Infrastructure components
- `test-deployment-flow.sh`: End-to-end validation
- `final-validation.sh`: Comprehensive system check

Reports generated in `./test-reports/` as HTML and JSON.

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

## AWS Well-Architected Principles

Follow the 6 pillars:
1. Operational Excellence
2. Security (least privilege, encryption by default)
3. Reliability (multi-AZ when using --multi-az)
4. Performance (GPU optimization, spot instances)
5. Cost Optimization (70% savings via spot instances)
6. Sustainability

Service selection order: Serverless → Containers → Kubernetes → VMs