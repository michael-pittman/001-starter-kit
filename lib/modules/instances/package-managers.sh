#!/bin/bash
# =============================================================================
# Platform-Specific Package Management Handlers
# Comprehensive package installation and management across different OS platforms
# =============================================================================

# Prevent multiple sourcing
[ -n "${_PACKAGE_MANAGERS_SH_LOADED:-}" ] && return 0
_PACKAGE_MANAGERS_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/os-compatibility.sh"

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

readonly PKG_MGR_VERSION="1.0.0"
readonly MAX_INSTALL_ATTEMPTS=3
readonly PACKAGE_TIMEOUT=300  # 5 minutes
readonly UPDATE_TIMEOUT=600   # 10 minutes

# Package categories for GeuseMaker deployment
readonly ESSENTIAL_PACKAGES="curl wget git unzip ca-certificates"
readonly BUILD_PACKAGES="gcc make build-essential"
readonly NETWORK_PACKAGES="net-tools netstat-nat"
readonly MONITORING_PACKAGES="htop iotop sysstat"
readonly SECURITY_PACKAGES="fail2ban ufw"

# =============================================================================
# GENERIC PACKAGE MANAGER INTERFACE
# =============================================================================

# Update package lists with retry logic
update_package_lists() {
    local pkg_mgr="${1:-$(get_package_manager)}"
    local attempt=1
    
    echo "Updating package lists for $pkg_mgr..." >&2
    
    while [ $attempt -le $MAX_INSTALL_ATTEMPTS ]; do
        echo "Update attempt $attempt/$MAX_INSTALL_ATTEMPTS" >&2
        
        case "$pkg_mgr" in
            apt)
                if timeout $UPDATE_TIMEOUT apt_update_with_cleanup; then
                    echo "✓ Package lists updated successfully" >&2
                    return 0
                fi
                ;;
            yum)
                if timeout $UPDATE_TIMEOUT yum makecache; then
                    echo "✓ Package cache updated successfully" >&2
                    return 0
                fi
                ;;
            dnf)
                if timeout $UPDATE_TIMEOUT dnf makecache; then
                    echo "✓ Package cache updated successfully" >&2
                    return 0
                fi
                ;;
            zypper)
                if timeout $UPDATE_TIMEOUT zypper refresh; then
                    echo "✓ Package repositories refreshed successfully" >&2
                    return 0
                fi
                ;;
            pacman)
                if timeout $UPDATE_TIMEOUT pacman -Sy; then
                    echo "✓ Package databases synchronized successfully" >&2
                    return 0
                fi
                ;;
            *)
                echo "ERROR: Unknown package manager: $pkg_mgr" >&2
                return 1
                ;;
        esac
        
        echo "Update attempt $attempt failed, waiting before retry..." >&2
        sleep $((attempt * 5))  # Exponential backoff
        attempt=$((attempt + 1))
    done
    
    echo "ERROR: Failed to update package lists after $MAX_INSTALL_ATTEMPTS attempts" >&2
    return 1
}

# Install packages with retry logic and error handling
install_packages() {
    local pkg_mgr="${1:-$(get_package_manager)}"
    shift
    local packages=("$@")
    
    if [ ${#packages[@]} -eq 0 ]; then
        echo "ERROR: No packages specified for installation" >&2
        return 1
    fi
    
    echo "Installing packages: ${packages[*]}" >&2
    
    # Update package lists first
    if ! update_package_lists "$pkg_mgr"; then
        echo "WARNING: Package list update failed, continuing with installation" >&2
    fi
    
    # Install packages based on package manager
    case "$pkg_mgr" in
        apt)
            install_packages_apt "${packages[@]}"
            ;;
        yum)
            install_packages_yum "${packages[@]}"
            ;;
        dnf)
            install_packages_dnf "${packages[@]}"
            ;;
        zypper)
            install_packages_zypper "${packages[@]}"
            ;;
        pacman)
            install_packages_pacman "${packages[@]}"
            ;;
        *)
            echo "ERROR: Unsupported package manager: $pkg_mgr" >&2
            return 1
            ;;
    esac
}

