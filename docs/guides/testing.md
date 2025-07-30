# Testing Guide

## Overview

GeuseMaker includes a comprehensive testing framework with multiple test categories and automated validation. All tests are designed to run without incurring AWS charges where possible.

## Test Categories

### Unit Tests
Test individual functions and modules in isolation.

```bash
./tools/test-runner.sh unit
```

**Coverage:**
- Variable sanitization
- Error handling functions
- Module loading
- Configuration validation

### Integration Tests
Test interactions between components.

```bash
./tools/test-runner.sh integration
```

**Coverage:**
- Module interactions
- Resource registry operations
- Error handling flows
- Configuration management

### Security Tests
Validate security configurations and policies.

```bash
./tools/test-runner.sh security
make security-check
```

**Coverage:**
- IAM policy validation
- Security group rules
- Parameter Store access
- Input sanitization

### Performance Tests
Benchmark system performance and resource usage.

```bash
./tools/test-runner.sh performance
```

**Coverage:**
- Spot pricing analysis speed
- Module loading times
- Memory usage patterns
- API call efficiency

### Deployment Tests
Validate deployment scripts without creating resources.

```bash
./tools/test-runner.sh deployment
```

**Coverage:**
- Script syntax validation
- Argument parsing
- Configuration generation
- Dry-run validation

### Smoke Tests
Quick validation for CI/CD pipelines.

```bash
./tools/test-runner.sh smoke
```

**Coverage:**
- Core module loading
- Basic functionality
- Help commands
- Version checks

## Key Test Scripts

### Core Module Tests

**test-modular-v2.sh**
```bash
./tests/test-modular-v2.sh
```
Tests the modular system components:
- Variable management and sanitization
- Resource registry operations
- Error handling integration
- Module loading and compatibility

**test-infrastructure-modules.sh**
```bash
./tests/test-infrastructure-modules.sh
```
Validates infrastructure modules:
- VPC module functionality
- Security group configuration
- IAM role creation
- EFS setup validation

**test-deployment-flow.sh**
```bash
./tests/test-deployment-flow.sh
```
End-to-end deployment validation:
- Orchestrator argument parsing
- Module integration
- Error handling flows
- AWS integration (if credentials available)

### Specialized Tests

**final-validation.sh**
```bash
./tests/final-validation.sh
```
Comprehensive system validation:
- All modules functional
- Scripts syntactically correct
- AWS integration working
- Key features operational

## Local Testing (No AWS Costs)

### Simple Demo Testing
```bash
./archive/demos/simple-demo.sh
```
Tests core logic without AWS:
- Spot instance selection algorithms
- Fallback strategies
- Cost calculations
- Instance type compatibility

### Intelligent Selection Testing
```bash
./archive/demos/test-intelligent-selection.sh
```
Validates selection logic:
- Multi-region analysis
- Instance type fallbacks
- Price optimization
- Capacity planning

### Module Testing
```bash
# Test specific modules
bash -n lib/modules/core/variables.sh
bash -n lib/modules/infrastructure/vpc.sh
bash -n lib/modules/compute/provisioner.sh
bash -n lib/modules/application/docker_manager.sh
```

## Test Runner Usage

### Basic Usage
```bash
# Run all tests
make test

# Run specific category
./tools/test-runner.sh unit

# Generate HTML report
./tools/test-runner.sh --report

# Verbose output
./tools/test-runner.sh --verbose unit
```

### Test Configuration
```bash
# Set test environment
export TEST_ENVIRONMENT=local
export TEST_SKIP_AWS=true

# Run with custom timeout
./tools/test-runner.sh --timeout 300 integration
```

## Test Reports

Tests generate reports in `./test-reports/`:

### HTML Reports
- `test-summary.html` - Human-readable results
- `test-details.html` - Detailed test output
- `coverage-report.html` - Coverage analysis

### JSON Reports
- `test-results.json` - Machine-readable results
- `test-metrics.json` - Performance metrics
- `test-errors.json` - Error details

### Example Report Structure
```json
{
  "summary": {
    "total": 45,
    "passed": 43,
    "failed": 2,
    "skipped": 0,
    "duration": "2m 15s"
  },
  "categories": {
    "unit": {"passed": 15, "failed": 0},
    "integration": {"passed": 12, "failed": 1},
    "security": {"passed": 8, "failed": 0},
    "deployment": {"passed": 8, "failed": 1}
  }
}
```

