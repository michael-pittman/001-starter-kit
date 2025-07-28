#!/usr/bin/env bash
# =============================================================================
# Bash Version Validation Module
# GeuseMaker Project - Standard bash 5.3.3+ requirement enforcement
# =============================================================================

# Module initialization guard to prevent multiple sourcing
if [[ -n "${_BASH_VERSION_MODULE_LOADED:-}" ]]; then
    return 0
fi
readonly _BASH_VERSION_MODULE_LOADED=1

# Global configuration - check if already defined before declaring as readonly
if [[ -z "${BASH_MIN_VERSION_MAJOR:-}" ]]; then
    readonly BASH_MIN_VERSION_MAJOR=5
fi
if [[ -z "${BASH_MIN_VERSION_MINOR:-}" ]]; then
    readonly BASH_MIN_VERSION_MINOR=3
fi
if [[ -z "${BASH_MIN_VERSION_PATCH:-}" ]]; then
    readonly BASH_MIN_VERSION_PATCH=3
fi
if [[ -z "${BASH_MIN_VERSION_STRING:-}" ]]; then
    readonly BASH_MIN_VERSION_STRING="5.3.3"
fi

# =============================================================================
# VERSION DETECTION AND VALIDATION FUNCTIONS
# =============================================================================

# Extract bash version components
get_bash_version_components() {
    local version_string="${BASH_VERSION}"
    local major minor patch
    
    # Parse version string (e.g., "5.3.3(1)-release" -> "5" "3" "3")
    if [[ $version_string =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        major="${BASH_REMATCH[1]}"
        minor="${BASH_REMATCH[2]}"
        patch="${BASH_REMATCH[3]}"
        
        echo "$major $minor $patch"
        return 0
    else
        echo "0 0 0"
        return 1
    fi
}

# Check if current bash version meets minimum requirements
check_bash_version() {
    local version_components
    version_components=$(get_bash_version_components)
    
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    read -r current_major current_minor current_patch <<< "$version_components"
    
    # Compare major version
    if (( current_major > BASH_MIN_VERSION_MAJOR )); then
        return 0
    elif (( current_major < BASH_MIN_VERSION_MAJOR )); then
        return 1
    fi
    
    # Major versions equal, compare minor
    if (( current_minor > BASH_MIN_VERSION_MINOR )); then
        return 0
    elif (( current_minor < BASH_MIN_VERSION_MINOR )); then
        return 1
    fi
    
    # Major and minor equal, compare patch
    if (( current_patch >= BASH_MIN_VERSION_PATCH )); then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# PLATFORM DETECTION
# =============================================================================

detect_platform() {
    case "$(uname -s)" in
        Darwin*)
            echo "macos"
            ;;
        Linux*)
            if [[ -f /etc/os-release ]]; then
                . /etc/os-release
                echo "${ID:-linux}"
            else
                echo "linux"
            fi
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# =============================================================================
# UPGRADE SUGGESTIONS
# =============================================================================

get_bash_upgrade_instructions() {
    local platform
    platform=$(detect_platform)
    
    # Use color if terminal supports it
    local bold=""
    local reset=""
    if [[ -t 2 ]]; then
        bold="\033[1m"
        reset="\033[0m"
    fi
    
    case "$platform" in
        macos)
            cat <<EOF
${bold}To upgrade bash on macOS:${reset}

1. ${bold}Install Homebrew${reset} (if not already installed):
   /bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

2. ${bold}Install latest bash:${reset}
   brew install bash

3. ${bold}Add Homebrew bash to allowed shells:${reset}
   # For Apple Silicon Macs (M1/M2/M3):
   echo '/opt/homebrew/bin/bash' | sudo tee -a /etc/shells
   
   # For Intel Macs:
   echo '/usr/local/bin/bash' | sudo tee -a /etc/shells

4. ${bold}Change your default shell${reset} (optional):
   # For Apple Silicon Macs:
   chsh -s /opt/homebrew/bin/bash
   
   # For Intel Macs:
   chsh -s /usr/local/bin/bash

5. ${bold}Restart your terminal or run:${reset}
   # For Apple Silicon Macs:
   exec /opt/homebrew/bin/bash
   
   # For Intel Macs:
   exec /usr/local/bin/bash

${bold}Note:${reset} You can check your Mac type with: uname -m
      • arm64 = Apple Silicon (M1/M2/M3)
      • x86_64 = Intel
EOF
            ;;
        ubuntu|debian)
            cat <<EOF
To upgrade bash on Ubuntu/Debian:

1. Update package lists:
   sudo apt update

2. Install latest bash:
   sudo apt install bash

3. Check installed version:
   bash --version

Note: Ubuntu 20.04+ usually has bash 5.0+, but you may need to compile from source
for bash 5.3.3+. Consider using Ubuntu 22.04+ for native bash 5.1+.
EOF
            ;;
        amzn|amazonlinux)
            cat <<EOF
