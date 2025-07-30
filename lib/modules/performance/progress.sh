#!/usr/bin/env bash
#
# Module: performance/progress
# Description: Progress indicators and enhanced error messages for better UX
# Version: 1.0.0
# Dependencies: core/variables.sh, core/errors.sh, core/logging.sh
#
# This module provides visual progress indicators, spinners, progress bars,
# and enhanced error messages to improve user experience during deployments.
#

set -euo pipefail

# Bash version compatibility
# Compatible with bash 3.x+

# Module directory detection
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"

# Source dependencies with error handling
source_dependency() {
    local dep="$1"
    local dep_path="${MODULE_DIR}/../${dep}"
    
    if [[ ! -f "$dep_path" ]]; then
        echo "ERROR: Required dependency not found: $dep_path" >&2
        return 1
    fi
    
    # shellcheck source=/dev/null
    source "$dep_path" || {
        echo "ERROR: Failed to source dependency: $dep_path" >&2
        return 1
    }
}

# Load core dependencies
source_dependency "core/variables.sh"
source_dependency "core/errors.sh"
source_dependency "core/logging.sh"

# Module state management using associative arrays
declare -gA PROGRESS_STATE=(
    [initialized]="false"
    [active_indicators]="0"
    [terminal_width]="80"
    [supports_ansi]="false"
    [current_spinner_pid]=""
    [current_progress_bar]=""
    [last_message]=""
)

# Progress tracking
declare -gA PROGRESS_TASKS
declare -gA PROGRESS_STEPS
declare -gA PROGRESS_TIMERS

# Module configuration
declare -gA PROGRESS_CONFIG=(
    [spinner_style]="dots"
    [progress_bar_style]="blocks"
    [show_elapsed_time]="true"
    [show_eta]="true"
    [update_interval_ms]="100"
    [clear_on_complete]="false"
    [color_enabled]="auto"
    [verbose_errors]="true"
)

# Spinner styles
declare -gA PROGRESS_SPINNERS=(
    [dots]="⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏"
    [line]="|/-\\"
    [arrow]="← ↖ ↑ ↗ → ↘ ↓ ↙"
    [bounce]="⠁ ⠂ ⠄ ⠂"
    [box]="▖ ▘ ▝ ▗"
    [circle]="◐ ◓ ◑ ◒"
)

# Progress bar characters
declare -gA PROGRESS_BAR_CHARS=(
    [blocks_full]="█"
    [blocks_partial]="▒"
    [blocks_empty]="░"
    [ascii_full]="#"
    [ascii_partial]="="
    [ascii_empty]="-"
)

# ANSI color codes
declare -grA PROGRESS_COLORS=(
    [reset]="\033[0m"
    [bold]="\033[1m"
    [red]="\033[31m"
    [green]="\033[32m"
    [yellow]="\033[33m"
    [blue]="\033[34m"
    [magenta]="\033[35m"
    [cyan]="\033[36m"
)

# Module-specific error types
declare -gA PROGRESS_ERROR_TYPES=(
    [PROGRESS_INIT_FAILED]="Progress module initialization failed"
    [PROGRESS_INVALID_TASK]="Invalid progress task"
    [PROGRESS_TERMINAL_ERROR]="Terminal capability error"
)

# ============================================================================
# Initialization Functions
# ============================================================================

#
# Initialize the progress module
#
# Returns:
#   0 - Success
#   1 - Initialization failed
#
progress_init() {
    log_info "[${MODULE_NAME}] Initializing progress module..."
    
    # Check if already initialized
    if [[ "${PROGRESS_STATE[initialized]}" == "true" ]]; then
        log_debug "[${MODULE_NAME}] Module already initialized"
        return 0
    fi
    
    # Detect terminal capabilities
    if [[ -t 1 ]]; then
        PROGRESS_STATE[terminal_width]=$(tput cols 2>/dev/null || echo 80)
        
        # Check ANSI support
        if [[ "${PROGRESS_CONFIG[color_enabled]}" == "auto" ]]; then
            if [[ -n "${TERM:-}" ]] && [[ "$TERM" != "dumb" ]]; then
                PROGRESS_STATE[supports_ansi]="true"
            fi
        elif [[ "${PROGRESS_CONFIG[color_enabled]}" == "true" ]]; then
            PROGRESS_STATE[supports_ansi]="true"
        fi
    fi
    
    # Mark as initialized
    PROGRESS_STATE[initialized]="true"
    
    log_info "[${MODULE_NAME}] Module initialized (ANSI: ${PROGRESS_STATE[supports_ansi]})"
    return 0
}

