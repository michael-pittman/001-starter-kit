# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**GeuseMaker** is an enterprise-ready AWS deployment system with AI infrastructure capabilities:
- **70% cost savings** via intelligent spot instance optimization
- **Multi-architecture support** (Intel x86_64 and ARM64 Graviton2)
- **AI Stack**: n8n workflows + Ollama (DeepSeek-R1:8B, Qwen2.5-VL:7B) + Qdrant + Crawl4AI
- **Enterprise features**: Multi-AZ, ALB, CloudFront CDN, EFS persistence, comprehensive monitoring
- **Unity Architecture**: Event-driven service architecture with plugin framework (ONLY deployment option)

## Essential Commands

### Unity Deployment Commands (Primary Interface)
```bash
# Unity CLI - All operations through single interface
./unity deploy spot dev-stack                  # Deploy spot instance (70% cost savings)
./unity deploy alb prod-stack                  # Deploy with Application Load Balancer
./unity deploy full prod-stack                 # Deploy complete stack (VPC+EC2+ALB+CDN)
./unity destroy dev-stack                      # Destroy all resources
./unity status dev-stack                       # Check deployment status
./unity monitor dev-stack                      # Real-time monitoring

# Direct deployment wrapper (alternative)
./deploy.sh spot dev-stack                     # Deploy spot instance
./deploy.sh alb prod-stack                     # Deploy with ALB
./deploy.sh full prod-stack                    # Deploy complete stack
./deploy.sh destroy dev-stack                  # Destroy resources
```

### Unity Development Commands
```bash
# Service management
./unity service list                           # List all Unity services
./unity service status aws                     # Check AWS service status
./unity service restart docker                 # Restart Docker service

# Configuration management
./unity config show                            # Display current configuration
./unity config set deployment.region us-west-2 # Update configuration
./unity config validate                        # Validate configuration

# Plugin management
./unity plugin list                            # List available plugins
./unity plugin enable cost-analyzer            # Enable a plugin
./unity plugin configure spot-optimizer        # Configure plugin settings
```

### Testing Commands
```bash
# Unity-specific tests
./tests/test-unity-performance.sh              # Unity performance benchmarks
./tests/test-unity-events-enhanced.sh          # Unity event system tests
./tests/unity/integration/test-unity-service-integration.sh  # Service integration
./tests/unity/unit/test-unity-aws-service.sh   # AWS service unit tests

# Comprehensive testing
./tests/unity/test-unity-complete-system.sh    # Full system validation
```

## High-Level Architecture

### Unity System Architecture

GeuseMaker uses the Unity event-driven service architecture as its sole deployment system. All operations are orchestrated through Unity services that communicate via events.

**Key Architectural Principles**:
- **Event-Driven**: All operations trigger and respond to events
- **Service Isolation**: Each component is a registered Unity service
- **Plugin Extensibility**: Custom functionality through Unity plugins
- **Reactive Patterns**: Asynchronous, non-blocking operations
- **Single Source of Truth**: Unity configuration drives all behavior

### Unity Architecture Components

```
lib/unity/
├── core/
│   ├── unity-core.sh         # Service registry, lifecycle management
│   ├── unity-events.sh       # Event bus implementation
│   ├── unity-plugins.sh      # Plugin framework
│   ├── service-dependency-resolver.sh  # Dependency resolution
│   └── service-recovery.sh   # Service recovery mechanisms
├── services/
│   ├── aws-service.sh        # AWS operations (EC2, VPC, ALB, etc.)
│   ├── docker-service.sh     # Container management
│   ├── config-service.sh     # Configuration management
│   ├── monitor-service.sh    # Monitoring and alerting
│   └── unity-deployment-service.sh  # Deployment orchestration
├── events/
│   ├── event-bus.sh          # Event dispatching
│   ├── event-persistence.sh  # Event storage
│   ├── reactive-patterns.sh  # Reactive programming patterns
│   └── rollback-manager.sh   # Rollback on failure
├── plugins/
│   ├── spot-optimizer/       # Spot instance optimization
│   ├── cost-analyzer/        # Cost analysis and reporting
│   ├── security-validator/   # Security compliance checks
│   └── performance-tuner/    # Performance optimization
└── templates/
    └── service-template.sh   # Template for new services
```

### Service Communication Pattern

All Unity services follow a standard interface and communicate via events:

```bash
# Service Interface Contract
init_<service>_service()      # Initialize service
start_<service>_service()     # Start service
stop_<service>_service()      # Stop service
health_<service>_service()    # Health check
config_<service>_service()    # Configuration management

# Event Communication
unity_emit_event "EVENT_NAME" "source" "data"
unity_on_event "EVENT_NAME" handler_function
```

