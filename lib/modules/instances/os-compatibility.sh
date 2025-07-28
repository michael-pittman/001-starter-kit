#!/bin/bash
# =============================================================================
# OS Compatibility and Bash Version Management Module
# Comprehensive OS detection, validation, and bash 5.3+ installation
# =============================================================================

# Prevent multiple sourcing
[ -n "${_OS_COMPATIBILITY_SH_LOADED:-}" ] && return 0
_OS_COMPATIBILITY_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/errors.sh"

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

readonly OS_COMPAT_VERSION="1.0.0"
readonly MIN_BASH_VERSION="5.3"
readonly BASH_COMPILE_PREFIX="/usr/local"
readonly BASH_SOURCE_URL="https://ftp.gnu.org/gnu/bash/bash-5.3.tar.gz"
readonly BASH_FALLBACK_URL="https://ftp.gnu.org/gnu/bash/bash-5.2.tar.gz"

# OS Detection patterns
readonly OS_PATTERNS=(
    "amazon:amzn amazonlinux"
    "ubuntu:ubuntu"
    "debian:debian"
    "centos:centos"
    "rhel:rhel"
    "rocky:rocky"
    "almalinux:almalinux"
    "suse:suse opensuse"
    "arch:arch"
    "fedora:fedora"
)

# Package managers by OS
readonly PACKAGE_MANAGERS=(
    "amazon:yum"
    "ubuntu:apt"
    "debian:apt"
    "centos:yum"
    "rhel:yum"
    "rocky:dnf"
    "almalinux:dnf"
    "suse:zypper"
    "arch:pacman"
    "fedora:dnf"
)

# =============================================================================
# OS DETECTION FUNCTIONS
# =============================================================================

# Detect operating system
detect_os() {
    local os_id=""
    local os_version=""
    local os_name=""
    local os_family=""
    
    # Try /etc/os-release first (systemd standard)
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        os_id="${ID:-unknown}"
        os_version="${VERSION_ID:-unknown}"
        os_name="${NAME:-unknown}"
        
        # Determine OS family
        case "$os_id" in
            amzn|amazonlinux)
                os_family="amazon"
                ;;
            ubuntu|debian)
                os_family="debian"
                ;;
            centos|rhel|rocky|almalinux|fedora)
                os_family="redhat"
                ;;
            suse|opensuse*)
                os_family="suse"
                ;;
            arch)
                os_family="arch"
                ;;
            *)
                os_family="unknown"
                ;;
        esac
    
    # Fallback to legacy detection methods
    elif [ -f /etc/redhat-release ]; then
        os_family="redhat"
        if grep -q "Amazon Linux" /etc/redhat-release; then
            os_id="amzn"
            os_version=$(grep -o "release [0-9]\+" /etc/redhat-release | cut -d' ' -f2)
        elif grep -q "CentOS" /etc/redhat-release; then
            os_id="centos"
            os_version=$(grep -o "release [0-9]\+" /etc/redhat-release | cut -d' ' -f2)
        elif grep -q "Red Hat" /etc/redhat-release; then
            os_id="rhel"
            os_version=$(grep -o "release [0-9]\+" /etc/redhat-release | cut -d' ' -f2)
        fi
        os_name=$(cat /etc/redhat-release)
        
    elif [ -f /etc/debian_version ]; then
        os_family="debian"
        if [ -f /etc/lsb-release ]; then
            . /etc/lsb-release
            os_id=$(echo "$DISTRIB_ID" | tr '[:upper:]' '[:lower:]')
            os_version="$DISTRIB_RELEASE"
            os_name="$DISTRIB_DESCRIPTION"
        else
            os_id="debian"
            os_version=$(cat /etc/debian_version)
            os_name="Debian GNU/Linux"
        fi
        
    elif [ -f /etc/arch-release ]; then
        os_family="arch"
        os_id="arch"
        os_version="rolling"
        os_name="Arch Linux"
        
    else
        # Final fallback using uname
        local kernel_name=$(uname -s)
        case "$kernel_name" in
            Linux)
                os_family="linux"
                os_id="unknown-linux"
                ;;
            Darwin)
                os_family="darwin"
                os_id="macos"
                ;;
            *)
                os_family="unknown"
                os_id="unknown"
                ;;
        esac
        os_version="unknown"
        os_name="$kernel_name"
    fi
    
    # Export detected information
    export OS_ID="$os_id"
    export OS_VERSION="$os_version"
    export OS_NAME="$os_name"
    export OS_FAMILY="$os_family"
    
    # Log detection results
    echo "OS Detection Results:" >&2
    echo "  ID: $os_id" >&2
    echo "  Version: $os_version" >&2
    echo "  Name: $os_name" >&2
    echo "  Family: $os_family" >&2
}

