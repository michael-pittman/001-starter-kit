# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**GeuseMaker** is an enterprise-ready AWS deployment system with AI infrastructure capabilities that has **fully migrated to Unity**, an event-driven service architecture:
- **70% cost savings** via intelligent spot instance optimization
- **Multi-architecture support** (Intel x86_64 and ARM64 Graviton2)
- **AI Stack**: n8n workflows + Ollama (DeepSeek-R1:8B, Qwen2.5-VL:7B) + Qdrant + Crawl4AI
- **Enterprise features**: Multi-AZ, ALB, CloudFront CDN, EFS persistence, comprehensive monitoring
- **Unity Architecture**: Event-driven service architecture with plugin framework (ONLY deployment option)

## Essential Commands

### Primary Deployment Interface
```bash
# Main entry point - ./unity
./unity deploy spot my-stack           # Deploy spot instance (70% cost savings)
./unity deploy alb prod-stack          # Deploy with Application Load Balancer
./unity deploy cdn prod-stack          # Deploy with CloudFront CDN
./unity deploy full prod-stack         # Deploy complete stack (VPC+EC2+ALB+CDN)
./unity destroy my-stack               # Destroy all resources

# Alternative entry point - deploy.sh (same functionality)
./deploy.sh spot dev-stack             # Deploy spot instance
./deploy.sh destroy dev-stack          # Destroy resources

# Backward compatibility - make wrapper
./make deploy-spot                     # Redirects to: ./unity deploy spot
./make deploy-alb                      # Redirects to: ./unity deploy alb
```

### Service and Configuration Management
```bash
# Service operations
./unity service list                   # List all Unity services
./unity service status aws             # Check specific service status
./unity service health docker          # Check service health
./unity service restart monitor        # Restart a service

# Configuration operations
./unity config show                    # Display all configuration
./unity config get aws.region          # Get specific value
./unity config set aws.region us-west-2 # Set configuration value
./unity config validate                # Validate configuration

# Monitoring and logs
./unity status my-stack                # Check deployment status
./unity monitor my-stack               # Real-time monitoring
./unity logs my-stack                  # View deployment logs
```

### Testing Commands
```bash
# Primary test suites
./tests/unity/test-unity-implementation.sh      # Implementation validation
./tests/unity/production-validation.sh          # Production readiness check
./tests/unity/test-unity-complete-system.sh     # Full system test

# Specific component tests
./tests/unity/unit/test-unity-aws-service.sh    # AWS service tests
./tests/unity/integration/test-unity-service-integration.sh  # Integration tests
./tests/unity/performance/test-unity-performance-benchmarks.sh  # Performance tests
```

### Migration and Legacy Support
```bash
# Deprecate legacy code (one-time operation)
./scripts/deprecate-legacy.sh          # Archives all legacy code to deprecated/

# Migration utilities
./scripts/migrate-to-unity/migrate-all.sh  # Migrate legacy modules to Unity
./scripts/port-makefile-to-unity.sh       # Port Makefile targets (already completed)
```

## High-Level Architecture

### Unity Event-Driven Architecture

GeuseMaker uses Unity as its **sole deployment system**. All operations follow an event-driven pattern where services communicate asynchronously through a central event bus.

**Core Architecture Principles**:
1. **Event-Driven Communication**: Services emit and react to events, enabling loose coupling
2. **Service Isolation**: Each service runs independently with clear interfaces
3. **Plugin Extensibility**: Add functionality without modifying core services
4. **Reactive Patterns**: Non-blocking, asynchronous operations throughout
5. **Single Configuration Source**: `config/unity.yml` drives all behavior

### Service Architecture

