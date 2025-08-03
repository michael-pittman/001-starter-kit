# Unity AWS Service Complete

A comprehensive Unity AWS service that provides production-ready AWS operations with event-driven architecture, proper lifecycle management, and advanced cost optimization.

## Features

### Core AWS Operations
- **VPC Management**: Complete VPC creation with intelligent CIDR allocation, multi-AZ support, subnets, route tables, and security groups
- **EC2 Operations**: Spot instance optimization (70% cost savings), on-demand instances, and Auto Scaling Groups
- **ALB Operations**: Application Load Balancer creation with target groups, listeners, and health checks
- **CloudFront Operations**: CDN distribution creation and management
- **EFS Operations**: Encrypted file system creation with mount targets and access points
- **IAM Operations**: Role and policy management with instance profiles

### Advanced Features
- **Event-Driven Architecture**: Full integration with Unity event system
- **Cost Optimization**: Real-time cost tracking, threshold monitoring, and optimization recommendations
- **Quota Management**: Proactive quota checking with alerts and warnings
- **Resource Lifecycle**: Complete resource tracking and cleanup with dependency management
- **Enhanced Security**: Encrypted EBS volumes, VPC isolation, security group management
- **Bash 3/4 Compatibility**: Works with both Bash 3.x and 4.x environments

## Service Interface

The service implements the complete Unity service interface:

```bash
# Service lifecycle
init_unity_aws_service     # Initialize service
start_unity_aws_service    # Start service
stop_unity_aws_service     # Stop service
health_unity_aws_service   # Health check
config_unity_aws_service   # Configuration management
```

## Usage Examples

### Basic Service Management

```bash
# Initialize the service
source lib/unity/services/unity-aws-service-complete.sh
unity_aws_complete init

# Start the service (enables background monitoring)
unity_aws_complete start

# Check service health
unity_aws_complete health

# Stop the service
unity_aws_complete stop
```

### VPC Operations

```bash
# Create single-AZ VPC
unity_aws_complete create-vpc my-stack

# Create multi-AZ VPC with custom CIDR
unity_aws_complete create-vpc prod-stack 10.0.0.0/16 true

# Create VPC with specific configuration
unity_aws_complete create-vpc dev-stack 172.16.0.0/16 false
```

### EC2 Operations

```bash
# Launch spot instance (70% cost savings)
unity_aws_complete launch-ec2 g4dn.xlarge spot my-stack

# Launch on-demand instance
unity_aws_complete launch-ec2 t3.large on-demand my-stack

# Launch Auto Scaling Group
unity_aws_complete launch-ec2 m5.xlarge asg my-stack
```

### Load Balancer Operations

```bash
# Create ALB (requires existing VPC)
unity_aws_complete create-alb my-stack vpc-12345678

# ALB automatically creates:
# - Target groups with health checks
# - Listeners for HTTP/HTTPS
# - Security groups with proper rules
```

### Storage Operations

```bash
# Create encrypted EFS with mount targets
unity_aws_complete create-efs my-stack vpc-12345678

# EFS automatically creates:
# - Encrypted file system
# - Mount targets in all subnets
# - Access points with proper permissions
# - Security groups for NFS access
```

### CDN Operations

```bash
# Create CloudFront distribution
unity_aws_complete create-cloudfront my-stack my-alb-dns-name.elb.amazonaws.com

# CloudFront automatically configures:
# - Origin pointing to ALB
# - Caching behaviors
# - SSL/TLS settings
```

### Cost Management

```bash
# Calculate deployment costs
unity_aws_complete cost my-stack 720 true

# Optimize deployment costs
unity_aws_complete optimize my-stack

# Apply cost optimizations
unity_aws_complete optimize my-stack true
```

### Resource Management

```bash
# List all resources for a stack
unity_aws_complete list my-stack

# List resources in JSON format
unity_aws_complete list my-stack json

# List resources in CSV format
unity_aws_complete list my-stack csv

# Delete stack resources (dry run)
unity_aws_complete delete my-stack false true

# Delete stack resources (force delete)
unity_aws_complete delete my-stack true false
```