# ============================================================================
# Spinner Functions
# ============================================================================

#
# Start a spinner with a message
#
# Arguments:
#   $1 - Message to display
#   $2 - Optional: Task ID for tracking
#
# Returns:
#   0 - Success
#   1 - Failed to start spinner
#
progress_spinner_start() {
    local message="$1"
    local task_id="${2:-spinner-$$}"
    
    # Stop any existing spinner
    progress_spinner_stop
    
    # Record task
    PROGRESS_TASKS[$task_id]="$message"
    PROGRESS_TIMERS[$task_id]=$(date +%s)
    
    # Get spinner characters
    local spinner_style="${PROGRESS_CONFIG[spinner_style]}"
    local spinner_chars="${PROGRESS_SPINNERS[$spinner_style]}"
    read -ra frames <<< "$spinner_chars"
    
    # Start spinner in background
    {
        local i=0
        while true; do
            if [[ "${PROGRESS_STATE[supports_ansi]}" == "true" ]]; then
                printf "\r${PROGRESS_COLORS[cyan]}%s${PROGRESS_COLORS[reset]} %s" \
                    "${frames[$i]}" "$message"
            else
                printf "\r%s %s" "${frames[$i]}" "$message"
            fi
            
            sleep 0.1
            i=$(( (i + 1) % ${#frames[@]} ))
        done
    } &
    
    local spinner_pid=$!
    PROGRESS_STATE[current_spinner_pid]="$spinner_pid"
    
    # Hide cursor
    [[ "${PROGRESS_STATE[supports_ansi]}" == "true" ]] && tput civis 2>/dev/null || true
    
    return 0
}

#
# Stop the current spinner
#
# Arguments:
#   $1 - Optional: Success message
#   $2 - Optional: Status (success|failure|warning)
#
progress_spinner_stop() {
    local message="${1:-}"
    local status="${2:-success}"
    
    # Kill spinner process
    if [[ -n "${PROGRESS_STATE[current_spinner_pid]}" ]]; then
        kill "${PROGRESS_STATE[current_spinner_pid]}" 2>/dev/null || true
        wait "${PROGRESS_STATE[current_spinner_pid]}" 2>/dev/null || true
        PROGRESS_STATE[current_spinner_pid]=""
    fi
    
    # Show cursor
    [[ "${PROGRESS_STATE[supports_ansi]}" == "true" ]] && tput cnorm 2>/dev/null || true
    
    # Display final message if provided
    if [[ -n "$message" ]]; then
        local symbol color
        case "$status" in
            success)
                symbol="✓"
                color="${PROGRESS_COLORS[green]}"
                ;;
            failure|error)
                symbol="✗"
                color="${PROGRESS_COLORS[red]}"
                ;;
            warning)
                symbol="!"
                color="${PROGRESS_COLORS[yellow]}"
                ;;
            *)
                symbol="•"
                color="${PROGRESS_COLORS[blue]}"
                ;;
        esac
        
        if [[ "${PROGRESS_STATE[supports_ansi]}" == "true" ]]; then
            printf "\r${color}%s${PROGRESS_COLORS[reset]} %s\n" "$symbol" "$message"
        else
            printf "\r[%s] %s\n" "$symbol" "$message"
        fi
    else
        printf "\r%*s\r" "${PROGRESS_STATE[terminal_width]}" ""
    fi
}

# ============================================================================
# Progress Bar Functions
# ============================================================================

#
# Create a progress bar
#
# Arguments:
#   $1 - Task ID
#   $2 - Total steps
#   $3 - Message
#
# Returns:
#   0 - Success
#
progress_bar_create() {
    local task_id="$1"
    local total_steps="$2"
    local message="$3"
    
    PROGRESS_TASKS[$task_id]="$message"
    PROGRESS_STEPS[$task_id:total]="$total_steps"
    PROGRESS_STEPS[$task_id:current]="0"
    PROGRESS_TIMERS[$task_id]=$(date +%s)
    PROGRESS_STATE[current_progress_bar]="$task_id"
    
    # Initial draw
    progress_bar_update "$task_id" 0
}

