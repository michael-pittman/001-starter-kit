#!/bin/bash
# =============================================================================
# Failsafe Recovery and Rollback Mechanisms
# Comprehensive error recovery and system restoration capabilities
# =============================================================================

# Prevent multiple sourcing
[ -n "${_FAILSAFE_RECOVERY_SH_LOADED:-}" ] && return 0
_FAILSAFE_RECOVERY_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/os-compatibility.sh"

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

readonly FAILSAFE_VERSION="1.0.0"
readonly BACKUP_DIR="/opt/geusmaker-backups"
readonly RECOVERY_LOG="/var/log/geusmaker-recovery.log"
readonly SYSTEM_STATE_FILE="/tmp/geusmaker-system-state.json"
readonly MAX_RECOVERY_ATTEMPTS=3
readonly RECOVERY_TIMEOUT=300  # 5 minutes

# Recovery states
readonly RECOVERY_STATES=(
    "initial"
    "os_detected"
    "packages_updated"
    "bash_installed"
    "dependencies_installed"
    "services_configured"
    "deployment_ready"
)

# Critical system paths to backup
readonly CRITICAL_PATHS=(
    "/etc/passwd"
    "/etc/group"
    "/etc/hosts"
    "/etc/resolv.conf"
    "/etc/ssh/sshd_config"
    "/etc/profile"
    "/etc/shells"
    "/etc/apt/sources.list"
    "/etc/yum.repos.d"
    "/etc/zypper/repos.d"
)

# =============================================================================
# SYSTEM STATE MANAGEMENT
# =============================================================================

# Initialize recovery system
init_recovery_system() {
    log "Initializing failsafe recovery system v$FAILSAFE_VERSION..." >&2
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
    
    # Initialize recovery log
    cat > "$RECOVERY_LOG" << EOF
Failsafe Recovery System Log
============================
Started: $(date)
Version: $FAILSAFE_VERSION
Host: $(uname -a)

EOF
    
    # Create initial system state snapshot
    create_system_state_snapshot "initial"
    
    # Setup signal handlers for emergency recovery
    trap 'emergency_recovery_handler $?' EXIT
    trap 'signal_recovery_handler SIGINT' INT
    trap 'signal_recovery_handler SIGTERM' TERM
    
    log "✓ Failsafe recovery system initialized" >&2
}

# Create system state snapshot
create_system_state_snapshot() {
    local state_name="${1:-unknown}"
    local timestamp=$(date +%s)
    local backup_subdir="$BACKUP_DIR/state-$state_name-$timestamp"
    
    echo "Creating system state snapshot: $state_name" >&2
    
    # Create snapshot directory
    mkdir -p "$backup_subdir"
    
    # Backup critical system files
    backup_critical_files "$backup_subdir"
    
    # Record system information
    record_system_info "$backup_subdir"
    
    # Update system state file
    cat > "$SYSTEM_STATE_FILE" << EOF
{
    "state": "$state_name",
    "timestamp": $timestamp,
    "backup_dir": "$backup_subdir",
    "os_id": "${OS_ID:-unknown}",
    "os_version": "${OS_VERSION:-unknown}",
    "bash_version": "$(get_bash_version 2>/dev/null || echo unknown)",
    "package_manager": "$(get_package_manager 2>/dev/null || echo unknown)"
}
EOF
    
    echo "✓ System state snapshot created: $backup_subdir" >&2
}

# Backup critical system files
backup_critical_files() {
    local backup_dir="$1"
    local files_backup_dir="$backup_dir/files"
    
    mkdir -p "$files_backup_dir"
    
    echo "Backing up critical system files..." >&2
    
    for path in "${CRITICAL_PATHS[@]}"; do
        if [ -e "$path" ]; then
            # Create directory structure
            local dest_dir="$files_backup_dir$(dirname "$path")"
            mkdir -p "$dest_dir"
            
            # Copy file/directory
            if [ -d "$path" ]; then
                cp -r "$path" "$dest_dir/" 2>/dev/null || true
            else
                cp "$path" "$dest_dir/" 2>/dev/null || true
            fi
            
            echo "Backed up: $path" >&2
        fi
    done
    
    # Backup package manager state
    backup_package_manager_state "$backup_dir"
}

