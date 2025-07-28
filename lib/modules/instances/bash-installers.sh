#!/bin/bash
# =============================================================================
# Bash 5.3+ Installation Scripts for Multiple Operating Systems
# Comprehensive installation strategies with fallbacks
# =============================================================================

# Prevent multiple sourcing
[ -n "${_BASH_INSTALLERS_SH_LOADED:-}" ] && return 0
_BASH_INSTALLERS_SH_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/os-compatibility.sh"

# =============================================================================
# CONSTANTS AND CONFIGURATION
# =============================================================================

readonly BASH_INSTALLERS_VERSION="1.0.0"
readonly TARGET_BASH_VERSION="5.3"
readonly FALLBACK_BASH_VERSION="5.2"
readonly INSTALL_PREFIX="/usr/local"
readonly BASH_SOURCE_BASE_URL="https://ftp.gnu.org/gnu/bash"
readonly BASH_PATCHES_BASE_URL="https://ftp.gnu.org/gnu/bash/bash-5.3-patches"

# Installation methods priority
readonly INSTALL_METHODS=(
    "repository"
    "third_party"
    "compile"
    "fallback"
)

# =============================================================================
# AMAZON LINUX INSTALLER
# =============================================================================

install_bash_amazon_linux() {
    local target_version="${1:-$TARGET_BASH_VERSION}"
    local method="${2:-auto}"
    
    echo "Installing bash $target_version on Amazon Linux..." >&2
    
    case "$method" in
        repository|auto)
            if install_bash_amazon_repository "$target_version"; then
                return 0
            elif [ "$method" = "repository" ]; then
                return 1
            fi
            ;&  # fallthrough
        compile)
            if install_bash_amazon_compile "$target_version"; then
                return 0
            elif [ "$method" = "compile" ]; then
                return 1
            fi
            ;&  # fallthrough
        fallback)
            install_bash_amazon_fallback
            ;;
        *)
            echo "ERROR: Unknown installation method: $method" >&2
            return 1
            ;;
    esac
}

install_bash_amazon_repository() {
    local target_version="$1"
    
    echo "Attempting Amazon Linux repository installation..." >&2
    
    # Update package lists
    yum update -y
    
    # Install EPEL repository for more packages
    if ! yum list installed epel-release >/dev/null 2>&1; then
        yum install -y epel-release
    fi
    
    # Try to install bash from repository
    if yum install -y bash; then
        local installed_version
        installed_version=$(get_bash_version)
        if version_compare "$installed_version" "$target_version" "ge"; then
            echo "✓ Repository installation successful: $installed_version" >&2
            return 0
        else
            echo "Repository version insufficient: $installed_version" >&2
            return 1
        fi
    else
        echo "Repository installation failed" >&2
        return 1
    fi
}

install_bash_amazon_compile() {
    local target_version="$1"
    
    echo "Compiling bash $target_version on Amazon Linux..." >&2
    
    # Install development tools
    yum groupinstall -y "Development Tools"
    yum install -y wget curl gcc make glibc-devel ncurses-devel readline-devel bison flex
    
    # Compile bash
    compile_bash_from_source "$target_version" "$INSTALL_PREFIX"
}

install_bash_amazon_fallback() {
    echo "Using Amazon Linux fallback installation..." >&2
    
    # Try older bash version
    if install_bash_amazon_compile "$FALLBACK_BASH_VERSION"; then
        echo "✓ Fallback installation successful" >&2
        return 0
    fi
    
    # Final fallback - ensure bash is at least installed
    yum install -y bash
    echo "WARNING: Using system bash, may not meet all requirements" >&2
    return 0
}

# =============================================================================
# UBUNTU/DEBIAN INSTALLER
# =============================================================================

install_bash_ubuntu() {
    local target_version="${1:-$TARGET_BASH_VERSION}"
    local method="${2:-auto}"
    
    echo "Installing bash $target_version on Ubuntu/Debian..." >&2
    
    case "$method" in
        repository|auto)
            if install_bash_ubuntu_repository "$target_version"; then
                return 0
            elif [ "$method" = "repository" ]; then
                return 1
            fi
            ;&  # fallthrough
        third_party)
            if install_bash_ubuntu_third_party "$target_version"; then
                return 0
            elif [ "$method" = "third_party" ]; then
                return 1
            fi
            ;&  # fallthrough
        compile)
            if install_bash_ubuntu_compile "$target_version"; then
                return 0
            elif [ "$method" = "compile" ]; then
                return 1
            fi
            ;&  # fallthrough
        fallback)
            install_bash_ubuntu_fallback
            ;;
        *)
            echo "ERROR: Unknown installation method: $method" >&2
            return 1
            ;;
    esac
}

