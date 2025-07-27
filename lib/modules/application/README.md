# Application Deployment Modules

This directory contains comprehensive modular components for deploying and managing the AI application stack on AWS infrastructure.

## Modules Overview

### 1. Docker Manager (`docker_manager.sh`)
**Purpose**: Complete Docker and Docker Compose setup with NVIDIA GPU support
- Docker Engine installation and configuration
- NVIDIA Docker runtime setup for GPU instances
- Container orchestration and resource management
- Docker environment optimization for AI workloads

**Key Functions**:
```bash
install_docker [skip_install]           # Install Docker with optimized config
setup_nvidia_docker [force_install]     # Setup NVIDIA runtime for GPU
deploy_ai_services compose_file [env]    # Deploy stack with Docker Compose
monitor_docker_resources                 # Monitor container resource usage
cleanup_docker_resources [aggressive]   # Clean up Docker resources
```

### 2. Service Configuration (`service_config.sh`)
**Purpose**: Generate and manage Docker Compose configurations and environment files
- Dynamic docker-compose.yml generation based on instance type
- Resource allocation optimization (CPU, memory, GPU)
- Environment variable management from Parameter Store
- Service-specific health checks and networking

**Key Functions**:
```bash
generate_docker_compose output_file instance_type [efs_dns] [enable_gpu]
generate_env_file output_file [param_prefix] [include_secrets]
get_instance_resources instance_type     # Get resource allocations
validate_compose_file compose_file       # Validate configuration
```

### 3. AI Services (`ai_services.sh`)
**Purpose**: Setup and manage AI models and service integrations
- Ollama model deployment with GPU optimization
- n8n workflow automation with AI integrations
- Qdrant vector database with collection management
- Crawl4AI web scraping with LLM extraction

**Key Functions**:
```bash
setup_ollama_models instance_type [config] [timeout]
setup_n8n_ai_integration [webhook_url] [enable_ai_nodes]
setup_qdrant_collections [config] [optimize_gpu]
setup_crawl4ai_integration [enable_browser] [llm_provider]
setup_ai_services_integration instance_type [webhook] [models]
```

### 4. Health Monitor (`health_monitor.sh`)
**Purpose**: Comprehensive health checking, monitoring, and alerting
- Multi-service health checks with detailed metrics
- Performance monitoring with GPU support
- Log aggregation and analysis
- Alerting system with webhook/email notifications

**Key Functions**:
```bash
check_application_health [format] [details] [timeout]
start_performance_monitoring [interval] [output_dir] [gpu]
setup_log_aggregation [log_dir] [retention] [rotation]
setup_alerting [webhook] [email] [thresholds]
```

## Integration Pattern

All modules follow the established modular architecture:

```bash
# Source dependencies in this order
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/registry.sh"
source "${SCRIPT_DIR}/../core/errors.sh"
source "${SCRIPT_DIR}/../config/variables.sh"

# Use error context wrapping
with_error_context "function_name" \
    _function_impl "$@"
```

## Usage Examples

### Complete AI Stack Deployment

```bash
#!/bin/bash
# Example deployment script

source "lib/modules/application/docker_manager.sh"
source "lib/modules/application/service_config.sh"
source "lib/modules/application/ai_services.sh"
source "lib/modules/application/health_monitor.sh"

INSTANCE_TYPE="g4dn.xlarge"
STACK_NAME="ai-prod"
EFS_DNS="fs-12345.efs.us-east-1.amazonaws.com"

# 1. Setup Docker environment
install_docker
setup_nvidia_docker

# 2. Generate configurations
generate_docker_compose "docker-compose.yml" "$INSTANCE_TYPE" "$EFS_DNS" "true"
generate_env_file ".env" "/aibuildkit" "false"

# 3. Deploy services
deploy_ai_services "docker-compose.yml" ".env"

# 4. Setup AI services
setup_ai_services_integration "$INSTANCE_TYPE" "http://$(curl -s ifconfig.me):5678"

# 5. Start monitoring
start_performance_monitoring 60 "/shared/monitoring" "true"
setup_alerting "https://hooks.slack.com/webhook" "admin@company.com"

# 6. Validate deployment
check_application_health "text" "true" "60"
```

### Instance-Specific Resource Allocation

The modules automatically optimize for different instance types:

- **g4dn.xlarge** (4 vCPU, 16GB RAM, T4 16GB): Balanced AI workload
- **g4dn.2xlarge** (8 vCPU, 32GB RAM, T4 16GB): High throughput
- **g5.xlarge** (4 vCPU, 16GB RAM, A10G 24GB): Advanced GPU capabilities
- **CPU-only**: Fallback for non-GPU instances

### Environment Variables Integration

Automatically loads from AWS Parameter Store:
```bash
/aibuildkit/POSTGRES_PASSWORD
/aibuildkit/n8n/ENCRYPTION_KEY
/aibuildkit/OPENAI_API_KEY
/aibuildkit/WEBHOOK_URL
```

## Testing and Validation

Each module includes comprehensive testing:

```bash
# Test Docker setup
./scripts/simple-demo.sh

# Test AI services integration
/shared/test-ai-integration.sh

# Test health monitoring
check_application_health "json" "true"

# Performance benchmarking
/shared/benchmark-models.sh
```

## Resource Monitoring

Health monitoring provides multiple output formats:

```bash
# Human-readable status
check_application_health "text"

# JSON for automation
check_application_health "json" | jq '.overall_status'

# Prometheus metrics
check_application_health "prometheus" > metrics.prom

# Quick summary
check_application_health "summary"
```

## Error Handling and Recovery

All modules use the centralized error handling system:
- Context-aware error reporting
- Automatic cleanup on failure
- Retry logic with exponential backoff
- Recovery strategies for common failures

## Compatibility

- **Bash 3.x** compatible (macOS default)
- **AWS CLI v1/v2** support
- **Docker 20.10+** and **Docker Compose v2**
- **NVIDIA Container Toolkit** for GPU support
- **jq** for JSON processing
- **curl, nc, bc** for utilities

## Files Created

The modules create several operational files:
- `/shared/test-models.sh` - AI model testing
- `/shared/test-ai-integration.sh` - End-to-end testing
- `/shared/monitoring/` - Performance data
- `/shared/logs/` - Centralized logging
- `/shared/alerts/` - Alert configuration and history
- `/shared/n8n-workflows/` - Sample workflows
- `/shared/crawl4ai-templates/` - Extraction templates