#
# Update progress bar
#
# Arguments:
#   $1 - Task ID
#   $2 - Current step (or increment if starts with +)
#
# Returns:
#   0 - Success
#
progress_bar_update() {
    local task_id="$1"
    local step="$2"
    
    # Handle increment
    if [[ "$step" =~ ^\+ ]]; then
        local current="${PROGRESS_STEPS[$task_id:current]:-0}"
        step=$((current + ${step:1}))
    fi
    
    PROGRESS_STEPS[$task_id:current]="$step"
    
    local total="${PROGRESS_STEPS[$task_id:total]}"
    local message="${PROGRESS_TASKS[$task_id]}"
    local percentage=$((step * 100 / total))
    
    # Calculate bar width
    local bar_width=$((PROGRESS_STATE[terminal_width] - ${#message} - 20))
    [[ $bar_width -lt 10 ]] && bar_width=10
    
    local filled=$((bar_width * step / total))
    local empty=$((bar_width - filled))
    
    # Get bar characters
    local style="${PROGRESS_CONFIG[progress_bar_style]}"
    local char_full="${PROGRESS_BAR_CHARS[${style}_full]}"
    local char_empty="${PROGRESS_BAR_CHARS[${style}_empty]}"
    
    # Build bar
    local bar=""
    for ((i = 0; i < filled; i++)); do
        bar+="$char_full"
    done
    for ((i = 0; i < empty; i++)); do
        bar+="$char_empty"
    done
    
    # Calculate elapsed time and ETA
    local elapsed_info=""
    if [[ "${PROGRESS_CONFIG[show_elapsed_time]}" == "true" ]]; then
        local start_time="${PROGRESS_TIMERS[$task_id]}"
        local elapsed=$(($(date +%s) - start_time))
        elapsed_info=$(progress_format_time "$elapsed")
        
        if [[ "${PROGRESS_CONFIG[show_eta]}" == "true" ]] && [[ $step -gt 0 ]]; then
            local eta=$((elapsed * (total - step) / step))
            elapsed_info+=" ETA: $(progress_format_time "$eta")"
        fi
    fi
    
    # Display progress bar
    if [[ "${PROGRESS_STATE[supports_ansi]}" == "true" ]]; then
        printf "\r%s [${PROGRESS_COLORS[blue]}%s${PROGRESS_COLORS[reset]}] %3d%% %s" \
            "$message" "$bar" "$percentage" "$elapsed_info"
    else
        printf "\r%s [%s] %3d%% %s" "$message" "$bar" "$percentage" "$elapsed_info"
    fi
}

#
# Complete progress bar
#
# Arguments:
#   $1 - Task ID
#   $2 - Optional: Completion message
#
progress_bar_complete() {
    local task_id="$1"
    local message="${2:-${PROGRESS_TASKS[$task_id]}}"
    
    # Update to 100%
    local total="${PROGRESS_STEPS[$task_id:total]}"
    progress_bar_update "$task_id" "$total"
    
    # Show completion
    if [[ "${PROGRESS_CONFIG[clear_on_complete]}" == "true" ]]; then
        printf "\r%*s\r" "${PROGRESS_STATE[terminal_width]}" ""
    else
        printf "\n"
    fi
    
    progress_spinner_stop "$message" "success"
    
    # Clean up
    unset "PROGRESS_TASKS[$task_id]"
    unset "PROGRESS_STEPS[$task_id:total]"
    unset "PROGRESS_STEPS[$task_id:current]"
    unset "PROGRESS_TIMERS[$task_id]"
}

# ============================================================================
# Enhanced Error Messages
# ============================================================================

#
# Display enhanced error message
#
# Arguments:
#   $1 - Error message
#   $2 - Optional: Error details/suggestion
#   $3 - Optional: Error code
#
progress_error() {
    local message="$1"
    local details="${2:-}"
    local code="${3:-1}"
    
    # Stop any active progress indicators
    progress_spinner_stop >/dev/null 2>&1
    
    if [[ "${PROGRESS_STATE[supports_ansi]}" == "true" ]]; then
        echo -e "\n${PROGRESS_COLORS[bold]}${PROGRESS_COLORS[red]}ERROR:${PROGRESS_COLORS[reset]} $message" >&2
    else
        echo -e "\nERROR: $message" >&2
    fi
    
    if [[ -n "$details" ]] && [[ "${PROGRESS_CONFIG[verbose_errors]}" == "true" ]]; then
        echo -e "  ↳ $details" >&2
    fi
    
    if [[ -n "$code" ]] && [[ "$code" != "1" ]]; then
        echo -e "  Error code: $code" >&2
    fi
    
    # Record error
    PROGRESS_STATE[last_message]="ERROR: $message"
    
    return "$code"
}

#
# Display enhanced warning message
#
# Arguments:
#   $1 - Warning message
#   $2 - Optional: Warning details
#
progress_warning() {
    local message="$1"
    local details="${2:-}"
    
    if [[ "${PROGRESS_STATE[supports_ansi]}" == "true" ]]; then
        echo -e "\n${PROGRESS_COLORS[yellow]}WARNING:${PROGRESS_COLORS[reset]} $message" >&2
    else
        echo -e "\nWARNING: $message" >&2
    fi
    
    if [[ -n "$details" ]]; then
        echo -e "  ↳ $details" >&2
    fi
    
    PROGRESS_STATE[last_message]="WARNING: $message"
}

#
# Display enhanced success message
#
# Arguments:
#   $1 - Success message
#
progress_success() {
    local message="$1"
    
    if [[ "${PROGRESS_STATE[supports_ansi]}" == "true" ]]; then
        echo -e "${PROGRESS_COLORS[green]}✓${PROGRESS_COLORS[reset]} $message"
    else
        echo -e "[SUCCESS] $message"
    fi
    
    PROGRESS_STATE[last_message]="SUCCESS: $message"
}

# ============================================================================
# Multi-Step Progress Functions
# ============================================================================

#
# Start multi-step progress tracking
#
# Arguments:
#   $1 - Task ID
#   $2 - Task name
#   $@ - Step names
#
progress_steps_start() {
    local task_id="$1"
    local task_name="$2"
    shift 2
    local steps=("$@")
    
    PROGRESS_TASKS[$task_id]="$task_name"
    PROGRESS_STEPS[$task_id:total]="${#steps[@]}"
    PROGRESS_STEPS[$task_id:current]="0"
    
    # Store step names
    local i=0
    for step in "${steps[@]}"; do
        PROGRESS_STEPS[$task_id:step:$i]="$step"
        ((i++))
    done
    
    # Display initial status
    progress_steps_display "$task_id"
}

#
# Complete a step
#
# Arguments:
#   $1 - Task ID
#   $2 - Step index (or current if not specified)
#   $3 - Optional: Status (success|failure|skip)
#
progress_step_complete() {
    local task_id="$1"
    local step_index="${2:-${PROGRESS_STEPS[$task_id:current]}}"
    local status="${3:-success}"
    
    PROGRESS_STEPS[$task_id:step:$step_index:status]="$status"
    
    # Move to next step
    local current="${PROGRESS_STEPS[$task_id:current]}"
    PROGRESS_STEPS[$task_id:current]=$((current + 1))
    
    # Redisplay
    progress_steps_display "$task_id"
}

#
# Display multi-step progress
#
# Arguments:
#   $1 - Task ID
#
progress_steps_display() {
    local task_id="$1"
    local task_name="${PROGRESS_TASKS[$task_id]}"
    local total="${PROGRESS_STEPS[$task_id:total]}"
    local current="${PROGRESS_STEPS[$task_id:current]}"
    
    # Clear previous output
    printf "\r%*s\r" "${PROGRESS_STATE[terminal_width]}" ""
    
    echo "$task_name ($current/$total)"
    
    for ((i = 0; i < total; i++)); do
        local step_name="${PROGRESS_STEPS[$task_id:step:$i]}"
        local step_status="${PROGRESS_STEPS[$task_id:step:$i:status]:-pending}"
        
        local symbol color
        case "$step_status" in
            success)
                symbol="✓"
                color="${PROGRESS_COLORS[green]}"
                ;;
            failure)
                symbol="✗"
                color="${PROGRESS_COLORS[red]}"
                ;;
            skip)
                symbol="-"
                color="${PROGRESS_COLORS[yellow]}"
                ;;
            pending)
                if [[ $i -eq $current ]]; then
                    symbol="→"
                    color="${PROGRESS_COLORS[blue]}"
                else
                    symbol="○"
                    color=""
                fi
                ;;
        esac
        
        if [[ "${PROGRESS_STATE[supports_ansi]}" == "true" ]] && [[ -n "$color" ]]; then
            echo "  ${color}${symbol}${PROGRESS_COLORS[reset]} $step_name"
        else
            echo "  [$symbol] $step_name"
        fi
    done
}