# Backup package manager state
backup_package_manager_state() {
    local backup_dir="$1"
    local pkg_mgr
    pkg_mgr=$(get_package_manager 2>/dev/null || echo "unknown")
    
    echo "Backing up package manager state..." >&2
    
    case "$pkg_mgr" in
        apt)
            # Backup installed packages list
            dpkg --get-selections > "$backup_dir/apt-packages.txt" 2>/dev/null || true
            apt-mark showhold > "$backup_dir/apt-holds.txt" 2>/dev/null || true
            cp -r /etc/apt "$backup_dir/apt-config" 2>/dev/null || true
            ;;
        yum)
            yum list installed > "$backup_dir/yum-packages.txt" 2>/dev/null || true
            cp -r /etc/yum.repos.d "$backup_dir/yum-repos" 2>/dev/null || true
            ;;
        dnf)
            dnf list installed > "$backup_dir/dnf-packages.txt" 2>/dev/null || true
            cp -r /etc/yum.repos.d "$backup_dir/dnf-repos" 2>/dev/null || true
            ;;
        zypper)
            zypper se -i > "$backup_dir/zypper-packages.txt" 2>/dev/null || true
            cp -r /etc/zypper "$backup_dir/zypper-config" 2>/dev/null || true
            ;;
    esac
}

# Record system information
record_system_info() {
    local backup_dir="$1"
    local info_file="$backup_dir/system-info.txt"
    
    echo "Recording system information..." >&2
    
    cat > "$info_file" << EOF
System Information Snapshot
===========================
Date: $(date)
Hostname: $(hostname)
Uptime: $(uptime)
Kernel: $(uname -a)
OS Release: $(cat /etc/os-release 2>/dev/null || echo "Not available")

Memory Information:
$(free -h 2>/dev/null || echo "Not available")

Disk Information:
$(df -h 2>/dev/null || echo "Not available")

Network Interfaces:
$(ip addr show 2>/dev/null || ifconfig 2>/dev/null || echo "Not available")

Process List:
$(ps aux 2>/dev/null | head -20 || echo "Not available")

Environment Variables:
$(env | sort 2>/dev/null || echo "Not available")

Bash Version:
$(bash --version 2>/dev/null || echo "Not available")

Package Manager:
$(get_package_manager 2>/dev/null || echo "Not available")

EOF
}

# =============================================================================
# RECOVERY MECHANISMS
# =============================================================================

# Attempt to recover from failure
attempt_recovery() {
    local failure_point="${1:-unknown}"
    local error_code="${2:-1}"
    local recovery_attempt="${3:-1}"
    
    echo "Attempting recovery from failure at: $failure_point (attempt $recovery_attempt)" >&2
    
    # Log recovery attempt
    cat >> "$RECOVERY_LOG" << EOF
[$(date)] Recovery attempt $recovery_attempt
Failure point: $failure_point
Error code: $error_code
Current state: $(get_current_state)

EOF
    
    case "$failure_point" in
        "os_detection")
            recover_os_detection
            ;;
        "package_update")
            recover_package_manager
            ;;
        "bash_installation")
            recover_bash_installation
            ;;
        "package_installation")
            recover_package_installation
            ;;
        "service_configuration")
            recover_service_configuration
            ;;
        *)
            generic_recovery "$failure_point" "$error_code"
            ;;
    esac
}

# Recover from OS detection failures
recover_os_detection() {
    echo "Recovering from OS detection failure..." >&2
    
    # Force manual OS detection
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        export OS_ID="${ID:-unknown}"
        export OS_VERSION="${VERSION_ID:-unknown}"
        export OS_NAME="${NAME:-unknown}"
        
        # Determine family manually
        case "$OS_ID" in
            ubuntu|debian) export OS_FAMILY="debian" ;;
            centos|rhel|rocky|almalinux|fedora) export OS_FAMILY="redhat" ;;
            amzn|amazonlinux) export OS_FAMILY="amazon" ;;
            *) export OS_FAMILY="unknown" ;;
        esac
        
        echo "✓ Manual OS detection completed: $OS_ID $OS_VERSION" >&2
        return 0
    fi
    
    # Fallback to kernel detection
    export OS_ID="linux"
    export OS_VERSION="unknown"
    export OS_NAME="Generic Linux"
    export OS_FAMILY="linux"
    
    echo "✓ Fallback OS detection completed" >&2
    return 0
}

