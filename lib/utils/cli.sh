#!/usr/bin/env bash

# CLI Utilities Module
# Enhanced user feedback system with professional appearance
# Provides success/failure indicators, helpful error messages, and consistent formatting

set -euo pipefail

# =============================================================================
# COLOR DEFINITIONS
# =============================================================================

# Enhanced color scheme for professional appearance
CLI_COLOR_RESET='\033[0m'
CLI_COLOR_BOLD='\033[1m'
CLI_COLOR_DIM='\033[2m'
CLI_COLOR_UNDERLINE='\033[4m'

# Primary colors
CLI_COLOR_GREEN='\033[0;32m'
CLI_COLOR_RED='\033[0;31m'
CLI_COLOR_YELLOW='\033[1;33m'
CLI_COLOR_BLUE='\033[0;34m'
CLI_COLOR_CYAN='\033[0;36m'
CLI_COLOR_MAGENTA='\033[0;35m'
CLI_COLOR_GRAY='\033[0;37m'

# Bright variants
CLI_COLOR_BRIGHT_GREEN='\033[0;92m'
CLI_COLOR_BRIGHT_RED='\033[0;91m'
CLI_COLOR_BRIGHT_YELLOW='\033[0;93m'
CLI_COLOR_BRIGHT_BLUE='\033[0;94m'
CLI_COLOR_BRIGHT_CYAN='\033[0;96m'

# Background colors
CLI_BG_GREEN='\033[42m'
CLI_BG_RED='\033[41m'
CLI_BG_YELLOW='\033[43m'
CLI_BG_BLUE='\033[44m'

# =============================================================================
# ICONS AND SYMBOLS
# =============================================================================

# Success/failure indicators
CLI_ICON_SUCCESS='✓'
CLI_ICON_FAILURE='✗'
CLI_ICON_WARNING='⚠'
CLI_ICON_INFO='ℹ'
CLI_ICON_QUESTION='?'
CLI_ICON_ARROW='→'
CLI_ICON_CHECK='✓'
CLI_ICON_CROSS='✗'
CLI_ICON_STAR='★'
CLI_ICON_DIAMOND='◆'
CLI_ICON_CIRCLE='●'

# =============================================================================
# MESSAGE TYPES
# =============================================================================

# Message type definitions
declare -A CLI_MESSAGE_TYPES=(
    [SUCCESS]="success"
    [ERROR]="error"
    [WARNING]="warning"
    [INFO]="info"
    [DEBUG]="debug"
    [PROMPT]="prompt"
    [STATUS]="status"
    [STEP]="step"
    [HEADER]="header"
    [SUBHEADER]="subheader"
)

# =============================================================================
# TERMINAL DETECTION
# =============================================================================

# Terminal capabilities
CLI_TERMINAL_SUPPORTS_COLOR=false
CLI_TERMINAL_WIDTH=80
CLI_TERMINAL_HEIGHT=24

# Detect terminal capabilities
cli_detect_terminal() {
    # Check if we're in a terminal
    if [[ ! -t 1 ]]; then
        CLI_TERMINAL_SUPPORTS_COLOR=false
        CLI_TERMINAL_WIDTH=80
        CLI_TERMINAL_HEIGHT=24
        return 0
    fi
    
    # Check color support
    if command -v tput >/dev/null 2>&1; then
        local colors=$(tput colors 2>/dev/null || echo 0)
        if [[ $colors -ge 8 ]]; then
            CLI_TERMINAL_SUPPORTS_COLOR=true
        fi
        
        # Get terminal dimensions with fallback
        CLI_TERMINAL_WIDTH=$(tput cols 2>/dev/null || echo 80)
        CLI_TERMINAL_HEIGHT=$(tput lines 2>/dev/null || echo 24)
        
        # Validate dimensions are reasonable
        if [[ ! "$CLI_TERMINAL_WIDTH" =~ ^[0-9]+$ ]] || [[ $CLI_TERMINAL_WIDTH -lt 20 ]]; then
            CLI_TERMINAL_WIDTH=80
        fi
        if [[ ! "$CLI_TERMINAL_HEIGHT" =~ ^[0-9]+$ ]] || [[ $CLI_TERMINAL_HEIGHT -lt 10 ]]; then
            CLI_TERMINAL_HEIGHT=24
        fi
    fi
    
    # Enhanced fallback color detection
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" != "true" ]]; then
        # Check for common terminal types that support color
        if [[ "${TERM:-}" =~ (xterm|screen|tmux|linux|vt100|vt220|ansi) ]]; then
            CLI_TERMINAL_SUPPORTS_COLOR=true
        elif [[ "${COLORTERM:-}" == "truecolor" ]] || [[ "${COLORTERM:-}" == "24bit" ]]; then
            CLI_TERMINAL_SUPPORTS_COLOR=true
        elif [[ "${CLICOLOR:-}" == "1" ]]; then
            CLI_TERMINAL_SUPPORTS_COLOR=true
        fi
    fi
    
    # Final fallback for terminal dimensions
    if [[ ! "$CLI_TERMINAL_WIDTH" =~ ^[0-9]+$ ]] || [[ $CLI_TERMINAL_WIDTH -lt 20 ]]; then
        CLI_TERMINAL_WIDTH=80
    fi
    if [[ ! "$CLI_TERMINAL_HEIGHT" =~ ^[0-9]+$ ]] || [[ $CLI_TERMINAL_HEIGHT -lt 10 ]]; then
        CLI_TERMINAL_HEIGHT=24
    fi
}

# =============================================================================
# SUCCESS/FAILURE INDICATORS
# =============================================================================

# Display success message with visual indicator
cli_success() {
    local message="$1"
    local details="${2:-}"
    
    local output=""
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
        output+="$CLI_COLOR_BOLD$CLI_COLOR_GREEN$CLI_ICON_SUCCESS Success$CLI_COLOR_RESET"
    else
        output+="$CLI_ICON_SUCCESS Success"
    fi
    
    output+=": $message"
    
    if [[ -n "$details" ]]; then
        output+=" $CLI_COLOR_DIM($details)$CLI_COLOR_RESET"
    fi
    
    printf "%s\n" "$output"
    
    # Log success if logging is available
    if [[ -n "${LIB_LOGGING_LOADED:-}" ]]; then
        log_info "CLI Success: $message"
    fi
}