# Get package manager for current OS
get_package_manager() {
    local os_id="${1:-$OS_ID}"
    
    for mapping in "${PACKAGE_MANAGERS[@]}"; do
        local os_pattern="${mapping%%:*}"
        local pkg_mgr="${mapping##*:}"
        
        if [ "$os_id" = "$os_pattern" ]; then
            echo "$pkg_mgr"
            return 0
        fi
    done
    
    # Fallback detection
    if command -v apt >/dev/null 2>&1; then
        echo "apt"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    else
        echo "unknown"
        return 1
    fi
}

# Check if OS is supported
is_os_supported() {
    local os_id="${1:-$OS_ID}"
    
    case "$os_id" in
        amzn|amazonlinux|ubuntu|debian|centos|rhel|rocky|almalinux)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# =============================================================================
# BASH VERSION DETECTION AND VALIDATION
# =============================================================================

# Get current bash version
get_bash_version() {
    local bash_path="${1:-$(command -v bash)}"
    
    if [ -x "$bash_path" ]; then
        "$bash_path" --version | head -n1 | sed 's/.*version \([0-9]\+\.[0-9]\+\).*/\1/'
    else
        echo "unknown"
        return 1
    fi
}

# Compare version strings
version_compare() {
    local version1="$1"
    local version2="$2"
    local operator="${3:-ge}"  # ge, gt, le, lt, eq, ne
    
    # Convert versions to comparable format
    local ver1_major=$(echo "$version1" | cut -d. -f1)
    local ver1_minor=$(echo "$version1" | cut -d. -f2 | sed 's/[^0-9].*//')
    local ver2_major=$(echo "$version2" | cut -d. -f1)
    local ver2_minor=$(echo "$version2" | cut -d. -f2 | sed 's/[^0-9].*//')
    
    # Normalize to integers
    ver1_major=${ver1_major:-0}
    ver1_minor=${ver1_minor:-0}
    ver2_major=${ver2_major:-0}
    ver2_minor=${ver2_minor:-0}
    
    # Convert to comparable numbers
    local ver1_num=$((ver1_major * 100 + ver1_minor))
    local ver2_num=$((ver2_major * 100 + ver2_minor))
    
    case "$operator" in
        ge) [ $ver1_num -ge $ver2_num ] ;;
        gt) [ $ver1_num -gt $ver2_num ] ;;
        le) [ $ver1_num -le $ver2_num ] ;;
        lt) [ $ver1_num -lt $ver2_num ] ;;
        eq) [ $ver1_num -eq $ver2_num ] ;;
        ne) [ $ver1_num -ne $ver2_num ] ;;
        *) return 2 ;;
    esac
}

# Check if current bash meets minimum version
check_bash_version() {
    local min_version="${1:-$MIN_BASH_VERSION}"
    local current_version
    
    current_version=$(get_bash_version)
    
    if [ "$current_version" = "unknown" ]; then
        echo "ERROR: Could not determine bash version" >&2
        return 1
    fi
    
    echo "Current bash version: $current_version" >&2
    echo "Required bash version: $min_version" >&2
    
    if version_compare "$current_version" "$min_version" "ge"; then
        echo "✓ Bash version meets requirements" >&2
        return 0
    else
        echo "✗ Bash version insufficient (current: $current_version, required: $min_version)" >&2
        return 1
    fi
}