To upgrade bash on Amazon Linux:

1. Update system:
   sudo yum update -y

2. Install development tools:
   sudo yum groupinstall -y "Development Tools"

3. Download and compile bash 5.3.3:
   cd /tmp
   wget https://ftp.gnu.org/gnu/bash/bash-5.3.3.tar.gz
   tar -xzf bash-5.3.3.tar.gz
   cd bash-5.3.3
   ./configure --prefix=/usr/local
   make && sudo make install

4. Update PATH (add to ~/.bashrc):
   export PATH="/usr/local/bin:\$PATH"

5. Restart session:
   exec /usr/local/bin/bash
EOF
            ;;
        *)
            cat <<EOF
To upgrade bash on your system:

1. Check your package manager:
   - Red Hat/CentOS/Fedora: yum install bash or dnf install bash
   - SUSE: zypper install bash
   - Arch: pacman -S bash

2. Or compile from source:
   wget https://ftp.gnu.org/gnu/bash/bash-5.3.3.tar.gz
   tar -xzf bash-5.3.3.tar.gz
   cd bash-5.3.3
   ./configure --prefix=/usr/local
   make && sudo make install

3. Update your PATH to use the new bash version.
EOF
            ;;
    esac
}

# =============================================================================
# USER-FRIENDLY VALIDATION WITH ERROR MESSAGES
# =============================================================================