```
lib/unity/
├── core/                             # Unity foundation
│   ├── unity-core.sh                # Service registry, lifecycle management
│   ├── unity-events.sh              # Event bus implementation
│   ├── unity-plugins.sh             # Plugin framework
│   └── unity-preflight.sh           # Pre-deployment validation
├── services/                         # Unity services
│   ├── unity-aws-service-complete.sh    # Complete AWS operations
│   ├── unity-docker-service-complete.sh # Docker container management
│   ├── unity-monitoring-complete.sh      # CloudWatch integration
│   └── unity-deployment-service.sh      # Deployment orchestration
└── events/                          # Event system
    ├── event-bus.sh                 # Event routing
    ├── event-persistence.sh         # Event storage
    └── rollback-manager.sh          # Failure recovery
```

### Service Communication Pattern

All Unity services implement a standard interface:
```bash
# Required service functions
init_<service>_service()      # Initialize service
start_<service>_service()     # Start service operations
stop_<service>_service()      # Stop service gracefully
health_<service>_service()    # Return health status
config_<service>_service()    # Manage configuration

# Event communication
unity_emit_event "EVENT_NAME" "source" "data"
unity_on_event "EVENT_NAME" handler_function
```

### Deployment Event Flow

A typical deployment follows this event sequence:
```
DEPLOYMENT_REQUESTED → PREFLIGHT_CHECKS_STARTED → RESOURCES_VALIDATED →
VPC_CREATION_STARTED → VPC_CREATED → EC2_LAUNCH_STARTED → EC2_LAUNCHED →
HEALTH_CHECK_STARTED → HEALTH_CHECK_PASSED → DEPLOYMENT_COMPLETED
```

### Configuration Hierarchy

Unity uses a unified configuration system (`config/unity.yml`) with priority ordering:
1. **Command-line arguments** (highest priority)
2. **Environment variables**
3. **Unity configuration file**
4. **AWS Parameter Store** (for secrets)
5. **Service defaults** (lowest priority)

## Development Patterns

### Creating a New Unity Service

1. **Copy the template**:
   ```bash
   cp lib/unity/templates/service-template.sh lib/unity/services/my-service.sh
   ```

2. **Implement required functions** with proper event emission:
   ```bash
   init_myservice_service() {
       unity_log "INFO" "Initializing my service..."
       unity_emit_event "SERVICE_INITIALIZING" "myservice" ""
       # initialization logic
       unity_emit_event "SERVICE_INITIALIZED" "myservice" ""
   }
   ```

3. **Register with dependencies**:
   ```bash
   unity_register_service "myservice" "$SCRIPT_DIR/my-service.sh" "standard" "config,aws"
   ```

### Event-Driven Development

**Emit events** for all significant actions:
```bash
unity_emit_event "RESOURCE_CREATED" "myservice" "resource_id:$id,type:vpc"
```

**React to events** from other services:
```bash
handle_vpc_created() {
    local event=$1 source=$2 data=$3
    # React to VPC creation
}
unity_on_event "VPC_CREATED" handle_vpc_created
```

### Testing Unity Components

**Unit tests** for service methods:
```bash
source lib/unity/services/my-service.sh
test_myservice_initialization() {
    init_myservice_service
    assert_equals "initialized" "$(get_service_status myservice)"
}
```

**Integration tests** for service interactions:
```bash
test_deployment_flow() {
    unity_emit_event "DEPLOYMENT_REQUESTED" "test" "spot:test-stack"
    wait_for_event "DEPLOYMENT_COMPLETED" 300  # 5 minute timeout
}
```

## Common Troubleshooting

### Unity-Specific Issues

| Issue | Solution |
|-------|----------|
| Service won't initialize | Check service dependencies in registration call |
| Events not being received | Verify handler registration with `unity_on_event()` |
| Deployment hangs | Check event flow in `.unity/events/` directory |
| Service health failing | Review health check implementation in service |
| Configuration not loading | Check priority order and file syntax |

### Debugging Techniques

1. **Enable debug logging**:
   ```bash
   UNITY_LOG_LEVEL=DEBUG ./unity deploy spot test-stack
   ```

