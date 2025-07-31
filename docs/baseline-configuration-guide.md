# GeuseMaker Baseline Configuration Guide

This guide documents all locations where baseline configurations and default values are set in the GeuseMaker codebase.

## Configuration Hierarchy (Priority Order)

1. **Command Line Arguments** - Highest priority
2. **Environment Variables** - Override defaults
3. **Environment Files** (.env, .env.local, .env.<environment>)
4. **AWS Parameter Store** - Secure values
5. **Deployment State** - Previous deployment values
6. **Configuration Files** - YAML/JSON configs
7. **Hardcoded Defaults** - Lowest priority

## Primary Configuration Locations

### 1. Core Variable Registration
**File**: `/lib/modules/config/variables.sh` (lines 465-489)

Key defaults:
```bash
AWS_REGION="us-east-1"
AWS_DEFAULT_REGION="us-east-1"
AWS_PROFILE="default"
DEPLOYMENT_TYPE="spot"
INSTANCE_TYPE="g4dn.xlarge"
VOLUME_SIZE="100"
ENVIRONMENT="production"
CLEANUP_ON_FAILURE="true"
```

### 2. Deployment Variable Management
**File**: `/lib/deployment-variable-management.sh` (lines 58-68)

Dynamic defaults:
```bash
AWS_REGION="us-east-1"
DEPLOYMENT_TYPE="spot"
INSTANCE_TYPE="g4dn.xlarge"
VOLUME_SIZE="30"  # Note: Different from variables.sh
ENVIRONMENT="development"  # Note: Different from variables.sh
CLEANUP_ON_FAILURE="true"
```

### 3. Legacy Script Defaults
**File**: `/archive/legacy/aws-deployment-v2-simple.sh` (lines 49-51)

```bash
readonly DEFAULT_INSTANCE_TYPE="g4dn.xlarge"
readonly DEFAULT_REGION="us-east-1"
readonly DEFAULT_DEPLOYMENT_TYPE="spot"
```

### 4. Global Configuration File
**File**: `/config/defaults.yml`

Structured defaults:
```yaml
global:
  project_name: GeuseMaker
  region: us-east-1

infrastructure:
  instance_types:
    gpu_instances: ["g4dn.xlarge", "g5g.xlarge", "g4dn.2xlarge", "g5g.2xlarge"]
    cpu_instances: ["t3.large", "t3.xlarge", "m5.large", "m5.xlarge"]
  
  networking:
    vpc_cidr: "10.0.0.0/16"
    public_subnet_count: 2
    private_subnet_count: 2
  
  storage:
    efs_encryption: true
    ebs_encryption: true
    backup_retention_days: 30
```

### 5. Deployment Types Configuration
**File**: `/config/deployment-types.yml`

Type-specific defaults:
```yaml
spot:
  instance_types:
    preferred: ["g4dn.xlarge"]
  
enterprise:
  instance_types:
    preferred: ["g4dn.xlarge", "g5g.xlarge", "g4dn.2xlarge"]
```

### 6. Terraform Variables
**File**: `/terraform/variables.tf`

Infrastructure as Code defaults:
```hcl
variable "aws_region" {
  default = "us-east-1"
}

variable "instance_type" {
  default = "g4dn.xlarge"
}
```

### 7. AWS Parameter Store Paths
**Prefix**: `/aibuildkit/`

Common parameters:
- `/aibuildkit/POSTGRES_PASSWORD`
- `/aibuildkit/n8n/ENCRYPTION_KEY`
- `/aibuildkit/n8n/USER_MANAGEMENT_JWT_SECRET`
- `/aibuildkit/OPENAI_API_KEY`
- `/aibuildkit/WEBHOOK_URL`

### 8. Environment Files
**Files**: 
- `.env` - Main environment file
- `.env.local` - Local overrides
- `.env.<environment>` - Environment-specific (e.g., .env.production)
- `.env.example` - Template with examples

## How to Set Baseline Configuration

### Method 1: Environment Variables (Recommended for CI/CD)
```bash
export AWS_REGION="us-west-2"
export INSTANCE_TYPE="g5.xlarge"
export DEPLOYMENT_TYPE="enterprise"
./scripts/aws-deployment-modular.sh my-stack
```

### Method 2: Environment File (Recommended for Development)
Create `.env.local`:
```bash
AWS_REGION=eu-west-1
INSTANCE_TYPE=g5.2xlarge
DEPLOYMENT_TYPE=spot
VOLUME_SIZE=50
ENVIRONMENT=staging
```

### Method 3: Configuration File Override
Create `config/overrides.yml`:
```yaml
global:
  region: ap-southeast-1
infrastructure:
  instance_types:
    gpu_instances: ["g5.2xlarge", "g4dn.2xlarge"]
```

### Method 4: Update Core Defaults
To change system-wide defaults, update:

1. `/lib/modules/config/variables.sh` - For variable registration
2. `/lib/deployment-variable-management.sh` - For dynamic defaults
3. `/config/defaults.yml` - For structured configuration

### Method 5: AWS Parameter Store
For secure values:
```bash
aws ssm put-parameter \
  --name "/aibuildkit/CUSTOM_API_KEY" \
  --value "your-secret-key" \
  --type "SecureString"
```

## Best Practices

1. **Never hardcode secrets** - Use Parameter Store or environment variables
2. **Use environment files** - For environment-specific configurations
3. **Maintain consistency** - Ensure defaults match across files
4. **Document changes** - Update this guide when changing defaults
5. **Test thoroughly** - Verify changes work with dynamic variable loading

## Common Configuration Scenarios

### Development Environment
```bash
# .env.development
ENVIRONMENT=development
INSTANCE_TYPE=t3.medium
VOLUME_SIZE=20
DEBUG=true
DRY_RUN=false
```

### Production Environment
```bash
# .env.production
ENVIRONMENT=production
DEPLOYMENT_TYPE=enterprise
INSTANCE_TYPE=g5.2xlarge
VOLUME_SIZE=100
ENABLE_MULTI_AZ=true
ENABLE_ALB=true
ENABLE_CLOUDFRONT=true
ENABLE_BACKUP=true
```

### Cost-Optimized Setup
```bash
# .env.cost-optimized
DEPLOYMENT_TYPE=spot
INSTANCE_TYPE=g4dn.xlarge
ENABLE_SPOT_FALLBACK=true
SPOT_INTERRUPTION_BEHAVIOR=terminate
```

## Validation

To validate your configuration:
```bash
# Check current configuration
./scripts/validate-environment.sh

# Test with dry run
DRY_RUN=true ./scripts/aws-deployment-modular.sh test-stack

# Validate specific deployment type
./scripts/aws-deployment-modular.sh --validate-only --type enterprise test-stack
```