### Configuration Management

Unity uses a unified configuration system with a single source of truth:

**Primary Configuration** (`config/unity.yml`):
```yaml
unity:
  deployment:
    types: [spot, alb, cdn, full]
    environments: [dev, staging, prod]
    defaults:
      instance_type: g4dn.xlarge
      region: us-east-1
  services:
    # Service-specific configurations
  plugins:
    # Plugin configurations
```

**Configuration Sources** (in priority order):
1. Command-line arguments (highest)
2. Environment variables
3. Unity configuration file
4. AWS Parameter Store (for secrets)
5. Service defaults (lowest)

## Development Patterns

### Creating a New Unity Service

1. Use the service template:
```bash
cp lib/unity/templates/service-template.sh lib/unity/services/my-service.sh
```

2. Implement the standard interface:
```bash
init_myservice_service() {
    # Initialize service
    unity_log "INFO" "Initializing my service..."
    # ... initialization logic
}

start_myservice_service() {
    # Start service operations
}

# ... implement all interface methods
```

3. Register the service:
```bash
unity_register_service "myservice" "$SCRIPT_DIR/my-service.sh" "standard" "config,aws"
```

### Event-Driven Development

1. Emit events for significant actions:
```bash
unity_emit_event "DEPLOYMENT_STARTED" "myservice" "$deployment_id"
```

2. React to events from other services:
```bash
handle_deployment_complete() {
    local event=$1
    local source=$2
    local data=$3
    # React to deployment completion
}
unity_on_event "DEPLOYMENT_COMPLETED" handle_deployment_complete
```

### Testing Unity Components

1. Unit test individual services:
```bash
./tests/unity/unit/test-unity-myservice.sh
```

2. Integration test service interactions:
```bash
./tests/unity/integration/test-unity-service-integration.sh
```

3. Performance benchmarks:
```bash
./tests/unity/performance/test-unity-performance-benchmarks.sh
```

## Deployment Workflows

### Standard Deployment Flow

1. **Pre-flight Checks**:
   ```bash
   ./unity deploy spot my-stack --preflight-only
   # Validates: AWS credentials, quotas, permissions, resources
   ```

2. **Deployment Execution**:
   ```bash
   ./unity deploy spot my-stack
   # Triggers: DEPLOYMENT_REQUESTED → SERVICE_INITIALIZED → RESOURCES_CREATED → DEPLOYMENT_COMPLETED
   ```

3. **Monitoring**:
   ```bash
   ./unity monitor my-stack
   # Real-time: Service health, metrics, logs, events
   ```

### Event Flow Example

```
User: ./unity deploy spot my-stack
  ↓
CLI → DEPLOYMENT_REQUESTED → Deployment Service
  ↓
Deployment Service → VALIDATE_RESOURCES → AWS Service
  ↓
AWS Service → VPC_CREATED, EC2_LAUNCHED → Monitor Service
  ↓
Monitor Service → HEALTH_CHECK_PASSED → Deployment Service
  ↓
Deployment Service → DEPLOYMENT_COMPLETED → User notification
```

## Common Troubleshooting

### Unity-Specific Issues

| Issue | Solution |
|-------|----------|
| Service not initializing | Check dependencies in unity_register_service() call |
| Events not firing | Verify event handler registration with unity_on_event() |
| Service discovery fails | Ensure service is registered before initialization |
| Dependency cycle | Review service dependencies in config/unity.yml |
| Performance degradation | Check event handler efficiency, avoid blocking operations |

### Development Tips

1. **Service Isolation**: Each service should be independently testable
2. **Event Documentation**: Document all events a service emits/consumes
3. **Error Recovery**: Implement proper error handling in event handlers
4. **Async Operations**: Use background processes for long-running tasks
5. **State Management**: Use Unity's state directory (.unity/state/)

## Testing Strategy

### Unity Testing Hierarchy

1. **Unit Tests** (`tests/unity/unit/`):
   - Test individual service methods
   - Mock dependencies and events
   - Fast, isolated execution

2. **Integration Tests** (`tests/unity/integration/`):
   - Test service interactions
   - Verify event flow
   - Real service dependencies

3. **System Tests** (`tests/unity/`):
   - End-to-end scenarios
   - Full Unity system validation
   - Performance benchmarks

### Test Execution Patterns