# ============================================================================
# Utility Functions
# ============================================================================

#
# Format time duration
#
# Arguments:
#   $1 - Duration in seconds
#
# Output:
#   Formatted time string
#
progress_format_time() {
    local seconds="$1"
    
    if [[ $seconds -lt 60 ]]; then
        echo "${seconds}s"
    elif [[ $seconds -lt 3600 ]]; then
        local minutes=$((seconds / 60))
        local remaining=$((seconds % 60))
        echo "${minutes}m ${remaining}s"
    else
        local hours=$((seconds / 3600))
        local remaining=$((seconds % 3600))
        local minutes=$((remaining / 60))
        echo "${hours}h ${minutes}m"
    fi
}

#
# Simple progress indicator for commands
#
# Arguments:
#   $1 - Message
#   $@ - Command to execute
#
# Returns:
#   Command exit code
#
progress_run() {
    local message="$1"
    shift
    
    progress_spinner_start "$message"
    
    local output_file="/tmp/progress-$$-output"
    local exit_code=0
    
    # Run command and capture output
    if "$@" > "$output_file" 2>&1; then
        progress_spinner_stop "$message - Complete" "success"
    else
        exit_code=$?
        progress_spinner_stop "$message - Failed" "failure"
        
        # Show error output if verbose
        if [[ "${PROGRESS_CONFIG[verbose_errors]}" == "true" ]]; then
            echo "Command output:" >&2
            cat "$output_file" >&2
        fi
    fi
    
    rm -f "$output_file"
    return $exit_code
}

