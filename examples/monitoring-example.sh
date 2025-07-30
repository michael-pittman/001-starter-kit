#!/usr/bin/env bash
# =============================================================================
# Monitoring System Usage Example
# Demonstrates how to use the GeuseMaker monitoring system
# =============================================================================

set -euo pipefail

# Setup paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$PROJECT_ROOT/lib"

# Source monitoring integration
source "$LIB_DIR/modules/monitoring/integration.sh"

# =============================================================================
# EXAMPLE 1: Basic Monitoring
# =============================================================================

basic_monitoring_example() {
    echo "=== Basic Monitoring Example ==="
    
    # Initialize monitoring with minimal profile
    init_deployment_monitoring "example-stack" "minimal"
    
    # Log some events
    log_info "Starting example deployment" "EXAMPLE"
    log_structured_event "INFO" "Deployment initialized" "example" "init"
    
    # Record metrics
    record_performance_metric "example.duration" "150" "gauge" "ms"
    record_performance_metric "example.success_rate" "95.5" "gauge" "percent"
    
    # Create an alert
    create_alert "example_warning" "warning" "High latency detected" "example" \
        '{"latency": 150, "threshold": 100}'
    
    # Cleanup
    cleanup_deployment_monitoring
    
    echo "Basic monitoring example completed"
}

# =============================================================================
# EXAMPLE 2: Comprehensive Monitoring
# =============================================================================

comprehensive_monitoring_example() {
    echo -e "\n=== Comprehensive Monitoring Example ==="
    
    # Initialize with comprehensive profile
    export MONITORING_OUTPUT_DIR="/tmp/monitoring_example_$$"
    init_deployment_monitoring "prod-stack" "comprehensive"
    
    # Pre-deployment monitoring
    monitor_pre_deployment "prod-stack"
    
    # Simulate deployment phases
    echo "Simulating deployment phases..."
    
    # Infrastructure phase
    monitor_deployment_phase "infrastructure" "start"
    sleep 1
    log_infrastructure_event "vpc" "create" "vpc-123" "success" '{"cidr": "10.0.0.0/16"}'
    log_infrastructure_event "subnet" "create" "subnet-456" "success" '{"az": "us-east-1a"}'
    monitor_deployment_phase "infrastructure" "end"
    
    # Compute phase
    monitor_deployment_phase "compute" "start"
    sleep 1
    
    # Monitor AWS operation
    echo '{"InstanceId": "i-1234567890"}' | \
        monitor_aws_operation "run-instances" "instance" "" cat
    
    monitor_deployment_phase "compute" "end"
    
    # Application phase
    monitor_deployment_phase "application" "start"
    sleep 1
    
    # Monitor service health
    check_n8n_health() { echo "healthy"; }
    check_qdrant_health() { echo "healthy"; }
    check_ollama_health() { echo "healthy"; }
    check_crawl4ai_health() { echo "healthy"; }
    
    for service in n8n qdrant ollama crawl4ai; do
        monitor_service_health "$service" "healthy"
    done
    
    monitor_deployment_phase "application" "end"
    
    # Post-deployment
    monitor_post_deployment "success"
    
    echo "Comprehensive monitoring example completed"
    echo "Reports available in: $MONITORING_OUTPUT_DIR"
}

# =============================================================================
# EXAMPLE 3: Debug Monitoring
# =============================================================================

debug_monitoring_example() {
    echo -e "\n=== Debug Monitoring Example ==="
    
    # Initialize with debug profile
    export MONITORING_OUTPUT_DIR="/tmp/monitoring_debug_$$"
    init_deployment_monitoring "debug-stack" "debug"
    
    # Enable debug logging
    debug_log 1 "Basic debug message" "EXAMPLE"
    debug_log 2 "Detailed debug message" "EXAMPLE"
    debug_log 3 "Verbose debug message" "EXAMPLE"
    
    # Set breakpoint
    set_breakpoint "example_breakpoint" "true"
    
    # Function with debug instrumentation
    example_function() {
        debug_function_entry "$@"
        
        local result="Processing: $1"
        debug_var "result"
        
        # Check breakpoint (in real usage, this would pause)
        # check_breakpoint "example_breakpoint"
        
        debug_function_exit 0
        echo "$result"
    }
    
    # Call instrumented function
    example_function "test input"
    
    # Run diagnostics
    run_diagnostics "$MONITORING_OUTPUT_DIR/diagnostics.txt"
    
    # Create debug dump
    create_debug_dump "example_dump"
    
    echo "Debug monitoring example completed"
    echo "Debug output in: $MONITORING_OUTPUT_DIR"
}