validate_bash_version_with_message() {
    local script_name="${1:-$0}"
    local exit_on_failure="${2:-true}"
    
    if check_bash_version; then
        return 0
    fi
    
    # Version check failed - show detailed error message
    local current_version="${BASH_VERSION%%\(*}"  # Remove release info
    local platform
    platform=$(detect_platform)
    
    # Get version components for detailed comparison
    local version_components
    version_components=$(get_bash_version_components)
    read -r current_major current_minor current_patch <<< "$version_components"
    
    # Use color if terminal supports it
    local red=""
    local yellow=""
    local green=""
    local reset=""
    if [[ -t 2 ]]; then
        red="\033[0;31m"
        yellow="\033[0;33m"
        green="\033[0;32m"
        reset="\033[0m"
    fi
    
    cat >&2 <<EOF

${red}════════════════════════════════════════════════════════════════════════════${reset}
${red}ERROR: Bash Version Requirement Not Met!${reset}
${red}════════════════════════════════════════════════════════════════════════════${reset}

${yellow}Current Version:${reset} bash $current_version (${current_major}.${current_minor}.${current_patch})
${yellow}Required Version:${reset} bash $BASH_MIN_VERSION_STRING or higher
${yellow}Platform:${reset} $platform
${yellow}Script:${reset} $script_name
${yellow}User:${reset} $(whoami)
${yellow}Hostname:${reset} $(hostname)

${red}Why bash $BASH_MIN_VERSION_STRING is required:${reset}

  • ${green}Associative Arrays:${reset} Essential for modern data structures
    - Pricing cache management
    - Configuration inheritance
    - Resource state tracking
    
  • ${green}Enhanced Error Handling:${reset} Critical for production reliability
    - Structured error recovery
    - Graceful degradation
    - Detailed debugging capabilities
    
  • ${green}Performance Optimizations:${reset} Faster script execution
    - Improved array operations
    - Better memory management
    - Efficient string manipulation
    
  • ${green}Security Fixes:${reset} Important vulnerability patches
    - Input validation improvements
    - Command injection protections
    - Variable expansion fixes

${yellow}════════════════════════════════════════════════════════════════════════════${reset}
${yellow}UPGRADE INSTRUCTIONS FOR YOUR PLATFORM${reset}
${yellow}════════════════════════════════════════════════════════════════════════════${reset}

$(get_bash_upgrade_instructions)

${yellow}════════════════════════════════════════════════════════════════════════════${reset}
${yellow}QUICK SOLUTIONS${reset}
${yellow}════════════════════════════════════════════════════════════════════════════${reset}

${green}Option 1: Use the correct bash directly${reset}
EOF

    # Check if modern bash exists in common locations
    local modern_bash_found=false
    local modern_bash_paths=(
        "/opt/homebrew/bin/bash"
        "/usr/local/bin/bash"
        "/usr/local/bin/bash-5.3"
    )
    
    for bash_path in "${modern_bash_paths[@]}"; do
        if [[ -x "$bash_path" ]]; then
            local test_version
            test_version=$($bash_path -c 'echo $BASH_VERSION' 2>/dev/null || echo "0.0.0")
            if [[ "$test_version" =~ ^5\.[3-9] ]] || [[ "$test_version" =~ ^[6-9] ]]; then
                echo -e "  ${green}Found modern bash at: $bash_path (version: $test_version)${reset}" >&2
                echo -e "  Run: ${green}$bash_path $script_name${reset}\n" >&2
                modern_bash_found=true
            fi
        fi
    done
    
    if [[ "$modern_bash_found" == "false" ]]; then
        echo -e "  ${red}No modern bash found in standard locations${reset}\n" >&2
    fi
    
    cat >&2 <<EOF
${green}Option 2: Verify after upgrade${reset}
  bash --version
  
${green}Option 3: Check which bash versions are installed${reset}
  which -a bash
  ls -la /usr/bin/bash* /usr/local/bin/bash* /opt/homebrew/bin/bash* 2>/dev/null

${yellow}════════════════════════════════════════════════════════════════════════════${reset}
${yellow}NEED HELP?${reset}
${yellow}════════════════════════════════════════════════════════════════════════════${reset}

• Documentation: https://github.com/anthropics/001-starter-kit/docs/OS-COMPATIBILITY.md
• Report Issue: https://github.com/anthropics/001-starter-kit/issues
• Current Path: \$PATH
$(echo "$PATH" | tr ':' '\n' | sed 's/^/  - /')

${red}Cannot proceed without bash $BASH_MIN_VERSION_STRING or higher.${reset}

EOF
    
    if [[ "$exit_on_failure" == "true" ]]; then
        exit 1
    else
        return 1
    fi
}

# =============================================================================
# EC2 USER DATA BASH INSTALLATION
# =============================================================================

get_ec2_bash_install_script() {
    cat <<'EOF'
# Install bash 5.3.3+ on EC2 instance
install_modern_bash() {
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        amzn|amazonlinux)
            echo "Installing bash 5.3.3 on Amazon Linux..."
            yum update -y
            yum groupinstall -y "Development Tools"
            
            cd /tmp
            wget -q https://ftp.gnu.org/gnu/bash/bash-5.3.3.tar.gz
            tar -xzf bash-5.3.3.tar.gz
            cd bash-5.3.3
            
            ./configure --prefix=/usr/local --enable-static-link
            make -j$(nproc) && make install
            
            # Create symlink for system scripts
            ln -sf /usr/local/bin/bash /usr/local/bin/bash-5.3
            
            # Update PATH for future sessions
            echo 'export PATH="/usr/local/bin:$PATH"' >> /etc/profile.d/modern-bash.sh
            chmod +x /etc/profile.d/modern-bash.sh
            
            echo "bash 5.3.3 installed successfully at /usr/local/bin/bash"
            ;;
        ubuntu|debian)
            echo "Installing latest bash on Ubuntu/Debian..."
            apt update -y
            apt install -y bash
            ;;
        *)
            echo "Unknown platform: $platform. Manual bash installation may be required."
            ;;
    esac
}
EOF
}

