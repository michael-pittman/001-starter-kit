# Unity Docker Service - Comprehensive Guide

## Overview

The Unity Docker Service is a comprehensive container management solution that consolidates all Docker-related functionality from the GeuseMaker system into a single, unified service. It provides enterprise-grade container orchestration, health monitoring, log aggregation, and resource management capabilities.

## Key Features

### 🚀 **Container Lifecycle Management**
- Complete container lifecycle operations (start, stop, restart, status)
- Intelligent health monitoring with auto-recovery
- Graceful shutdown with configurable timeouts
- Container resource monitoring and optimization

### 🐋 **Docker Compose Orchestration**
- Enhanced Docker Compose deployment with dependency management
- Service health checking and startup coordination
- Environment-specific configuration management
- Stack monitoring and auto-recovery

### 📊 **Health Monitoring & Auto-Recovery**
- Real-time container health monitoring
- Automatic restart of unhealthy containers
- Compose stack monitoring
- Configurable failure thresholds and recovery strategies

### 📝 **Log Aggregation & Analysis**
- Centralized log collection from all containers
- Automated log rotation and retention
- Log analysis and error detection
- Integration with existing log aggregation systems

### 🎮 **NVIDIA GPU Support**
- Automatic GPU detection and setup
- NVIDIA Container Toolkit installation
- GPU runtime configuration
- GPU resource monitoring

### 🔧 **Resource Management**
- Docker resource cleanup and optimization
- Image and volume management
- Network resource cleanup
- Storage usage monitoring

## Architecture

The Unity Docker Service follows GeuseMaker's modular architecture:

```
Unity Docker Service
├── Container Lifecycle Management
├── Docker Compose Orchestration  
├── Health Monitoring & Auto-Recovery
├── Log Aggregation & Analysis
├── Resource Management & Optimization
├── NVIDIA GPU Support
└── Unity Service Integration
```

## Installation & Setup

### 1. Load the Service

```bash
# Source the unified Docker service
source lib/unity/services/unity-docker-service.sh

# Initialize the service
unity_docker_init
```

### 2. Validate Installation

```bash
# Check service status
unity_docker_status

# Validate Docker environment
unity_docker_validate
```

### 3. Install Docker (if needed)

```bash
# Install Docker with default settings
unity_docker_execute install

# Install Docker with GPU support
unity_docker_execute install false true

# Install on specific distributions (handled automatically)
unity_docker_execute install false auto
```

## Usage Examples

### Container Operations

#### Start a Container
```bash
# Basic container start
unity_docker_execute start "nginx:latest" "my-nginx"

# Start with custom options
unity_docker_execute start "postgres:13" "my-db" "-e POSTGRES_PASSWORD=secret -p 5432:5432"

# Start without health check wait
unity_docker_execute start "redis:alpine" "my-redis" "" false
```

#### Monitor Container Status
```bash
# Get detailed container status (JSON)
unity_docker_execute status "my-nginx" json

# Get simple status
unity_docker_execute status "my-nginx" text
```

#### Stop and Restart Containers
```bash
# Stop container gracefully (30s timeout)
unity_docker_execute stop "my-nginx"

# Stop with custom timeout and remove
unity_docker_execute stop "my-nginx" 60 true

# Restart container
unity_docker_execute restart "my-nginx"
```

### Docker Compose Operations

#### Deploy a Stack
```bash
# Deploy complete stack
unity_docker_execute compose-deploy "docker-compose.yml" ".env.local" "my-stack"

# Deploy specific services
unity_docker_execute compose-deploy "docker-compose.yml" ".env.local" "my-stack" "web db"

# Deploy without health check wait
unity_docker_execute compose-deploy "docker-compose.yml" ".env.local" "my-stack" "" false
```

#### Monitor Stack Status
```bash
# Get stack status (table format)
unity_docker_execute compose-status "docker-compose.yml" ".env.local" "my-stack"

# Get status in JSON format
unity_docker_execute compose-status "docker-compose.yml" ".env.local" "my-stack" json
```

#### Stop Stack
```bash
# Stop stack (containers only)
unity_docker_execute compose-stop "docker-compose.yml" ".env.local" "my-stack"

# Stop specific services
unity_docker_execute compose-stop "docker-compose.yml" ".env.local" "my-stack" "web"

# Stop and remove volumes
unity_docker_execute compose-stop "docker-compose.yml" ".env.local" "my-stack" "" true
```

### Health Monitoring

#### Manual Health Checks
```bash
# Wait for container to become healthy
unity_docker_execute health-check "my-nginx" 120

# Check with custom timeout
unity_docker_execute health-check "my-db" 300
```

#### Background Monitoring
```bash
# Container monitoring happens automatically when DOCKER_MONITORING_ENABLED=true
# You can also start monitoring manually:

# Monitor specific container (runs in background)
docker_monitor_container "my-nginx" 30 true &

# Monitor compose stack (runs in background)  
docker_monitor_compose_stack "my-stack" 60 &
```

### Log Management

#### Setup Log Aggregation
```bash
# Setup with default settings
docker_setup_log_aggregation

# Setup with custom directory and retention
docker_setup_log_aggregation "/shared/logs/docker" 14
```

