# Existing Resources Implementation Plan

## Overview
This plan outlines the implementation of a feature that allows users to specify existing AWS resources (VPC, EFS, CloudFront, ALB, etc.) instead of creating new ones during deployment.

## Current Architecture Analysis

### Key Components Identified:
1. **Main Deployment Script**: `deploy.sh` - Orchestrates the entire deployment process
2. **Infrastructure Modules**: `lib/modules/infrastructure/*.sh` - Handle specific resource creation
3. **Configuration System**: `config/defaults.yml` and `config/environments/*.yml`
4. **Resource Registry**: `lib/modules/core/registry.sh` - Tracks created resources
5. **Variable Management**: Uses a variable store system for resource IDs

### Current Deployment Flow:
1. Load configuration and environment variables
2. Create VPC infrastructure
3. Create security infrastructure  
4. Create compute infrastructure
5. Create optional components (EFS, ALB, CloudFront, Monitoring)
6. Finalize deployment

## Implementation Plan

### Phase 1: Configuration Structure Enhancement

#### 1.1 Update Configuration Schema
**File**: `config/defaults.yml`
```yaml
# Add new section
existing_resources:
  enabled: false
  validation_mode: strict  # strict, lenient, skip
  auto_discovery: false
  reuse_policy:
    vpc: false
    subnets: false
    security_groups: false
    efs: false
    alb: false
    cloudfront: false
  resources:
    vpc:
      id: null
      cidr_block: null
    subnets:
      public: { ids: [], cidr_blocks: [] }
      private: { ids: [], cidr_blocks: [] }
    security_groups:
      alb: { id: null, name: null }
      ec2: { id: null, name: null }
      efs: { id: null, name: null }
    efs:
      file_system_id: null
      access_point_id: null
    alb:
      load_balancer_arn: null
      target_group_arn: null
    cloudfront:
      distribution_id: null
      domain_name: null
```

#### 1.2 Environment-Specific Configuration
**File**: `config/environments/dev.yml`
```yaml
existing_resources:
  enabled: true
  validation_mode: lenient
  auto_discovery: true
  reuse_policy:
    vpc: true
    subnets: true
    security_groups: true
    efs: false
    alb: true
    cloudfront: false
  resources:
    vpc:
      id: "vpc-12345678"
    subnets:
      public:
        ids: ["subnet-12345678", "subnet-87654321"]
      private:
        ids: ["subnet-abcdef12", "subnet-21fedcba"]
    security_groups:
      alb:
        id: "sg-12345678"
      ec2:
        id: "sg-87654321"
      efs:
        id: "sg-abcdef12"
    alb:
      load_balancer_arn: "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/GeuseMaker-dev-alb/1234567890123456"
```

### Phase 2: Core Infrastructure Module

#### 2.1 Create Existing Resources Module
**File**: `lib/modules/infrastructure/existing-resources.sh`

**Key Functions**:
- `load_existing_resources_config()` - Load configuration from YAML
- `validate_existing_vpc()` - Validate VPC exists and is accessible
- `validate_existing_subnets()` - Validate subnets and VPC association
- `validate_existing_security_groups()` - Validate security groups
- `discover_existing_resources()` - Auto-discover resources by naming patterns
- `map_existing_resources()` - Map resources to deployment variables
- `setup_existing_resources()` - Main orchestration function

**Resource Discovery Patterns**:
```bash
# VPC: {project_name}-{environment}-vpc
# Subnets: {project_name}-{environment}-{type}-subnet-*
# Security Groups: {project_name}-{environment}-{type}-sg
# ALB: {project_name}-{environment}-alb
# EFS: {project_name}-{environment}-efs
# CloudFront: {project_name}-{environment}-cdn
```

### Phase 3: Enhanced Infrastructure Modules

#### 3.1 Modify VPC Module
**File**: `lib/modules/infrastructure/vpc.sh`

**Changes**:
- Add existing VPC check in `create_vpc_with_subnets()`
- Skip creation if existing VPC ID is provided
- Validate existing VPC before use
- Register existing VPC in resource registry

#### 3.2 Modify EFS Module  
**File**: `lib/modules/infrastructure/efs.sh`

**Changes**:
- Add existing EFS check in `create_efs_file_system()`
- Skip creation if existing EFS ID is provided
- Validate existing EFS before use
- Register existing EFS in resource registry

#### 3.3 Modify ALB Module
**File**: `lib/modules/infrastructure/alb.sh`

**Changes**:
- Add existing ALB check in `create_alb_with_target_group()`
- Skip creation if existing ALB ARN is provided
- Validate existing ALB before use
- Register existing ALB in resource registry

#### 3.4 Modify CloudFront Module
**File**: `lib/modules/infrastructure/cloudfront.sh`

**Changes**:
- Add existing CloudFront check in `create_cloudfront_distribution()`
- Skip creation if existing distribution ID is provided
- Validate existing distribution before use
- Register existing CloudFront in resource registry

### Phase 4: Enhanced Deployment Script

#### 4.1 Modify Main Deployment Script
**File**: `deploy.sh`