## AWS Integration Testing

### Prerequisites
```bash
# Configure AWS credentials
aws configure

# Verify access
aws sts get-caller-identity
```

### Safe AWS Testing
```bash
# Test without creating resources
./scripts/aws-deployment-v2-simple.sh --help
./scripts/aws-deployment-v2-simple.sh -t t3.micro --skip-validation test-stack

# Validate instance availability
aws ec2 describe-instance-type-offerings \
  --filters "Name=instance-type,Values=t3.micro" \
  --query 'InstanceTypeOfferings[0].InstanceType'
```

### Resource Cleanup Testing
```bash
# Test cleanup without actual resources
./scripts/cleanup-consolidated.sh --dry-run --stack test-stack

# Test registry cleanup
./tests/test-modular-migration.sh
```

## Continuous Integration

### GitHub Actions Integration
```yaml
name: Test Suite
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run tests
        run: |
          make test
          ./tools/test-runner.sh --report
      - name: Upload results
        uses: actions/upload-artifact@v2
        with:
          name: test-reports
          path: test-reports/
```

### Pre-commit Hooks
```bash
# Install pre-commit hooks
cp tools/pre-commit-hook .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# Hook runs:
# - make lint
# - ./tools/test-runner.sh smoke
# - Security validation
```

## Writing New Tests

### Test Structure
```bash
#!/bin/bash
set -euo pipefail

# Test metadata
readonly TEST_NAME="my-new-test"
readonly TEST_CATEGORY="unit"

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test functions
test_my_feature() {
    local expected="expected_value"
    local actual=$(my_function "input")
    
    if [[ "$actual" == "$expected" ]]; then
        echo "PASS: my_feature test"
        return 0
    else
        echo "FAIL: Expected '$expected', got '$actual'"
        return 1
    fi
}

# Main execution
main() {
    echo "Running $TEST_NAME tests..."
    
    test_my_feature
    
    echo "All tests passed!"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

### Test Best Practices

1. **No side effects** - Tests should not modify system state
2. **Deterministic** - Same input always produces same output
3. **Fast execution** - Avoid unnecessary delays
4. **Clear assertions** - Obvious pass/fail conditions
5. **Good error messages** - Help debug failures

### Mock AWS Calls
```bash
# Mock AWS CLI for testing
mock_aws() {
    case "$1" in
        "ec2")
            case "$2" in
                "describe-instances")
                    echo '{"Reservations": []}'
                    ;;
                "describe-instance-types")
                    echo '{"InstanceTypes": [{"InstanceType": "t3.micro"}]}'
                    ;;
            esac
            ;;
    esac
}

# Use in tests
AWS_CLI_COMMAND="mock_aws" my_test_function
```

## Troubleshooting Tests

### Common Issues

**Test failures on macOS**
```bash
# Check bash version
bash --version

# Use bash 3.x compatible syntax
# Avoid: declare -g -A array
# Use: declare -A array
```

**AWS credential issues**
```bash
# Set environment to skip AWS tests
export TEST_SKIP_AWS=true

# Or configure test credentials
aws configure --profile test
export AWS_PROFILE=test
```

**Module loading failures**
```bash
# Check module syntax
bash -n lib/modules/core/variables.sh

# Test module loading
source lib/modules/core/variables.sh
echo "Module loaded successfully"
```

### Debug Mode
```bash
# Enable debug output
export TEST_DEBUG=true
./tools/test-runner.sh unit

# Verbose bash execution
bash -x ./tests/test-modular-v2.sh
```

## Performance Testing

### Benchmarking
```bash
# Measure spot pricing performance
time ./archive/demos/simple-demo.sh

# Profile module loading
time for i in {1..10}; do
    source lib/modules/core/variables.sh
done
```

### Resource Usage
```bash
# Monitor memory usage during tests
ps aux | grep test-runner
top -p $(pgrep -f test-runner)

# Check disk usage
du -sh test-reports/
```

## Test Maintenance

### Regular Tasks

1. **Update test data** - Keep mock responses current
2. **Review coverage** - Ensure new features are tested
3. **Performance monitoring** - Track test execution times
4. **Documentation** - Keep test docs updated

### Test Cleanup
```bash
# Clean test artifacts
rm -rf test-reports/*
rm -f /tmp/test-*

# Reset test environment
unset TEST_DEBUG TEST_SKIP_AWS TEST_ENVIRONMENT
```