# Check if packages are installed
check_packages_installed() {
    local pkg_mgr="${1:-$(get_package_manager)}"
    shift
    local packages=("$@")
    local all_installed=true
    
    for package in "${packages[@]}"; do
        if ! is_package_installed "$pkg_mgr" "$package"; then
            echo "Package not installed: $package" >&2
            all_installed=false
        fi
    done
    
    [ "$all_installed" = "true" ]
}

# Check if a single package is installed
is_package_installed() {
    local pkg_mgr="$1"
    local package="$2"
    
    case "$pkg_mgr" in
        apt)
            dpkg -l "$package" >/dev/null 2>&1
            ;;
        yum)
            yum list installed "$package" >/dev/null 2>&1
            ;;
        dnf)
            dnf list installed "$package" >/dev/null 2>&1
            ;;
        zypper)
            zypper se -i "$package" >/dev/null 2>&1
            ;;
        pacman)
            pacman -Q "$package" >/dev/null 2>&1
            ;;
        *)
            # Fallback to command availability check
            command -v "$package" >/dev/null 2>&1
            ;;
    esac
}

# =============================================================================
# APT (DEBIAN/UBUNTU) SPECIFIC FUNCTIONS
# =============================================================================

# Enhanced APT update with lock handling and cleanup
apt_update_with_cleanup() {
    export DEBIAN_FRONTEND=noninteractive
    
    # Wait for any existing APT processes to complete
    wait_for_apt_locks
    
    # Clean and update
    apt-get clean
    apt-get update
}

# Wait for APT locks to be released
wait_for_apt_locks() {
    local max_wait=600  # 10 minutes
    local wait_time=0
    
    echo "Checking for APT locks..." >&2
    
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
          pgrep -f "apt-get|dpkg|unattended-upgrade" >/dev/null 2>&1; do
        
        if [ $wait_time -ge $max_wait ]; then
            echo "Timeout waiting for APT locks, attempting to resolve..." >&2
            # Kill unattended upgrades that might be blocking
            pkill -f unattended-upgrade || true
            sleep 10
            break
        fi
        
        echo "APT is locked, waiting 15 seconds..." >&2
        sleep 15
        wait_time=$((wait_time + 15))
    done
    
    echo "APT locks released" >&2
}

