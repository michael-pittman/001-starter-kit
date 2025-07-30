# Performance Benchmark Report
Date: Tue Jul 29 23:34:12 EDT 2025

## Validation Scripts Comparison

### Original validate-environment.sh
Average: Benchmarking: Original Validation
Script: /Users/nucky/Repos/001-starter-kit/scripts/validate-environment.sh
  Run 1/3... FAILED
  Run 2/3... FAILED
  Run 3/3... FAILED
0s

### Consolidated validate-module-consolidation.sh
Average: Benchmarking: Consolidated Validation
Script: /Users/nucky/Repos/001-starter-kit/scripts/validate-module-consolidation.sh
  Run 1/3... FAILED
  Run 2/3... FAILED
  Run 3/3... FAILED
0s

### Validation Improvement: 0%

## Test Suite Performance

### test-suite-integration-simple.sh
Average: Benchmarking: Simple Integration Suite
Script: /Users/nucky/Repos/001-starter-kit/tests/test-suite-integration-simple.sh
  Run 1/2... FAILED
  Run 2/2... FAILED
0s

### test-deployment-flow.sh
Average: Benchmarking: Deployment Flow
Script: /Users/nucky/Repos/001-starter-kit/tests/test-deployment-flow.sh
  Run 1/2... FAILED
  Run 2/2... FAILED
0s

## Script Wrapper Performance

### Original health-check-advanced.sh
Average: Benchmarking: Original Health Check
Script: /Users/nucky/Repos/001-starter-kit/scripts/health-check-advanced.sh
  Run 1/2... FAILED
  Run 2/2... FAILED
0s

### Wrapper health-check-advanced-wrapper.sh
Average: Benchmarking: Wrapper Health Check
Script: /Users/nucky/Repos/001-starter-kit/scripts/health-check-advanced-wrapper.sh
  Run 1/2... FAILED
  Run 2/2... FAILED
0s

### Health Check Improvement: 0%

## Module Loading Test

Average module loading time: Benchmarking: Module Loading
Script: /Users/nucky/Repos/001-starter-kit/benchmark-results/test-module-loading.sh
  Run 1/5... FAILED
  Run 2/5... FAILED
  Run 3/5... FAILED
  Run 4/5... FAILED
  Run 5/5... FAILED
0s

## Summary


Results saved to:
- Summary: /Users/nucky/Repos/001-starter-kit/benchmark-results/benchmark_summary_20250729_233412.md
- Detailed: /Users/nucky/Repos/001-starter-kit/benchmark-results/benchmark_results_20250729_233412.txt