#### Analyze Logs
```bash
# Analyze logs from default directory
unity_docker_execute analyze-logs

# Analyze with custom directory and output file
unity_docker_execute analyze-logs "/shared/logs/docker" "/tmp/docker-analysis.txt"
```

### Resource Management

#### Monitor Resources
```bash
# Monitor for 1 hour with 30s intervals
unity_docker_execute monitor

# Monitor with custom settings
unity_docker_execute monitor "/tmp/docker-metrics.jsonl" 7200 60
```

#### Clean Up Resources
```bash
# Basic cleanup (24h retention)
unity_docker_execute cleanup

# Aggressive cleanup
unity_docker_execute cleanup true

# Custom retention period
unity_docker_execute cleanup false "48h"
```

### GPU Operations

#### Setup NVIDIA Support
```bash
# Setup GPU support (auto-detects GPU)
unity_docker_execute setup-gpu

# Force GPU setup installation
unity_docker_execute setup-gpu true
```

#### Check GPU Availability
```bash
# Check if GPU is available
if docker_has_gpu; then
    echo "GPU support available"
else
    echo "No GPU detected"
fi
```

### List Operations

#### List Containers
```bash
# List GeuseMaker managed containers
unity_docker_execute list

# List in JSON format
unity_docker_execute list json

# List container names only
unity_docker_execute list names

# List all containers
unity_docker_execute list-all
```

#### System Information
```bash
# Get Docker system info
unity_docker_execute system-info

# Get info in JSON format
unity_docker_execute system-info json
```

## Configuration

The Unity Docker Service supports extensive configuration through environment variables:

### Core Configuration
```bash
# Docker daemon settings
export DOCKER_DATA_ROOT="/var/lib/docker"
export DOCKER_LOG_MAX_SIZE="100m"
export DOCKER_LOG_MAX_FILE="3"

# Health monitoring
export DOCKER_HEALTH_CHECK_INTERVAL="30s"
export DOCKER_HEALTH_CHECK_TIMEOUT="10s"
export DOCKER_HEALTH_CHECK_RETRIES="3"

# Feature toggles
export DOCKER_MONITORING_ENABLED="true"
export DOCKER_LOG_AGGREGATION_ENABLED="true"
export DOCKER_AUTO_RECOVERY_ENABLED="true"

# Storage paths
export DOCKER_SHARED_STORAGE="/shared"
export DOCKER_LOG_DIR="/shared/logs/docker"
export DOCKER_METRICS_DIR="/shared/metrics"
```

### Advanced Configuration
```bash
# Cleanup behavior
export DOCKER_CLEANUP_ON_EXIT="false"

# Resource limits (set automatically based on instance type)
export DOCKER_CPU_LIMIT="3.4"
export DOCKER_MEMORY_LIMIT="14G"

# Build settings
export DOCKER_BUILDKIT="1"
export COMPOSE_DOCKER_CLI_BUILD="1"
```

## Integration with GeuseMaker AI Stack

The Unity Docker Service is optimized for GeuseMaker's AI services stack:

### Deploying the AI Stack
```bash
# Deploy the complete AI services stack
unity_docker_execute compose-deploy "docker-compose.gpu-optimized.yml" ".env.local" "ai-stack"

# Monitor AI services health
docker_monitor_compose_stack "ai-stack" 60 &

# Check specific AI service status
unity_docker_execute status "n8n-ai" json
unity_docker_execute status "ollama-ai" json
unity_docker_execute status "qdrant-ai" json
```

### AI Service Logs
```bash
# Analyze AI service logs
unity_docker_execute analyze-logs "/shared/logs/docker" "/tmp/ai-services-analysis.txt"

# Collect logs from specific AI services
docker logs n8n-ai --since "1h" > /shared/logs/n8n-recent.log
docker logs ollama-ai --since "1h" > /shared/logs/ollama-recent.log
```

## Best Practices

### 1. Container Labeling
Always use GeuseMaker labels for proper management:
```bash
# Containers started through the service automatically get:
# --label com.geusemaker.managed=true
# --label com.geusemaker.service=unity-docker
# --label com.geusemaker.stack=${STACK_NAME}
```

### 2. Health Checks
Define health checks in your Docker images or Compose files:
```yaml
services:
  web:
    image: nginx:latest
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
```

### 3. Resource Limits
Set appropriate resource limits:
```yaml
services:
  ai-service:
    image: ollama/ollama:latest
    deploy:
      resources:
        limits:
          memory: 8G
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
```

### 4. Logging Configuration
Use structured logging:
```yaml
services:
  app:
    image: myapp:latest
    logging:
      driver: json-file
      options:
        max-size: "100m"
        max-file: "3"
        labels: "com.geusemaker.log-aggregation=enabled"
```

## Troubleshooting

### Common Issues

#### 1. Docker Daemon Not Running
```bash
# Check daemon status
sudo systemctl status docker

# Start daemon
sudo systemctl start docker

# Validate through service
unity_docker_validate
```

#### 2. Permission Issues
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Re-login or run:
newgrp docker

