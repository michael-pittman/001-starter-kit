# Architecture Overview

> GeuseMaker's Unity-based event-driven architecture for AWS infrastructure deployment

## System Architecture

GeuseMaker uses the Unity event-driven service architecture as its sole deployment system. All operations are orchestrated through Unity services that communicate via events.

### Key Architectural Principles

- **Event-Driven**: All operations trigger and respond to events
- **Service Isolation**: Each component is a registered Unity service  
- **Plugin Extensibility**: Custom functionality through Unity plugins
- **Reactive Patterns**: Asynchronous, non-blocking operations
- **Single Source of Truth**: Unity configuration drives all behavior

## Unity Architecture Components

```
lib/unity/
├── core/                          # Core Unity system
│   ├── unity-core.sh             # Service registry, lifecycle management
│   ├── unity-events.sh           # Event bus implementation
│   ├── unity-plugins.sh          # Plugin framework
│   ├── service-dependency-resolver.sh  # Dependency resolution
│   └── service-recovery.sh       # Service recovery mechanisms
├── services/                      # Unity services
│   ├── aws-service.sh            # AWS operations (EC2, VPC, ALB, etc.)
│   ├── docker-service.sh         # Container management
│   ├── config-service.sh         # Configuration management
│   ├── monitor-service.sh        # Monitoring and alerting
│   └── unity-deployment-service.sh  # Deployment orchestration
├── events/                        # Event system
│   ├── event-bus.sh              # Event dispatching
│   ├── event-persistence.sh      # Event storage
│   ├── reactive-patterns.sh      # Reactive programming patterns
│   └── rollback-manager.sh       # Rollback on failure
├── plugins/                       # Plugin system
│   ├── spot-optimizer/           # Spot instance optimization
│   ├── cost-analyzer/            # Cost analysis and reporting
│   ├── security-validator/       # Security compliance checks
│   └── performance-tuner/        # Performance optimization
└── templates/
    └── service-template.sh       # Template for new services
```

## Service Communication Pattern

All Unity services follow a standard interface:

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

## Deployment Flow Architecture

### Event-Driven Deployment Sequence

```
User Command → Unity CLI
    ↓
CLI emits → DEPLOYMENT_REQUESTED
    ↓
Deployment Service → VALIDATE_RESOURCES
    ↓
AWS Service → VPC_CREATED, EC2_LAUNCHED
    ↓
Monitor Service → HEALTH_CHECK_PASSED
    ↓
Deployment Service → DEPLOYMENT_COMPLETED
    ↓
User Notification
```

### Service Dependencies

```yaml
aws-service:
  depends_on: [config-service]
  provides: [vpc, ec2, alb, cloudfront]

docker-service:
  depends_on: [aws-service]
  provides: [containers, ai-stack]

monitor-service:
  depends_on: [aws-service, docker-service]
  provides: [health-checks, metrics]

deployment-service:
  depends_on: [aws-service, docker-service, monitor-service]
  provides: [orchestration, rollback]
```

## AWS Infrastructure Architecture

### Network Architecture

```
VPC (10.0.0.0/16)
├── Public Subnets (Multi-AZ)
│   ├── 10.0.1.0/24 (us-east-1a)
│   ├── 10.0.2.0/24 (us-east-1b)
│   └── 10.0.3.0/24 (us-east-1c)
├── Private Subnets (Multi-AZ)
│   ├── 10.0.11.0/24 (us-east-1a)
│   ├── 10.0.12.0/24 (us-east-1b)
│   └── 10.0.13.0/24 (us-east-1c)
├── Internet Gateway
├── NAT Gateways (Multi-AZ)
└── Route Tables
```

### Security Architecture

```
Security Groups:
├── ALB Security Group
│   ├── Inbound: HTTP (80), HTTPS (443)
│   └── Outbound: All traffic
├── EC2 Security Group
│   ├── Inbound: SSH (22), HTTP (80), HTTPS (443)
│   └── Outbound: All traffic
└── EFS Security Group
    ├── Inbound: NFS (2049) from EC2
    └── Outbound: All traffic
```

### Compute Architecture

```
EC2 Instances:
├── Spot Instances (70% cost savings)
│   ├── Instance Type: g4dn.xlarge (default)
│   ├── GPU: NVIDIA T4 (16GB)
│   └── Storage: 100GB GP3 SSD
├── Auto Scaling Groups (optional)
│   ├── Min: 1, Max: 3, Desired: 1
│   └── Health Check: ALB + EC2
└── Launch Templates
    ├── User Data: Docker + AI stack setup
    └── IAM Instance Profile
```

## AI Stack Architecture

### Container Architecture

```
Docker Compose Stack:
├── n8n (Workflow Automation)
│   ├── Port: 5678
│   ├── Volume: n8n_data
│   └── Dependencies: PostgreSQL
├── Ollama (LLM Inference)
│   ├── Port: 11434
│   ├── GPU: NVIDIA runtime
│   ├── Models: DeepSeek-R1:8B, Qwen2.5-VL:7B
│   └── Volume: ollama_data
├── Qdrant (Vector Database)
│   ├── Port: 6333
│   ├── Volume: qdrant_data
│   └── Collections: Configurable
├── Crawl4AI (Web Scraping)
│   ├── Port: 11235
│   ├── Dependencies: Chrome, Python
│   └── Volume: crawl4ai_data
└── Reverse Proxy (Nginx)
    ├── SSL Termination
    ├── Load Balancing
    └── Rate Limiting
```

### Storage Architecture