2. **Monitor event flow**:
   ```bash
   tail -f .unity/events/event.log
   ```

3. **Check service status**:
   ```bash
   ./unity service status
   ```

## Performance Considerations

### Unity Optimizations

1. **Event Processing**: Asynchronous, non-blocking event handlers
2. **Service Caching**: AWS API responses cached for 1 hour
3. **Parallel Operations**: Services start concurrently when no dependencies exist
4. **Resource Pooling**: Reuse AWS clients and connections

### Performance Targets

- Unity initialization: < 500ms
- Service startup: < 2 seconds each
- Event latency: < 100ms average
- Full deployment: < 3 minutes

## Security Model

1. **Service Isolation**: Each service runs in separate process
2. **Event Validation**: All events validated before processing
3. **Secrets Management**: AWS Parameter Store integration
4. **Audit Logging**: Complete event trail in `.unity/events/`

## Implementation Status

### Completed Features ✅

**Phase 1 & 2**: Foundation and Service Enhancement (100% complete)
- Unity CLI with full deployment capabilities
- Complete AWS service (VPC, EC2, ALB, CloudFront, EFS)
- Docker service with AI stack support
- Monitoring service with CloudWatch integration
- Pre-flight validation system
- Migration tools for legacy code

**Phase 3**: Legacy Removal (Ready to execute)
- Deprecation script created (`./scripts/deprecate-legacy.sh`)
- Makefile compatibility wrapper (`./make`)
- All references updated to use Unity

### Current State

Unity is **production-ready** and serves as the sole deployment system. The legacy Makefile and modular scripts are archived but not removed. Run `./scripts/deprecate-legacy.sh` to complete the migration.

## Critical Implementation Details

### AWS Service Implementation

The enhanced AWS service (`lib/unity/services/unity-aws-service-complete.sh`) provides:
- **VPC Operations**: Single/multi-AZ with automatic CIDR allocation
- **EC2 Management**: Spot optimization with 70% cost savings
- **Load Balancing**: ALB with health checks and target groups
- **CDN**: CloudFront distribution with origin configuration
- **Cost Optimization**: Real-time tracking and recommendations

### Docker Service Implementation

The enhanced Docker service (`lib/unity/services/unity-docker-service-complete.sh`) provides:
- **Compose Generation**: Environment-specific configurations
- **AI Stack Support**: Ollama with GPU, n8n, Qdrant, PostgreSQL
- **Health Monitoring**: Container health checks with auto-recovery
- **Log Management**: Centralized logging with rotation

### Monitoring Service Implementation

The monitoring service (`lib/unity/services/unity-monitoring-complete.sh`) provides:
- **CloudWatch Integration**: Dashboards and custom metrics
- **Real-time Alerts**: Threshold-based alerting
- **Performance Metrics**: CPU, memory, disk, network tracking
- **Cost Monitoring**: Hourly cost tracking with alerts

## Claude Code Agents

Use specialized agents for complex Unity tasks:

### Unity Architecture Agents
- **unity-deployment-orchestrator**: Deployment flows and rollback strategies
- **unity-event-system-architect**: Event bus design and patterns
- **unity-service-architect**: Service implementation patterns
- **unity-test-framework-architect**: Testing infrastructure design

### AWS and Infrastructure Agents
- **aws-deployment-debugger**: Debug deployment failures
- **ec2-provisioning-specialist**: EC2 and spot instance issues
- **spot-instance-optimizer**: Cost optimization strategies
- **aws-cost-optimizer**: Cost analysis and savings

## Important Notes

1. **Unity is the ONLY deployment system** - All legacy scripts are deprecated
2. **Event-driven patterns are mandatory** - All operations must emit events
3. **Services must be isolated** - No direct service-to-service calls
4. **Configuration is centralized** - Use `config/unity.yml` as source of truth
5. **Legacy code is archived** in `archive/unity-cleanup-20250803_024204/`