# Recover from package manager failures
recover_package_manager() {
    echo "Recovering from package manager failure..." >&2
    
    local pkg_mgr
    pkg_mgr=$(get_package_manager)
    
    case "$pkg_mgr" in
        apt)
            # Clean and fix APT
            apt-get clean || true
            dpkg --configure -a || true
            apt-get update --fix-missing || true
            ;;
        yum)
            # Clean YUM cache
            yum clean all || true
            yum makecache || true
            ;;
        dnf)
            # Clean DNF cache
            dnf clean all || true
            dnf makecache || true
            ;;
        *)
            echo "No specific recovery for package manager: $pkg_mgr" >&2
            ;;
    esac
    
    echo "✓ Package manager recovery completed" >&2
    return 0
}

# Recover from bash installation failures
recover_bash_installation() {
    echo "Recovering from bash installation failure..." >&2
    
    # Try to restore from backup
    local current_state
    current_state=$(get_current_state)
    
    if [ -f "$SYSTEM_STATE_FILE" ]; then
        local backup_dir
        backup_dir=$(jq -r '.backup_dir' "$SYSTEM_STATE_FILE" 2>/dev/null || echo "")
        
        if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
            echo "Restoring bash configuration from backup..." >&2
            
            # Restore /etc/shells if backed up
            if [ -f "$backup_dir/files/etc/shells" ]; then
                cp "$backup_dir/files/etc/shells" /etc/shells || true
            fi
            
            # Restore profile configurations
            if [ -d "$backup_dir/files/etc/profile.d" ]; then
                cp -r "$backup_dir/files/etc/profile.d"/* /etc/profile.d/ 2>/dev/null || true
            fi
        fi
    fi
    
    # Ensure basic bash is available
    if ! command -v bash >/dev/null 2>&1; then
        echo "Installing basic bash package..." >&2
        local pkg_mgr
        pkg_mgr=$(get_package_manager)
        
        case "$pkg_mgr" in
            apt) apt-get install -y bash || true ;;
            yum) yum install -y bash || true ;;
            dnf) dnf install -y bash || true ;;
            zypper) zypper install -y bash || true ;;
        esac
    fi
    
    echo "✓ Bash recovery completed" >&2
    return 0
}

# Recover from package installation failures
recover_package_installation() {
    echo "Recovering from package installation failure..." >&2
    
    # Try to install minimal essential packages
    local essential_packages="curl wget"
    local pkg_mgr
    pkg_mgr=$(get_package_manager)
    
    echo "Installing minimal essential packages..." >&2
    for package in $essential_packages; do
        echo "Attempting to install: $package" >&2
        case "$pkg_mgr" in
            apt) apt-get install -y "$package" || true ;;
            yum) yum install -y "$package" || true ;;
            dnf) dnf install -y "$package" || true ;;
            zypper) zypper install -y "$package" || true ;;
        esac
    done
    
    echo "✓ Package installation recovery completed" >&2
    return 0
}

# Recover from service configuration failures
recover_service_configuration() {
    echo "Recovering from service configuration failure..." >&2
    
    # Check and recover Docker if needed
    if command -v docker >/dev/null 2>&1; then
        if ! systemctl is-active --quiet docker; then
            echo "Attempting to restart Docker..." >&2
            systemctl restart docker || true
        fi
    fi
    
    # Check disk space and clean if needed
    local available_space
    available_space=$(df / | awk 'NR==2 {print $4}')
    local min_space=1048576  # 1GB in KB
    
    if [ "$available_space" -lt "$min_space" ]; then
        echo "Low disk space detected, attempting cleanup..." >&2
        
        # Clean package caches
        case "$(get_package_manager)" in
            apt) apt-get clean || true ;;
            yum) yum clean all || true ;;
            dnf) dnf clean all || true ;;
        esac
        
        # Clean temporary files
        find /tmp -type f -atime +1 -delete 2>/dev/null || true
        find /var/tmp -type f -atime +1 -delete 2>/dev/null || true
    fi
    
    echo "✓ Service configuration recovery completed" >&2
    return 0
}

# Generic recovery procedure
generic_recovery() {
    local failure_point="$1"
    local error_code="$2"
    
    echo "Performing generic recovery for: $failure_point" >&2
    
    # Basic system checks and fixes
    check_and_fix_permissions
    check_and_fix_disk_space
    check_and_fix_network
    
    echo "✓ Generic recovery completed" >&2
    return 0
}

# =============================================================================
# SYSTEM CHECKS AND FIXES
# =============================================================================

# Check and fix file permissions
check_and_fix_permissions() {
    echo "Checking and fixing critical file permissions..." >&2
    
    # Fix common permission issues
    chmod 644 /etc/passwd /etc/group /etc/hosts 2>/dev/null || true
    chmod 600 /etc/shadow 2>/dev/null || true
    chmod 755 /bin /usr/bin /usr/local/bin 2>/dev/null || true
    chmod 755 /etc/profile.d/*.sh 2>/dev/null || true
    
    echo "✓ Permission check completed" >&2
}

# Check and fix disk space issues
check_and_fix_disk_space() {
    echo "Checking disk space..." >&2
    
    local available_space
    available_space=$(df / | awk 'NR==2 {print $4}')
    local min_space=1048576  # 1GB in KB
    
    if [ "$available_space" -lt "$min_space" ]; then
        echo "WARNING: Low disk space detected ($(($available_space/1024))MB available)" >&2
        
        # Attempt cleanup
        echo "Attempting disk cleanup..." >&2
        
        # Clean logs
        find /var/log -name "*.log" -size +100M -exec truncate -s 10M {} \; 2>/dev/null || true
        
        # Clean package caches
        case "$(get_package_manager)" in
            apt) apt-get clean || true ;;
            yum) yum clean all || true ;;
            dnf) dnf clean all || true ;;
        esac
        
        echo "✓ Disk cleanup attempted" >&2
    else
        echo "✓ Disk space sufficient ($(($available_space/1024/1024))GB available)" >&2
    fi
}

# Check and fix network connectivity
check_and_fix_network() {
    echo "Checking network connectivity..." >&2
    
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        echo "✓ Network connectivity confirmed" >&2
    else
        echo "WARNING: Network connectivity issues detected" >&2
        
        # Attempt to restart network services
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart network-manager 2>/dev/null || true
            systemctl restart networking 2>/dev/null || true
        fi
        
        echo "✓ Network restart attempted" >&2
    fi
}

# =============================================================================
# ROLLBACK MECHANISMS
# =============================================================================

# Rollback to previous state
rollback_to_state() {
    local target_state="${1:-initial}"
    
    echo "Rolling back to state: $target_state" >&2
    
    # Find backup for target state
    local backup_dirs
    backup_dirs=($(find "$BACKUP_DIR" -type d -name "state-$target_state-*" | sort -r))
    
    if [ ${#backup_dirs[@]} -eq 0 ]; then
        echo "ERROR: No backup found for state: $target_state" >&2
        return 1
    fi
    
    local latest_backup="${backup_dirs[0]}"
    echo "Using backup: $latest_backup" >&2
    
    # Restore system files
    restore_system_files "$latest_backup"
    
    # Restore package manager state
    restore_package_manager_state "$latest_backup"
    
    echo "✓ Rollback to $target_state completed" >&2
    
    # Log rollback
    cat >> "$RECOVERY_LOG" << EOF
[$(date)] Rollback completed
Target state: $target_state
Backup used: $latest_backup

EOF
}

# Restore system files from backup
restore_system_files() {
    local backup_dir="$1"
    local files_backup_dir="$backup_dir/files"
    
    if [ ! -d "$files_backup_dir" ]; then
        echo "WARNING: No files backup found in: $backup_dir" >&2
        return 1
    fi
    
    echo "Restoring system files from backup..." >&2
    
    # Restore critical files
    for path in "${CRITICAL_PATHS[@]}"; do
        local backup_path="$files_backup_dir$path"
        if [ -e "$backup_path" ]; then
            echo "Restoring: $path" >&2
            if [ -d "$backup_path" ]; then
                cp -r "$backup_path" "$(dirname "$path")/" || true
            else
                cp "$backup_path" "$path" || true
            fi
        fi
    done
    
    echo "✓ System files restored" >&2
}

# Restore package manager state
restore_package_manager_state() {
    local backup_dir="$1"
    local pkg_mgr
    pkg_mgr=$(get_package_manager)
    
    echo "Restoring package manager state..." >&2
    
    case "$pkg_mgr" in
        apt)
            if [ -f "$backup_dir/apt-packages.txt" ]; then
                echo "Restoring APT package selections..." >&2
                dpkg --set-selections < "$backup_dir/apt-packages.txt" || true
            fi
            
            if [ -f "$backup_dir/apt-holds.txt" ]; then
                echo "Restoring APT package holds..." >&2
                while read -r package; do
                    apt-mark hold "$package" 2>/dev/null || true
                done < "$backup_dir/apt-holds.txt"
            fi
            
            if [ -d "$backup_dir/apt-config" ]; then
                echo "Restoring APT configuration..." >&2
                cp -r "$backup_dir/apt-config"/* /etc/apt/ || true
            fi
            ;;
        yum|dnf)
            if [ -d "$backup_dir/yum-repos" ] || [ -d "$backup_dir/dnf-repos" ]; then
                echo "Restoring repository configuration..." >&2
                local repos_backup="$backup_dir/yum-repos"
                [ -d "$backup_dir/dnf-repos" ] && repos_backup="$backup_dir/dnf-repos"
                cp -r "$repos_backup"/* /etc/yum.repos.d/ || true
            fi
            ;;
    esac
    
    echo "✓ Package manager state restored" >&2
}

# =============================================================================
# EMERGENCY RECOVERY
# =============================================================================

# Emergency recovery handler for script exit
emergency_recovery_handler() {
    local exit_code="$1"
    
    # Only trigger on non-zero exit codes
    if [ "$exit_code" -ne 0 ]; then
        echo "Emergency recovery triggered (exit code: $exit_code)" >&2
        
        # Log emergency
        cat >> "$RECOVERY_LOG" << EOF
[$(date)] EMERGENCY RECOVERY TRIGGERED
Exit code: $exit_code
Current working directory: $(pwd)
Current user: $(whoami)
Process ID: $$

EOF
        
        # Attempt basic recovery
        basic_emergency_recovery
    fi
}

# Signal recovery handler
signal_recovery_handler() {
    local signal="$1"
    
    echo "Signal recovery triggered: $signal" >&2
    
    # Log signal
    cat >> "$RECOVERY_LOG" << EOF
[$(date)] SIGNAL RECOVERY TRIGGERED
Signal: $signal
Process ID: $$

EOF
    
    # Graceful shutdown
    basic_emergency_recovery
    exit 1
}

# Basic emergency recovery
basic_emergency_recovery() {
    echo "Performing basic emergency recovery..." >&2
    
    # Ensure essential commands are available
    if ! command -v bash >/dev/null 2>&1; then
        echo "CRITICAL: bash not available" >&2
    fi
    
    if ! command -v ls >/dev/null 2>&1; then
        echo "CRITICAL: ls not available" >&2
    fi
    
    # Check system basics
    echo "System status at emergency recovery:" >&2
    echo "  Current directory: $(pwd)" >&2
    echo "  Available space: $(df / | awk 'NR==2 {print $4}')KB" >&2
    echo "  Load average: $(uptime)" >&2
    
    # Create emergency marker
    echo "Emergency recovery executed at $(date)" > /tmp/geusmaker-emergency-recovery
    
    echo "✓ Basic emergency recovery completed" >&2
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get current system state
get_current_state() {
    if [ -f "$SYSTEM_STATE_FILE" ]; then
        jq -r '.state' "$SYSTEM_STATE_FILE" 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# Update current state
update_current_state() {
    local new_state="$1"
    
    if [ -f "$SYSTEM_STATE_FILE" ]; then
        local temp_file=$(mktemp)
        jq --arg state "$new_state" '.state = $state' "$SYSTEM_STATE_FILE" > "$temp_file" && \
        mv "$temp_file" "$SYSTEM_STATE_FILE"
    fi
    
    echo "State updated to: $new_state" >&2
}

# Check if recovery is needed
needs_recovery() {
    local check_type="${1:-basic}"
    
    case "$check_type" in
        "basic")
            # Check if essential commands are available
            ! command -v bash >/dev/null 2>&1 || \
            ! command -v ls >/dev/null 2>&1 || \
            ! command -v cat >/dev/null 2>&1
            ;;
        "disk_space")
            local available_space
            available_space=$(df / | awk 'NR==2 {print $4}')
            [ "$available_space" -lt 524288 ]  # Less than 512MB
            ;;
        "network")
            ! ping -c 1 8.8.8.8 >/dev/null 2>&1
            ;;
        *)
            false
            ;;
    esac
}

# Show recovery status
show_recovery_status() {
    echo "=== Failsafe Recovery Status ==="
    echo "Recovery system version: $FAILSAFE_VERSION"
    echo "Current state: $(get_current_state)"
    echo "Backup directory: $BACKUP_DIR"
    echo "Recovery log: $RECOVERY_LOG"
    echo ""
    
    echo "Available backups:"
    if [ -d "$BACKUP_DIR" ]; then
        find "$BACKUP_DIR" -type d -name "state-*" | sort -r | head -5
    else
        echo "  No backups found"
    fi
    echo ""
    
    echo "System health checks:"
    echo "  Bash available: $(command -v bash >/dev/null 2>&1 && echo "✓ YES" || echo "✗ NO")"
    echo "  Disk space: $(df / | awk 'NR==2 {print int($4/1024)}')MB available"
    echo "  Network: $(ping -c 1 8.8.8.8 >/dev/null 2>&1 && echo "✓ OK" || echo "✗ FAIL")"
    echo "  Recovery needed: $(needs_recovery && echo "YES" || echo "NO")"
    echo ""
    
    if [ -f "$RECOVERY_LOG" ]; then
        echo "Recent recovery events:"
        tail -10 "$RECOVERY_LOG" 2>/dev/null || echo "  No recent events"
    fi
}

# Clean old backups
clean_old_backups() {
    local max_age_days="${1:-7}"
    
    echo "Cleaning backups older than $max_age_days days..." >&2
    
    if [ -d "$BACKUP_DIR" ]; then
        find "$BACKUP_DIR" -type d -name "state-*" -mtime +$max_age_days -exec rm -rf {} \; 2>/dev/null || true
        echo "✓ Old backups cleaned" >&2
    fi
}

# =============================================================================
# MAIN RECOVERY INTERFACE
# =============================================================================

# Main recovery function
perform_recovery() {
    local recovery_type="${1:-auto}"
    local target_state="${2:-}"
    
    echo "Starting recovery procedure: $recovery_type" >&2
    
    case "$recovery_type" in
        "auto")
            # Automatic recovery based on detected issues
            if needs_recovery "basic"; then
                attempt_recovery "basic_commands" 1
            elif needs_recovery "disk_space"; then
                attempt_recovery "disk_space" 1
            elif needs_recovery "network"; then
                attempt_recovery "network" 1
            else
                echo "No recovery needed" >&2
            fi
            ;;
        "rollback")
            if [ -n "$target_state" ]; then
                rollback_to_state "$target_state"
            else
                echo "ERROR: Target state required for rollback" >&2
                return 1
            fi
            ;;
        "emergency")
            basic_emergency_recovery
            ;;
        *)
            echo "ERROR: Unknown recovery type: $recovery_type" >&2
            return 1
            ;;
    esac
}