# Find best available bash
find_best_bash() {
    local min_version="${1:-$MIN_BASH_VERSION}"
    local best_bash=""
    local best_version=""
    
    # Search common locations
    local bash_locations=(
        "/usr/local/bin/bash"
        "/opt/bash/bin/bash"
        "/usr/bin/bash"
        "/bin/bash"
        "$(command -v bash 2>/dev/null)"
    )
    
    for bash_path in "${bash_locations[@]}"; do
        if [ -x "$bash_path" ]; then
            local version
            version=$(get_bash_version "$bash_path")
            
            if [ "$version" != "unknown" ] && version_compare "$version" "$min_version" "ge"; then
                if [ -z "$best_version" ] || version_compare "$version" "$best_version" "gt"; then
                    best_bash="$bash_path"
                    best_version="$version"
                fi
            fi
        fi
    done
    
    if [ -n "$best_bash" ]; then
        echo "Found suitable bash: $best_bash (version $best_version)" >&2
        echo "$best_bash"
        return 0
    else
        echo "No suitable bash found (minimum version: $min_version)" >&2
        return 1
    fi
}

# =============================================================================
# BASH INSTALLATION FUNCTIONS
# =============================================================================

# Install development tools for bash compilation
install_build_dependencies() {
    local pkg_mgr
    pkg_mgr=$(get_package_manager)
    
    echo "Installing build dependencies for bash compilation..." >&2
    
    case "$pkg_mgr" in
        apt)
            DEBIAN_FRONTEND=noninteractive apt-get update
            DEBIAN_FRONTEND=noninteractive apt-get install -y \
                build-essential wget curl gcc make libc6-dev \
                libncurses5-dev libreadline-dev bison flex
            ;;
        yum)
            yum groupinstall -y "Development Tools"
            yum install -y wget curl gcc make glibc-devel \
                ncurses-devel readline-devel bison flex
            ;;
        dnf)
            dnf groupinstall -y "Development Tools"
            dnf install -y wget curl gcc make glibc-devel \
                ncurses-devel readline-devel bison flex
            ;;
        zypper)
            zypper install -y -t pattern devel_basis
            zypper install -y wget curl gcc make glibc-devel \
                ncurses-devel readline-devel bison flex
            ;;
        pacman)
            pacman -Sy --noconfirm base-devel wget curl
            ;;
        *)
            echo "ERROR: Unknown package manager: $pkg_mgr" >&2
            return 1
            ;;
    esac
}