# Install packages via APT with comprehensive error handling
install_packages_apt() {
    local packages=("$@")
    local failed_packages=()
    local installed_packages=()
    
    export DEBIAN_FRONTEND=noninteractive
    
    # Try bulk installation first
    echo "Attempting bulk installation of ${#packages[@]} packages..." >&2
    if apt-get install -y "${packages[@]}"; then
        echo "✓ Bulk installation successful" >&2
        return 0
    fi
    
    echo "Bulk installation failed, trying individual packages..." >&2
    
    # Install packages individually
    for package in "${packages[@]}"; do
        echo "Installing package: $package" >&2
        
        local attempt=1
        local package_installed=false
        
        while [ $attempt -le $MAX_INSTALL_ATTEMPTS ]; do
            if timeout $PACKAGE_TIMEOUT apt-get install -y "$package"; then
                installed_packages+=("$package")
                package_installed=true
                echo "✓ Successfully installed: $package" >&2
                break
            else
                echo "Installation attempt $attempt failed for: $package" >&2
                attempt=$((attempt + 1))
                
                if [ $attempt -le $MAX_INSTALL_ATTEMPTS ]; then
                    sleep $((attempt * 2))
                fi
            fi
        done
        
        if [ "$package_installed" != "true" ]; then
            failed_packages+=("$package")
            echo "✗ Failed to install: $package" >&2
        fi
    done
    
    # Report results
    if [ ${#installed_packages[@]} -gt 0 ]; then
        echo "Successfully installed ${#installed_packages[@]} packages: ${installed_packages[*]}" >&2
    fi
    
    if [ ${#failed_packages[@]} -gt 0 ]; then
        echo "Failed to install ${#failed_packages[@]} packages: ${failed_packages[*]}" >&2
        return 1
    fi
    
    return 0
}

# Configure APT repositories and sources
configure_apt_repositories() {
    local enable_universe="${1:-true}"
    local enable_multiverse="${2:-false}"
    local enable_backports="${3:-false}"
    
    echo "Configuring APT repositories..." >&2
    
    # Enable universe repository (Ubuntu)
    if [ "$enable_universe" = "true" ] && command -v add-apt-repository >/dev/null 2>&1; then
        add-apt-repository universe -y >/dev/null 2>&1 || true
    fi
    
    # Enable multiverse repository (Ubuntu)
    if [ "$enable_multiverse" = "true" ] && command -v add-apt-repository >/dev/null 2>&1; then
        add-apt-repository multiverse -y >/dev/null 2>&1 || true
    fi
    
    # Enable backports (Debian/Ubuntu)
    if [ "$enable_backports" = "true" ]; then
        local codename
        codename=$(lsb_release -sc 2>/dev/null || echo "")
        if [ -n "$codename" ]; then
            echo "deb http://deb.debian.org/debian $codename-backports main" > /etc/apt/sources.list.d/backports.list
        fi
    fi
    
    # Update after configuration changes
    apt_update_with_cleanup
}

# =============================================================================
# YUM (CENTOS/RHEL/AMAZON LINUX) SPECIFIC FUNCTIONS
# =============================================================================

# Install packages via YUM
install_packages_yum() {
    local packages=("$@")
    local failed_packages=()
    local installed_packages=()
    
    # Enable EPEL repository if not present
    enable_epel_repository
    
    # Try bulk installation first
    echo "Attempting bulk installation of ${#packages[@]} packages..." >&2
    if yum install -y "${packages[@]}"; then
        echo "✓ Bulk installation successful" >&2
        return 0
    fi
    
    echo "Bulk installation failed, trying individual packages..." >&2
    
    # Install packages individually
    for package in "${packages[@]}"; do
        echo "Installing package: $package" >&2
        
        local attempt=1
        local package_installed=false
        
        while [ $attempt -le $MAX_INSTALL_ATTEMPTS ]; do
            if timeout $PACKAGE_TIMEOUT yum install -y "$package"; then
                installed_packages+=("$package")
                package_installed=true
                echo "✓ Successfully installed: $package" >&2
                break
            else
                echo "Installation attempt $attempt failed for: $package" >&2
                attempt=$((attempt + 1))
                
                if [ $attempt -le $MAX_INSTALL_ATTEMPTS ]; then
                    sleep $((attempt * 2))
                fi
            fi
        done
        
        if [ "$package_installed" != "true" ]; then
            failed_packages+=("$package")
            echo "✗ Failed to install: $package" >&2
        fi
    done
    
    # Report results
    if [ ${#installed_packages[@]} -gt 0 ]; then
        echo "Successfully installed ${#installed_packages[@]} packages: ${installed_packages[*]}" >&2
    fi
    
    if [ ${#failed_packages[@]} -gt 0 ]; then
        echo "Failed to install ${#failed_packages[@]} packages: ${failed_packages[*]}" >&2
        return 1
    fi
    
    return 0
}

# Enable EPEL repository
enable_epel_repository() {
    if ! yum list installed epel-release >/dev/null 2>&1; then
        echo "Installing EPEL repository..." >&2
        yum install -y epel-release || echo "EPEL installation failed, continuing..." >&2
    fi
}

# =============================================================================
# DNF (FEDORA/ROCKY/ALMA) SPECIFIC FUNCTIONS
# =============================================================================

# Install packages via DNF
install_packages_dnf() {
    local packages=("$@")
    local failed_packages=()
    local installed_packages=()
    
    # Enable EPEL and PowerTools/CRB repositories
    enable_dnf_repositories
    
    # Try bulk installation first
    echo "Attempting bulk installation of ${#packages[@]} packages..." >&2
    if dnf install -y "${packages[@]}"; then
        echo "✓ Bulk installation successful" >&2
        return 0
    fi
    
    echo "Bulk installation failed, trying individual packages..." >&2
    
    # Install packages individually
    for package in "${packages[@]}"; do
        echo "Installing package: $package" >&2
        
        local attempt=1
        local package_installed=false
        
        while [ $attempt -le $MAX_INSTALL_ATTEMPTS ]; do
            if timeout $PACKAGE_TIMEOUT dnf install -y "$package"; then
                installed_packages+=("$package")
                package_installed=true
                echo "✓ Successfully installed: $package" >&2
                break
            else
                echo "Installation attempt $attempt failed for: $package" >&2
                attempt=$((attempt + 1))
                
                if [ $attempt -le $MAX_INSTALL_ATTEMPTS ]; then
                    sleep $((attempt * 2))
                fi
            fi
        done
        
        if [ "$package_installed" != "true" ]; then
            failed_packages+=("$package")
            echo "✗ Failed to install: $package" >&2
        fi
    done
    
    # Report results
    if [ ${#installed_packages[@]} -gt 0 ]; then
        echo "Successfully installed ${#installed_packages[@]} packages: ${installed_packages[*]}" >&2
    fi
    
    if [ ${#failed_packages[@]} -gt 0 ]; then
        echo "Failed to install ${#failed_packages[@]} packages: ${failed_packages[*]}" >&2
        return 1
    fi
    
    return 0
}

# Enable DNF repositories (EPEL, PowerTools, CRB)
enable_dnf_repositories() {
    # Install EPEL
    if ! dnf list installed epel-release >/dev/null 2>&1; then
        echo "Installing EPEL repository..." >&2
        dnf install -y epel-release || echo "EPEL installation failed, continuing..." >&2
    fi
    
    # Enable PowerTools (CentOS 8) or CRB (Rocky/Alma 9+)
    if dnf config-manager --set-enabled powertools >/dev/null 2>&1; then
        echo "Enabled PowerTools repository" >&2
    elif dnf config-manager --set-enabled crb >/dev/null 2>&1; then
        echo "Enabled CRB repository" >&2
    else
        echo "Could not enable PowerTools/CRB repository" >&2
    fi
}

# =============================================================================
# ZYPPER (SUSE) SPECIFIC FUNCTIONS
# =============================================================================

# Install packages via Zypper
install_packages_zypper() {
    local packages=("$@")
    local failed_packages=()
    local installed_packages=()
    
    # Try bulk installation first
    echo "Attempting bulk installation of ${#packages[@]} packages..." >&2
    if zypper install -y "${packages[@]}"; then
        echo "✓ Bulk installation successful" >&2
        return 0
    fi
    
    echo "Bulk installation failed, trying individual packages..." >&2
    
    # Install packages individually
    for package in "${packages[@]}"; do
        echo "Installing package: $package" >&2
        
        local attempt=1
        local package_installed=false
        
        while [ $attempt -le $MAX_INSTALL_ATTEMPTS ]; do
            if timeout $PACKAGE_TIMEOUT zypper install -y "$package"; then
                installed_packages+=("$package")
                package_installed=true
                echo "✓ Successfully installed: $package" >&2
                break
            else
                echo "Installation attempt $attempt failed for: $package" >&2
                attempt=$((attempt + 1))
                
                if [ $attempt -le $MAX_INSTALL_ATTEMPTS ]; then
                    sleep $((attempt * 2))
                fi
            fi
        done
        
        if [ "$package_installed" != "true" ]; then
            failed_packages+=("$package")
            echo "✗ Failed to install: $package" >&2
        fi
    done
    
    # Report results
    if [ ${#installed_packages[@]} -gt 0 ]; then
        echo "Successfully installed ${#installed_packages[@]} packages: ${installed_packages[*]}" >&2
    fi
    
    if [ ${#failed_packages[@]} -gt 0 ]; then
        echo "Failed to install ${#failed_packages[@]} packages: ${failed_packages[*]}" >&2
        return 1
    fi
    
    return 0
}

# =============================================================================
# PACMAN (ARCH) SPECIFIC FUNCTIONS
# =============================================================================

# Install packages via Pacman
install_packages_pacman() {
    local packages=("$@")
    local failed_packages=()
    local installed_packages=()
    
    # Try bulk installation first
    echo "Attempting bulk installation of ${#packages[@]} packages..." >&2
    if pacman -S --noconfirm "${packages[@]}"; then
        echo "✓ Bulk installation successful" >&2
        return 0
    fi
    
    echo "Bulk installation failed, trying individual packages..." >&2
    
    # Install packages individually
    for package in "${packages[@]}"; do
        echo "Installing package: $package" >&2
        
        local attempt=1
        local package_installed=false
        
        while [ $attempt -le $MAX_INSTALL_ATTEMPTS ]; do
            if timeout $PACKAGE_TIMEOUT pacman -S --noconfirm "$package"; then
                installed_packages+=("$package")
                package_installed=true
                echo "✓ Successfully installed: $package" >&2
                break
            else
                echo "Installation attempt $attempt failed for: $package" >&2
                attempt=$((attempt + 1))
                
                if [ $attempt -le $MAX_INSTALL_ATTEMPTS ]; then
                    sleep $((attempt * 2))
                fi
            fi
        done
        
        if [ "$package_installed" != "true" ]; then
            failed_packages+=("$package")
            echo "✗ Failed to install: $package" >&2
        fi
    done
    
    # Report results
    if [ ${#installed_packages[@]} -gt 0 ]; then
        echo "Successfully installed ${#installed_packages[@]} packages: ${installed_packages[*]}" >&2
    fi
    
    if [ ${#failed_packages[@]} -gt 0 ]; then
        echo "Failed to install ${#failed_packages[@]} packages: ${failed_packages[*]}" >&2
        return 1
    fi
    
    return 0
}

# =============================================================================
# HIGH-LEVEL INSTALLATION FUNCTIONS
# =============================================================================

# Install essential packages for GeuseMaker
install_essential_packages() {
    local pkg_mgr="${1:-$(get_package_manager)}"
    
    echo "Installing essential packages for GeuseMaker deployment..." >&2
    
    # Define packages by category
    local essential_list
    local build_list
    local network_list
    
    case "$pkg_mgr" in
        apt)
            essential_list="curl wget git unzip ca-certificates gnupg lsb-release"
            build_list="build-essential gcc make libc6-dev"
            network_list="net-tools iproute2"
            ;;
        yum|dnf)
            essential_list="curl wget git unzip ca-certificates gnupg"
            build_list="gcc make glibc-devel"
            network_list="net-tools iproute"
            ;;
        zypper)
            essential_list="curl wget git unzip ca-certificates gpg2"
            build_list="gcc make glibc-devel"
            network_list="net-tools iproute2"
            ;;
        pacman)
            essential_list="curl wget git unzip ca-certificates gnupg"
            build_list="gcc make glibc"
            network_list="net-tools iproute2"
            ;;
        *)
            echo "ERROR: Unsupported package manager: $pkg_mgr" >&2
            return 1
            ;;
    esac
    
    # Install in priority order
    echo "Installing essential packages..." >&2
    if ! install_packages "$pkg_mgr" $essential_list; then
        echo "ERROR: Failed to install essential packages" >&2
        return 1
    fi
    
    echo "Installing build packages..." >&2
    if ! install_packages "$pkg_mgr" $build_list; then
        echo "WARNING: Failed to install some build packages" >&2
    fi
    
    echo "Installing network packages..." >&2
    if ! install_packages "$pkg_mgr" $network_list; then
        echo "WARNING: Failed to install some network packages" >&2
    fi
    
    echo "✓ Essential package installation completed" >&2
    return 0
}

# Install Docker dependencies
install_docker_dependencies() {
    local pkg_mgr="${1:-$(get_package_manager)}"
    
    echo "Installing Docker dependencies..." >&2
    
    case "$pkg_mgr" in
        apt)
            install_packages "$pkg_mgr" \
                apt-transport-https \
                ca-certificates \
                curl \
                gnupg \
                lsb-release
            ;;
        yum|dnf)
            install_packages "$pkg_mgr" \
                yum-utils \
                device-mapper-persistent-data \
                lvm2
            ;;
        zypper)
            install_packages "$pkg_mgr" \
                docker \
                docker-compose
            ;;
        *)
            echo "WARNING: Unknown Docker dependencies for package manager: $pkg_mgr" >&2
            return 1
            ;;
    esac
}

# Install monitoring tools
install_monitoring_packages() {
    local pkg_mgr="${1:-$(get_package_manager)}"
    
    echo "Installing monitoring packages..." >&2
    
    local monitoring_list
    case "$pkg_mgr" in
        apt)
            monitoring_list="htop iotop sysstat psmisc"
            ;;
        yum|dnf)
            monitoring_list="htop iotop sysstat psmisc"
            ;;
        zypper)
            monitoring_list="htop iotop sysstat psmisc"
            ;;
        pacman)
            monitoring_list="htop iotop sysstat psmisc"
            ;;
        *)
            echo "WARNING: Unknown monitoring packages for package manager: $pkg_mgr" >&2
            return 1
            ;;
    esac
    
    install_packages "$pkg_mgr" $monitoring_list
}

# Install security packages
install_security_packages() {
    local pkg_mgr="${1:-$(get_package_manager)}"
    
    echo "Installing security packages..." >&2
    
    local security_list
    case "$pkg_mgr" in
        apt)
            security_list="fail2ban ufw unattended-upgrades"
            ;;
        yum|dnf)
            security_list="fail2ban firewalld"
            ;;
        zypper)
            security_list="fail2ban SuSEfirewall2"
            ;;
        *)
            echo "WARNING: Unknown security packages for package manager: $pkg_mgr" >&2
            return 1
            ;;
    esac
    
    install_packages "$pkg_mgr" $security_list
}

# =============================================================================
# PACKAGE VERIFICATION AND CLEANUP
# =============================================================================

# Verify critical packages are available
verify_critical_packages() {
    local critical_commands=("curl" "wget" "git" "docker")
    local missing_commands=()
    
    echo "Verifying critical packages..." >&2
    
    for cmd in "${critical_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
            echo "✗ Missing critical command: $cmd" >&2
        else
            echo "✓ Found critical command: $cmd" >&2
        fi
    done
    
    if [ ${#missing_commands[@]} -gt 0 ]; then
        echo "ERROR: Missing critical commands: ${missing_commands[*]}" >&2
        return 1
    fi
    
    echo "✓ All critical packages verified" >&2
    return 0
}

# Clean package manager caches
clean_package_caches() {
    local pkg_mgr="${1:-$(get_package_manager)}"
    
    echo "Cleaning package manager caches..." >&2
    
    case "$pkg_mgr" in
        apt)
            apt-get clean
            apt-get autoclean
            apt-get autoremove -y
            ;;
        yum)
            yum clean all
            ;;
        dnf)
            dnf clean all
            ;;
        zypper)
            zypper clean --all
            ;;
        pacman)
            pacman -Sc --noconfirm
            ;;
        *)
            echo "WARNING: Unknown cache cleanup for package manager: $pkg_mgr" >&2
            ;;
    esac
    
    echo "✓ Package caches cleaned" >&2
}