# ============================================================================
# Configuration Functions
# ============================================================================

#
# Configure progress settings
#
# Arguments:
#   $1 - Setting name
#   $2 - Setting value
#
progress_configure() {
    local setting="$1"
    local value="$2"
    
    if [[ -n "${PROGRESS_CONFIG[$setting]+x}" ]]; then
        PROGRESS_CONFIG[$setting]="$value"
        log_debug "[${MODULE_NAME}] Set $setting=$value"
    else
        log_warn "[${MODULE_NAME}] Unknown setting: $setting"
    fi
}

#
# Disable all progress indicators (for non-interactive mode)
#
progress_disable() {
    PROGRESS_STATE[supports_ansi]="false"
    PROGRESS_CONFIG[color_enabled]="false"
    PROGRESS_CONFIG[show_elapsed_time]="false"
    PROGRESS_CONFIG[show_eta]="false"
    log_info "[${MODULE_NAME}] Progress indicators disabled"
}

# ============================================================================
# Error Handler Functions
# ============================================================================

#
# Register module-specific error handlers
#
progress_register_error_handlers() {
    for error_type in "${!PROGRESS_ERROR_TYPES[@]}"; do
        local handler_name="error_$(echo "$error_type" | tr '[:upper:]' '[:lower:]')"
        
        # Create error handler function dynamically
        eval "
        $handler_name() {
            local message=\"\${1:-${PROGRESS_ERROR_TYPES[$error_type]}}\"
            progress_error \"\$message\"
            return 1
        }
        "
    done
}

# Register error handlers
progress_register_error_handlers

# ============================================================================
# Module Exports
# ============================================================================

# Export public functions
export -f progress_init
export -f progress_spinner_start
export -f progress_spinner_stop
export -f progress_bar_create
export -f progress_bar_update
export -f progress_bar_complete
export -f progress_error
export -f progress_warning
export -f progress_success
export -f progress_steps_start
export -f progress_step_complete
export -f progress_run
export -f progress_configure
export -f progress_disable

# Export module state
export PROGRESS_STATE
export PROGRESS_CONFIG

# Module metadata
export PROGRESS_MODULE_VERSION="1.0.0"
export PROGRESS_MODULE_NAME="${MODULE_NAME}"

# Cleanup on exit
trap 'progress_spinner_stop 2>/dev/null || true' EXIT

# Indicate module is loaded
log_debug "[${MODULE_NAME}] Module loaded successfully"