# Validate permissions
docker ps
```

#### 3. Container Health Check Failures
```bash
# Check container logs
docker logs container-name

# Get detailed container status
unity_docker_execute status "container-name" json

# Force restart
unity_docker_execute restart "container-name"
```

#### 4. Compose Stack Issues
```bash
# Check compose file syntax
docker compose -f docker-compose.yml config

# Get stack status
unity_docker_execute compose-status "docker-compose.yml" ".env.local" "stack-name"

# Check individual service logs
docker logs stack-name_service-name_1
```

### Debugging Mode

Enable debug logging:
```bash
export DEBUG=true
export LOG_LEVEL=DEBUG

# Re-initialize service
unity_docker_init
```

## Performance Optimization

### 1. Container Resource Monitoring
```bash
# Monitor resource usage
unity_docker_execute monitor "/tmp/metrics.jsonl" 3600 30

# Analyze metrics
jq '.CPUPerc' /tmp/metrics.jsonl | sort -n | tail -10
```

### 2. Docker System Optimization
```bash
# Regular cleanup
unity_docker_execute cleanup false "24h"

# Check disk usage
docker system df

# Prune build cache
docker builder prune -f
```

### 3. Log Management
```bash
# Setup automated log rotation
docker_setup_log_aggregation "/shared/logs/docker" 7

# Analyze log patterns
docker_analyze_logs "/shared/logs/docker"
```

## API Reference

### Core Functions

#### `unity_docker_init()`
Initialize the Unity Docker Service
- **Returns**: 0 on success, error code on failure

#### `unity_docker_validate()`
Validate Docker environment
- **Returns**: 0 if valid, error code if validation fails

#### `unity_docker_execute(operation, ...args)`
Execute Docker operations
- **Parameters**: 
  - `operation`: Operation name (see usage examples)
  - `...args`: Operation-specific arguments
- **Returns**: Operation-specific return value

#### `unity_docker_status()`
Display service status
- **Returns**: 0 always

#### `unity_docker_cleanup()`
Clean up service resources
- **Returns**: 0 on success

### Container Management Functions

#### `docker_start_container(image, name, options, wait_for_health)`
Start a Docker container with monitoring
- **Parameters**:
  - `image`: Docker image name
  - `name`: Container name (optional)
  - `options`: Docker run options (optional)
  - `wait_for_health`: Wait for health check (default: true)

#### `docker_stop_container(name, timeout, remove)`
Stop a Docker container gracefully
- **Parameters**:
  - `name`: Container name
  - `timeout`: Graceful shutdown timeout (default: 30s)
  - `remove`: Remove container after stop (default: false)

#### `docker_get_container_status(name, format)`
Get detailed container status
- **Parameters**:
  - `name`: Container name
  - `format`: Output format ("json" or "text")
- **Returns**: Container status information

### Compose Management Functions

#### `docker_compose_deploy(compose_file, env_file, stack_name, services, wait_for_health)`
Deploy Docker Compose stack
- **Parameters**:
  - `compose_file`: Path to compose file
  - `env_file`: Path to environment file (optional)
  - `stack_name`: Stack name (default: "geusemaker")
  - `services`: Specific services to deploy (optional)
  - `wait_for_health`: Wait for health checks (default: true)

#### `docker_compose_stop(compose_file, env_file, stack_name, services, remove_volumes)`
Stop Docker Compose stack
- **Parameters**:
  - `compose_file`: Path to compose file
  - `env_file`: Path to environment file (optional)
  - `stack_name`: Stack name
  - `services`: Specific services to stop (optional)
  - `remove_volumes`: Remove volumes (default: false)

### Monitoring Functions

#### `docker_monitor_container(name, interval, recovery_enabled)`
Monitor container health with auto-recovery
- **Parameters**:
  - `name`: Container name
  - `interval`: Check interval in seconds (default: 30)
  - `recovery_enabled`: Enable auto-recovery (default: true)

#### `docker_monitor_resources(output_file, duration, interval)`
Monitor Docker resource usage
- **Parameters**:
  - `output_file`: Output file path
  - `duration`: Monitoring duration in seconds (default: 3600)
  - `interval`: Collection interval in seconds (default: 30)

### Utility Functions

#### `docker_has_gpu()`
Check if NVIDIA GPU is available
- **Returns**: 0 if GPU available, 1 otherwise

#### `docker_cleanup_resources(aggressive, max_age)`
Clean up Docker resources
- **Parameters**:
  - `aggressive`: Perform aggressive cleanup (default: false)
  - `max_age`: Maximum age for cleanup (default: "24h")

## Contributing

The Unity Docker Service is part of the GeuseMaker project. When contributing:

1. Follow the existing code patterns and conventions
2. Add comprehensive error handling
3. Include bash 3.x compatibility
4. Add appropriate logging statements
5. Update documentation for new features
6. Test with various Docker versions and configurations

## Support

For support and troubleshooting:
1. Check the troubleshooting section above
2. Review Docker and GeuseMaker logs
3. Validate configuration settings
4. Test with minimal configurations
5. Consult GeuseMaker documentation

The Unity Docker Service provides a robust, enterprise-ready foundation for container management in the GeuseMaker AI infrastructure platform.