**Changes**:
- Add existing resources setup before infrastructure creation
- Modify infrastructure creation functions to check for existing resources
- Add validation and error handling for existing resources
- Maintain backward compatibility

**New Functions**:
```bash
setup_existing_resources_for_deployment() {
    # Load existing resources module
    # Setup existing resources
    # Map resources to deployment variables
}

# Modified infrastructure functions
create_vpc_infrastructure() {
    # Check for existing VPC
    # Use existing or create new
}

create_efs_infrastructure() {
    # Check for existing EFS
    # Use existing or create new
}

create_alb_infrastructure() {
    # Check for existing ALB
    # Use existing or create new
}

create_cloudfront_infrastructure() {
    # Check for existing CloudFront
    # Use existing or create new
}
```

### Phase 5: CLI Management Tools

#### 5.1 Create Resource Management Script
**File**: `scripts/manage-existing-resources.sh`

**Commands**:
- `discover` - Auto-discover existing resources
- `validate` - Validate existing resources
- `map` - Map resources to deployment variables
- `list` - List configured existing resources
- `test` - Test resource connectivity and permissions

**Usage Examples**:
```bash
# Discover existing resources
./scripts/manage-existing-resources.sh discover -e dev -s GeuseMaker-dev

# Validate existing resources
./scripts/manage-existing-resources.sh validate -e dev -s GeuseMaker-dev

# Test resource connectivity
./scripts/manage-existing-resources.sh test -e dev -s GeuseMaker-dev
```

### Phase 6: Testing Strategy

#### 6.1 Unit Tests
**Directory**: `tests/unit/`

**Test Files**:
- `test-existing-resources-config.sh` - Test configuration loading
- `test-existing-resources-validation.sh` - Test resource validation
- `test-existing-resources-discovery.sh` - Test auto-discovery
- `test-existing-resources-mapping.sh` - Test variable mapping

#### 6.2 Integration Tests
**Directory**: `tests/`

**Test Files**:
- `test-existing-resources-integration.sh` - Test full integration
- `test-existing-resources-deployment.sh` - Test deployment with existing resources
- `test-existing-resources-rollback.sh` - Test rollback with existing resources

#### 6.3 Test Scenarios
1. **Fresh Deployment** - No existing resources (current behavior)
2. **Partial Existing** - Some resources exist, others created
3. **Full Existing** - All resources exist, none created
4. **Invalid Resources** - Existing resources are invalid
5. **Mixed Environment** - Different environments with different resource states

### Phase 7: Migration and Compatibility

#### 7.1 Backward Compatibility
- Default `existing_resources.enabled: false`
- All existing deployments continue to work unchanged
- Gradual migration path for users

#### 7.2 Migration Tools
**File**: `scripts/migrate-to-existing-resources.sh`

**Features**:
- Analyze current deployment
- Discover existing resources
- Generate configuration file
- Validate migration plan
- Execute migration

#### 7.3 Documentation Updates
- Update `README.md` with new feature
- Add configuration examples
- Create troubleshooting guide
- Update deployment guides

## Implementation Timeline

### Week 1: Configuration and Core Module
- [ ] Update configuration schema
- [ ] Create existing-resources.sh module
- [ ] Implement basic validation functions
- [ ] Add unit tests for core functionality

### Week 2: Infrastructure Module Updates
- [ ] Modify VPC module
- [ ] Modify EFS module
- [ ] Modify ALB module
- [ ] Modify CloudFront module
- [ ] Add integration tests

### Week 3: Deployment Script Integration
- [ ] Update main deployment script
- [ ] Add existing resources setup
- [ ] Implement resource checking logic
- [ ] Add error handling and rollback support

### Week 4: CLI Tools and Testing
- [ ] Create resource management script
- [ ] Implement discovery and validation commands
- [ ] Add comprehensive test suite
- [ ] Create migration tools

### Week 5: Documentation and Polish
- [ ] Update documentation
- [ ] Add configuration examples
- [ ] Create troubleshooting guide
- [ ] Final testing and bug fixes

## Risk Mitigation

### Technical Risks
1. **Resource Validation Failures** - Implement lenient validation modes
2. **Configuration Errors** - Add comprehensive validation and error messages
3. **Rollback Complexity** - Ensure existing resources are not deleted during rollback
4. **Performance Impact** - Cache validation results and minimize API calls

### Operational Risks
1. **User Confusion** - Provide clear documentation and examples
2. **Migration Complexity** - Create automated migration tools
3. **Testing Coverage** - Implement comprehensive test scenarios
4. **Backward Compatibility** - Maintain full compatibility with existing deployments

## Success Criteria

1. **Functionality** - Users can specify existing resources in configuration
2. **Validation** - System validates existing resources before use
3. **Discovery** - Auto-discovery works for common naming patterns
4. **Compatibility** - Existing deployments continue to work unchanged
5. **Documentation** - Clear documentation and examples provided
6. **Testing** - Comprehensive test coverage for all scenarios
7. **Performance** - No significant performance impact on deployments

## Next Steps

1. Review and approve this implementation plan
2. Set up development environment
3. Begin Phase 1 implementation
4. Create detailed technical specifications for each module
5. Establish testing framework and CI/CD pipeline
6. Begin iterative development and testing 