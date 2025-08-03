# Unity Configuration Reference

## Table of Contents

1. [Configuration Overview](#configuration-overview)
2. [Configuration Files](#configuration-files)
3. [Core Configuration](#core-configuration)
4. [Service Configuration](#service-configuration)
5. [Plugin Configuration](#plugin-configuration)
6. [Environment-Specific Settings](#environment-specific-settings)
7. [Security Configuration](#security-configuration)
8. [Advanced Configuration](#advanced-configuration)
9. [Configuration Best Practices](#configuration-best-practices)

## Configuration Overview

Unity uses a hierarchical configuration system with multiple sources:

1. **Default Configuration** (`config/defaults.yml`)
2. **Unity Configuration** (`config/unity.yml`)
3. **Environment Overrides** (`config/environments/*.yml`)
4. **Runtime Overrides** (command-line arguments)
5. **AWS Parameter Store** (optional)

### Configuration Priority

Higher priority overrides lower priority:

```
Command Line Arguments (Highest)
         ↓
Environment Variables
         ↓
.env.local / .env.<environment>
         ↓
AWS Parameter Store
         ↓
Environment-specific YAML
         ↓
config/unity.yml
         ↓
config/defaults.yml (Lowest)
```

## Configuration Files

### Main Configuration File

**Location**: `config/unity.yml`

```yaml
# Unity System Configuration
version: 1.0.0

# System-wide settings
system:
  name: unity
  environment: ${ENVIRONMENT:-development}
  debug: ${UNITY_DEBUG:-false}
  log_level: ${UNITY_LOG_LEVEL:-info}
  
# Service registry configuration
registry:
  enabled: true
  health_check_interval: 30
  startup_timeout: 300
  shutdown_grace_period: 30
  
# Event bus configuration
events:
  enabled: true
  persistent: true
  store_path: /var/lib/unity/events
  retention_days: 30
  max_queue_size: 10000
  worker_threads: 4
  
# Core services configuration
services:
  aws:
    enabled: true
    region: ${AWS_REGION:-us-east-1}
    profile: ${AWS_PROFILE:-default}
    
  config:
    enabled: true
    auto_reload: true
    validation: strict
    
  docker:
    enabled: true
    compose_file: docker-compose.yml
    health_check: true
    
  monitor:
    enabled: true
    providers:
      - cloudwatch
      - internal
```

### Environment Configuration

**Location**: `config/environments/production.yml`

```yaml
# Production environment overrides
system:
  environment: production
  debug: false
  log_level: warn
  
# Production AWS settings
services:
  aws:
    region: us-east-1
    multi_az: true
    backup_enabled: true
    spot_enabled: true
    spot_percentage: 70
    
# Production monitoring
services:
  monitor:
    alert_email: ops@company.com
    alert_severity: critical
    metrics_retention: 90
    
# Production security
security:
  ssl_required: true
  encryption_at_rest: true
  audit_logging: true
```

## Core Configuration

### System Configuration

```yaml
system:
  # Basic settings
  name: string                    # System identifier
  environment: string             # Environment name
  region: string                  # Primary AWS region
  
  # Logging
  log_level: enum                 # trace|debug|info|warn|error|fatal
  log_format: enum                # json|text
  log_file: path                  # Log file location
  log_rotation: boolean           # Enable log rotation
  log_max_size: string            # Max log file size (e.g., "100M")
  log_max_age: integer            # Max log age in days
  
  # Performance
  worker_threads: integer         # Number of worker threads
  max_memory: string              # Memory limit (e.g., "2G")
  cache_enabled: boolean          # Enable caching
  cache_ttl: integer              # Cache TTL in seconds
  
  # Debugging
  debug: boolean                  # Enable debug mode
  trace: boolean                  # Enable trace logging
  profile: boolean                # Enable profiling
```

### Registry Configuration

```yaml
registry:
  # Basic settings
  enabled: boolean                # Enable service registry
  storage: enum                   # memory|file|redis
  storage_path: path              # Path for file storage
  
  # Health monitoring
  health_check_interval: integer  # Seconds between health checks
  health_check_timeout: integer   # Health check timeout
  health_check_retries: integer   # Number of retries
  unhealthy_threshold: integer    # Failures before marking unhealthy
  
  # Service lifecycle
  startup_timeout: integer        # Service startup timeout
  shutdown_grace_period: integer  # Graceful shutdown period
  restart_policy: enum            # always|on-failure|never
  restart_delay: integer          # Delay between restarts
  max_restart_attempts: integer   # Maximum restart attempts
```

### Event Bus Configuration

```yaml
events:
  # Basic settings
  enabled: boolean                # Enable event bus
  transport: enum                 # memory|redis|kafka|sqs
  
  # Persistence
  persistent: boolean             # Enable event persistence
  store_type: enum                # file|database|s3
  store_path: path                # Storage location
  retention_days: integer         # Event retention period
  
  # Performance
  max_queue_size: integer         # Maximum queue size
  worker_threads: integer         # Event worker threads
  batch_size: integer             # Event batch size
  flush_interval: integer         # Batch flush interval
  
  # Reliability
  retry_enabled: boolean          # Enable event retry
  retry_attempts: integer         # Maximum retry attempts
  retry_delay: integer            # Initial retry delay
  retry_backoff: float            # Backoff multiplier
  dead_letter_queue: boolean      # Enable DLQ
```

## Service Configuration

### AWS Service Configuration

```yaml
services:
  aws:
    # Authentication
    region: string                # AWS region
    profile: string               # AWS profile
    role_arn: string              # IAM role to assume
    mfa_serial: string            # MFA device serial
    
    # EC2 settings
    ec2:
      instance_type: string       # Default instance type
      key_name: string            # SSH key pair name
      security_groups: list       # Security group IDs
      subnet_ids: list            # Subnet IDs
      
    # Spot instances
    spot:
      enabled: boolean            # Enable spot instances
      percentage: integer         # Spot instance percentage
      price_threshold: float      # Maximum spot price
      interruption_behavior: enum # terminate|stop|hibernate
      
    # Auto-scaling
    auto_scaling:
      enabled: boolean            # Enable auto-scaling
      min_size: integer           # Minimum instances
      max_size: integer           # Maximum instances
      target_cpu: integer         # Target CPU percentage
      
    # Backup settings
    backup:
      enabled: boolean            # Enable backups
      retention_days: integer     # Backup retention
      schedule: string            # Cron schedule
      
    # Cost optimization
    cost:
      budget_alert: float         # Budget alert threshold
      reserved_instances: boolean # Use reserved instances
      savings_plan: boolean       # Use savings plan
```

### Docker Service Configuration

```yaml
services:
  docker:
    # Basic settings
    enabled: boolean              # Enable Docker service
    socket: path                  # Docker socket path
    api_version: string           # Docker API version
    
    # Compose settings
    compose:
      file: path                  # Compose file path
      project_name: string        # Project name
      profiles: list              # Active profiles
      env_file: path              # Environment file
      
    # Container settings
    containers:
      restart_policy: enum        # always|unless-stopped|on-failure
      memory_limit: string        # Memory limit (e.g., "2g")
      cpu_limit: float            # CPU limit (e.g., 1.5)
      shm_size: string            # Shared memory size
      
    # Health monitoring
    health:
      enabled: boolean            # Enable health checks
      interval: integer           # Check interval
      timeout: integer            # Check timeout
      retries: integer            # Check retries
      
    # Logging
    logging:
      driver: enum                # json-file|syslog|journald
      max_size: string            # Max log size
      max_files: integer          # Max log files
```

### Monitor Service Configuration

```yaml
services:
  monitor:
    # Basic settings
    enabled: boolean              # Enable monitoring
    interval: integer             # Collection interval
    
    # Providers
    providers:
      - cloudwatch                # AWS CloudWatch
      - prometheus                # Prometheus
      - internal                  # Internal metrics
      
    # CloudWatch settings
    cloudwatch:
      namespace: string           # Custom namespace
      detailed_monitoring: boolean # Detailed monitoring
      custom_metrics: boolean     # Custom metrics
      
    # Alerting
    alerts:
      enabled: boolean            # Enable alerting
      channels:                   # Alert channels
        email:
          enabled: boolean
          recipients: list
        slack:
          enabled: boolean
          webhook_url: string
        pagerduty:
          enabled: boolean
          service_key: string
          
    # Thresholds
    thresholds:
      cpu_critical: integer       # CPU critical threshold
      memory_critical: integer    # Memory critical threshold
      disk_critical: integer      # Disk critical threshold
      
    # Dashboards
    dashboards:
      enabled: boolean            # Enable dashboards
      auto_create: boolean        # Auto-create dashboards
      refresh_interval: integer   # Refresh interval
```

## Plugin Configuration

### Plugin System Configuration

```yaml
plugins:
  # System settings
  enabled: boolean                # Enable plugin system
  directory: path                 # Plugin directory
  auto_load: boolean              # Auto-load plugins
  
  # Security
  sandbox: boolean                # Enable sandboxing
  allowed_commands: list          # Allowed commands
  resource_limits:
    memory: string                # Memory limit
    cpu: float                    # CPU limit
    timeout: integer              # Execution timeout
    
  # Plugin settings
  spot_optimizer:
    enabled: boolean
    check_interval: 300
    regions: list
    instance_types: list
    
  cost_analyzer:
    enabled: boolean
    report_interval: daily
    cost_threshold: 1000
    
  security_validator:
    enabled: boolean
    scan_on_deploy: true
    compliance: [pci, hipaa]
```

## Environment-Specific Settings

### Development Environment

```yaml
# config/environments/development.yml
system:
  environment: development
  debug: true
  log_level: debug
  
services:
  aws:
    spot:
      enabled: false              # Disable spot in dev
    backup:
      enabled: false              # Disable backups in dev
      
  monitor:
    alerts:
      enabled: false              # Disable alerts in dev
```

### Staging Environment

```yaml
# config/environments/staging.yml
system:
  environment: staging
  debug: false
  log_level: info
  
services:
  aws:
    spot:
      enabled: true
      percentage: 50              # 50% spot in staging
      
  monitor:
    alerts:
      channels:
        email:
          recipients: [staging@company.com]
```

### Production Environment

```yaml
# config/environments/production.yml
system:
  environment: production
  debug: false
  log_level: warn
  
services:
  aws:
    multi_az: true
    spot:
      enabled: true
      percentage: 70              # 70% spot in production
    backup:
      enabled: true
      retention_days: 30
      
  monitor:
    alerts:
      channels:
        email:
          recipients: [ops@company.com]
        pagerduty:
          enabled: true
```

## Security Configuration

### Authentication & Authorization

```yaml
security:
  # Authentication
  auth:
    enabled: boolean              # Enable authentication
    provider: enum                # local|ldap|oauth|saml
    mfa_required: boolean         # Require MFA
    session_timeout: integer      # Session timeout
    
  # Authorization
  rbac:
    enabled: boolean              # Enable RBAC
    default_role: string          # Default role
    roles:
      admin:
        permissions: ["*"]
      operator:
        permissions: ["deploy", "monitor"]
      viewer:
        permissions: ["read"]
        
  # API security
  api:
    enabled: boolean              # Enable API security
    rate_limit: integer           # Requests per minute
    api_keys_required: boolean    # Require API keys
    
  # Encryption
  encryption:
    at_rest: boolean              # Encrypt at rest
    in_transit: boolean           # Encrypt in transit
    key_rotation: boolean         # Enable key rotation
    kms_key_id: string            # KMS key ID
```

### Compliance Configuration

```yaml
compliance:
  # Standards
  standards:
    - pci_dss
    - hipaa
    - soc2
    
  # Audit logging
  audit:
    enabled: boolean              # Enable audit logging
    retention_days: integer       # Audit log retention
    destinations:
      - s3://audit-bucket/
      - cloudwatch_logs
      
  # Data governance
  data:
    classification: boolean       # Enable classification
    retention_policy: boolean     # Enable retention
    gdpr_compliance: boolean      # GDPR compliance
```

## Advanced Configuration

### Performance Tuning

```yaml
performance:
  # Caching
  cache:
    provider: enum                # memory|redis|memcached
    ttl: integer                  # Default TTL
    max_size: string              # Max cache size
    eviction_policy: enum         # lru|lfu|fifo
    
  # Connection pooling
  connections:
    pool_size: integer            # Connection pool size
    max_idle: integer             # Max idle connections
    timeout: integer              # Connection timeout
    
  # Resource limits
  limits:
    max_concurrent_operations: integer
    rate_limit_per_second: integer
    queue_size: integer
```

### Integration Configuration

```yaml
integrations:
  # CI/CD
  cicd:
    github_actions:
      enabled: boolean
      webhook_secret: string
    jenkins:
      enabled: boolean
      url: string
      
  # Monitoring
  external_monitoring:
    datadog:
      enabled: boolean
      api_key: string
    new_relic:
      enabled: boolean
      license_key: string
      
  # Notifications
  notifications:
    webhook:
      enabled: boolean
      url: string
      headers: map
```

## Configuration Best Practices

### 1. Use Environment Variables

```yaml
# Good: Use environment variables for sensitive data
database:
  password: ${DB_PASSWORD}
  
# Bad: Hardcoded credentials
database:
  password: "hardcoded123"
```

### 2. Separate Environments

```yaml
# Use separate files for each environment
config/
  ├── unity.yml              # Base configuration
  ├── environments/
  │   ├── development.yml
  │   ├── staging.yml
  │   └── production.yml
```

### 3. Validate Configuration

```bash
# Always validate before deploying
./scripts/unity-cli.sh config validate

# Test configuration loading
./scripts/unity-cli.sh config test
```

### 4. Document Custom Settings

```yaml
# Document custom configuration
custom:
  # This setting controls the widget refresh rate
  # Valid values: 1-60 (seconds)
  # Default: 10
  widget_refresh: 10
```

### 5. Use Sensible Defaults

```yaml
# Provide sensible defaults
timeout: ${TIMEOUT:-30}
retries: ${RETRIES:-3}
```

### 6. Version Configuration

```yaml
# Include version for compatibility
version: 1.0.0
min_unity_version: 1.0.0
```

## Configuration Tools

### Configuration Management CLI

```bash
# Show current configuration
./scripts/unity-cli.sh config show

# Show resolved configuration (with overrides)
./scripts/unity-cli.sh config show --resolved

# Validate configuration
./scripts/unity-cli.sh config validate

# Test configuration
./scripts/unity-cli.sh config test

# Generate configuration
./scripts/unity-cli.sh config generate

# Diff configurations
./scripts/unity-cli.sh config diff \
    --from config/unity.yml \
    --to config/environments/production.yml
```

### Configuration Migration

```bash
# Migrate from .env files
./scripts/unity-cli.sh config migrate \
    --from .env.production \
    --to config/environments/production.yml

# Convert between formats
./scripts/unity-cli.sh config convert \
    --from json \
    --to yaml
```

## Troubleshooting Configuration

### Common Issues

1. **Configuration not loading**
   ```bash
   # Check configuration path
   echo $UNITY_CONFIG_PATH
   
   # Validate syntax
   ./scripts/unity-cli.sh config validate
   ```

2. **Environment variables not resolving**
   ```bash
   # Check environment
   env | grep UNITY
   
   # Test resolution
   ./scripts/unity-cli.sh config show --resolved
   ```

3. **Permission issues**
   ```bash
   # Check file permissions
   ls -la config/
   
   # Fix permissions
   chmod 644 config/*.yml
   ```

### Debug Configuration Loading

```bash
# Enable configuration debug
export UNITY_CONFIG_DEBUG=true

# Trace configuration loading
./scripts/unity-cli.sh --trace config load
```