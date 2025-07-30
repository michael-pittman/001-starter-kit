# Compute Module Consolidation Plan

## Executive Summary

This document outlines the consolidation plan for compute-related modules in the GeuseMaker project. The analysis reveals significant overlap and redundancy across 5 modules, with opportunities to reduce code by approximately 60% while improving maintainability and functionality.

## Current State Analysis

### Modules Analyzed
1. **infrastructure/compute.sh** (633 lines) - Auto Scaling and Launch Template management
2. **infrastructure/ec2.sh** (768 lines) - Uniform EC2 creation and management  
3. **compute/provisioner.sh** (509 lines) - Enhanced retry logic and failover
4. **instances/launch.sh** (459 lines) - Common launch patterns and lifecycle
5. **compute/spot_optimizer.sh** (623 lines) - Spot pricing and optimization

**Total Lines**: 2,992 lines across 5 modules

### Key Findings

#### 1. Duplicate Functionality
- **AMI Selection**: 4 different implementations
  - `get_latest_ami()` in compute.sh
  - `get_latest_amazon_linux_ami()` in ec2.sh
  - `get_optimal_ami()` in provisioner.sh
  - `get_ami_for_instance()` in launch.sh
  
- **Security Group Creation**: 3 implementations
  - `create_compute_security_group()` in compute.sh
  - `create_ec2_security_group()` in ec2.sh
  - Security group logic embedded in launch.sh

- **Instance State Management**: Multiple overlapping functions
  - `wait_for_instance_running()` appears in 3 modules
  - `wait_for_instance_ready()` appears in 2 modules
  - Different timeout and retry mechanisms

- **Launch Template/Configuration**: 3 different approaches
  - JSON-based in compute.sh
  - Command-based in ec2.sh
  - Hybrid approach in launch.sh

#### 2. Inconsistent Error Handling
- compute.sh: Basic error returns
- provisioner.sh: Advanced structured errors with recovery
- launch.sh: throw_error pattern
- ec2.sh: Mixed approaches
- spot_optimizer.sh: throw_error with fallback strategies

#### 3. Resource Management
- Different resource registration patterns
- Inconsistent cleanup approaches
- Variable scope management varies

#### 4. Spot Instance Handling
- Separate spot_optimizer.sh module
- Spot logic duplicated in launch.sh
- Provisioner.sh has its own spot fallback logic

## Proposed Consolidated Architecture

### 1. Core Compute Module Structure
```
/lib/modules/compute/
├── core.sh              # Base compute functionality
├── ami.sh               # AMI selection (already exists, enhance)
├── launch.sh            # Unified launch logic
├── lifecycle.sh         # Instance state management
├── spot.sh              # Spot instance optimization
├── autoscaling.sh       # Auto Scaling Group management
└── security.sh          # Security group management
```

### 2. Consolidation Strategy

#### Phase 1: Core Consolidation (Week 1)
1. **Merge AMI Selection Logic**
   - Keep existing ami.sh as base
   - Consolidate all AMI selection functions
   - Add intelligent caching
   - Support for GPU, ARM, and x86 architectures

2. **Unify Instance Launch**
   - Create single `launch_instance()` function
   - Support both spot and on-demand
   - Consistent error handling
   - Unified resource registration

3. **Standardize State Management**
   - Single `wait_for_instance_state()` function
   - Configurable timeouts and intervals
   - Consistent status checking

#### Phase 2: Advanced Features (Week 2)
1. **Enhance Spot Optimization**
   - Merge spot_optimizer.sh logic
   - Add cross-region pricing analysis
   - Implement intelligent failover chains
   - Cost calculation and reporting

2. **Auto Scaling Integration**
   - Consolidate ASG management
   - Unified scaling policies
   - Health check standardization

3. **Security Group Optimization**
   - Single security group creation flow
   - Rule management abstraction
   - Dependency tracking

#### Phase 3: Testing and Migration (Week 3)
1. **Create Compatibility Layer**
   - Wrapper functions for backward compatibility
   - Deprecation warnings
   - Migration documentation

2. **Update Dependent Scripts**
   - aws-deployment-modular.sh
   - aws-deployment-v2-simple.sh
   - All test scripts

3. **Comprehensive Testing**
   - Unit tests for each function
   - Integration tests for workflows
   - Performance benchmarks

## Implementation Details

### 1. Unified Launch Function
```bash
# Proposed unified interface
launch_compute_instance() {
    local config="$1"  # JSON configuration
    
    # Parse configuration
    local instance_type=$(echo "$config" | jq -r '.instance_type')
    local launch_type=$(echo "$config" | jq -r '.launch_type // "on-demand"')
    local spot_config=$(echo "$config" | jq -r '.spot_config // {}')
    
    # Select appropriate AMI
    local ami_id=$(select_optimal_ami "$instance_type")
    
    # Build launch configuration
    local launch_config=$(build_launch_configuration "$config" "$ami_id")
    
    # Launch with appropriate method
    case "$launch_type" in
        spot)
            launch_spot_instance_with_optimization "$launch_config" "$spot_config"
            ;;
        on-demand)
            launch_ondemand_instance "$launch_config"
            ;;
        auto-scaling)
            create_auto_scaling_group "$launch_config"
            ;;
    esac
}
```

### 2. Consistent Error Handling
```bash
# Standardized error handling across all compute functions
handle_compute_error() {
    local error_type="$1"
    local context="$2"
    
    case "$error_type" in
        EC2_INSUFFICIENT_CAPACITY)
            # Trigger failover logic
            attempt_capacity_failover "$context"
            ;;
        EC2_INSTANCE_LIMIT_EXCEEDED)
            # Check quotas and suggest alternatives
            suggest_quota_solutions "$context"
            ;;
        *)
            # Standard error propagation
            throw_error "$error_type" "$context"
            ;;
    esac
}
```