install_bash_ubuntu_repository() {
    local target_version="$1"
    
    echo "Attempting Ubuntu repository installation..." >&2
    
    # Update package lists
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    
    # Try to install latest bash
    if apt-get install -y bash; then
        local installed_version
        installed_version=$(get_bash_version)
        if version_compare "$installed_version" "$target_version" "ge"; then
            echo "✓ Repository installation successful: $installed_version" >&2
            return 0
        else
            echo "Repository version insufficient: $installed_version" >&2
            return 1
        fi
    else
        echo "Repository installation failed" >&2
        return 1
    fi
}

install_bash_ubuntu_third_party() {
    local target_version="$1"
    
    echo "Attempting third-party repository installation..." >&2
    
    # Add potential third-party repositories
    export DEBIAN_FRONTEND=noninteractive
    
    # Try to add newer repositories for Ubuntu
    if command -v add-apt-repository >/dev/null 2>&1; then
        # Add universe repository if not present
        add-apt-repository universe -y >/dev/null 2>&1 || true
        
        # Update after adding repositories
        apt-get update
        
        # Try installing bash again
        if apt-get install -y bash; then
            local installed_version
            installed_version=$(get_bash_version)
            if version_compare "$installed_version" "$target_version" "ge"; then
                echo "✓ Third-party installation successful: $installed_version" >&2
                return 0
            fi
        fi
    fi
    
    echo "Third-party installation failed or insufficient" >&2
    return 1
}

install_bash_ubuntu_compile() {
    local target_version="$1"
    
    echo "Compiling bash $target_version on Ubuntu..." >&2
    
    # Install development tools
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y build-essential wget curl gcc make libc6-dev \
        libncurses5-dev libreadline-dev bison flex
    
    # Compile bash
    compile_bash_from_source "$target_version" "$INSTALL_PREFIX"
}

install_bash_ubuntu_fallback() {
    echo "Using Ubuntu fallback installation..." >&2
    
    # Try compiling older version
    if install_bash_ubuntu_compile "$FALLBACK_BASH_VERSION"; then
        echo "✓ Fallback installation successful" >&2
        return 0
    fi
    
    # Ensure bash is installed
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y bash
    echo "WARNING: Using system bash, may not meet all requirements" >&2
    return 0
}

# =============================================================================
# ROCKY LINUX / ALMALINUX INSTALLER
# =============================================================================

install_bash_rocky() {
    local target_version="${1:-$TARGET_BASH_VERSION}"
    local method="${2:-auto}"
    
    echo "Installing bash $target_version on Rocky Linux/AlmaLinux..." >&2
    
    case "$method" in
        repository|auto)
            if install_bash_rocky_repository "$target_version"; then
                return 0
            elif [ "$method" = "repository" ]; then
                return 1
            fi
            ;&  # fallthrough
        third_party)
            if install_bash_rocky_third_party "$target_version"; then
                return 0
            elif [ "$method" = "third_party" ]; then
                return 1
            fi
            ;&  # fallthrough
        compile)
            if install_bash_rocky_compile "$target_version"; then
                return 0
            elif [ "$method" = "compile" ]; then
                return 1
            fi
            ;&  # fallthrough
        fallback)
            install_bash_rocky_fallback
            ;;
        *)
            echo "ERROR: Unknown installation method: $method" >&2
            return 1
            ;;
    esac
}