# Display failure message with visual indicator
cli_failure() {
    local message="$1"
    local details="${2:-}"
    local recovery="${3:-}"
    
    local output=""
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
        output+="$CLI_COLOR_BOLD$CLI_COLOR_RED$CLI_ICON_FAILURE Error$CLI_COLOR_RESET"
    else
        output+="$CLI_ICON_FAILURE Error"
    fi
    
    output+=": $message"
    
    if [[ -n "$details" ]]; then
        output+=" $CLI_COLOR_DIM($details)$CLI_COLOR_RESET"
    fi
    
    printf "%s\n" "$output"
    
    # Show recovery suggestion if provided
    if [[ -n "$recovery" ]]; then
        cli_info "Recovery: $recovery"
    fi
    
    # Log error if logging is available
    if [[ -n "${LIB_LOGGING_LOADED:-}" ]]; then
        log_error "CLI Error: $message"
    fi
}

# Display warning message
cli_warning() {
    local message="$1"
    local details="${2:-}"
    
    local output=""
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
        output+="$CLI_COLOR_BOLD$CLI_COLOR_YELLOW$CLI_ICON_WARNING Warning$CLI_COLOR_RESET"
    else
        output+="$CLI_ICON_WARNING Warning"
    fi
    
    output+=": $message"
    
    if [[ -n "$details" ]]; then
        output+=" $CLI_COLOR_DIM($details)$CLI_COLOR_RESET"
    fi
    
    printf "%s\n" "$output"
    
    # Log warning if logging is available
    if [[ -n "${LIB_LOGGING_LOADED:-}" ]]; then
        log_warn "CLI Warning: $message"
    fi
}

# Display info message
cli_info() {
    local message="$1"
    local details="${2:-}"
    
    local output=""
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
        output+="$CLI_COLOR_BOLD$CLI_COLOR_BLUE$CLI_ICON_INFO Info$CLI_COLOR_RESET"
    else
        output+="$CLI_ICON_INFO Info"
    fi
    
    output+=": $message"
    
    if [[ -n "$details" ]]; then
        output+=" $CLI_COLOR_DIM($details)$CLI_COLOR_RESET"
    fi
    
    printf "%s\n" "$output"
    
    # Log info if logging is available
    if [[ -n "${LIB_LOGGING_LOADED:-}" ]]; then
        log_info "CLI Info: $message"
    fi
}

# =============================================================================
# STATUS UPDATES
# =============================================================================

# Display step status update
cli_step() {
    local step_number="$1"
    local total_steps="$2"
    local description="$3"
    local status="${4:-pending}"
    
    local output=""
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
        output+="$CLI_COLOR_BOLD$CLI_COLOR_CYAN[$step_number/$total_steps]$CLI_COLOR_RESET"
    else
        output+="[$step_number/$total_steps]"
    fi
    
    output+=" $description"
    
    case "$status" in
        "pending")
            if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
                output+=" $CLI_COLOR_GRAY(pending)$CLI_COLOR_RESET"
            else
                output+=" (pending)"
            fi
            ;;
        "running")
            if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
                output+=" $CLI_COLOR_YELLOW$CLI_ICON_ARROW running...$CLI_COLOR_RESET"
            else
                output+=" -> running..."
            fi
            ;;
        "completed")
            if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
                output+=" $CLI_COLOR_GREEN$CLI_ICON_CHECK completed$CLI_COLOR_RESET"
            else
                output+=" ✓ completed"
            fi
            ;;
        "failed")
            if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
                output+=" $CLI_COLOR_RED$CLI_ICON_CROSS failed$CLI_COLOR_RESET"
            else
                output+=" ✗ failed"
            fi
            ;;
    esac
    
    printf "%s\n" "$output"
}

# Display operation status
cli_status() {
    local operation="$1"
    local status="$2"
    local details="${3:-}"
    
    local output=""
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
        output+="$CLI_COLOR_BOLD$CLI_COLOR_BLUE$operation$CLI_COLOR_RESET"
    else
        output+="$operation"
    fi
    
    output+=": "
    
    case "$status" in
        "success"|"completed"|"ok")
            if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
                output+="$CLI_COLOR_GREEN$CLI_ICON_SUCCESS$CLI_COLOR_RESET"
            else
                output+="$CLI_ICON_SUCCESS"
            fi
            ;;
        "error"|"failed"|"failed")
            if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
                output+="$CLI_COLOR_RED$CLI_ICON_FAILURE$CLI_COLOR_RESET"
            else
                output+="$CLI_ICON_FAILURE"
            fi
            ;;
        "warning"|"warn")
            if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
                output+="$CLI_COLOR_YELLOW$CLI_ICON_WARNING$CLI_COLOR_RESET"
            else
                output+="$CLI_ICON_WARNING"
            fi
            ;;
        "info"|"information")
            if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
                output+="$CLI_COLOR_BLUE$CLI_ICON_INFO$CLI_COLOR_RESET"
            else
                output+="$CLI_ICON_INFO"
            fi
            ;;
        *)
            output+="$status"
            ;;
    esac
    
    if [[ -n "$details" ]]; then
        output+=" $CLI_COLOR_DIM($details)$CLI_COLOR_RESET"
    fi
    
    printf "%s\n" "$output"
}

# =============================================================================
# HEADERS AND FORMATTING
# =============================================================================

# Display section header
cli_header() {
    local title="$1"
    local subtitle="${2:-}"
    
    printf "\n"
    
    local output=""
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
        output+="$CLI_COLOR_BOLD$CLI_COLOR_CYAN$CLI_ICON_DIAMOND $title$CLI_COLOR_RESET"
    else
        output+="$CLI_ICON_DIAMOND $title"
    fi
    
    printf "%s\n" "$output"
    
    if [[ -n "$subtitle" ]]; then
        if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
            printf "%s\n" "$CLI_COLOR_DIM$subtitle$CLI_COLOR_RESET"
        else
            printf "%s\n" "$subtitle"
        fi
    fi
    
    # Add separator line
    cli_separator
}