# =============================================================================
# CONVENIENCE FUNCTIONS
# =============================================================================

# Quick validation for use in scripts
require_bash_533() {
    validate_bash_version_with_message "$@"
}

# Non-exiting check for conditional logic
bash_533_available() {
    check_bash_version
}

# Get current bash version string
get_current_bash_version() {
    echo "${BASH_VERSION%%\(*}"
}

# Enhanced version comparison function
compare_bash_versions() {
    local version1="$1"
    local version2="$2"
    local operator="${3:-ge}"  # Default to greater-or-equal
    
    # Parse version1
    local v1_major v1_minor v1_patch
    if [[ $version1 =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        v1_major="${BASH_REMATCH[1]}"
        v1_minor="${BASH_REMATCH[2]}"
        v1_patch="${BASH_REMATCH[3]}"
    else
        return 2  # Invalid version format
    fi
    
    # Parse version2
    local v2_major v2_minor v2_patch
    if [[ $version2 =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
        v2_major="${BASH_REMATCH[1]}"
        v2_minor="${BASH_REMATCH[2]}"
        v2_patch="${BASH_REMATCH[3]}"
    else
        return 2  # Invalid version format
    fi
    
    # Convert to comparable numbers
    local v1_num=$((v1_major * 10000 + v1_minor * 100 + v1_patch))
    local v2_num=$((v2_major * 10000 + v2_minor * 100 + v2_patch))
    
    # Perform comparison
    case "$operator" in
        "eq") [[ $v1_num -eq $v2_num ]] ;;
        "ne") [[ $v1_num -ne $v2_num ]] ;;
        "lt") [[ $v1_num -lt $v2_num ]] ;;
        "le") [[ $v1_num -le $v2_num ]] ;;
        "gt") [[ $v1_num -gt $v2_num ]] ;;
        "ge") [[ $v1_num -ge $v2_num ]] ;;
        *) return 2 ;;  # Invalid operator
    esac
}

# Find best available bash
find_best_bash() {
    local min_version="${1:-$BASH_MIN_VERSION_STRING}"
    local best_bash=""
    local best_version="0.0.0"
    
    # Common bash locations
    local bash_locations=(
        "/opt/homebrew/bin/bash"
        "/usr/local/bin/bash"
        "/usr/local/bin/bash-5.3"
        "/usr/bin/bash"
        "/bin/bash"
    )
    
    for bash_path in "${bash_locations[@]}"; do
        if [[ -x "$bash_path" ]]; then
            local test_version
            test_version=$($bash_path -c 'echo ${BASH_VERSION%%\(*}' 2>/dev/null || echo "0.0.0")
            
            if compare_bash_versions "$test_version" "$min_version" "ge" && \
               compare_bash_versions "$test_version" "$best_version" "gt"; then
                best_bash="$bash_path"
                best_version="$test_version"
            fi
        fi
    done
    
    if [[ -n "$best_bash" ]]; then
        echo "$best_bash"
        return 0
    else
        return 1
    fi
}

# =============================================================================
# ENHANCED BASH VERSION CHECK (Makefile Compatible)
# =============================================================================

