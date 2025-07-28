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
**Recent Major Changes**: Complete bash 5.3+ modernization, enhanced modular deployment system, comprehensive error handling

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
- **bash-script-validator**: Script validation for bash 5.3+ compatibility and optimization

## Essential Commands

### Testing and Validation
```bash
make test                          # Run all tests (MANDATORY before deployment)
make lint                          # Run shellcheck on all scripts
make security-check                # Security validation
make check-quotas REGION=us-east-1 # Check AWS service quotas
./tools/test-runner.sh unit        # Run specific test category
./tools/test-runner.sh --report    # Generate HTML test report
```

### Core Deployment Commands

| Command | Description | Use Case |
|---------|-------------|----------|
| `make deploy-simple STACK_NAME=dev` | Development deployment | Quick testing, local development |
| `make deploy-spot STACK_NAME=prod` | Cost-optimized production | 70% cost savings with spot instances |
| `make deploy-enterprise STACK_NAME=prod` | Enterprise multi-AZ with ALB | High-availability production |
| `make destroy STACK_NAME=stack` | Clean resource removal | Cleanup after testing |

### Advanced Modular Deployment
```bash
# Enterprise deployment with all features  
./scripts/aws-deployment-modular.sh --multi-az --private-subnets --nat-gateway --alb --spot production-stack

# Cost-optimized deployment with intelligent fallback
./scripts/aws-deployment-modular.sh --spot --multi-az stack-name

# Simple development deployment
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
- **Modern Bash Requirement**: bash 5.3+ for enhanced reliability and security
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

# Modern bash 5.3+ scripts should also include:
source "$PROJECT_ROOT/lib/associative-arrays.sh"    # Enhanced data structures
source "$PROJECT_ROOT/lib/aws-cli-v2.sh"           # Modern AWS CLI integration
# Plus any additional specialized libraries as needed:
# source "$PROJECT_ROOT/lib/config-management.sh"
# source "$PROJECT_ROOT/lib/aws-resource-manager.sh"
```

**Primary Orchestrators**:
1. **aws-deployment-v2-simple.sh**: Core features for development and testing
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

### Bash 5.3+ Requirements (MANDATORY)
All scripts require bash 5.3 or higher for:
- **Associative arrays**: Extensive use throughout the codebase
- **Nameref variables**: Used in modular architecture patterns  
- **Enhanced error handling**: Modern error tracking and recovery
- **Process substitution**: Required for complex pipeline operations

```bash
# Modern bash 5.3+ patterns used throughout:
declare -A CONFIG_CACHE
declare -n config_ref="CONFIG_CACHE"
config_ref["key"]="value"
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

# Advanced testing and validation
make health-check-advanced STACK_NAME=stack    # Comprehensive health diagnostics
make config-validate ENV=development           # Validate configuration files
make aws-cli-demo                              # AWS CLI v2 integration demo

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
- **AWS quota limits**: `make check-quotas REGION=region-name`
- **Health check failures**: `make health-check-advanced STACK_NAME=stack`
- **Configuration issues**: `make config-validate ENV=environment`

## n8n Workflow Development

When working with n8n workflows:
1. Pre-validate: `validate_node_minimal()` → `validate_node_operation()`
2. Build workflow with validated configs
3. Post-validate: `validate_workflow()` → `validate_workflow_connections()`
4. Deploy using `n8n_update_partial_workflow()` for 80-90% token savings

Remember: ANY node can be an AI tool, not just those with usableAsTool=true.

## Bash Requirements and Compatibility

### Minimum Version: bash 5.3+ (Modernized Scripts)

**Important Compatibility Note**: The GeuseMaker project supports both legacy (bash 3.x/4.x) and modern (bash 5.3+) deployment approaches:

- **Legacy Scripts**: `aws-deployment-v2-simple.sh` - Compatible with bash 3.x/4.x (macOS/Linux)
- **Modern Scripts**: `aws-deployment-modular.sh` and enhanced modules require **bash 5.3+**

All **new** scripts and enhanced modules require **bash 5.3 or higher** for:
- **Comprehensive associative arrays** - Modern data structures for pricing, configuration, and state management
- **Enhanced error handling** - Structured error tracking with associative arrays
- **Advanced array operations** - Utility functions for merge, filter, validate, and transform operations
- **Type-safe configurations** - Validated configuration management with inheritance and overrides
- **Performance optimizations** - Efficient caching and state management using native bash features
- **Security improvements** - Critical bug fixes and improved input validation

### Platform Support

| Platform | Installation Method | Notes |
|----------|-------------------|-------|
| **macOS** | `brew install bash` | Required - system bash 3.2 not supported |
| **Ubuntu 22.04+** | `apt install bash` | Usually has bash 5.1+, may need source compile |
| **Amazon Linux 2** | Auto-installed via EC2 user data | Compiled from source during deployment |
| **Development** | Manual upgrade required | See upgrade instructions in docs/OS-COMPATIBILITY.md |
| **Development** | Manual upgrade required | See upgrade instructions below |

### Automatic Version Validation

Every script automatically validates bash version:
- **Critical scripts**: Exit with helpful error message if version too old
- **Sourced modules**: Display warning but continue (for compatibility)
- **EC2 instances**: Auto-install bash 5.3.3 during boot process

### Upgrade Instructions

**macOS (required):**
```bash
# Install Homebrew bash
brew install bash