# Display subheader
cli_subheader() {
    local title="$1"
    
    local output=""
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
        output+="$CLI_COLOR_BOLD$CLI_COLOR_BLUE$CLI_ICON_STAR $title$CLI_COLOR_RESET"
    else
        output+="$CLI_ICON_STAR $title"
    fi
    
    printf "%s\n" "$output"
}

# Display separator line
cli_separator() {
    local char="${1:--}"
    local width="${2:-$CLI_TERMINAL_WIDTH}"
    
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
        printf "%s\n" "$CLI_COLOR_DIM$(printf "%${width}s" | tr ' ' "$char")$CLI_COLOR_RESET"
    else
        printf "%s\n" "$(printf "%${width}s" | tr ' ' "$char")"
    fi
}

# =============================================================================
# USER-FRIENDLY MESSAGES
# =============================================================================

# Display user-friendly operation message
cli_operation() {
    local operation="$1"
    local description="$2"
    local status="${3:-starting}"
    
    local output=""
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
        output+="$CLI_COLOR_BOLD$CLI_COLOR_MAGENTA$operation$CLI_COLOR_RESET"
    else
        output+="$operation"
    fi
    
    output+=": $description"
    
    case "$status" in
        "starting")
            if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
                output+=" $CLI_COLOR_YELLOW$CLI_ICON_ARROW starting...$CLI_COLOR_RESET"
            else
                output+=" -> starting..."
            fi
            ;;
        "in_progress")
            if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
                output+=" $CLI_COLOR_BLUE$CLI_ICON_ARROW in progress...$CLI_COLOR_RESET"
            else
                output+=" -> in progress..."
            fi
            ;;
        "completed")
            if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
                output+=" $CLI_COLOR_GREEN$CLI_ICON_CHECK completed$CLI_COLOR_RESET"
            else
                output+=" ✓ completed"
            fi
            ;;
        "failed")
            if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
                output+=" $CLI_COLOR_RED$CLI_ICON_CROSS failed$CLI_COLOR_RESET"
            else
                output+=" ✗ failed"
            fi
            ;;
    esac
    
    printf "%s\n" "$output"
}

# Display helpful tip
cli_tip() {
    local tip="$1"
    
    local output=""
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
        output+="$CLI_COLOR_BOLD$CLI_COLOR_CYAN Tip$CLI_COLOR_RESET: "
    else
        output+="Tip: "
    fi
    
    output+="$tip"
    
    printf "%s\n" "$output"
}

# Display note
cli_note() {
    local note="$1"
    
    local output=""
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
        output+="$CLI_COLOR_BOLD$CLI_COLOR_BLUE Note$CLI_COLOR_RESET: "
    else
        output+="Note: "
    fi
    
    output+="$note"
    
    printf "%s\n" "$output"
}

# =============================================================================
# ERROR MESSAGE HELPERS
# =============================================================================

# Display helpful error message with recovery suggestions
cli_error_with_recovery() {
    local error_message="$1"
    local error_code="${2:-}"
    local recovery_steps="${3:-}"
    local additional_info="${4:-}"
    
    # Input validation
    if [[ -z "$error_message" ]]; then
        error_message="Unknown error occurred"
    fi
    
    # Validate error message is a string
    if [[ ! "$error_message" =~ ^[[:print:]]+$ ]]; then
        error_message="Invalid error message format"
    fi
    
    # Display error
    cli_failure "$error_message" "$error_code"
    
    # Show recovery steps if provided
    if [[ -n "$recovery_steps" ]]; then
        printf "\n"
        cli_subheader "Recovery Steps"
        
        # Split recovery steps by newline and display each
        while IFS= read -r step; do
            if [[ -n "$step" ]]; then
                if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
                    printf "  $CLI_COLOR_CYAN$CLI_ICON_ARROW$CLI_COLOR_RESET %s\n" "$step"
                else
                    printf "  $CLI_ICON_ARROW %s\n" "$step"
                fi
            fi
        done <<< "$recovery_steps"
    fi
    
    # Show additional information if provided
    if [[ -n "$additional_info" ]]; then
        printf "\n"
        cli_note "$additional_info"
    fi
}

# Display common error patterns with helpful messages
cli_common_error() {
    local error_type="$1"
    local details="${2:-}"
    
    case "$error_type" in
        "aws_credentials")
            cli_error_with_recovery \
                "AWS credentials not found or invalid" \
                "AWS_CREDENTIALS_ERROR" \
                "1. Run 'aws configure' to set up credentials\n2. Check your AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables\n3. Verify your AWS profile is correctly configured" \
                "Make sure you have the necessary AWS permissions for this operation."
            ;;
        "network_timeout")
            cli_error_with_recovery \
                "Network operation timed out" \
                "NETWORK_TIMEOUT" \
                "1. Check your internet connection\n2. Verify the target service is accessible\n3. Try again in a few moments\n4. Check firewall settings if applicable" \
                "This may be a temporary network issue."
            ;;
        "permission_denied")
            cli_error_with_recovery \
                "Permission denied for operation" \
                "PERMISSION_DENIED" \
                "1. Check if you have the required permissions\n2. Verify your user/role has the necessary access\n3. Contact your system administrator\n4. Check file/directory permissions" \
                "You may need elevated privileges for this operation."
            ;;
        "resource_not_found")
            cli_error_with_recovery \
                "Required resource not found" \
                "RESOURCE_NOT_FOUND" \
                "1. Verify the resource exists\n2. Check the resource name/ID is correct\n3. Ensure you're in the correct region/account\n4. Create the resource if it doesn't exist" \
                "The resource may have been deleted or moved."
            ;;
        "configuration_error")
            cli_error_with_recovery \
                "Configuration error detected" \
                "CONFIG_ERROR" \
                "1. Check your configuration files\n2. Verify all required parameters are set\n3. Validate configuration format\n4. Review configuration documentation" \
                "Configuration files should be in YAML or JSON format."
            ;;
        *)
            cli_failure "Unknown error type: $error_type" "$details"
            ;;
    esac
}

