#!/bin/bash
# =============================================================================
# OS Compatibility Testing Script
# Quick testing and validation for local development
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source required libraries
source "$PROJECT_ROOT/lib/aws-deployment-common.sh"
source "$PROJECT_ROOT/lib/modules/instances/os-compatibility.sh"

# =============================================================================
# QUICK TESTS
# =============================================================================

# Quick OS detection test
test_os_detection_quick() {
    log "Testing OS detection..."
    
    if detect_os; then
        success "✓ OS Detection: $OS_ID $OS_VERSION ($OS_FAMILY)"
        return 0
    else
        error "✗ OS Detection failed"
        return 1
    fi
}

# Quick bash version test
test_bash_version_quick() {
    log "Testing bash version detection..."
    
    local current_version
    current_version=$(get_bash_version)
    
    if [ "$current_version" != "unknown" ]; then
        if check_bash_version "5.3"; then
            success "✓ Bash version meets requirements: $current_version"
        else
            log "⚠ Bash version may need upgrade: $current_version (required: 5.3+)"
        fi
        return 0
    else
        error "✗ Could not detect bash version"
        return 1
    fi
}

# Quick package manager test
test_package_manager_quick() {
    log "Testing package manager detection..."
    
    local pkg_mgr
    pkg_mgr=$(get_package_manager)
    
    if [ "$pkg_mgr" != "unknown" ]; then
        success "✓ Package manager detected: $pkg_mgr"
        return 0
    else
        error "✗ Could not detect package manager"
        return 1
    fi
}