install_bash_rocky_repository() {
    local target_version="$1"
    
    echo "Attempting Rocky Linux repository installation..." >&2
    
    # Update package lists
    dnf update -y
    
    # Install EPEL repository
    if ! dnf list installed epel-release >/dev/null 2>&1; then
        dnf install -y epel-release
    fi
    
    # Try to install bash
    if dnf install -y bash; then
        local installed_version
        installed_version=$(get_bash_version)
        if version_compare "$installed_version" "$target_version" "ge"; then
            echo "✓ Repository installation successful: $installed_version" >&2
            return 0
        else
            echo "Repository version insufficient: $installed_version" >&2
            return 1
        fi
    else
        echo "Repository installation failed" >&2
        return 1
    fi
}

install_bash_rocky_third_party() {
    local target_version="$1"
    
    echo "Attempting third-party repository installation..." >&2
    
    # Try PowerTools/CRB repository
    if dnf config-manager --set-enabled powertools >/dev/null 2>&1 || \
       dnf config-manager --set-enabled crb >/dev/null 2>&1; then
        dnf update -y
        
        if dnf install -y bash; then
            local installed_version
            installed_version=$(get_bash_version)
            if version_compare "$installed_version" "$target_version" "ge"; then
                echo "✓ Third-party installation successful: $installed_version" >&2
                return 0
            fi
        fi
    fi
    
    echo "Third-party installation failed or insufficient" >&2
    return 1
}

install_bash_rocky_compile() {
    local target_version="$1"
    
    echo "Compiling bash $target_version on Rocky Linux..." >&2
    
    # Install development tools
    dnf groupinstall -y "Development Tools"
    dnf install -y wget curl gcc make glibc-devel ncurses-devel readline-devel bison flex
    
    # Compile bash
    compile_bash_from_source "$target_version" "$INSTALL_PREFIX"
}

install_bash_rocky_fallback() {
    echo "Using Rocky Linux fallback installation..." >&2
    
    # Try older version
    if install_bash_rocky_compile "$FALLBACK_BASH_VERSION"; then
        echo "✓ Fallback installation successful" >&2
        return 0
    fi
    
    # Ensure bash is installed
    dnf install -y bash
    echo "WARNING: Using system bash, may not meet all requirements" >&2
    return 0
}

# =============================================================================
# DEBIAN INSTALLER
# =============================================================================

install_bash_debian() {
    local target_version="${1:-$TARGET_BASH_VERSION}"
    local method="${2:-auto}"
    
    echo "Installing bash $target_version on Debian..." >&2
    
    case "$method" in
        repository|auto)
            if install_bash_debian_repository "$target_version"; then
                return 0
            elif [ "$method" = "repository" ]; then
                return 1
            fi
            ;&  # fallthrough
        third_party)
            if install_bash_debian_third_party "$target_version"; then
                return 0
            elif [ "$method" = "third_party" ]; then
                return 1
            fi
            ;&  # fallthrough
        compile)
            if install_bash_debian_compile "$target_version"; then
                return 0
            elif [ "$method" = "compile" ]; then
                return 1
            fi
            ;&  # fallthrough
        fallback)
            install_bash_debian_fallback
            ;;
        *)
            echo "ERROR: Unknown installation method: $method" >&2
            return 1
            ;;
    esac
}

install_bash_debian_repository() {
    local target_version="$1"
    
    echo "Attempting Debian repository installation..." >&2
    
    # Update package lists
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    
    # Try to install bash
    if apt-get install -y bash; then
        local installed_version
        installed_version=$(get_bash_version)
        if version_compare "$installed_version" "$target_version" "ge"; then
            echo "✓ Repository installation successful: $installed_version" >&2
            return 0
        else
            echo "Repository version insufficient: $installed_version" >&2
            return 1
        fi
    else
        echo "Repository installation failed" >&2
        return 1
    fi
}

install_bash_debian_third_party() {
    local target_version="$1"
    
    echo "Attempting Debian backports installation..." >&2
    
    # Try to enable backports
    local debian_version
    debian_version=$(cat /etc/debian_version | cut -d. -f1)
    
    if [ -n "$debian_version" ] && [ "$debian_version" -ge 9 ]; then
        # Add backports repository
        echo "deb http://deb.debian.org/debian $(lsb_release -sc)-backports main" > /etc/apt/sources.list.d/backports.list
        
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        
        # Try installing from backports
        if apt-get install -y -t "$(lsb_release -sc)-backports" bash; then
            local installed_version
            installed_version=$(get_bash_version)
            if version_compare "$installed_version" "$target_version" "ge"; then
                echo "✓ Backports installation successful: $installed_version" >&2
                return 0
            fi
        fi
    fi
    
    echo "Third-party installation failed or insufficient" >&2
    return 1
}

install_bash_debian_compile() {
    local target_version="$1"
    
    echo "Compiling bash $target_version on Debian..." >&2
    
    # Install development tools
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y build-essential wget curl gcc make libc6-dev \
        libncurses5-dev libreadline-dev bison flex
    
    # Compile bash
    compile_bash_from_source "$target_version" "$INSTALL_PREFIX"
}

install_bash_debian_fallback() {
    echo "Using Debian fallback installation..." >&2
    
    # Try compiling older version
    if install_bash_debian_compile "$FALLBACK_BASH_VERSION"; then
        echo "✓ Fallback installation successful" >&2
        return 0
    fi
    
    # Ensure bash is installed
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y bash
    echo "WARNING: Using system bash, may not meet all requirements" >&2
    return 0
}

# =============================================================================
# UNIVERSAL INSTALLER DISPATCHER
# =============================================================================

install_bash_for_os() {
    local target_version="${1:-$TARGET_BASH_VERSION}"
    local method="${2:-auto}"
    local os_id="${3:-$OS_ID}"
    
    echo "Starting bash installation for OS: $os_id" >&2
    
    # Detect OS if not provided
    if [ -z "$os_id" ]; then
        detect_os
        os_id="$OS_ID"
    fi
    
    case "$os_id" in
        amzn|amazonlinux)
            install_bash_amazon_linux "$target_version" "$method"
            ;;
        ubuntu)
            install_bash_ubuntu "$target_version" "$method"
            ;;
        debian)
            install_bash_debian "$target_version" "$method"
            ;;
        rocky|almalinux)
            install_bash_rocky "$target_version" "$method"
            ;;
        centos)
            # CentOS uses similar method to Rocky Linux
            install_bash_rocky "$target_version" "$method"
            ;;
        rhel)
            # RHEL uses similar method to Rocky Linux
            install_bash_rocky "$target_version" "$method"
            ;;
        *)
            echo "ERROR: Unsupported OS for bash installation: $os_id" >&2
            echo "Attempting generic compilation..." >&2
            generic_bash_compile "$target_version"
            ;;
    esac
}

# Generic compilation for unsupported OSes
generic_bash_compile() {
    local target_version="$1"
    
    echo "Attempting generic bash compilation..." >&2
    
    # Try to determine package manager and install dependencies
    local pkg_mgr
    pkg_mgr=$(get_package_manager)
    
    case "$pkg_mgr" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update
            apt-get install -y build-essential wget curl gcc make \
                libncurses5-dev libreadline-dev bison flex
            ;;
        yum)
            yum groupinstall -y "Development Tools"
            yum install -y wget curl gcc make ncurses-devel readline-devel bison flex
            ;;
        dnf)
            dnf groupinstall -y "Development Tools"
            dnf install -y wget curl gcc make ncurses-devel readline-devel bison flex
            ;;
        zypper)
            zypper install -y -t pattern devel_basis
            zypper install -y wget curl gcc make ncurses-devel readline-devel bison flex
            ;;
        pacman)
            pacman -Sy --noconfirm base-devel wget curl
            ;;
        *)
            echo "ERROR: Cannot install build dependencies - unknown package manager" >&2
            return 1
            ;;
    esac
    
    # Compile bash
    compile_bash_from_source "$target_version" "$INSTALL_PREFIX"
}

# =============================================================================
# ADVANCED COMPILATION WITH PATCHES
# =============================================================================

compile_bash_with_patches() {
    local bash_version="${1:-$TARGET_BASH_VERSION}"
    local install_prefix="${2:-$INSTALL_PREFIX}"
    local apply_patches="${3:-true}"
    
    echo "Compiling bash $bash_version with patches..." >&2
    
    local temp_dir="/tmp/bash-build-advanced-$$"
    mkdir -p "$temp_dir"
    cd "$temp_dir" || return 1
    
    # Download bash source
    local source_file="bash-${bash_version}.tar.gz"
    local source_url="$BASH_SOURCE_BASE_URL/$source_file"
    
    if ! wget -q --timeout=30 "$source_url"; then
        echo "ERROR: Failed to download bash source from $source_url" >&2
        cd / && rm -rf "$temp_dir"
        return 1
    fi
    
    # Extract source
    if ! tar -xzf "$source_file"; then
        echo "ERROR: Failed to extract bash source" >&2
        cd / && rm -rf "$temp_dir"
        return 1
    fi
    
    cd "bash-$bash_version" || return 1
    
    # Apply patches if requested
    if [ "$apply_patches" = "true" ]; then
        echo "Downloading and applying bash patches..." >&2
        local patch_count=0
        
        # Try to download patches (bash patches are numbered sequentially)
        for i in {001..050}; do
            local patch_file="bash${bash_version//.}-$i"
            local patch_url="$BASH_PATCHES_BASE_URL/$patch_file"
            
            if wget -q --timeout=10 "$patch_url"; then
                if patch -p0 < "$patch_file"; then
                    patch_count=$((patch_count + 1))
                    echo "Applied patch $patch_file" >&2
                else
                    echo "WARNING: Failed to apply patch $patch_file" >&2
                fi
            else
                # No more patches available
                break
            fi
        done
        
        echo "Applied $patch_count patches" >&2
    fi
    
    # Configure with comprehensive options
    echo "Configuring bash build with comprehensive options..." >&2
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
        --enable-readline \
        --enable-restricted \
        --enable-separate-helpfiles \
        --enable-single-help-strings \
        --with-bash-malloc \
        --with-curses; then
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
    
    # Run tests if possible
    echo "Running bash tests..." >&2
    if ! make tests; then
        echo "WARNING: Some bash tests failed, continuing with installation" >&2
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
        echo "✓ Successfully compiled and installed bash $new_version at $new_bash_path" >&2
        
        # Set up environment
        setup_bash_environment "$new_bash_path"
        return 0
    else
        echo "ERROR: Bash installation verification failed" >&2
        return 1
    fi
}

# =============================================================================
# ENVIRONMENT SETUP
# =============================================================================

setup_bash_environment() {
    local bash_path="$1"
    local bash_dir=$(dirname "$bash_path")
    
    echo "Setting up bash environment..." >&2
    
    # Create profile script
    local profile_script="/etc/profile.d/modern-bash.sh"
    cat > "$profile_script" << EOF
# Modern Bash Configuration
# Generated by GeuseMaker bash installer

# Add modern bash to PATH
export PATH="$bash_dir:\$PATH"

# Set bash as default shell for scripts
export BASH="$bash_path"

# Enable modern bash features
export BASH_VERSINFO=(5 3 0)

# Set up aliases for compatibility
alias bash-modern="$bash_path"
alias bash5="$bash_path"
EOF
    
    chmod +x "$profile_script"
    
    # Create compatibility symlinks
    ln -sf "$bash_path" /usr/local/bin/bash-modern
    ln -sf "$bash_path" /usr/local/bin/bash5
    
    # Update /etc/shells if not already present
    if ! grep -q "^$bash_path$" /etc/shells 2>/dev/null; then
        echo "$bash_path" >> /etc/shells
    fi
    
    echo "✓ Bash environment setup completed" >&2
}

# =============================================================================
# INSTALLATION VERIFICATION
# =============================================================================

verify_bash_installation() {
    local target_version="${1:-$TARGET_BASH_VERSION}"
    local bash_path="${2:-$(command -v bash)}"
    
    echo "Verifying bash installation..." >&2
    
    # Check if bash exists
    if [ ! -x "$bash_path" ]; then
        echo "ERROR: Bash not found at $bash_path" >&2
        return 1
    fi
    
    # Check version
    local installed_version
    installed_version=$(get_bash_version "$bash_path")
    
    if [ "$installed_version" = "unknown" ]; then
        echo "ERROR: Could not determine bash version" >&2
        return 1
    fi
    
    echo "Installed bash version: $installed_version" >&2
    echo "Target version: $target_version" >&2
    
    if ! version_compare "$installed_version" "$target_version" "ge"; then
        echo "ERROR: Installed bash version is insufficient" >&2
        return 1
    fi
    
    # Test basic functionality
    if ! "$bash_path" -c 'echo "Bash basic test passed"' >/dev/null 2>&1; then
        echo "ERROR: Bash basic functionality test failed" >&2
        return 1
    fi
    
    # Test advanced features
    if ! "$bash_path" -c 'declare -A test_array; test_array[key]=value; [[ ${test_array[key]} == "value" ]]' >/dev/null 2>&1; then
        echo "WARNING: Bash associative arrays test failed" >&2
    fi
    
    # Test modern bash features
    if ! "$bash_path" -c 'declare -n nameref=test_var; test_var="hello"; [[ $nameref == "hello" ]]' >/dev/null 2>&1; then
        echo "WARNING: Bash nameref test failed" >&2
    fi
    
    echo "✓ Bash installation verification completed successfully" >&2
    echo "  Path: $bash_path" >&2
    echo "  Version: $installed_version" >&2
    return 0
}