# =============================================================================
# PROMPT AND INTERACTION
# =============================================================================

# Display user prompt
cli_prompt() {
    local question="$1"
    local default="${2:-}"
    local options="${3:-}"
    
    local output=""
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
        output+="$CLI_COLOR_BOLD$CLI_COLOR_YELLOW$CLI_ICON_QUESTION $question$CLI_COLOR_RESET"
    else
        output+="$CLI_ICON_QUESTION $question"
    fi
    
    if [[ -n "$default" ]]; then
        output+=" $CLI_COLOR_DIM(default: $default)$CLI_COLOR_RESET"
    fi
    
    if [[ -n "$options" ]]; then
        output+=" $CLI_COLOR_DIM($options)$CLI_COLOR_RESET"
    fi
    
    output+=": "
    
    printf "%s" "$output"
}

# Display confirmation prompt
cli_confirm() {
    local question="$1"
    local default="${2:-y}"
    
    local default_text=""
    case "$default" in
        "y"|"yes") default_text="Y/n" ;;
        "n"|"no") default_text="y/N" ;;
        *) default_text="y/n" ;;
    esac
    
    cli_prompt "$question" "" "$default_text"
}

# =============================================================================
# PROGRESS AND LOADING
# =============================================================================

# Display loading spinner
cli_spinner() {
    local message="$1"
    local pid="$2"
    
    local spinner_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    
    while kill -0 "$pid" 2>/dev/null; do
        local spinner="${spinner_chars[$i]}"
        if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
            printf "\r$CLI_COLOR_CYAN$spinner$CLI_COLOR_RESET $message"
        else
            printf "\r$spinner $message"
        fi
        sleep 0.1
        i=$(((i + 1) % ${#spinner_chars[@]}))
    done
    
    printf "\r"
    printf "%${#message}s" ""  # Clear the message
    printf "\r"
}

# Display progress percentage
cli_progress() {
    local current="$1"
    local total="$2"
    local description="$3"
    
    # Parameter validation
    if [[ ! "$current" =~ ^[0-9]+$ ]] || [[ ! "$total" =~ ^[0-9]+$ ]]; then
        printf "\rError: Invalid progress parameters (current: %s, total: %s)\n" "$current" "$total"
        return 1
    fi
    
    if [[ $total -eq 0 ]]; then
        printf "\rError: Total cannot be zero\n"
        return 1
    fi
    
    if [[ $current -lt 0 ]] || [[ $current -gt $total ]]; then
        printf "\rError: Current value (%d) must be between 0 and %d\n" "$current" "$total"
        return 1
    fi
    
    local percentage=$((current * 100 / total))
    local bar_width=20
    local filled=$((bar_width * current / total))
    local empty=$((bar_width - filled))
    
    local bar=""
    if [[ $filled -gt 0 ]]; then
        bar+=$(printf "%${filled}s" | tr ' ' '█')
    fi
    if [[ $empty -gt 0 ]]; then
        bar+=$(printf "%${empty}s" | tr ' ' '░')
    fi
    
    local output=""
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
        output+="$CLI_COLOR_CYAN[$bar]$CLI_COLOR_RESET"
    else
        output+="[$bar]"
    fi
    
    output+=" $percentage% - $description"
    
    printf "\r%s" "$output"
}

# =============================================================================
# INTERACTIVE CLI FEATURES
# =============================================================================

# Help system with numbered options
declare -A CLI_HELP_SECTIONS=()
declare -A CLI_COMMANDS=()
declare -A CLI_COMMAND_DESCRIPTIONS=()
declare -A CLI_COMMAND_EXAMPLES=()

# Register a command for help system
cli_register_command() {
    local command="$1"
    local description="$2"
    local example="${3:-}"
    local section="${4:-General}"
    
    CLI_COMMANDS["$command"]="$description"
    if [[ -n "$example" ]]; then
        CLI_COMMAND_EXAMPLES["$command"]="$example"
    fi
    
    # Add to section
    if [[ -z "${CLI_HELP_SECTIONS[$section]:-}" ]]; then
        CLI_HELP_SECTIONS["$section"]=""
    fi
    CLI_HELP_SECTIONS["$section"]+="$command "
}

# Display comprehensive help menu
cli_help_menu() {
    local section_filter="${1:-}"
    
    cli_header "Interactive CLI Help System"
    
    if [[ -n "$section_filter" ]]; then
        cli_help_section "$section_filter"
        return 0
    fi
    
    # Display main menu
    printf "\n"
    cli_subheader "Available Sections"
    
    local section_number=1
    for section in "${!CLI_HELP_SECTIONS[@]}"; do
        if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
            printf "  $CLI_COLOR_BOLD$CLI_COLOR_CYAN%d.$CLI_COLOR_RESET %s\n" "$section_number" "$section"
        else
            printf "  %d. %s\n" "$section_number" "$section"
        fi
        section_number=$((section_number + 1))
    done
    
    printf "\n"
    cli_tip "Type a section number or name to view detailed help"
    cli_tip "Use 'help <command>' for specific command help"
    cli_tip "Use 'help all' to view all commands"
    
    # Interactive section selection
    cli_prompt "Enter section number or name" "" "or 'q' to quit"
    read -r user_input
    
    case "$user_input" in
        "q"|"quit"|"exit")
            cli_info "Help system closed"
            return 0
            ;;
        "all")
            cli_help_all_commands
            ;;
        *)
            # Try to find section by number or name
            local selected_section=""
            if [[ "$user_input" =~ ^[0-9]+$ ]]; then
                # Number input
                local section_index=1
                for section in "${!CLI_HELP_SECTIONS[@]}"; do
                    if [[ $section_index -eq $user_input ]]; then
                        selected_section="$section"
                        break
                    fi
                    section_index=$((section_index + 1))
                done
            else
                # Name input - fuzzy matching
                for section in "${!CLI_HELP_SECTIONS[@]}"; do
                    if [[ "$section" == *"$user_input"* ]] || [[ "$user_input" == *"$section"* ]]; then
                        selected_section="$section"
                        break
                    fi
                done
            fi
            
            if [[ -n "$selected_section" ]]; then
                cli_help_section "$selected_section"
            else
                cli_warning "Section not found: $user_input"
                cli_help_menu
            fi
            ;;
    esac
}