# Add to allowed shells
sudo echo '/opt/homebrew/bin/bash' >> /etc/shells

# Use in new terminals or change default shell
chsh -s /opt/homebrew/bin/bash
```

**Ubuntu/Debian:**
```bash
# Update to latest available
sudo apt update && sudo apt install bash

# For bash 5.3+ compile from source if needed
wget https://ftp.gnu.org/gnu/bash/bash-5.3.tar.gz
tar -xzf bash-5.3.tar.gz && cd bash-5.3
./configure --prefix=/usr/local && make && sudo make install
```

**Verification:**
```bash
bash --version  # Should show 5.3 or higher
```

### Deployment Impact

- **EC2 Instances**: Bash 5.3+ auto-installed via user data script
- **Docker Containers**: Use images with modern bash (Ubuntu 22.04+)
- **CI/CD**: Ensure runners have bash 5.3+ installed
- **Development**: All team members must upgrade local bash

### Modern Associative Array Architecture

The project now leverages comprehensive associative arrays throughout the codebase:

#### Core Libraries Enhanced with Associative Arrays:

1. **`/lib/associative-arrays.sh`** - Comprehensive utility library
   - `aa_get()`, `aa_set()`, `aa_has_key()`, `aa_delete()` - Basic operations
   - `aa_merge()`, `aa_copy()`, `aa_filter_keys()`, `aa_transform()` - Advanced operations
   - `aa_validate()`, `aa_stats()` - Data validation and analytics
   - `aa_to_json()`, `aa_from_json()` - Serialization support

2. **`/lib/spot-instance.sh`** - Pricing analysis with associative arrays
   - Intelligent pricing cache with TTL support
   - Instance capability matrices for selection optimization
   - Historical pricing data and trend analysis
   - Enhanced cost calculations with GPU cost-per-GB metrics

3. **`/lib/config-management.sh`** - Configuration inheritance system
   - Environment-specific overrides using associative arrays
   - Configuration profiles (ml_development, ml_production, cost_optimized)
   - Type-safe configuration validation (string, number, boolean)
   - YAML configuration loading into structured arrays

4. **`/lib/aws-resource-manager.sh`** - Resource lifecycle management
   - Comprehensive resource tracking and state management
   - Dependency mapping and lifecycle policies
   - Automated cleanup based on rules and age
   - Resource health monitoring and reporting

5. **`/lib/enhanced-test-framework.sh`** - Test execution and reporting
   - Test categorization and dependency resolution
   - Parallel test execution with progress tracking
   - Enhanced reporting (HTML, JSON, YAML formats)
   - Custom assertion framework with detailed results

6. **`/lib/deployment-state-manager.sh`** - Deployment orchestration
   - Multi-phase deployment with progress tracking
   - Rollback and recovery mechanisms
   - Deployment dependencies and validation
   - Real-time status reporting and notifications

#### Key Patterns and Benefits:

- **Structured Data**: Replace string manipulation with proper data structures
- **Type Safety**: Validation rules and type checking for configuration values
- **Performance**: Efficient caching and lookup mechanisms
- **Maintainability**: Clear separation of concerns and modular architecture
- **Extensibility**: Easy addition of new features through array-based APIs

#### Migration Notes:
- All new scripts should use the associative array utilities
- Legacy scripts are being gradually updated to use the new patterns
- Backward compatibility maintained through wrapper functions
- Enhanced error handling provides better debugging information

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
- `docs/` - Comprehensive documentation including:
  - `guides/` - Deployment, architecture, testing, troubleshooting guides
  - `BASH_MODERNIZATION_GUIDE.md` - Bash 5.3+ upgrade instructions
  - `ENHANCED_DEPLOYMENT_GUIDE.md` - Advanced deployment patterns
  - `OS-COMPATIBILITY.md` - Platform compatibility matrix
- `lib/modules/` - 23 specialized modules for modular deployment
- `scripts/` - Primary deployment and management scripts
- `tests/` - Comprehensive test suite with categories
- `tools/` - Development and monitoring utilities
- `MODERNIZATION_SUMMARY.md` - Recent modernization changes summary