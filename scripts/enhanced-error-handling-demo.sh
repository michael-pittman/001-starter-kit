#!/usr/bin/env bash
# =============================================================================
# Enhanced Error Handling Demonstration Script
# Shows how to use the modern bash 5.3+ error handling patterns
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the enhanced error handling libraries
source "$PROJECT_ROOT/lib/error-handling.sh"
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"

echo "🧪 Enhanced Error Handling Demonstration"
echo "========================================"

# Initialize enhanced error handling with modern features
if declare -f init_enhanced_error_handling >/dev/null 2>&1; then
    echo "🚀 Initializing enhanced error handling with modern features..."
    init_enhanced_error_handling "auto" "true" "true"
    echo "✅ Enhanced error handling initialized"
else
    echo "⚙️  Falling back to basic error handling..."
    init_error_handling "strict"
    echo "✅ Basic error handling initialized"
fi

echo
echo "📊 Testing structured logging..."

# Demonstrate structured logging
if declare -f log_structured >/dev/null 2>&1; then
    log_structured "INFO" "This is a structured log message" \
        "component=demo" \
        "feature=structured_logging" \
        "importance=high"
else
    log "This is a basic log message"
fi

echo
echo "🔄 Testing enhanced AWS logging..."

# Demonstrate enhanced AWS logging
success "Deployment completed successfully" "45.2" "instances=3,cost=0.45"
warning "Instance type not optimal" "PERFORMANCE" "true"
error "AWS API rate limit exceeded" "AWS" "Implement exponential backoff and retry"

echo
echo "⏱️  Testing performance monitoring..."

# Demonstrate performance monitoring
if declare -f profile_execution >/dev/null 2>&1; then
    echo "Running performance-monitored operation..."
    profile_execution "demo_sleep" sleep 1
    
    echo "Generating performance report..."
    local report_file
    report_file=$(generate_performance_report)
    echo "📊 Performance report saved to: $report_file"
else
    echo "⚠️  Performance monitoring not available"
fi

echo
echo "🔍 Testing AWS error parsing..."

# Demonstrate AWS error parsing
if declare -f parse_aws_error >/dev/null 2>&1; then
    source "$PROJECT_ROOT/lib/aws-api-error-handling.sh" 2>/dev/null
    
    echo "Analyzing sample AWS errors..."
    
    # Test various AWS error patterns
    local aws_errors=(
        "An error occurred (InvalidUserID.NotFound) when calling the DescribeInstances operation"
        "An error occurred (Throttling) when calling the RunInstances operation: Rate exceeded"
        "An error occurred (InsufficientInstanceCapacity) when calling the RunInstances operation"
        "An error occurred (AccessDenied) when calling the CreateSecurityGroup operation"
    )
    
    for aws_error in "${aws_errors[@]}"; do
        echo "  Error: $aws_error"
        local analysis
        analysis=$(parse_aws_error "$aws_error" "demo_command" 1)
        local error_type
        error_type=$(echo "$analysis" | grep '"error_type"' | cut -d: -f2 | tr -d ' ,"')
        local is_retryable
        is_retryable=$(echo "$analysis" | grep '"is_retryable"' | cut -d: -f2 | tr -d ' ,"')
        echo "    → Type: $error_type, Retryable: $is_retryable"
    done
else
    echo "⚠️  AWS error parsing not available"
fi

echo
echo "🧪 Testing intelligent retry mechanism..."

# Demonstrate intelligent retry
if declare -f aws_retry_with_intelligence >/dev/null 2>&1; then
    echo "Testing successful operation..."
    local result
    result=$(AWS_OPERATION_NAME="demo_success" aws_retry_with_intelligence echo "Success!")
    echo "Result: $result"
    
    echo "Testing failing operation (will demonstrate retry logic)..."
    AWS_OPERATION_NAME="demo_failure" aws_retry_with_intelligence sh -c 'echo "Simulated failure" >&2; exit 1' 2>/dev/null || echo "Operation failed as expected"
else
    echo "⚠️  Intelligent retry not available"
fi

echo
echo "📋 Testing error analytics..."

# Generate some sample errors for analytics
log_error "Sample network error" "Connection timeout" 1 "NETWORK" "Check network connectivity"
log_error "Sample AWS error" "Rate limiting" 1 "AWS" "Implement exponential backoff"
log_error "Sample validation error" "Invalid parameter" 1 "VALIDATION" "Check input parameters"

echo
echo "📈 Generating error report..."

# Generate comprehensive error report
local error_report
error_report=$(generate_error_report)
echo "📊 Error report generated: $error_report"

echo
echo "🏁 Demo completed successfully!"
echo
echo "Summary:"
echo "  - Enhanced error handling: $(declare -f init_enhanced_error_handling >/dev/null 2>&1 && echo "✅ Available" || echo "❌ Not available")"
echo "  - Structured logging: $(declare -f log_structured >/dev/null 2>&1 && echo "✅ Available" || echo "❌ Not available")"
echo "  - Performance monitoring: $(declare -f profile_execution >/dev/null 2>&1 && echo "✅ Available" || echo "❌ Not available")"
echo "  - AWS error parsing: $(declare -f parse_aws_error >/dev/null 2>&1 && echo "✅ Available" || echo "❌ Not available")"
echo "  - Intelligent retry: $(declare -f aws_retry_with_intelligence >/dev/null 2>&1 && echo "✅ Available" || echo "❌ Not available")"
echo
echo "Check the following files for detailed output:"
echo "  - Error log: $ERROR_LOG_FILE"
echo "  - Error report: $error_report"
if declare -f generate_performance_report >/dev/null 2>&1; then
    echo "  - Performance report: Available via generate_performance_report function"
fi

echo
echo "🎉 Enhanced error handling demonstration complete!"