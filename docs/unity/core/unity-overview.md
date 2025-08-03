# Unity System Overview

## Introduction

Unity is a comprehensive service management framework for GeuseMaker that transforms fragmented deployment scripts into a cohesive, event-driven architecture. It provides a unified interface for AWS services, configuration management, monitoring, and deployment orchestration.

## Architecture Overview

Unity follows a modular, event-driven architecture with these core components:

```
┌─────────────────────────────────────────────────────────────┐
│                      Unity CLI Interface                      │
├─────────────────────────────────────────────────────────────┤
│                        Service Registry                       │
├──────────────┬──────────────┬──────────────┬───────────────┤
│  AWS Service │ Config Service│Docker Service│Monitor Service│
├──────────────┴──────────────┴──────────────┴───────────────┤
│                         Event Bus                            │
├─────────────────────────────────────────────────────────────┤
│                     Plugin Framework                         │
├─────────────────────────────────────────────────────────────┤
│              Core Libraries & Utilities                      │
└─────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. Service Registry
The heart of Unity - manages service registration, discovery, and lifecycle:
- **Location**: `lib/unity/services/registry.sh`
- **Purpose**: Central registration point for all Unity services
- **Key Features**:
  - Service registration and discovery
  - Health monitoring
  - Dependency management
  - Service lifecycle control

### 2. Event Bus
Enables loose coupling between components through event-driven communication:
- **Location**: `lib/unity/events/event-bus.sh`
- **Purpose**: Asynchronous communication between services
- **Key Features**:
  - Event publishing and subscription
  - Event persistence and replay
  - Pattern-based routing
  - Error handling and retries

### 3. Unified Services

#### AWS Service (`lib/unity/services/aws.sh`)
Consolidates all AWS operations:
- EC2 instance management
- VPC and networking
- ALB and CloudFront configuration
- EFS storage management
- Cost optimization
- Quota checking

#### Config Service (`lib/unity/services/config.sh`)
Centralized configuration management:
- YAML-based configuration
- Environment-specific overrides
- Dynamic reloading
- Validation and type safety
- Parameter Store integration

#### Docker Service (`lib/unity/services/docker.sh`)
Container lifecycle management:
- Docker Compose orchestration
- Health monitoring
- Log aggregation
- Resource management
- Service discovery

#### Monitor Service (`lib/unity/services/monitor.sh`)
Comprehensive monitoring and alerting:
- Health checks
- Metrics collection
- Alert management
- Performance analytics
- Dashboard integration

### 4. Plugin Framework
Extensible architecture for custom functionality:
- **Location**: `lib/unity/plugins/`
- **Purpose**: Add custom features without modifying core
- **Standard Plugins**:
  - Spot Optimizer
  - Cost Analyzer
  - Security Validator
  - Performance Tuner

## System Requirements

### Supported Platforms
- **Operating Systems**: Linux, macOS
- **Bash Version**: 3.x+ (macOS compatible)
- **AWS CLI**: v2 recommended, v1 supported
- **Docker**: 20.10+ with Compose v2

### AWS Requirements
- Valid AWS credentials configured
- Appropriate IAM permissions
- Supported regions: All standard AWS regions

### Hardware Requirements
- **Minimum**: 2 CPU cores, 4GB RAM
- **Recommended**: 4 CPU cores, 8GB RAM
- **Storage**: 20GB free space for logs and cache

## Quick Start Guide

### 1. Installation

```bash
# Clone the repository
git clone https://github.com/your-org/geusemaker.git
cd geusemaker

# Initialize Unity system
./scripts/unity-cli.sh init

# Verify installation
./scripts/unity-cli.sh status
```

### 2. Configuration

```bash
# Interactive configuration setup
./scripts/setup-configuration.sh

# Or copy and edit configuration
cp config/unity.yml.example config/unity.yml
vi config/unity.yml
```

### 3. First Deployment

```bash
# Deploy with Unity
./scripts/unity-cli.sh deploy my-stack --spot --multi-az

# Monitor deployment
./scripts/unity-cli.sh monitor my-stack

# Check status
./scripts/unity-cli.sh status my-stack
```

## Key Benefits

### 1. Unified Interface
- Single CLI for all operations
- Consistent command structure
- Integrated help system
- Tab completion support

### 2. Event-Driven Architecture
- Loose coupling between components
- Reactive deployment patterns
- Automatic error recovery
- Real-time status updates

### 3. Extensibility
- Plugin-based architecture
- Custom event handlers
- Service integration points
- Configuration hooks

### 4. Cost Optimization
- Intelligent spot instance selection
- Resource lifecycle management
- Cost tracking and reporting
- Automatic cleanup

### 5. Enterprise Features
- Multi-environment support
- Role-based access control
- Audit logging
- Compliance reporting

## Integration Points

### Legacy Compatibility
Unity maintains full compatibility with existing GeuseMaker scripts:
- `deploy.sh` wrapper for backward compatibility
- Module-by-module migration support
- Gradual adoption path

### CI/CD Integration
- GitHub Actions workflows
- Jenkins pipeline support
- GitLab CI integration
- Custom webhook support

### Monitoring Integration
- CloudWatch metrics
- Prometheus export
- Grafana dashboards
- Custom alerting

## Best Practices

### 1. Service Design
- Keep services focused and single-purpose
- Use events for inter-service communication
- Implement proper error handling
- Add comprehensive logging

### 2. Configuration Management
- Use environment-specific configs
- Store secrets in Parameter Store
- Version control configurations
- Document all settings

### 3. Event Handling
- Use specific event patterns
- Implement idempotent handlers
- Add retry logic for critical events
- Monitor event processing

### 4. Plugin Development
- Follow the plugin template
- Add comprehensive tests
- Document all interfaces
- Version plugins properly

## Troubleshooting

### Common Issues

1. **Service Registration Failures**
   ```bash
   # Check registry status
   ./scripts/unity-cli.sh registry status
   
   # Re-register service
   ./scripts/unity-cli.sh registry register <service>
   ```

2. **Event Processing Issues**
   ```bash
   # Check event bus
   ./scripts/unity-cli.sh events status
   
   # View event log
   ./scripts/unity-cli.sh events log --tail 100
   ```

3. **Configuration Problems**
   ```bash
   # Validate configuration
   ./scripts/unity-cli.sh config validate
   
   # Show effective configuration
   ./scripts/unity-cli.sh config show --resolved
   ```

### Debug Mode

Enable debug mode for detailed logging:
```bash
export UNITY_DEBUG=true
export UNITY_LOG_LEVEL=debug
./scripts/unity-cli.sh deploy my-stack
```

## Next Steps

1. **Developer Guide**: Deep dive into Unity development
2. **Migration Guide**: Migrate existing deployments to Unity
3. **API Reference**: Complete API documentation
4. **Tutorials**: Hands-on examples and exercises

## Support

- **Documentation**: `/docs/unity/`
- **Issues**: GitHub Issues
- **Community**: Slack channel #unity-support
- **Email**: unity-support@geusemaker.com