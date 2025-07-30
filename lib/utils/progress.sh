#!/usr/bin/env bash

# Progress Indicator Module
# Provides professional progress bars for long-running operations
# Supports real-time updates, terminal compatibility, and error handling

set -euo pipefail

# Progress indicator configuration
PROGRESS_BAR_WIDTH=50
PROGRESS_CURRENT_PERCENT=0
PROGRESS_CURRENT_DESCRIPTION=""
PROGRESS_START_TIME=0
PROGRESS_IS_ACTIVE=false
PROGRESS_TERMINAL_TYPE=""
PROGRESS_SUPPORTS_COLOR=false

# Color codes for professional appearance
PROGRESS_COLOR_RESET='\033[0m'
PROGRESS_COLOR_BOLD='\033[1m'
PROGRESS_COLOR_GREEN='\033[0;32m'
PROGRESS_COLOR_BLUE='\033[0;34m'
PROGRESS_COLOR_YELLOW='\033[1;33m'
PROGRESS_COLOR_RED='\033[0;31m'
PROGRESS_COLOR_CYAN='\033[0;36m'
PROGRESS_COLOR_GRAY='\033[0;37m'

# Progress bar characters
PROGRESS_CHAR_FILLED='█'
PROGRESS_CHAR_EMPTY='░'
PROGRESS_CHAR_ARROW='▶'
PROGRESS_CHAR_CHECK='✓'
PROGRESS_CHAR_CROSS='✗'

# Key milestone percentages
readonly PROGRESS_MILESTONES=(0 25 50 75 87 100)

# Initialize progress tracking system
progress_init() {
    local description="${1:-Initializing...}"
    
    # Detect terminal capabilities
    progress_detect_terminal
    
    # Initialize progress state
    PROGRESS_CURRENT_PERCENT=0
    PROGRESS_CURRENT_DESCRIPTION="$description"
    PROGRESS_START_TIME=$(date +%s)
    PROGRESS_IS_ACTIVE=true
    
    # Clear line and show initial progress
    progress_clear_line
    progress_display_bar
    
    # Log progress initialization
    if [[ -n "${LIB_LOGGING_LOADED:-}" ]]; then
        log_info "Progress tracking initialized: $description"
    fi
}

# Detect terminal capabilities and type
progress_detect_terminal() {
    # Check if we're in a terminal
    if [[ ! -t 1 ]]; then
        PROGRESS_TERMINAL_TYPE="non-interactive"
        PROGRESS_SUPPORTS_COLOR=false
        return 0
    fi
    
    # Detect terminal type
    PROGRESS_TERMINAL_TYPE="${TERM:-unknown}"
    
    # Check color support
    if command -v tput >/dev/null 2>&1; then
        local colors=$(tput colors 2>/dev/null || echo 0)
        if [[ $colors -ge 8 ]]; then
            PROGRESS_SUPPORTS_COLOR=true
        fi
    fi
    
    # Fallback color detection
    if [[ "$PROGRESS_TERMINAL_TYPE" =~ (xterm|screen|tmux|linux) ]]; then
        PROGRESS_SUPPORTS_COLOR=true
    fi
}

# Update progress with new percentage and description
progress_update() {
    local percent="$1"
    local description="${2:-$PROGRESS_CURRENT_DESCRIPTION}"
    
    # Validate percentage
    if ! progress_validate_percentage "$percent"; then
        progress_error "Invalid percentage: $percent"
        return 1
    fi
    
    # Update progress state
    PROGRESS_CURRENT_PERCENT=$percent
    PROGRESS_CURRENT_DESCRIPTION="$description"
    
    # Clear previous line and redraw
    progress_clear_line
    progress_display_bar
    
    # Log milestone achievements
    if progress_is_milestone "$percent"; then
        if [[ -n "${LIB_LOGGING_LOADED:-}" ]]; then
            log_info "Progress milestone reached: ${percent}% - $description"
        fi
    fi
}

