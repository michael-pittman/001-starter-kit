# Phase 2: Configuration Unification Migration Guide

## Overview

This guide covers migrating from multiple configuration sources (.env files, hardcoded values, scattered configs) to Unity's unified YAML-based configuration system with proper hierarchy and validation.

## Pre-Migration Assessment

```bash
# Scan current configuration
./scripts/unity-cli.sh migrate config scan \
    --report config-assessment.html

# Current configuration sources:
# - .env files (5-10 files)
# - Hardcoded values in scripts
# - AWS Parameter Store
# - config/*.yml files
# - Environment variables
```

## Migration Strategy

### Configuration Hierarchy

```
1. Command-line arguments (highest priority)
2. Environment variables
3. .env.local / .env.<environment>
4. AWS Parameter Store
5. config/environments/<env>.yml
6. config/unity.yml
7. config/defaults.yml (lowest priority)
```

## Step-by-Step Migration

### Step 1: Create Configuration Inventory

```bash
# Find all .env files
find . -name ".env*" -type f | grep -v node_modules > env-files.txt

# Extract all variables
for file in $(cat env-files.txt); do
    echo "=== $file ==="
    grep -E "^[A-Z_]+=" "$file" | cut -d= -f1 | sort -u
done > all-variables.txt

# Find hardcoded configs in scripts
grep -r "export [A-Z_]*=" scripts/ --include="*.sh" > hardcoded-configs.txt
```

### Step 2: Generate Unified Configuration

```bash
# Auto-generate base configuration
./scripts/unity-cli.sh migrate config generate \
    --scan-env-files \
    --scan-scripts \
    --output config/unity.yml

# Review generated configuration
cat config/unity.yml
```

### Step 3: Organize by Environment

```bash
# Split configuration by environment
for env in development staging production; do
    ./scripts/unity-cli.sh migrate config split \
        --environment $env \
        --source .env.$env \
        --output config/environments/$env.yml
done
```

### Step 4: Migrate Secrets to Parameter Store

```bash
# Identify secrets
./scripts/unity-cli.sh migrate config identify-secrets \
    --patterns "PASSWORD,KEY,TOKEN,SECRET"

# Move to Parameter Store
./scripts/unity-cli.sh migrate config move-secrets \
    --to-parameter-store \
    --prefix "/unity/${ENVIRONMENT}"
```

### Step 5: Update Configuration Loading

Replace legacy configuration loading:

**Before:**
```bash
# Load from .env file
if [[ -f .env.${ENVIRONMENT} ]]; then
    source .env.${ENVIRONMENT}
fi

# Hardcoded defaults
export INSTANCE_TYPE="${INSTANCE_TYPE:-t3.medium}"
export REGION="${REGION:-us-east-1}"
```

**After:**
```bash
# Load Unity configuration
source "${UNITY_LIB_DIR}/services/config.sh"
unity_config_load "$ENVIRONMENT"

# Get values with validation
INSTANCE_TYPE=$(unity_config_get "aws.ec2.instance_type" "t3.medium")
REGION=$(unity_config_get "aws.region" "us-east-1")
```

## Configuration Examples

### Example 1: AWS Configuration

**Legacy (.env):**
```bash
AWS_REGION=us-east-1
AWS_PROFILE=production
INSTANCE_TYPE=g4dn.xlarge
SPOT_ENABLED=true
SPOT_PRICE=0.50
```

**Unity (YAML):**
```yaml
services:
  aws:
    region: ${AWS_REGION:-us-east-1}
    profile: ${AWS_PROFILE:-production}
    ec2:
      instance_type: g4dn.xlarge
    spot:
      enabled: true
      max_price: 0.50
```

### Example 2: Application Configuration

**Legacy:**
```bash
# Scattered across multiple files
export N8N_PORT=5678
export OLLAMA_HOST=http://localhost:11434
export POSTGRES_DB=n8n
export POSTGRES_USER=n8n
export POSTGRES_PASSWORD_FILE=/run/secrets/db_password
```