```bash
# Run specific test categories
./tests/unity/test-unity-basic.sh              # Basic functionality
./tests/unity/test-unity-critical-fixes.sh     # Critical bug fixes
./tests/unity/test-unity-system-validation.sh  # Full validation

# Run with debugging
UNITY_LOG_LEVEL=DEBUG ./tests/unity/test-unity-basic.sh
```

## Performance Considerations

### Unity Optimization

1. **Event Bus Performance**:
   - Events are processed asynchronously
   - Handlers execute in subshells to prevent blocking
   - Event persistence can be disabled for performance

2. **Service Caching**:
   - AWS API responses cached in .unity/cache/
   - Configuration cached per session
   - Service status cached to reduce lookups

3. **Parallel Operations**:
   - Services can start in parallel if no dependencies
   - Event handlers execute concurrently
   - Background monitoring processes

## Security Considerations

### Unity Security Model

1. **Service Isolation**: Services run in separate processes
2. **Event Validation**: Events are validated before processing
3. **Configuration Security**: Sensitive data in AWS Parameter Store
4. **Audit Trail**: All events logged to .unity/events/

## Implementation Priority

### Immediate Actions (Active Development)

1. **Unity CLI Implementation** (`./unity`):
   - Primary interface for all operations
   - Replaces legacy Makefile targets
   - Event-driven command execution

2. **Deployment Wrapper** (`./deploy.sh`):
   - Unity-based deployment orchestration
   - Backward-compatible command structure
   - Pre-flight validation

3. **Service Enhancements**:
   - AWS Service: Full VPC, EC2, ALB, CloudFront support
   - Docker Service: Complete container lifecycle
   - Config Service: Unified configuration management
   - Monitor Service: Real-time metrics and alerting

### Migration Timeline

**Week 1-2**: Foundation
- Unity CLI implementation
- Deployment wrapper creation
- Pre-flight checks
- Migration tools

**Week 3-8**: Service Migration
- Port all AWS operations to Unity
- Enhance service capabilities
- Remove legacy dependencies
- Comprehensive testing

**Week 9-12**: Advanced Features
- Unity UI dashboard
- Performance optimization
- Production validation
- Documentation completion

## Unity Plugin Development

### Creating Custom Plugins

1. **Plugin Structure**:
   ```bash
   lib/unity/plugins/my-plugin/
   ├── plugin.sh           # Main plugin file
   ├── config.yml          # Plugin configuration
   └── README.md          # Plugin documentation
   ```

2. **Plugin Interface**:
   ```bash
   # Required functions
   init_plugin()           # Initialize plugin
   handle_event()          # Process events
   get_config()           # Return configuration
   cleanup()              # Cleanup resources
   ```

3. **Registration**:
   ```yaml
   # In config/unity.yml
   plugins:
     my-plugin:
       enabled: true
       priority: 100
       settings:
         # Plugin-specific settings
   ```

## Claude Code Agents

Use specialized agents for complex tasks related to Unity and deployment:

### Unity-Specific Agents
- **unity-deployment-architect**: Design and implement unified deployment systems, consolidate fragmented functionality, architect plugin-based frameworks
- **unity-test-framework-architect**: Create comprehensive testing infrastructure including unit tests, integration tests, and performance benchmarks

### AWS and Infrastructure Agents
- **ec2-provisioning-specialist**: Handle EC2 operations, spot instance optimization, and capacity issues
- **aws-deployment-debugger**: Debug deployment failures and AWS-specific issues
- **spot-instance-optimizer**: Optimize spot instance selection and cost savings
- **aws-cost-optimizer**: Analyze and optimize AWS costs

### Service Architecture Agents
- **config-unification-specialist**: Consolidate and unify configuration systems
- **docker-service-consolidator**: Unify Docker operations and container management
- **event-system-architect**: Design event-driven architectures and reactive patterns
- **monitoring-integration-specialist**: Unify monitoring and observability systems
- **deployment-orchestration-specialist**: Design event-driven deployment orchestration

### Quality and Performance Agents
- **security-validator**: Perform pre-production security validation
- **test-runner-specialist**: Orchestrate comprehensive test suites
- **bash-script-validator**: Validate bash scripts for compatibility and best practices
- **performance-optimization-specialist**: Tune system performance and optimize operations
- **plugin-framework-architect**: Design extensible plugin systems

### Usage Example
When facing complex architectural decisions or implementation challenges:
```
"I need to design a comprehensive test framework for the Unity system"
→ Use unity-test-framework-architect agent

"Help me optimize our spot instance costs"
→ Use spot-instance-optimizer agent

"Design the event flow for deployment orchestration"
→ Use deployment-orchestration-specialist agent
```