### 3. Resource Registry Integration
```bash
# Unified resource registration
register_compute_resource() {
    local resource_type="$1"
    local resource_id="$2"
    local metadata="$3"
    
    # Register with central registry
    register_resource "$resource_type" "$resource_id" "$metadata"
    
    # Update deployment state
    update_deployment_state "compute.$resource_type.$resource_id" "$metadata"
    
    # Set cleanup handler
    set_cleanup_handler "$resource_type" "$resource_id" "cleanup_compute_resource"
}
```

## Benefits of Consolidation

### 1. Code Reduction
- **Before**: 2,992 lines across 5 modules
- **After**: ~1,200 lines in organized structure
- **Reduction**: ~60% fewer lines of code

### 2. Improved Maintainability
- Single source of truth for each function
- Consistent error handling
- Unified testing approach
- Clear module boundaries

### 3. Enhanced Functionality
- Better spot instance optimization
- Improved failover capabilities
- Consistent resource tracking
- Performance optimizations

### 4. Better Testing
- Easier to test consolidated functions
- Reduced test duplication
- Comprehensive coverage

## Migration Plan

### Week 1: Core Implementation
- [ ] Create new module structure
- [ ] Implement core consolidation
- [ ] Add compatibility wrappers
- [ ] Basic unit tests

### Week 2: Feature Enhancement
- [ ] Merge advanced features
- [ ] Optimize performance
- [ ] Add monitoring hooks
- [ ] Integration tests

### Week 3: Migration and Testing
- [ ] Update dependent scripts
- [ ] Run comprehensive tests
- [ ] Performance validation
- [ ] Documentation updates

### Week 4: Cleanup
- [ ] Remove deprecated code
- [ ] Final testing
- [ ] Performance benchmarks
- [ ] Release notes

## Risk Mitigation

1. **Backward Compatibility**
   - Maintain wrapper functions during transition
   - Extensive testing of existing workflows
   - Gradual migration approach

2. **Testing Coverage**
   - Comprehensive unit tests before migration
   - Integration tests for all workflows
   - Performance regression tests

3. **Documentation**
   - Update all documentation
   - Migration guides for users
   - Clear deprecation notices

## Success Metrics

1. **Code Quality**
   - 60% reduction in lines of code
   - 100% test coverage for core functions
   - Zero regression in functionality

2. **Performance**
   - 20% faster instance launches
   - 30% reduction in API calls
   - Improved error recovery time

3. **Maintainability**
   - Single implementation per function
   - Consistent patterns throughout
   - Clear module boundaries

## Conclusion

The consolidation of compute modules will significantly improve the codebase by eliminating redundancy, standardizing patterns, and enhancing functionality. The phased approach ensures minimal disruption while delivering substantial benefits in maintainability and performance.

## Next Steps

1. Review and approve consolidation plan
2. Create detailed implementation tasks
3. Set up feature branch for development
4. Begin Phase 1 implementation

## Appendix: Detailed Function Mapping

### AMI Selection Functions
| Current Module | Function | Lines | Consolidate To |
|----------------|----------|-------|----------------|
| infrastructure/compute.sh | get_latest_ami() | 15 | ami.sh: select_optimal_ami() |
| infrastructure/ec2.sh | get_latest_amazon_linux_ami() | 20 | ami.sh: select_optimal_ami() |
| compute/provisioner.sh | get_optimal_ami() | 22 | ami.sh: select_optimal_ami() |
| instances/launch.sh | imported from ami.sh | - | Keep as is |
| compute/spot_optimizer.sh | get_nvidia_optimized_ami() | 35 | ami.sh: select_optimal_ami() |

### State Management Functions
| Current Module | Function | Lines | Consolidate To |
|----------------|----------|-------|----------------|
| infrastructure/compute.sh | wait_for_instance_running() | 25 | lifecycle.sh: wait_for_instance_state() |
| infrastructure/compute.sh | wait_for_instance_ready() | 30 | lifecycle.sh: wait_for_instance_state() |
| compute/provisioner.sh | wait_for_instance_running() | 35 | lifecycle.sh: wait_for_instance_state() |
| instances/launch.sh | wait_for_instance_state() | 40 | Keep and enhance |
| infrastructure/ec2.sh | wait_for_ec2_instance_ready() | 45 | lifecycle.sh: wait_for_instance_state() |

### Security Group Functions
| Current Module | Function | Lines | Consolidate To |
|----------------|----------|-------|----------------|
| infrastructure/compute.sh | create_compute_security_group() | 50 | security.sh: create_security_group() |
| infrastructure/compute.sh | configure_compute_security_group_rules() | 85 | security.sh: configure_security_rules() |
| infrastructure/ec2.sh | create_ec2_security_group() | 45 | security.sh: create_security_group() |
| infrastructure/ec2.sh | add_ec2_inbound_rules() | 55 | security.sh: configure_security_rules() |

### Launch Functions
| Current Module | Function | Lines | Consolidate To |
|----------------|----------|-------|----------------|
| infrastructure/compute.sh | create_launch_template() | 105 | launch.sh: create_launch_configuration() |
| infrastructure/ec2.sh | create_launch_template() | 80 | launch.sh: create_launch_configuration() |
| instances/launch.sh | build_launch_config() | 95 | Keep and enhance |
| compute/provisioner.sh | provision_instance() | 110 | launch.sh: launch_compute_instance() |