# =============================================================================
# MAIN INSTALLATION WORKFLOW
# =============================================================================

# Complete package installation workflow for GeuseMaker
install_all_packages() {
    local pkg_mgr="${1:-$(get_package_manager)}"
    local include_optional="${2:-true}"
    
    echo "Starting complete package installation for GeuseMaker..." >&2
    echo "Package manager: $pkg_mgr" >&2
    echo "Include optional packages: $include_optional" >&2
    
    # Step 1: Update package lists
    if ! update_package_lists "$pkg_mgr"; then
        echo "ERROR: Failed to update package lists" >&2
        return 1
    fi
    
    # Step 2: Install essential packages
    if ! install_essential_packages "$pkg_mgr"; then
        echo "ERROR: Failed to install essential packages" >&2
        return 1
    fi
    
    # Step 3: Install Docker dependencies
    if ! install_docker_dependencies "$pkg_mgr"; then
        echo "WARNING: Failed to install Docker dependencies" >&2
    fi
    
    # Step 4: Install optional packages
    if [ "$include_optional" = "true" ]; then
        install_monitoring_packages "$pkg_mgr" || echo "WARNING: Failed to install monitoring packages" >&2
        install_security_packages "$pkg_mgr" || echo "WARNING: Failed to install security packages" >&2
    fi
    
    # Step 5: Verify critical packages
    if ! verify_critical_packages; then
        echo "ERROR: Critical package verification failed" >&2
        return 1
    fi
    
    # Step 6: Clean up
    clean_package_caches "$pkg_mgr"
    
    echo "✓ Complete package installation workflow completed successfully" >&2
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Show package manager status
show_package_manager_status() {
    local pkg_mgr="${1:-$(get_package_manager)}"
    
    echo "=== Package Manager Status ==="
    echo "Detected package manager: $pkg_mgr"
    echo "OS Family: ${OS_FAMILY:-not detected}"
    echo ""
    
    case "$pkg_mgr" in
        apt)
            echo "APT Status:"
            echo "  Available packages: $(apt list 2>/dev/null | wc -l)"
            echo "  Installed packages: $(dpkg -l | grep ^ii | wc -l)"
            echo "  Upgradable packages: $(apt list --upgradable 2>/dev/null | wc -l)"
            ;;
        yum)
            echo "YUM Status:"
            echo "  Available packages: $(yum list available 2>/dev/null | wc -l)"
            echo "  Installed packages: $(yum list installed 2>/dev/null | wc -l)"
            echo "  Update count: $(yum check-update 2>/dev/null | wc -l)"
            ;;
        dnf)
            echo "DNF Status:"
            echo "  Available packages: $(dnf list available 2>/dev/null | wc -l)"
            echo "  Installed packages: $(dnf list installed 2>/dev/null | wc -l)"
            echo "  Update count: $(dnf check-update 2>/dev/null | wc -l)"
            ;;
        *)
            echo "Status information not available for: $pkg_mgr"
            ;;
    esac
    
    echo ""
    echo "Critical Commands:"
    local critical_commands=("curl" "wget" "git" "docker" "docker-compose")
    for cmd in "${critical_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "  ✓ $cmd: $(command -v "$cmd")"
        else
            echo "  ✗ $cmd: not found"
        fi
    done
}

# List available packages in a category
list_packages_in_category() {
    local category="$1"
    local pkg_mgr="${2:-$(get_package_manager)}"
    
    case "$category" in
        essential)
            echo "$ESSENTIAL_PACKAGES"
            ;;
        build)
            echo "$BUILD_PACKAGES"
            ;;
        network)
            echo "$NETWORK_PACKAGES"
            ;;
        monitoring)
            echo "$MONITORING_PACKAGES"
            ;;
        security)
            echo "$SECURITY_PACKAGES"
            ;;
        *)
            echo "ERROR: Unknown package category: $category" >&2
            echo "Available categories: essential, build, network, monitoring, security" >&2
            return 1
            ;;
    esac
}