**Unity:**
```yaml
applications:
  n8n:
    port: 5678
    database:
      name: n8n
      user: n8n
      password: ${SSM:/unity/production/postgres_password}
  ollama:
    host: http://localhost:11434
    models:
      - deepseek-r1:8b
      - qwen2.5-vl:7b
```

## Variable Registration

All variables must be registered in the system:

```bash
# Register custom variables
cat > config/custom-variables.yml << EOF
custom_variables:
  - name: CUSTOM_TIMEOUT
    type: integer
    default: 30
    description: "Custom operation timeout"
    
  - name: CUSTOM_RETRY_COUNT
    type: integer
    default: 3
    validation:
      min: 1
      max: 10
EOF

# Apply registration
./scripts/unity-cli.sh config register \
    --file config/custom-variables.yml
```

## Validation and Testing

### Step 1: Validate Configuration

```bash
# Validate syntax
./scripts/unity-cli.sh config validate

# Check for missing variables
./scripts/unity-cli.sh config check-completeness

# Test variable resolution
./scripts/unity-cli.sh config show --resolved
```

### Step 2: Test Configuration Loading

```bash
# Test each environment
for env in development staging production; do
    echo "Testing $env environment..."
    ENVIRONMENT=$env ./scripts/unity-cli.sh config test
done

# Compare with legacy
./scripts/unity-cli.sh config compare \
    --legacy .env.production \
    --unity config/environments/production.yml
```

## Rollback Procedure

```bash
# 1. Disable Unity config
export UNITY_CONFIG_ENABLED=false

# 2. Restore .env files
./scripts/unity-cli.sh migrate config restore \
    --from-backup

# 3. Verify legacy loading
source .env.production
echo "INSTANCE_TYPE=$INSTANCE_TYPE"
```

## Benefits After Migration

1. **Single Source of Truth**: All configuration in one place
2. **Type Safety**: Validation and type checking
3. **Environment Management**: Clear separation of environments
4. **Secret Management**: Integrated with Parameter Store
5. **Dynamic Reloading**: Change configuration without restart
6. **Better Documentation**: Self-documenting YAML format

## Common Patterns

### Pattern 1: Feature Flags

```yaml
features:
  spot_instances:
    enabled: ${FEATURE_SPOT_ENABLED:-true}
    environments: [development, staging, production]
  
  multi_az:
    enabled: ${FEATURE_MULTI_AZ:-false}
    environments: [production]
```

### Pattern 2: Environment-Specific Overrides

```yaml
# config/unity.yml (base)
database:
  host: localhost
  port: 5432

# config/environments/production.yml
database:
  host: prod-db.example.com
  ssl: required
  connection_pool: 20
```

### Pattern 3: Dynamic Values

```yaml
# Reference other values
api:
  base_url: https://${services.aws.region}.api.example.com
  timeout: ${system.default_timeout}
  
# Compute values
cache:
  size: ${MEMORY_LIMIT:-1G}
  ttl: ${CACHE_TTL:-3600}
```

## Troubleshooting

### Issue: Variable Not Found

```bash
# Debug variable resolution
UNITY_CONFIG_DEBUG=true ./scripts/unity-cli.sh config get my.variable

# List all available variables
./scripts/unity-cli.sh config list-variables
```

### Issue: Type Validation Failures

```bash
# Show validation errors
./scripts/unity-cli.sh config validate --verbose

# Fix type issues
./scripts/unity-cli.sh config fix-types --interactive
```

## Post-Migration Checklist

- [ ] All .env files migrated to YAML
- [ ] Secrets moved to Parameter Store
- [ ] Variable validation implemented
- [ ] Team trained on new configuration
- [ ] Documentation updated
- [ ] CI/CD pipelines updated
- [ ] Monitoring for config errors
- [ ] Backup of legacy configuration

## Next Steps

1. Monitor configuration usage for 1 week
2. Gather team feedback
3. Optimize configuration structure
4. Plan Phase 3: Docker Service Consolidation