### Configuration Management

```bash
# Get all configuration
unity_aws_complete config get

# Get specific config value
unity_aws_complete config get region

# Set configuration value
unity_aws_complete config set cost_threshold 200

# Validate configuration
unity_aws_complete config validate
```

## Event Integration

The service emits comprehensive events for monitoring and integration:

### System Events
- `system.startup` - Service initialization
- `system.service.started` - Service started
- `system.service.stopped` - Service stopped

### Resource Events
- `aws.resource.created` - Resource created with metadata
- `aws.resource.deleted` - Resource deleted
- `aws.resource.failed` - Resource operation failed

### Specific Resource Events
- `aws.vpc.created` - VPC created
- `aws.ec2.launched` - EC2 instance launched
- `aws.alb.created` - ALB created
- `aws.efs.created` - EFS created
- `aws.cloudfront.created` - CloudFront created

### Cost Events
- `aws.cost.calculated` - Cost calculation completed
- `aws.cost.threshold_exceeded` - Cost threshold exceeded
- `aws.cost.tracked` - Cost tracking updated

### Quota Events
- `aws.quota.checked` - Quota check performed
- `aws.quota.warning` - Approaching quota limit (80%)
- `aws.quota.exceeded` - Quota limit exceeded

## Configuration Options

The service supports these configuration parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `region` | `us-east-1` | AWS region |
| `cost_threshold` | `100` | Monthly cost alert threshold ($) |
| `spot_savings_target` | `70` | Target spot instance savings (%) |
| `quota_check_interval` | `300` | Quota check interval (seconds) |

## Error Handling

The service implements comprehensive error handling:

- **Automatic Retry**: Failed operations are retried with exponential backoff
- **Event Emission**: All errors emit events for external monitoring
- **Graceful Degradation**: Service continues operating when non-critical components fail
- **Resource Cleanup**: Failed resources are automatically cleaned up

## Dependencies

- AWS CLI configured with appropriate credentials
- Unity Core System (`unity-core.sh`)
- Unity Event System (`unity-events.sh`)
- Basic Unix tools: `bc`, `grep`, `sed`, `awk`

## Architecture Integration

This service integrates with:

- **Unity Service Registry**: Automatic service registration
- **Unity Event Bus**: Event emission and handling
- **Unity Configuration System**: Unified configuration management
- **Unity Dependency Resolver**: Service dependency management

## Security Features

- **Encrypted Storage**: All EBS volumes and EFS are encrypted by default
- **VPC Isolation**: Resources deployed in dedicated VPCs
- **Security Groups**: Least-privilege access rules
- **IAM Roles**: Service-specific roles with minimal permissions
- **Key Management**: Automatic SSH key pair creation and management

## Cost Optimization

The service provides several cost optimization features:

- **Spot Instances**: Up to 70% cost savings on EC2
- **Real-time Monitoring**: Continuous cost tracking
- **Threshold Alerts**: Automatic alerts when costs exceed thresholds
- **Optimization Recommendations**: Automated cost optimization suggestions
- **Resource Right-sizing**: Analysis of over-provisioned resources

## Monitoring and Observability

- **Health Checks**: Continuous service health monitoring
- **Metrics Collection**: Resource utilization and cost metrics
- **Event Auditing**: Complete audit trail of all operations
- **Performance Tracking**: Service performance metrics

## Production Readiness

This service is designed for production use with:

- **High Availability**: Multi-AZ deployment support
- **Fault Tolerance**: Automatic error recovery
- **Scalability**: Auto Scaling Group support
- **Monitoring**: Comprehensive observability
- **Security**: Enterprise-grade security features
- **Cost Control**: Built-in cost optimization

## Support

For issues or questions about this service:

1. Check the Unity service logs: `logs/unity/core.log`
2. Review event logs: `logs/unity/events.log`
3. Verify AWS credentials and permissions
4. Check quota limits with `unity_aws_complete check-quota`