# =============================================================================
# EXAMPLE 4: Real-time Dashboard
# =============================================================================

dashboard_example() {
    echo -e "\n=== Dashboard Example ==="
    
    # Initialize monitoring
    export MONITORING_OUTPUT_DIR="/tmp/monitoring_dashboard_$$"
    init_deployment_monitoring "dashboard-stack" "standard"
    
    # Create custom dashboard
    local dashboard_id=$(create_dashboard "deployment-monitor" "deployment")
    
    # Add custom widgets
    add_widget_to_dashboard "$dashboard_id" "custom_metrics" "Custom Metrics" "metrics"
    add_widget_to_dashboard "$dashboard_id" "error_log" "Recent Errors" "log_viewer"
    
    # Simulate some activity
    echo "Generating sample data..."
    for i in {1..10}; do
        log_structured_event "INFO" "Processing item $i" "dashboard" "example"
        record_performance_metric "dashboard.items_processed" "$i" "counter" "count"
        
        # Simulate occasional errors
        if [[ $((i % 3)) -eq 0 ]]; then
            log_structured_event "ERROR" "Error processing item $i" "dashboard" "error"
        fi
        
        sleep 0.5
    done
    
    # Render dashboard
    echo -e "\nRendering dashboard..."
    render_dashboard "$dashboard_id" "console"
    
    # Export dashboard
    export_dashboard "$dashboard_id" "$MONITORING_OUTPUT_DIR/dashboard.json" "json"
    
    echo -e "\nDashboard example completed"
    echo "Dashboard exported to: $MONITORING_OUTPUT_DIR/dashboard.json"
}

# =============================================================================
# EXAMPLE 5: Alerting and Analysis
# =============================================================================

alerting_example() {
    echo -e "\n=== Alerting and Analysis Example ==="
    
    # Initialize monitoring
    export MONITORING_OUTPUT_DIR="/tmp/monitoring_alerts_$$"
    init_deployment_monitoring "alert-stack" "comprehensive"
    
    # Define custom alert rules
    add_alert_rule "high_error_rate" "High Error Rate" "critical" \
        '{"condition": "error_rate > 20", "window": 60}'
    
    add_alert_rule "slow_response" "Slow Response Time" "warning" \
        '{"condition": "response_time > 1000", "window": 300}'
    
    # Generate events that trigger alerts
    echo "Simulating error conditions..."
    
    # Normal operation
    for i in {1..5}; do
        log_structured_event "INFO" "Request processed" "api" "request"
        record_performance_metric "api.response_time" "200" "gauge" "ms"
    done
    
    # Error spike
    for i in {1..10}; do
        log_structured_event "ERROR" "Request failed" "api" "error"
        record_performance_metric "api.response_time" "1500" "gauge" "ms"
    done
    
    # Evaluate alert rules
    evaluate_alert_rules '{"error_rate": 25, "response_time": 1500}'
    
    # Show active alerts
    echo -e "\nActive Alerts:"
    get_active_alerts | jq '.[] | {name, severity, message}'
    
    # Generate analysis report
    echo -e "\nGenerating analysis reports..."
    generate_aggregation_report "$MONITORING_OUTPUT_DIR/aggregation_report.txt"
    generate_performance_report "$MONITORING_OUTPUT_DIR/performance_report.txt"
    generate_alert_report "$MONITORING_OUTPUT_DIR/alert_report.txt"
    
    # Show insights
    echo -e "\nLog Analysis Insights:"
    analyze_log_patterns
    generate_insights
    
    echo -e "\nAlerting example completed"
    echo "Reports available in: $MONITORING_OUTPUT_DIR"
}

# =============================================================================
# MAIN MENU
# =============================================================================

show_menu() {
    echo ""
    echo "GeuseMaker Monitoring System Examples"
    echo "====================================="
    echo "1. Basic Monitoring"
    echo "2. Comprehensive Monitoring"
    echo "3. Debug Monitoring"
    echo "4. Real-time Dashboard"
    echo "5. Alerting and Analysis"
    echo "6. Run All Examples"
    echo "0. Exit"
    echo ""
}

run_all_examples() {
    basic_monitoring_example
    comprehensive_monitoring_example
    debug_monitoring_example
    dashboard_example
    alerting_example
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    while true; do
        show_menu
        read -p "Select an example (0-6): " choice
        
        case $choice in
            1) basic_monitoring_example ;;
            2) comprehensive_monitoring_example ;;
            3) debug_monitoring_example ;;
            4) dashboard_example ;;
            5) alerting_example ;;
            6) run_all_examples ;;
            0) echo "Exiting..."; exit 0 ;;
            *) echo "Invalid choice. Please try again." ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
fi