# Validate percentage value
progress_validate_percentage() {
    local percent="$1"
    
    # Check if it's a number
    if ! [[ "$percent" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    # Check range
    if [[ $percent -lt 0 || $percent -gt 100 ]]; then
        return 1
    fi
    
    return 0
}

# Check if percentage is a milestone
progress_is_milestone() {
    local percent="$1"
    
    for milestone in "${PROGRESS_MILESTONES[@]}"; do
        if [[ $percent -eq $milestone ]]; then
            return 0
        fi
    done
    
    return 1
}

# Display the progress bar
progress_display_bar() {
    local percent=$PROGRESS_CURRENT_PERCENT
    local description="$PROGRESS_CURRENT_DESCRIPTION"
    
    # Calculate progress bar components
    local filled_width=$((PROGRESS_BAR_WIDTH * percent / 100))
    local empty_width=$((PROGRESS_BAR_WIDTH - filled_width))
    
    # Build progress bar string
    local progress_bar=""
    if [[ $filled_width -gt 0 ]]; then
        progress_bar+=$(printf "%${filled_width}s" | tr ' ' "$PROGRESS_CHAR_FILLED")
    fi
    
    if [[ $empty_width -gt 0 ]]; then
        progress_bar+=$(printf "%${empty_width}s" | tr ' ' "$PROGRESS_CHAR_EMPTY")
    fi
    
    # Add arrow at current position
    if [[ $percent -gt 0 && $percent -lt 100 ]]; then
        progress_bar="${progress_bar:0:$((filled_width-1))}$PROGRESS_CHAR_ARROW${progress_bar:$filled_width}"
    fi
    
    # Format output with colors if supported
    local output=""
    if [[ "$PROGRESS_SUPPORTS_COLOR" == "true" ]]; then
        output+="$PROGRESS_COLOR_BOLD$PROGRESS_COLOR_BLUE[$PROGRESS_COLOR_RESET"
        output+="$PROGRESS_COLOR_CYAN$progress_bar$PROGRESS_COLOR_RESET"
        output+="$PROGRESS_COLOR_BOLD$PROGRESS_COLOR_BLUE]$PROGRESS_COLOR_RESET"
        output+=" $PROGRESS_COLOR_YELLOW$percent%$PROGRESS_COLOR_RESET"
        output+=" $PROGRESS_COLOR_GRAY$description$PROGRESS_COLOR_RESET"
    else
        output+="[$progress_bar] $percent% $description"
    fi
    
    # Print progress bar
    printf "\r%s" "$output"
}

# Clear the current line
progress_clear_line() {
    if [[ "$PROGRESS_TERMINAL_TYPE" != "non-interactive" ]]; then
        printf "\r%${PROGRESS_BAR_WIDTH}s\r" ""
    fi
}

# Complete progress and show final status
progress_complete() {
    local success="${1:-true}"
    local final_description="${2:-$PROGRESS_CURRENT_DESCRIPTION}"
    
    # Update to 100% if not already
    if [[ $PROGRESS_CURRENT_PERCENT -lt 100 ]]; then
        progress_update 100 "$final_description"
    fi
    
    # Calculate duration
    local duration=0
    if [[ $PROGRESS_START_TIME -gt 0 ]]; then
        duration=$(($(date +%s) - PROGRESS_START_TIME))
    fi
    
    # Clear line and show completion
    progress_clear_line
    
    local completion_message=""
    if [[ "$success" == "true" ]]; then
        if [[ "$PROGRESS_SUPPORTS_COLOR" == "true" ]]; then
            completion_message="$PROGRESS_COLOR_BOLD$PROGRESS_COLOR_GREEN$PROGRESS_CHAR_CHECK Completed$PROGRESS_COLOR_RESET"
        else
            completion_message="$PROGRESS_CHAR_CHECK Completed"
        fi
    else
        if [[ "$PROGRESS_SUPPORTS_COLOR" == "true" ]]; then
            completion_message="$PROGRESS_COLOR_BOLD$PROGRESS_COLOR_RED$PROGRESS_CHAR_CROSS Failed$PROGRESS_COLOR_RESET"
        else
            completion_message="$PROGRESS_CHAR_CROSS Failed"
        fi
    fi
    
    completion_message+=" - $final_description"
    
    if [[ $duration -gt 0 ]]; then
        completion_message+=" (${duration}s)"
    fi
    
    printf "%s\n" "$completion_message"
    
    # Reset progress state
    PROGRESS_IS_ACTIVE=false
    
    # Log completion
    if [[ -n "${LIB_LOGGING_LOADED:-}" ]]; then
        if [[ "$success" == "true" ]]; then
            log_info "Progress completed successfully: $final_description (${duration}s)"
        else
            log_error "Progress failed: $final_description (${duration}s)"
        fi
    fi
}

# Handle progress errors
progress_error() {
    local error_message="$1"
    
    # Clear current progress display
    progress_clear_line
    
    # Show error message
    local error_output=""
    if [[ "$PROGRESS_SUPPORTS_COLOR" == "true" ]]; then
        error_output="$PROGRESS_COLOR_BOLD$PROGRESS_COLOR_RED$PROGRESS_CHAR_CROSS Error$PROGRESS_COLOR_RESET: $error_message"
    else
        error_output="$PROGRESS_CHAR_CROSS Error: $error_message"
    fi
    
    printf "%s\n" "$error_output"
    
    # Reset progress state
    PROGRESS_IS_ACTIVE=false
    
    # Log error
    if [[ -n "${LIB_LOGGING_LOADED:-}" ]]; then
        log_error "Progress error: $error_message"
    fi
}

# Clean up progress display
progress_cleanup() {
    if [[ "$PROGRESS_IS_ACTIVE" == "true" ]]; then
        progress_clear_line
        PROGRESS_IS_ACTIVE=false
    fi
}

# Get current progress percentage
progress_get_percentage() {
    echo "$PROGRESS_CURRENT_PERCENT"
}

# Get current progress description
progress_get_description() {
    echo "$PROGRESS_CURRENT_DESCRIPTION"
}

# Check if progress is active
progress_is_active() {
    [[ "$PROGRESS_IS_ACTIVE" == "true" ]]
}

# Get progress duration in seconds
progress_get_duration() {
    if [[ $PROGRESS_START_TIME -gt 0 ]]; then
        local current_time=$(date +%s)
        local duration=$((current_time - PROGRESS_START_TIME))
        echo "$duration"
    else
        echo 0
    fi
}

# Export functions for use in other modules
export -f progress_init
export -f progress_update
export -f progress_complete
export -f progress_error
export -f progress_cleanup
export -f progress_get_percentage
export -f progress_get_description
export -f progress_is_active
export -f progress_get_duration