# Compile and install bash from source
compile_bash_from_source() {
    local bash_version="${1:-5.3}"
    local install_prefix="${2:-$BASH_COMPILE_PREFIX}"
    local temp_dir="/tmp/bash-build-$$"
    
    echo "Compiling bash $bash_version from source..." >&2
    
    # Create temporary build directory
    mkdir -p "$temp_dir"
    cd "$temp_dir" || return 1
    
    # Download bash source
    local source_url="https://ftp.gnu.org/gnu/bash/bash-${bash_version}.tar.gz"
    if ! wget -q --timeout=30 "$source_url"; then
        echo "Failed to download from primary URL, trying fallback..." >&2
        source_url="$BASH_FALLBACK_URL"
        if ! wget -q --timeout=30 "$source_url"; then
            echo "ERROR: Failed to download bash source" >&2
            cd / && rm -rf "$temp_dir"
            return 1
        fi
    fi
    
    # Extract source
    if ! tar -xzf "bash-${bash_version}.tar.gz"; then
        echo "ERROR: Failed to extract bash source" >&2
        cd / && rm -rf "$temp_dir"
        return 1
    fi
    
    cd "bash-${bash_version}" || return 1
    
    # Configure build
    echo "Configuring bash build..." >&2
    if ! ./configure \
        --prefix="$install_prefix" \
        --enable-static-link \
        --with-installed-readline \
        --enable-progcomp \
        --enable-history \
        --enable-bang-history \
        --enable-alias \
        --enable-select \
        --enable-arith-for-command \
        --enable-array-variables \
        --enable-brace-expansion \
        --enable-casemod-attrs \
        --enable-casemod-expansions \
        --enable-command-timing \
        --enable-cond-command \
        --enable-cond-regexp \
        --enable-debugger \
        --enable-directory-stack \
        --enable-disabled-builtins \
        --enable-dparen-arithmetic \
        --enable-extended-glob \
        --enable-help-builtin \
        --enable-job-control \
        --enable-multibyte \
        --enable-net-redirections \
        --enable-process-substitution \
        --enable-readline; then
        echo "ERROR: Bash configure failed" >&2
        cd / && rm -rf "$temp_dir"
        return 1
    fi
    
    # Compile
    echo "Compiling bash (this may take several minutes)..." >&2
    local cpu_count=$(nproc 2>/dev/null || echo 2)
    if ! make -j"$cpu_count"; then
        echo "ERROR: Bash compilation failed" >&2
        cd / && rm -rf "$temp_dir"
        return 1
    fi
    
    # Install
    echo "Installing bash to $install_prefix..." >&2
    if ! make install; then
        echo "ERROR: Bash installation failed" >&2
        cd / && rm -rf "$temp_dir"
        return 1
    fi
    
    # Clean up
    cd / && rm -rf "$temp_dir"
    
    # Verify installation
    local new_bash_path="$install_prefix/bin/bash"
    if [ -x "$new_bash_path" ]; then
        local new_version
        new_version=$(get_bash_version "$new_bash_path")
        echo "✓ Successfully installed bash $new_version at $new_bash_path" >&2
        return 0
    else
        echo "ERROR: Bash installation verification failed" >&2
        return 1
    fi
}

# Install bash using package manager
install_bash_via_package_manager() {
    local pkg_mgr
    pkg_mgr=$(get_package_manager)
    
    echo "Installing bash via package manager: $pkg_mgr" >&2
    
    case "$pkg_mgr" in
        apt)
            DEBIAN_FRONTEND=noninteractive apt-get update
            DEBIAN_FRONTEND=noninteractive apt-get install -y bash
            ;;
        yum)
            yum update -y bash
            ;;
        dnf)
            dnf update -y bash
            ;;
        zypper)
            zypper install -y bash
            ;;
        pacman)
            pacman -Sy --noconfirm bash
            ;;
        *)
            echo "ERROR: Unsupported package manager: $pkg_mgr" >&2
            return 1
            ;;
    esac
}

# =============================================================================
# COMPREHENSIVE BASH UPGRADE
# =============================================================================

# Upgrade bash to meet minimum requirements
upgrade_bash() {
    local min_version="${1:-$MIN_BASH_VERSION}"
    local force_compile="${2:-false}"
    
    echo "Starting bash upgrade process..." >&2
    
    # Check if upgrade is needed
    if [ "$force_compile" != "true" ] && check_bash_version "$min_version"; then
        echo "Bash version already meets requirements" >&2
        return 0
    fi
    
    # Try package manager first (unless force compile)
    if [ "$force_compile" != "true" ]; then
        echo "Attempting package manager upgrade..." >&2
        if install_bash_via_package_manager; then
            if check_bash_version "$min_version"; then
                echo "✓ Package manager upgrade successful" >&2
                return 0
            else
                echo "Package manager upgrade insufficient, will compile from source" >&2
            fi
        else
            echo "Package manager upgrade failed, will compile from source" >&2
        fi
    fi
    
    # Install build dependencies
    if ! install_build_dependencies; then
        echo "ERROR: Failed to install build dependencies" >&2
        return 1
    fi
    
    # Compile from source
    if ! compile_bash_from_source "$min_version"; then
        echo "ERROR: Failed to compile bash from source" >&2
        return 1
    fi
    
    # Update PATH and symlinks
    local new_bash_path="$BASH_COMPILE_PREFIX/bin/bash"
    if [ -x "$new_bash_path" ]; then
        # Create symlink for compatibility
        ln -sf "$new_bash_path" /usr/local/bin/bash-modern
        
        # Update PATH in profile
        local profile_script="/etc/profile.d/modern-bash.sh"
        cat > "$profile_script" << EOF
# Modern bash configuration
export PATH="$BASH_COMPILE_PREFIX/bin:\$PATH"
EOF
        chmod +x "$profile_script"
        
        echo "✓ Bash upgrade completed successfully" >&2
        echo "New bash location: $new_bash_path" >&2
        echo "Version: $(get_bash_version "$new_bash_path")" >&2
        return 0
    else
        echo "ERROR: Bash upgrade verification failed" >&2
        return 1
    fi
}

# =============================================================================
# SCRIPT EXECUTION WITH MODERN BASH
# =============================================================================

# Execute script with best available bash
exec_with_modern_bash() {
    local script_path="$1"
    shift
    local args=("$@")
    
    local modern_bash
    if ! modern_bash=$(find_best_bash); then
        echo "ERROR: No suitable bash found for script execution" >&2
        return 1
    fi
    
    echo "Executing script with bash: $modern_bash" >&2
    exec "$modern_bash" "$script_path" "${args[@]}"
}

# Switch to modern bash if available
switch_to_modern_bash() {
    local current_bash="${BASH:-/bin/bash}"
    local min_version="${1:-$MIN_BASH_VERSION}"
    
    # Check if we're already using a suitable bash
    if check_bash_version "$min_version" >/dev/null 2>&1; then
        return 0
    fi
    
    # Find better bash
    local better_bash
    if better_bash=$(find_best_bash "$min_version"); then
        echo "Switching to modern bash: $better_bash" >&2
        export BASH="$better_bash"
        
        # Re-execute current script with modern bash if we have script path
        if [ -n "${BASH_SOURCE[1]:-}" ]; then
            exec "$better_bash" "${BASH_SOURCE[1]}" "$@"
        fi
    else
        echo "WARNING: No modern bash available, continuing with current version" >&2
        return 1
    fi
}

# =============================================================================
# VALIDATION AND TESTING
# =============================================================================

# Validate bash installation
validate_bash_installation() {
    local bash_path="${1:-$(command -v bash)}"
    local min_version="${2:-$MIN_BASH_VERSION}"
    
    echo "Validating bash installation..." >&2
    
    # Check if executable exists
    if [ ! -x "$bash_path" ]; then
        echo "ERROR: Bash not found or not executable: $bash_path" >&2
        return 1
    fi
    
    # Check version
    local version
    version=$(get_bash_version "$bash_path")
    if [ "$version" = "unknown" ]; then
        echo "ERROR: Could not determine bash version" >&2
        return 1
    fi
    
    if ! version_compare "$version" "$min_version" "ge"; then
        echo "ERROR: Bash version insufficient (found: $version, required: $min_version)" >&2
        return 1
    fi
    
    # Test basic functionality
    if ! "$bash_path" -c 'echo "Basic test passed"' >/dev/null 2>&1; then
        echo "ERROR: Bash basic functionality test failed" >&2
        return 1
    fi
    
    # Test advanced features (bash 4.0+ features)
    if ! "$bash_path" -c 'declare -A test_array; test_array[key]=value; [[ ${test_array[key]} == "value" ]]' >/dev/null 2>&1; then
        echo "WARNING: Bash advanced features test failed" >&2
    fi
    
    echo "✓ Bash validation successful: $bash_path (version $version)" >&2
    return 0
}

# Test OS compatibility
test_os_compatibility() {
    echo "Testing OS compatibility..." >&2
    
    # Detect OS
    detect_os
    
    # Check if supported
    if ! is_os_supported; then
        echo "WARNING: OS not officially supported: $OS_ID" >&2
        return 1
    fi
    
    # Check package manager
    local pkg_mgr
    pkg_mgr=$(get_package_manager)
    if [ "$pkg_mgr" = "unknown" ]; then
        echo "ERROR: Could not determine package manager" >&2
        return 1
    fi
    
    # Test package manager
    case "$pkg_mgr" in
        apt)
            if ! dpkg --version >/dev/null 2>&1; then
                echo "ERROR: APT package manager not functional" >&2
                return 1
            fi
            ;;
        yum|dnf)
            if ! rpm --version >/dev/null 2>&1; then
                echo "ERROR: RPM package manager not functional" >&2
                return 1
            fi
            ;;
        zypper)
            if ! zypper --version >/dev/null 2>&1; then
                echo "ERROR: Zypper package manager not functional" >&2
                return 1
            fi
            ;;
        pacman)
            if ! pacman --version >/dev/null 2>&1; then
                echo "ERROR: Pacman package manager not functional" >&2
                return 1
            fi
            ;;
    esac
    
    echo "✓ OS compatibility test passed" >&2
    echo "  OS: $OS_NAME ($OS_ID $OS_VERSION)" >&2
    echo "  Family: $OS_FAMILY" >&2
    echo "  Package Manager: $pkg_mgr" >&2
    return 0
}

# =============================================================================
# MAIN FUNCTIONS
# =============================================================================

# Initialize OS compatibility system
init_os_compatibility() {
    echo "Initializing OS compatibility system v$OS_COMPAT_VERSION..." >&2
    
    # Detect operating system
    detect_os
    
    # Test OS compatibility
    if ! test_os_compatibility; then
        echo "WARNING: OS compatibility issues detected" >&2
    fi
    
    # Check bash version
    if ! check_bash_version; then
        echo "Bash upgrade required" >&2
        return 1
    fi
    
    echo "✓ OS compatibility system initialized successfully" >&2
    return 0
}

# Full OS and bash setup
setup_os_and_bash() {
    local min_bash_version="${1:-$MIN_BASH_VERSION}"
    local force_compile="${2:-false}"
    
    echo "Starting comprehensive OS and bash setup..." >&2
    
    # Initialize OS compatibility
    if ! init_os_compatibility >/dev/null 2>&1; then
        echo "OS compatibility initialization had issues, continuing..." >&2
    fi
    
    # Upgrade bash if needed
    if ! check_bash_version "$min_bash_version" >/dev/null 2>&1; then
        echo "Bash upgrade required, starting upgrade process..." >&2
        if ! upgrade_bash "$min_bash_version" "$force_compile"; then
            echo "ERROR: Bash upgrade failed" >&2
            return 1
        fi
    fi
    
    # Validate final setup
    if ! validate_bash_installation "$(command -v bash)" "$min_bash_version"; then
        echo "ERROR: Final bash validation failed" >&2
        return 1
    fi
    
    echo "✓ OS and bash setup completed successfully" >&2
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Show compatibility status
show_compatibility_status() {
    echo "=== OS Compatibility Status ==="
    echo "OS Detection:"
    echo "  ID: ${OS_ID:-not detected}"
    echo "  Version: ${OS_VERSION:-not detected}"
    echo "  Name: ${OS_NAME:-not detected}"
    echo "  Family: ${OS_FAMILY:-not detected}"
    echo ""
    echo "Package Manager: $(get_package_manager 2>/dev/null || echo "not detected")"
    echo "OS Supported: $(is_os_supported && echo "Yes" || echo "No")"
    echo ""
    echo "Bash Information:"
    echo "  Current Path: $(command -v bash)"
    echo "  Current Version: $(get_bash_version)"
    echo "  Required Version: $MIN_BASH_VERSION"
    echo "  Version Check: $(check_bash_version >/dev/null 2>&1 && echo "✓ PASS" || echo "✗ FAIL")"
    echo ""
    echo "Available Bash Versions:"
    local bash_locations=("/usr/local/bin/bash" "/usr/bin/bash" "/bin/bash")
    for bash_path in "${bash_locations[@]}"; do
        if [ -x "$bash_path" ]; then
            local version=$(get_bash_version "$bash_path")
            echo "  $bash_path: $version"
        fi
    done
}