# Display help for a specific section
cli_help_section() {
    local section="$1"
    
    if [[ -z "${CLI_HELP_SECTIONS[$section]:-}" ]]; then
        cli_warning "Section not found: $section"
        return 1
    fi
    
    cli_header "Help: $section"
    
    local commands_in_section=(${CLI_HELP_SECTIONS[$section]})
    local command_number=1
    
    for command in "${commands_in_section[@]}"; do
        if [[ -n "${CLI_COMMANDS[$command]:-}" ]]; then
            if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
                printf "  $CLI_COLOR_BOLD$CLI_COLOR_GREEN%d.$CLI_COLOR_RESET %s\n" "$command_number" "$command"
                printf "     $CLI_COLOR_DIM%s$CLI_COLOR_RESET\n" "${CLI_COMMANDS[$command]}"
            else
                printf "  %d. %s\n" "$command_number" "$command"
                printf "     %s\n" "${CLI_COMMANDS[$command]}"
            fi
            
            if [[ -n "${CLI_COMMAND_EXAMPLES[$command]:-}" ]]; then
                if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
                    printf "     %sExample:%s %s\n" "$CLI_COLOR_CYAN" "$CLI_COLOR_RESET" "${CLI_COMMAND_EXAMPLES[$command]}"
                else
                    printf "     Example: %s\n" "${CLI_COMMAND_EXAMPLES[$command]}"
                fi
            fi
            printf "\n"
            command_number=$((command_number + 1))
        fi
    done
    
    cli_tip "Use 'help <command>' for detailed command information"
}

# Display help for all commands
cli_help_all_commands() {
    cli_header "All Available Commands"
    
    local command_number=1
    for command in "${!CLI_COMMANDS[@]}"; do
        if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
            printf "  $CLI_COLOR_BOLD$CLI_COLOR_GREEN%d.$CLI_COLOR_RESET %s\n" "$command_number" "$command"
            printf "     $CLI_COLOR_DIM%s$CLI_COLOR_RESET\n" "${CLI_COMMANDS[$command]}"
        else
            printf "  %d. %s\n" "$command_number" "$command"
            printf "     %s\n" "${CLI_COMMANDS[$command]}"
        fi
        
        if [[ -n "${CLI_COMMAND_EXAMPLES[$command]:-}" ]]; then
            if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
                printf "     %sExample:%s %s\n" "$CLI_COLOR_CYAN" "$CLI_COLOR_RESET" "${CLI_COMMAND_EXAMPLES[$command]}"
            else
                printf "     Example: %s\n" "${CLI_COMMAND_EXAMPLES[$command]}"
            fi
        fi
        printf "\n"
        command_number=$((command_number + 1))
    done
}

# Display help for a specific command
cli_help_command() {
    local command="$1"
    
    if [[ -z "${CLI_COMMANDS[$command]:-}" ]]; then
        cli_warning "Command not found: $command"
        
        # Suggest similar commands
        local suggestions=()
        for cmd in "${!CLI_COMMANDS[@]}"; do
            if [[ "$cmd" == *"$command"* ]] || [[ "$command" == *"$cmd"* ]]; then
                suggestions+=("$cmd")
            fi
        done
        
        if [[ ${#suggestions[@]} -gt 0 ]]; then
            cli_info "Did you mean one of these commands?"
            for suggestion in "${suggestions[@]}"; do
                printf "  - %s\n" "$suggestion"
            done
        fi
        return 1
    fi
    
    cli_header "Command Help: $command"
    
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
        printf "%sDescription:%s %s\n\n" "$CLI_COLOR_BOLD$CLI_COLOR_BLUE" "$CLI_COLOR_RESET" "${CLI_COMMANDS[$command]}"
    else
        printf "Description: %s\n\n" "${CLI_COMMANDS[$command]}"
    fi
    
    if [[ -n "${CLI_COMMAND_EXAMPLES[$command]:-}" ]]; then
        if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
            printf "%sUsage:%s\n" "$CLI_COLOR_BOLD$CLI_COLOR_CYAN" "$CLI_COLOR_RESET"
            printf "  %s\n\n" "${CLI_COMMAND_EXAMPLES[$command]}"
        else
            printf "Usage:\n"
            printf "  %s\n\n" "${CLI_COMMAND_EXAMPLES[$command]}"
        fi
    fi
    
    # Show related commands
    cli_show_related_commands "$command"
}

# Show related commands
cli_show_related_commands() {
    local command="$1"
    local related=()
    
    # Find commands in the same section
    for section in "${!CLI_HELP_SECTIONS[@]}"; do
        if [[ "${CLI_HELP_SECTIONS[$section]}" == *"$command"* ]]; then
            for cmd in ${CLI_HELP_SECTIONS[$section]}; do
                if [[ "$cmd" != "$command" ]]; then
                    related+=("$cmd")
                fi
            done
            break
        fi
    done
    
    if [[ ${#related[@]} -gt 0 ]]; then
        if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
            printf "%sRelated Commands:%s\n" "$CLI_COLOR_BOLD$CLI_COLOR_MAGENTA" "$CLI_COLOR_RESET"
        else
            printf "Related Commands:\n"
        fi
        for cmd in "${related[@]}"; do
            printf "  - %s\n" "$cmd"
        done
        printf "\n"
    fi
}

# =============================================================================
# COMMAND DISCOVERY AND AUTO-COMPLETION
# =============================================================================

# Command discovery with fuzzy matching
cli_discover_commands() {
    local query="$1"
    local max_results="${2:-10}"
    
    if [[ -z "$query" ]]; then
        cli_warning "No search query provided"
        return 1
    fi
    
    local matches=()
    local match_scores=()
    
    for command in "${!CLI_COMMANDS[@]}"; do
        local score=0
        
        # Exact match gets highest score
        if [[ "$command" == "$query" ]]; then
            score=100
        elif [[ "$command" == *"$query"* ]]; then
            score=50
        elif [[ "$query" == *"$command"* ]]; then
            score=30
        else
            # Fuzzy matching based on character similarity
            local query_lower="${query,,}"
            local command_lower="${command,,}"
            
            # Check for character sequence matches
            local query_chars=($(echo "$query_lower" | grep -o .))
            local match_count=0
            local last_pos=0
            
            for char in "${query_chars[@]}"; do
                local pos=$(echo "$command_lower" | grep -o "$char" | wc -l)
                if [[ $pos -gt $last_pos ]]; then
                    match_count=$((match_count + 1))
                    last_pos=$pos
                fi
            done
            
            if [[ $match_count -gt 0 ]]; then
                score=$((match_count * 10))
            fi
        fi
        
        if [[ $score -gt 0 ]]; then
            matches+=("$command")
            match_scores+=("$score")
        fi
    done
    
    # Sort by score (descending)
    if [[ ${#matches[@]} -gt 1 ]]; then
        for i in $(seq 0 $((${#matches[@]} - 1))); do
            for j in $(seq $((i + 1)) $((${#matches[@]} - 1))); do
                if [[ $i -lt ${#matches[@]} && $j -lt ${#matches[@]} && ${match_scores[$i]:-0} -lt ${match_scores[$j]:-0} ]]; then
                    # Swap matches
                    local temp_match="${matches[$i]}"
                    matches[$i]="${matches[$j]}"
                    matches[$j]="$temp_match"
                    
                    # Swap scores
                    local temp_score="${match_scores[$i]}"
                    match_scores[$i]="${match_scores[$j]}"
                    match_scores[$j]="$temp_score"
                fi
            done
        done
    fi
    
    # Display results
    if [[ ${#matches[@]} -eq 0 ]]; then
        cli_warning "No commands found matching: $query"
        return 1
    fi
    
    cli_header "Command Discovery Results: $query"
    
    local display_count=0
    for i in $(seq 0 $((${#matches[@]} - 1))); do
        if [[ $display_count -ge $max_results ]]; then
            break
        fi
        
        local command="${matches[$i]}"
        local score="${match_scores[$i]}"
        
        if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
            printf "  $CLI_COLOR_BOLD$CLI_COLOR_GREEN%s$CLI_COLOR_RESET" "$command"
            printf " $CLI_COLOR_DIM(score: %d)$CLI_COLOR_RESET\n" "$score"
            printf "     %s\n" "${CLI_COMMANDS[$command]}"
        else
            printf "  %s (score: %d)\n" "$command" "$score"
            printf "     %s\n" "${CLI_COMMANDS[$command]}"
        fi
        
        display_count=$((display_count + 1))
    done
    
    if [[ ${#matches[@]} -gt $max_results ]]; then
        printf "\n"
        cli_info "Showing top $max_results results. Use more specific search for better results."
    fi
}

# Auto-completion for commands
cli_autocomplete() {
    local partial_command="$1"
    local max_suggestions="${2:-5}"
    
    if [[ -z "$partial_command" ]]; then
        return 0
    fi
    
    local suggestions=()
    
    for command in "${!CLI_COMMANDS[@]}"; do
        if [[ "$command" == "$partial_command"* ]]; then
            suggestions+=("$command")
        fi
    done
    
    if [[ ${#suggestions[@]} -eq 0 ]]; then
        return 1
    fi
    
    # Sort suggestions alphabetically
    IFS=$'\n' suggestions=($(sort <<<"${suggestions[*]}"))
    unset IFS
    
    # Limit suggestions
    if [[ ${#suggestions[@]} -gt $max_suggestions ]]; then
        suggestions=("${suggestions[@]:0:$max_suggestions}")
    fi
    
    # Display suggestions
    printf "\n"
    cli_info "Suggestions for '$partial_command':"
    for suggestion in "${suggestions[@]}"; do
        printf "  %s\n" "$suggestion"
    done
    
    return 0
}

# =============================================================================
# INTERACTIVE VALIDATION
# =============================================================================

# Interactive configuration validation
cli_validate_config_interactive() {
    local config_file="$1"
    local auto_fix="${2:-false}"
    
    if [[ ! -f "$config_file" ]]; then
        cli_failure "Configuration file not found: $config_file"
        return 1
    fi
    
    cli_header "Interactive Configuration Validation"
    cli_info "Validating: $config_file"
    
    local validation_errors=()
    local validation_warnings=()
    local fixable_issues=()
    
    # Check file permissions
    if [[ ! -r "$config_file" ]]; then
        validation_errors+=("File is not readable")
    fi
    
    # Check file format
    local file_extension="${config_file##*.}"
    case "$file_extension" in
        "yml"|"yaml")
            if ! command -v yq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
                validation_warnings+=("YAML validation tools not available")
            else
                # Basic YAML syntax check
                if command -v yq >/dev/null 2>&1; then
                    if ! yq eval '.' "$config_file" >/dev/null 2>&1; then
                        validation_errors+=("Invalid YAML syntax")
                        fixable_issues+=("yaml_syntax")
                    fi
                elif command -v python3 >/dev/null 2>&1; then
                    if ! python3 -c "import yaml; yaml.safe_load(open('$config_file'))" 2>/dev/null; then
                        validation_errors+=("Invalid YAML syntax")
                        fixable_issues+=("yaml_syntax")
                    fi
                fi
            fi
            ;;
        "json")
            if ! jq '.' "$config_file" >/dev/null 2>&1; then
                validation_errors+=("Invalid JSON syntax")
                fixable_issues+=("json_syntax")
            fi
            ;;
        *)
            validation_warnings+=("Unknown file format: $file_extension")
            ;;
    esac
    
    # Check for common issues
    if grep -q "TODO\|FIXME\|XXX" "$config_file" 2>/dev/null; then
        validation_warnings+=("Contains TODO/FIXME comments")
    fi
    
    if grep -q "password\|secret\|key" "$config_file" 2>/dev/null; then
        validation_warnings+=("Contains potential sensitive data")
    fi
    
    # Display validation results
    printf "\n"
    if [[ ${#validation_errors[@]} -eq 0 && ${#validation_warnings[@]} -eq 0 ]]; then
        cli_success "Configuration validation passed"
        return 0
    fi
    
    if [[ ${#validation_errors[@]} -gt 0 ]]; then
        cli_subheader "Validation Errors"
        for error in "${validation_errors[@]}"; do
            cli_failure "$error"
        done
    fi
    
    if [[ ${#validation_warnings[@]} -gt 0 ]]; then
        cli_subheader "Validation Warnings"
        for warning in "${validation_warnings[@]}"; do
            cli_warning "$warning"
        done
    fi
    
    # Offer fixes for fixable issues
    if [[ ${#fixable_issues[@]} -gt 0 ]]; then
        printf "\n"
        cli_subheader "Available Fixes"
        
        local fix_number=1
        for issue in "${fixable_issues[@]}"; do
            case "$issue" in
                "yaml_syntax")
                    printf "  %d. Fix YAML syntax issues\n" "$fix_number"
                    ;;
                "json_syntax")
                    printf "  %d. Fix JSON syntax issues\n" "$fix_number"
                    ;;
            esac
            fix_number=$((fix_number + 1))
        done
        
        if [[ "$auto_fix" == "true" ]]; then
            cli_auto_fix_issues "$config_file" "${fixable_issues[@]}"
        else
            cli_prompt "Would you like to attempt automatic fixes?" "n" "y/n"
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                cli_auto_fix_issues "$config_file" "${fixable_issues[@]}"
            fi
        fi
    fi
    
    return ${#validation_errors[@]}
}

# Auto-fix configuration issues
cli_auto_fix_issues() {
    local config_file="$1"
    shift
    local issues=("$@")
    
    cli_header "Auto-Fixing Configuration Issues"
    
    for issue in "${issues[@]}"; do
        case "$issue" in
            "yaml_syntax")
                cli_info "Attempting to fix YAML syntax..."
                if command -v yq >/dev/null 2>&1; then
                    local temp_file=$(mktemp)
                    if yq eval '.' "$config_file" > "$temp_file" 2>/dev/null; then
                        mv "$temp_file" "$config_file"
                        cli_success "YAML syntax fixed"
                    else
                        rm -f "$temp_file"
                        cli_failure "Could not fix YAML syntax"
                    fi
                else
                    cli_warning "YAML fix tool (yq) not available"
                fi
                ;;
            "json_syntax")
                cli_info "Attempting to fix JSON syntax..."
                local temp_file=$(mktemp)
                if jq '.' "$config_file" > "$temp_file" 2>/dev/null; then
                    mv "$temp_file" "$config_file"
                    cli_success "JSON syntax fixed"
                else
                    rm -f "$temp_file"
                    cli_failure "Could not fix JSON syntax"
                fi
                ;;
        esac
    done
}

# =============================================================================
# CONFIRMATION PROMPTS
# =============================================================================

# Enhanced confirmation prompt with safety checks
cli_confirm_destructive() {
    local operation="$1"
    local resource="$2"
    local additional_info="${3:-}"
    
    cli_warning "⚠️  DESTRUCTIVE OPERATION DETECTED"
    printf "\n"
    cli_subheader "Operation Details"
    printf "  Operation: %s\n" "$operation"
    printf "  Resource: %s\n" "$resource"
    
    if [[ -n "$additional_info" ]]; then
        printf "  Details: %s\n" "$additional_info"
    fi
    
    printf "\n"
    cli_warning "This operation cannot be undone!"
    
    # Require explicit confirmation
    cli_prompt "Type 'CONFIRM' to proceed" "" "or 'cancel' to abort"
    read -r confirmation
    
    if [[ "$confirmation" != "CONFIRM" ]]; then
        cli_info "Operation cancelled by user"
        return 1
    fi
    
    # Double confirmation for critical operations
    if [[ "$operation" == *"delete"* ]] || [[ "$operation" == *"destroy"* ]] || [[ "$operation" == *"remove"* ]]; then
        cli_prompt "Final confirmation: Type 'YES' to confirm deletion" "" "or 'no' to cancel"
        read -r final_confirmation
        
        if [[ "$final_confirmation" != "YES" ]]; then
            cli_info "Operation cancelled at final confirmation"
            return 1
        fi
    fi
    
    cli_info "Proceeding with operation..."
    return 0
}

# Confirmation prompt with timeout
cli_confirm_timeout() {
    local question="$1"
    local timeout="${2:-30}"
    local default="${3:-n}"
    
    local default_text=""
    case "$default" in
        "y"|"yes") default_text="Y/n" ;;
        "n"|"no") default_text="y/N" ;;
        *) default_text="y/n" ;;
    esac
    
    cli_prompt "$question (timeout: ${timeout}s)" "" "$default_text"
    
    # Read with timeout
    if read -t "$timeout" -r response; then
        case "$response" in
            "y"|"yes"|"Y"|"YES")
                return 0
                ;;
            "n"|"no"|"N"|"NO")
                return 1
                ;;
            "")
                # Use default
                case "$default" in
                    "y"|"yes") return 0 ;;
                    *) return 1 ;;
                esac
                ;;
            *)
                cli_warning "Invalid response. Using default: $default"
                case "$default" in
                    "y"|"yes") return 0 ;;
                    *) return 1 ;;
                esac
                ;;
        esac
    else
        cli_warning "Timeout reached. Using default: $default"
        case "$default" in
            "y"|"yes") return 0 ;;
            *) return 1 ;;
        esac
    fi
}

# =============================================================================
# CONTEXT-SENSITIVE HELP
# =============================================================================

# Context-sensitive help based on current state
cli_context_help() {
    local context="$1"
    local current_command="${2:-}"
    local current_args="${3:-}"
    
    case "$context" in
        "deployment")
            cli_header "Deployment Context Help"
            cli_info "You're in a deployment context. Available actions:"
            printf "  1. Continue deployment\n"
            printf "  2. Pause deployment\n"
            printf "  3. Rollback deployment\n"
            printf "  4. View deployment status\n"
            printf "  5. Cancel deployment\n"
            ;;
        "configuration")
            cli_header "Configuration Context Help"
            cli_info "You're in a configuration context. Available actions:"
            printf "  1. Validate configuration\n"
            printf "  2. Edit configuration\n"
            printf "  3. Reset to defaults\n"
            printf "  4. Backup configuration\n"
            printf "  5. Compare configurations\n"
            ;;
        "error")
            cli_header "Error Recovery Help"
            cli_info "You've encountered an error. Available recovery options:"
            printf "  1. Retry operation\n"
            printf "  2. Check logs\n"
            printf "  3. Validate prerequisites\n"
            printf "  4. Get detailed error info\n"
            printf "  5. Contact support\n"
            ;;
        "command")
            if [[ -n "$current_command" ]]; then
                cli_help_command "$current_command"
            else
                cli_help_menu
            fi
            ;;
        *)
            cli_help_menu
            ;;
    esac
}

# Smart suggestions based on user behavior
cli_smart_suggestions() {
    local user_input="$1"
    local context="${2:-}"
    
    local suggestions=()
    
    # Common command patterns
    if [[ "$user_input" == *"help"* ]]; then
        suggestions+=("help menu" "help commands" "help <command>")
    fi
    
    if [[ "$user_input" == *"deploy"* ]]; then
        suggestions+=("deploy start" "deploy status" "deploy rollback")
    fi
    
    if [[ "$user_input" == *"config"* ]]; then
        suggestions+=("config validate" "config edit" "config backup")
    fi
    
    # Context-specific suggestions
    case "$context" in
        "deployment")
            suggestions+=("status" "logs" "rollback" "cancel")
            ;;
        "error")
            suggestions+=("retry" "debug" "logs" "help")
            ;;
        "configuration")
            suggestions+=("validate" "edit" "backup" "restore")
            ;;
    esac
    
    if [[ ${#suggestions[@]} -gt 0 ]]; then
        printf "\n"
        cli_info "Suggestions:"
        for suggestion in "${suggestions[@]}"; do
            printf "  - %s\n" "$suggestion"
        done
    fi
}

# =============================================================================
# COMMAND SYNTAX AND EXAMPLES
# =============================================================================

# Display command syntax with examples
cli_show_syntax() {
    local command="$1"
    
    if [[ -z "${CLI_COMMANDS[$command]:-}" ]]; then
        cli_warning "Command not found: $command"
        return 1
    fi
    
    cli_header "Command Syntax: $command"
    
    if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
        printf "%sUsage:%s\n" "$CLI_COLOR_BOLD$CLI_COLOR_BLUE" "$CLI_COLOR_RESET"
    else
        printf "Usage:\n"
    fi
    
    printf "  %s\n\n" "$command"
    
    if [[ -n "${CLI_COMMAND_EXAMPLES[$command]:-}" ]]; then
        if [[ "$CLI_TERMINAL_SUPPORTS_COLOR" == "true" ]]; then
            printf "%sExamples:%s\n" "$CLI_COLOR_BOLD$CLI_COLOR_CYAN" "$CLI_COLOR_RESET"
        else
            printf "Examples:\n"
        fi
        
        printf "  %s\n\n" "${CLI_COMMAND_EXAMPLES[$command]}"
    fi
    
    # Show options if available
    cli_show_command_options "$command"
}

# Show command options and parameters
cli_show_command_options() {
    local command="$1"
    
    # This would be populated with actual command options
    # For now, we'll show a generic structure
    case "$command" in
        "deploy")
            printf "Options:\n"
            printf "  --environment, -e    Target environment (dev/staging/prod)\n"
            printf "  --dry-run, -d        Show what would be deployed\n"
            printf "  --force, -f          Skip confirmation prompts\n"
            printf "  --verbose, -v        Show detailed output\n"
            ;;
        "config")
            printf "Options:\n"
            printf "  --validate, -v       Validate configuration\n"
            printf "  --edit, -e           Open in editor\n"
            printf "  --backup, -b         Create backup\n"
            printf "  --restore, -r        Restore from backup\n"
            ;;
        *)
            # Generic options
            printf "Options:\n"
            printf "  --help, -h           Show this help\n"
            printf "  --verbose, -v        Show detailed output\n"
            printf "  --quiet, -q          Suppress output\n"
            ;;
    esac
}

# =============================================================================
# INITIALIZATION
# =============================================================================

# Initialize CLI utilities
cli_init() {
    # Detect terminal capabilities
    cli_detect_terminal
    
    # Log initialization if logging is available
    if [[ -n "${LIB_LOGGING_LOADED:-}" ]]; then
        log_info "CLI utilities initialized (color support: $CLI_TERMINAL_SUPPORTS_COLOR)"
    fi
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

# Export all CLI functions for use in other modules
export -f cli_init
export -f cli_detect_terminal
export -f cli_success
export -f cli_failure
export -f cli_warning
export -f cli_info
export -f cli_step
export -f cli_status
export -f cli_header
export -f cli_subheader
export -f cli_separator
export -f cli_operation
export -f cli_tip
export -f cli_note
export -f cli_error_with_recovery
export -f cli_common_error
export -f cli_prompt
export -f cli_confirm
export -f cli_spinner
export -f cli_progress
export -f cli_register_command
export -f cli_help_menu
export -f cli_help_section
export -f cli_help_all_commands
export -f cli_help_command
export -f cli_show_related_commands
export -f cli_discover_commands
export -f cli_autocomplete
export -f cli_validate_config_interactive
export -f cli_auto_fix_issues
export -f cli_confirm_destructive
export -f cli_confirm_timeout
export -f cli_context_help
export -f cli_smart_suggestions
export -f cli_show_syntax
export -f cli_show_command_options

# Initialize CLI utilities when sourced
cli_init