# Test essential commands
test_essential_commands() {
    log "Testing essential commands availability..."
    
    local essential_commands=("curl" "wget" "git" "make" "gcc")
    local missing_commands=()
    
    for cmd in "${essential_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log "  ✓ $cmd: $(command -v "$cmd")"
        else
            log "  ✗ $cmd: not found"
            missing_commands+=("$cmd")
        fi
    done
    
    if [ ${#missing_commands[@]} -eq 0 ]; then
        success "✓ All essential commands available"
        return 0
    else
        log "⚠ Missing commands: ${missing_commands[*]}"
        return 1
    fi
}

# Test system resources
test_system_resources() {
    log "Testing system resources..."
    
    # Check disk space
    local available_space
    available_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=2097152  # 2GB in KB
    
    if [ "$available_space" -gt "$required_space" ]; then
        success "✓ Sufficient disk space: $(($available_space/1024/1024))GB available"
    else
        log "⚠ Limited disk space: $(($available_space/1024/1024))GB available (recommended: 2GB+)"
    fi
    
    # Check memory
    local available_memory
    available_memory=$(free -k | awk 'NR==2{print $2}')
    local required_memory=1048576  # 1GB in KB
    
    if [ "$available_memory" -gt "$required_memory" ]; then
        success "✓ Sufficient memory: $(($available_memory/1024/1024))GB total"
    else
        log "⚠ Limited memory: $(($available_memory/1024/1024))GB total (recommended: 1GB+)"
    fi
    
    # Check CPU cores
    local cpu_cores
    cpu_cores=$(nproc)
    
    if [ "$cpu_cores" -ge 2 ]; then
        success "✓ Sufficient CPU cores: $cpu_cores"
    else
        log "⚠ Limited CPU cores: $cpu_cores (recommended: 2+)"
    fi
    
    return 0
}

# Test network connectivity
test_network_connectivity() {
    log "Testing network connectivity..."
    
    # Test basic connectivity
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        success "✓ Internet connectivity available"
    else
        error "✗ No internet connectivity"
        return 1
    fi
    
    # Test specific hosts
    local test_hosts=("github.com" "ftp.gnu.org" "download.docker.com")
    local reachable_hosts=0
    
    for host in "${test_hosts[@]}"; do
        if ping -c 1 "$host" >/dev/null 2>&1; then
            log "  ✓ $host: reachable"
            reachable_hosts=$((reachable_hosts + 1))
        else
            log "  ✗ $host: unreachable"
        fi
    done
    
    if [ $reachable_hosts -eq ${#test_hosts[@]} ]; then
        success "✓ All test hosts reachable"
        return 0
    else
        log "⚠ $reachable_hosts/${#test_hosts[@]} test hosts reachable"
        return 1
    fi
}

# =============================================================================
# SIMULATION TESTS
# =============================================================================

# Simulate different OS environments
test_os_simulation() {
    log "Testing OS simulation scenarios..."
    
    local test_scenarios=(
        "ubuntu:22.04:debian"
        "amazonlinux:2:amazon"
        "rocky:9:redhat"
        "debian:12:debian"
    )
    
    local original_os_id="${OS_ID:-}"
    local original_os_version="${OS_VERSION:-}"
    local original_os_family="${OS_FAMILY:-}"
    
    for scenario in "${test_scenarios[@]}"; do
        local os_id=$(echo "$scenario" | cut -d: -f1)
        local os_version=$(echo "$scenario" | cut -d: -f2)
        local expected_family=$(echo "$scenario" | cut -d: -f3)
        
        # Simulate OS
        export OS_ID="$os_id"
        export OS_VERSION="$os_version"
        export OS_FAMILY="$expected_family"
        
        # Test package manager detection
        local pkg_mgr
        pkg_mgr=$(get_package_manager 2>/dev/null || echo "unknown")
        
        log "  Scenario $os_id:$os_version -> family:$expected_family, pkg_mgr:$pkg_mgr"
    done
    
    # Restore original values
    export OS_ID="$original_os_id"
    export OS_VERSION="$original_os_version"
    export OS_FAMILY="$original_os_family"
    
    success "✓ OS simulation tests completed"
    return 0
}

# =============================================================================
# MAIN TEST EXECUTION
# =============================================================================

run_quick_tests() {
    log "Running quick OS compatibility tests..."
    echo ""
    
    local failed_tests=0
    
    # Run individual tests
    test_os_detection_quick || failed_tests=$((failed_tests + 1))
    echo ""
    
    test_bash_version_quick || failed_tests=$((failed_tests + 1))
    echo ""
    
    test_package_manager_quick || failed_tests=$((failed_tests + 1))
    echo ""
    
    test_essential_commands || failed_tests=$((failed_tests + 1))
    echo ""
    
    test_system_resources || failed_tests=$((failed_tests + 1))
    echo ""
    
    test_network_connectivity || failed_tests=$((failed_tests + 1))
    echo ""
    
    test_os_simulation || failed_tests=$((failed_tests + 1))
    echo ""
    
    # Summary
    if [ $failed_tests -eq 0 ]; then
        success "🎉 All quick tests passed!"
        return 0
    else
        error "❌ $failed_tests test(s) failed"
        return 1
    fi
}

# Show system information
show_system_info() {
    cat << EOF
=== System Information ===
Hostname: $(hostname)
Kernel: $(uname -a)
Uptime: $(uptime)

OS Detection:
  ID: ${OS_ID:-not detected}
  Version: ${OS_VERSION:-not detected}  
  Name: ${OS_NAME:-not detected}
  Family: ${OS_FAMILY:-not detected}

Bash Information:
  Path: $(command -v bash)
  Version: $(get_bash_version)
  Available versions:
$(find /usr /opt -name bash -type f 2>/dev/null | while read -r bash_path; do
    if [ -x "$bash_path" ]; then
        local version=$("$bash_path" --version 2>/dev/null | head -n1 | sed 's/.*version \([0-9]\+\.[0-9]\+\).*/\1/' || echo "unknown")
        echo "    $bash_path: $version"
    fi
done)

Package Manager: $(get_package_manager)

System Resources:
  CPU Cores: $(nproc)
  Memory: $(free -h | awk 'NR==2{print $2}')
  Disk Space: $(df -h / | awk 'NR==2{print $4}') available

Network:
  Connectivity: $(ping -c 1 8.8.8.8 >/dev/null 2>&1 && echo "✓ OK" || echo "✗ FAIL")
  DNS: $(nslookup google.com >/dev/null 2>&1 && echo "✓ OK" || echo "✗ FAIL")

EOF
}

# =============================================================================
# CLI INTERFACE
# =============================================================================

show_usage() {
    cat << EOF
OS Compatibility Testing Script

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose output
    -i, --info          Show system information only
    -q, --quick         Run quick tests (default)
    -f, --full          Run full validation (calls validate-os-compatibility.sh)

Examples:
    $0                  # Run quick tests
    $0 --info           # Show system information
    $0 --full           # Run comprehensive validation
    $0 -v --quick       # Run quick tests with verbose output

EOF
}

main() {
    local mode="quick"
    local verbose=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                return 0
                ;;
            -v|--verbose)
                verbose=true
                set -x
                shift
                ;;
            -i|--info)
                mode="info"
                shift
                ;;
            -q|--quick)
                mode="quick"
                shift
                ;;
            -f|--full)
                mode="full"
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                return 1
                ;;
        esac
    done
    
    # Initialize OS compatibility
    detect_os >/dev/null 2>&1 || true
    
    case "$mode" in
        "info")
            show_system_info
            ;;
        "quick")
            show_system_info
            echo ""
            run_quick_tests
            ;;
        "full")
            log "Running full OS compatibility validation..."
            "$SCRIPT_DIR/validate-os-compatibility.sh" all
            ;;
        *)
            error "Unknown mode: $mode"
            return 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi