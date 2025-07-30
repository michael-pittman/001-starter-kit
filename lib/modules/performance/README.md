# Performance Optimization Module

This module provides comprehensive performance optimization capabilities for GeuseMaker, including monitoring, caching, parallel execution, and CloudWatch integration.

## Components

### 1. Performance Monitoring (`monitoring.sh`)
- **Purpose**: Track and measure performance metrics across all operations
- **Features**:
  - Real-time performance tracking
  - Phase-based timing measurements
  - Memory usage monitoring
  - API call tracking
  - Performance baseline comparison
  - Automatic report generation

**Key Functions**:
- `perf_init()` - Initialize performance monitoring
- `perf_start_phase()` - Start timing a phase
- `perf_end_phase()` - End timing and record duration
- `perf_record_api_call()` - Track AWS API usage
- `perf_generate_report()` - Generate performance report
- `perf_check_targets()` - Compare against performance targets

### 2. Core Optimization (`optimization.sh`)
- **Purpose**: Apply various optimization techniques to improve performance
- **Features**:
  - Lazy module loading
  - Environment check caching
  - API call deduplication
  - Memory optimization
  - File operation buffering
  - Process management

**Key Functions**:
- `perf_optimize_startup()` - Optimize script startup time
- `perf_optimize_module_loading()` - Implement lazy loading
- `perf_cached_api_call()` - Cache and deduplicate API calls
- `perf_apply_all_optimizations()` - Apply optimization suite

### 3. Intelligent Caching (`caching.sh`)
- **Purpose**: Multi-tier caching system for AWS responses and data
- **Features**:
  - Two-tier cache (L1 memory, L2 file)
  - Automatic cache size management
  - TTL-based expiration
  - Pattern-based invalidation
  - Cache statistics and monitoring
  - AWS-specific caching functions

**Key Functions**:
- `cache_init()` - Initialize cache system
- `cache_set()` - Store data in cache
- `cache_get()` - Retrieve cached data
- `cache_aws_response()` - Cache AWS API responses
- `cache_spot_prices()` - Specialized spot price caching
- `cache_stats()` - Display cache statistics

### 4. Parallel Execution (`parallel.sh`)
- **Purpose**: Execute operations in parallel for improved performance
- **Features**:
  - Job queue management
  - Configurable parallelism limits
  - Job timeout handling
  - Output/error capture
  - Map-reduce patterns
  - AWS-specific parallel operations

**Key Functions**:
- `parallel_init()` - Initialize parallel execution
- `parallel_execute()` - Run commands in parallel
- `parallel_get_spot_prices()` - Query spot prices in parallel
- `parallel_map_reduce()` - Map-reduce implementation
- `parallel_stats()` - Display execution statistics

### 5. CloudWatch Integration (`cloudwatch.sh`)
- **Purpose**: Send metrics and create dashboards in CloudWatch
- **Features**:
  - Automated dashboard creation
  - Real-time metric publishing
  - Performance alarms
  - Metric querying and analysis
  - Performance insights generation

**Key Functions**:
- `create_performance_dashboard()` - Create CloudWatch dashboard
- `send_performance_metrics()` - Publish metrics to CloudWatch
- `create_performance_alarms()` - Set up performance alerts
- `generate_performance_insights()` - Analyze performance trends

## Performance Targets

The module enforces these performance targets:
- **Startup Time**: <2 seconds
- **Deployment Time**: <3 minutes (180 seconds)
- **Peak Memory Usage**: <100MB
- **API Call Reduction**: 50% through caching

## Usage

### Basic Performance Analysis
```bash
# Analyze current performance
./scripts/performance-optimization.sh analyze

# Apply standard optimizations
./scripts/performance-optimization.sh optimize

# Run performance benchmarks
./scripts/performance-optimization.sh benchmark
```

### Advanced Usage
```bash
# Apply aggressive optimizations for production
./scripts/performance-optimization.sh optimize prod-stack aggressive

# Monitor real-time performance
./scripts/performance-optimization.sh monitor prod-stack

# Compare to baseline
./scripts/performance-optimization.sh compare
```

### In Your Scripts
```bash
# Load performance modules
source "$LIB_DIR/modules/performance/monitoring.sh"
source "$LIB_DIR/modules/performance/optimization.sh"
source "$LIB_DIR/modules/performance/caching.sh"
source "$LIB_DIR/modules/performance/parallel.sh"

# Initialize performance optimization
perf_init "my-deployment"
cache_init 100  # 100MB cache
parallel_init "auto"  # Auto-detect CPU cores

# Apply optimizations
perf_apply_all_optimizations "standard"

# Track operations
perf_start_phase "deployment"
# ... deployment code ...
perf_end_phase "deployment"

# Use caching for AWS calls
response=$(cache_aws_response "spot_prices_us_east_1" \
    "aws ec2 describe-spot-price-history --region us-east-1" \
    300)  # 5 minute TTL

# Execute in parallel
parallel_get_spot_prices "g4dn.xlarge" "us-east-1" "us-west-2" "eu-west-1"

# Generate report
perf_finalize
```

## Optimization Levels

### Minimal
- Basic startup optimizations
- Small cache (50MB)
- Limited parallelism (2 jobs)

### Standard (Default)
- Full startup optimizations
- API call caching and batching
- Moderate cache (100MB)
- Balanced parallelism (4 jobs)

### Aggressive
- All optimizations enabled
- Large cache (200MB)
- Maximum parallelism (CPU cores)
- Pre-warmed caches
- Aggressive API batching

## Environment Variables

- `PERF_CACHE_SIZE` - Cache size in MB (default: 100)
- `PERF_MAX_PARALLEL` - Max parallel jobs (default: 4 or auto)
- `PERF_VERBOSE` - Enable verbose output (default: false)
- `CACHE_ENABLED` - Enable/disable caching (default: true)
- `PARALLEL_VERBOSE` - Verbose parallel execution (default: false)

## CloudWatch Metrics

The module publishes these metrics to CloudWatch:
- `DeploymentDuration` - Total deployment time
- `PeakMemoryUsage` - Maximum memory usage
- `StartupTime` - Script initialization time
- `APICallCount` - Number of AWS API calls
- `CacheHitRate` - Cache effectiveness percentage
- `ParallelJobsCompleted` - Successful parallel jobs
- `ParallelJobsFailed` - Failed parallel jobs
- `ParallelSpeedup` - Parallelization efficiency

## Best Practices

1. **Always Initialize**: Call `perf_init()` at the start of your scripts
2. **Use Phase Timing**: Wrap major operations with `perf_start_phase()` and `perf_end_phase()`
3. **Cache AWS Calls**: Use `cache_aws_response()` for expensive API calls
4. **Batch Operations**: Use parallel execution for independent operations
5. **Monitor Memory**: Keep arrays bounded and clean up large variables
6. **Choose Right Level**: Use aggressive optimization for production, standard for development

## Testing

Run the comprehensive test suite:
```bash
./tests/test-performance-optimization.sh
```

This validates:
- Performance monitoring accuracy
- Optimization effectiveness
- Cache functionality
- Parallel execution correctness
- CloudWatch integration
- Performance target compliance