# Enhanced bash version check with instructions (Makefile compatible)
check_bash_version_enhanced() {
    echo -e "\n=== Checking Bash Version ==="
    
    local current_version="${BASH_VERSION}"
    local major_version="${BASH_VERSINFO[0]}"
    local minor_version="${BASH_VERSINFO[1]}"
    
    echo "Current Bash version: $current_version"
    
    if [[ $major_version -lt 5 ]] || ([[ $major_version -eq 5 ]] && [[ $minor_version -lt 3 ]]); then
        echo -e "\n✗ ERROR: Bash version 5.3 or higher is required"
        echo -e "\nYour current version ($current_version) is too old for this project."
        echo -e "\nUpgrade Instructions:"
        
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo -e "\nmacOS:"
            echo "  1. Install Homebrew if not already installed:"
            echo "     /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
            echo "  2. Install modern Bash:"
            echo "     brew install bash"
            echo "  3. Add to allowed shells:"
            echo "     sudo echo '/opt/homebrew/bin/bash' >> /etc/shells"
            echo "  4. Change your default shell (optional):"
            echo "     chsh -s /opt/homebrew/bin/bash"
            echo "  5. Or run scripts with:"
            echo "     /opt/homebrew/bin/bash script.sh"
        elif [[ -f /etc/debian_version ]]; then
            echo -e "\nUbuntu/Debian:"
            echo "  1. Update package list:"
            echo "     sudo apt update"
            echo "  2. Install latest bash:"
            echo "     sudo apt install -y bash"
            echo "  3. If still old, compile from source:"
            echo "     wget https://ftp.gnu.org/gnu/bash/bash-5.3.tar.gz"
            echo "     tar -xzf bash-5.3.tar.gz && cd bash-5.3"
            echo "     ./configure --prefix=/usr/local && make && sudo make install"
            echo "     sudo ln -sf /usr/local/bin/bash /usr/bin/bash"
        elif [[ -f /etc/redhat-release ]] || [[ -f /etc/system-release ]]; then
            echo -e "\nRed Hat/CentOS/Amazon Linux:"
            echo "  1. Enable EPEL repository:"
            echo "     sudo yum install -y epel-release"
            echo "  2. Install development tools:"
            echo "     sudo yum groupinstall -y 'Development Tools'"
            echo "  3. Compile from source:"
            echo "     wget https://ftp.gnu.org/gnu/bash/bash-5.3.tar.gz"
            echo "     tar -xzf bash-5.3.tar.gz && cd bash-5.3"
            echo "     ./configure --prefix=/usr/local && make && sudo make install"
            echo "     sudo ln -sf /usr/local/bin/bash /usr/bin/bash"
        fi
        
        echo -e "\nVerify installation:"
        echo "  bash --version"
        
        return 1
    else
        echo "✓ Bash version $current_version meets requirements"
        return 0
    fi
}

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

# Export functions for use by sourcing scripts (only if not already exported)
if ! declare -F check_bash_version >/dev/null 2>&1; then
    export -f check_bash_version
fi
if ! declare -F validate_bash_version_with_message >/dev/null 2>&1; then
    export -f validate_bash_version_with_message
fi
if ! declare -F require_bash_533 >/dev/null 2>&1; then
    export -f require_bash_533
fi
if ! declare -F bash_533_available >/dev/null 2>&1; then
    export -f bash_533_available
fi
if ! declare -F get_current_bash_version >/dev/null 2>&1; then
    export -f get_current_bash_version
fi
if ! declare -F detect_platform >/dev/null 2>&1; then
    export -f detect_platform
fi
if ! declare -F get_bash_upgrade_instructions >/dev/null 2>&1; then
    export -f get_bash_upgrade_instructions
fi
if ! declare -F get_ec2_bash_install_script >/dev/null 2>&1; then
    export -f get_ec2_bash_install_script
fi
if ! declare -F compare_bash_versions >/dev/null 2>&1; then
    export -f compare_bash_versions
fi
if ! declare -F find_best_bash >/dev/null 2>&1; then
    export -f find_best_bash
fi
if ! declare -F get_bash_version_components >/dev/null 2>&1; then
    export -f get_bash_version_components
fi
if ! declare -F check_bash_version_enhanced >/dev/null 2>&1; then
    export -f check_bash_version_enhanced
fi