# =============================================================================
# MAIN INSTALLATION FUNCTION
# =============================================================================

install_modern_bash() {
    local target_version="${1:-$TARGET_BASH_VERSION}"
    local method="${2:-auto}"
    local force="${3:-false}"
    
    echo "Starting modern bash installation process..." >&2
    echo "Target version: $target_version" >&2
    echo "Method: $method" >&2
    echo "Force: $force" >&2
    
    # Check if already satisfied (unless forced)
    if [ "$force" != "true" ] && check_bash_version "$target_version" >/dev/null 2>&1; then
        echo "✓ Bash version already meets requirements" >&2
        return 0
    fi
    
    # Detect OS if not already done
    if [ -z "${OS_ID:-}" ]; then
        detect_os
    fi
    
    # Install bash for detected OS
    if install_bash_for_os "$target_version" "$method"; then
        echo "✓ Bash installation completed" >&2
    else
        echo "ERROR: Bash installation failed" >&2
        return 1
    fi
    
    # Verify installation
    if verify_bash_installation "$target_version"; then
        echo "✓ Bash installation verification passed" >&2
        return 0
    else
        echo "ERROR: Bash installation verification failed" >&2
        return 1
    fi
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

show_installation_status() {
    echo "=== Bash Installation Status ==="
    echo "Current bash: $(command -v bash)"
    echo "Current version: $(get_bash_version)"
    echo "Target version: $TARGET_BASH_VERSION"
    echo "Version check: $(check_bash_version "$TARGET_BASH_VERSION" >/dev/null 2>&1 && echo "✓ PASS" || echo "✗ FAIL")"
    echo ""
    echo "Available bash installations:"
    local bash_locations=("/usr/local/bin/bash" "/usr/bin/bash" "/bin/bash")
    for bash_path in "${bash_locations[@]}"; do
        if [ -x "$bash_path" ]; then
            local version=$(get_bash_version "$bash_path")
            echo "  $bash_path: $version"
        fi
    done
    echo ""
    echo "OS Information:"
    echo "  OS: ${OS_ID:-not detected}"
    echo "  Version: ${OS_VERSION:-not detected}"
    echo "  Package Manager: $(get_package_manager 2>/dev/null || echo "not detected")"
}

list_available_methods() {
    local os_id="${1:-$OS_ID}"
    
    echo "Available installation methods for $os_id:"
    case "$os_id" in
        amzn|amazonlinux)
            echo "  - repository: Use yum/dnf package manager"
            echo "  - compile: Compile from source"
            echo "  - fallback: Install older version or system default"
            ;;
        ubuntu|debian)
            echo "  - repository: Use apt package manager"
            echo "  - third_party: Use backports or additional repositories"
            echo "  - compile: Compile from source"
            echo "  - fallback: Install older version or system default"
            ;;
        rocky|almalinux|centos|rhel)
            echo "  - repository: Use dnf/yum package manager"
            echo "  - third_party: Use EPEL or PowerTools repositories"
            echo "  - compile: Compile from source"
            echo "  - fallback: Install older version or system default"
            ;;
        *)
            echo "  - compile: Compile from source (generic)"
            echo "  - fallback: System default"
            ;;
    esac
    echo ""
    echo "Usage: install_bash_for_os <version> <method> <os_id>"
    echo "Example: install_bash_for_os 5.3 compile ubuntu"
}