```
EFS (Elastic File System):
├── Mount Targets (Multi-AZ)
├── Encryption: AES-256
├── Performance Mode: General Purpose
├── Throughput Mode: Provisioned
└── Mount Points:
    ├── /efs/n8n → n8n workflows
    ├── /efs/ollama → LLM models
    ├── /efs/qdrant → vector data
    └── /efs/crawl4ai → scraped data
```

## Plugin Architecture

### Plugin Framework

```bash
# Plugin Interface
init_plugin()           # Initialize plugin
handle_event()          # Process events
get_config()           # Return configuration
cleanup()              # Cleanup resources

# Plugin Registration
unity_register_plugin "spot-optimizer" \
  "$PLUGIN_DIR/spot-optimizer/plugin.sh" \
  "high" \
  "ec2,aws"
```

### Available Plugins

1. **Spot Optimizer Plugin**
   - 70% cost savings through intelligent spot instance selection
   - Real-time pricing analysis
   - Automatic fallback to on-demand instances

2. **Cost Analyzer Plugin**
   - Cost tracking and reporting
   - Budget alerts and recommendations
   - Resource utilization analysis

3. **Security Validator Plugin**
   - Pre-deployment security checks
   - Compliance validation
   - Vulnerability scanning

4. **Performance Tuner Plugin**
   - Resource optimization recommendations
   - Performance monitoring
   - Auto-scaling configuration

## Configuration Architecture

### Unified Configuration System

```yaml
# config/unity.yml (Single Source of Truth)
unity:
  deployment:
    types: [spot, alb, cdn, full]
    environments: [dev, staging, prod]
    defaults:
      instance_type: g4dn.xlarge
      region: us-east-1
  services:
    aws:
      enabled: true
      config:
        spot_enabled: true
        multi_az: true
    docker:
      enabled: true
      config:
        gpu_enabled: true
        ai_stack: true
  plugins:
    spot-optimizer:
      enabled: true
      priority: 100
    cost-analyzer:
      enabled: true
      priority: 80
```

### Configuration Hierarchy

1. Command-line arguments (highest priority)
2. Environment variables
3. Unity configuration file (`config/unity.yml`)
4. AWS Parameter Store (for secrets)
5. Service defaults (lowest priority)

## Monitoring Architecture

### Health Check System

```
Health Checks:
├── Unity Service Health
│   ├── Service status monitoring
│   ├── Event system health
│   └── Plugin health checks
├── AWS Resource Health
│   ├── EC2 instance status
│   ├── ALB target health
│   └── VPC connectivity
├── Application Health
│   ├── Docker container status
│   ├── AI service endpoints
│   └── Resource utilization
└── Performance Metrics
    ├── Response times
    ├── Throughput
    └── Error rates
```

### Monitoring Stack

```
CloudWatch:
├── Custom Metrics
│   ├── Unity service metrics
│   ├── Application metrics
│   └── Business metrics
├── Alarms
│   ├── Resource utilization
│   ├── Error rate thresholds
│   └── Cost budgets
└── Dashboards
    ├── Infrastructure overview
    ├── Application performance
    └── Cost analysis
```

## Deployment Types Architecture

### Development (Spot)
- **Components**: VPC, EC2 (spot instance)
- **Cost**: ~$0.50/hour (70% savings)
- **Use Case**: Development, testing
- **Features**: Auto-cleanup, rapid iteration

### Staging (ALB)
- **Components**: VPC, EC2, ALB, EFS
- **Cost**: ~$2-3/hour
- **Use Case**: Pre-production testing
- **Features**: Production-like setup, load balancing

### Production (Full)
- **Components**: VPC, EC2, ALB, CloudFront, EFS, Multi-AZ
- **Cost**: ~$5-10/hour
- **Use Case**: Production workloads
- **Features**: High availability, CDN, monitoring

## Security Architecture

### Network Security
- **VPC**: Isolated network environment
- **Security Groups**: Stateful firewall rules
- **NACLs**: Subnet-level network access control
- **Private Subnets**: EC2 instances in private subnets
- **NAT Gateways**: Secure outbound internet access

### Data Security
- **EFS Encryption**: AES-256 encryption at rest
- **SSL/TLS**: Encryption in transit
- **IAM Roles**: Least privilege access
- **Secrets Management**: AWS Parameter Store integration

### Application Security
- **Container Security**: Docker security best practices
- **API Security**: Authentication and rate limiting
- **Network Policies**: Service-to-service communication rules
- **Security Scanning**: Automated vulnerability assessment

## Scalability Architecture

### Horizontal Scaling
- **Auto Scaling Groups**: Dynamic instance scaling
- **Load Balancing**: Traffic distribution
- **Multi-AZ**: High availability across zones
- **Container Orchestration**: Service scaling

### Vertical Scaling
- **Instance Types**: GPU-optimized instances
- **Storage Scaling**: EFS automatic scaling
- **Memory Optimization**: Efficient resource utilization
- **Performance Tuning**: Automatic optimization

## Future Architecture Considerations

### Kubernetes Migration Path
- Container orchestration migration
- Service mesh integration
- Advanced scheduling capabilities
- Enhanced monitoring and observability

### Multi-Cloud Support
- Cloud-agnostic service interfaces
- Provider abstraction layers
- Cross-cloud networking
- Unified management plane

### Advanced AI Features
- Model serving optimization
- Distributed inference
- Model versioning and rollback
- A/B testing for models

---

For detailed implementation guides, see:
- [Unity Architecture Documentation](../unity/unity-architecture.md)
- [Deployment Guide](deployment.md)
- [Plugin Development Guide](../unity/plugin-development-guide.md)