# Clear Error Messages Guide

## Overview

The Clear Error Messages module (Story 5.3 Task 3) provides user-friendly, actionable error messages that help users understand what went wrong and how to fix it. This implementation replaces technical error codes with clear explanations and recovery guidance.

## Features

### 1. Three-Level Message Clarity

The system supports three levels of error message clarity:

- **Technical (Level 0)**: Brief technical format with error codes
- **Standard (Level 1)**: Structured format with why/fix sections  
- **User-Friendly (Level 2)**: Full explanations with emojis and examples

### 2. Comprehensive Error Templates

Each error includes four components:
- **What happened**: Clear description of the problem
- **Why it occurred**: Root cause explanation
- **How to fix**: Actionable recovery steps
- **Example**: Concrete command or action to take

### 3. Recovery Guidance

Automatic recovery suggestions based on error type:
- **Retry**: Temporary issues that may self-resolve
- **Fallback**: System can try alternatives automatically
- **Manual**: User intervention required
- **Abort**: Operation cannot continue
- **Skip**: Can proceed without this step

## Usage

### Basic Setup

```bash
# Source the clear messages module
source lib/modules/errors/clear_messages.sh

# Set desired clarity level (default is user-friendly)
export ERROR_MESSAGE_CLARITY=2  # 0=technical, 1=standard, 2=user-friendly
```

### Using Clear Error Functions

```bash
# Instead of generic errors, use clear error functions
error_ec2_insufficient_capacity_clear "g4dn.xlarge" "us-east-1"
error_auth_invalid_credentials_clear "EC2"
error_network_vpc_not_found_clear "vpc-12345"
```

### Example Output

#### Technical Format (Level 0)
```
[EC2_INSUFFICIENT_CAPACITY] Unable to launch EC2 instance - Instance type: g4dn.xlarge, Region: us-east-1
```

#### User-Friendly Format (Level 2)
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
❌ What happened: Unable to launch EC2 instance

📋 Why this occurred: AWS doesn't have enough capacity for the requested instance type in this region

💡 How to fix: Try a different instance type (e.g., g5.xlarge instead of g4dn.xlarge) or switch to another region

📝 Example: aws ec2 run-instances --instance-type g5.xlarge --region us-west-2

🔧 Recovery: The system will automatically try an alternative approach
💡 Tip: AWS capacity varies by region and time - try different regions or wait 5-10 minutes
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Adding New Clear Error Messages

To add a new clear error message:

1. Add the error template to `CLEAR_ERROR_MESSAGES` array:
```bash
CLEAR_ERROR_MESSAGES["YOUR_ERROR_CODE"]="what:Description|why:Reason|how:Solution|example:Command"
```

2. Create a clear error function:
```bash
error_your_error_clear() {
    local param1="$1"
    log_clear_error "YOUR_ERROR_CODE" "$param1" 1 "Technical details" "$RECOVERY_RETRY"
}
```

3. Update the original error function to use the clear version:
```bash
error_your_error() {
    if command -v error_your_error_clear >/dev/null 2>&1; then
        error_your_error_clear "$@"
    else
        # Fallback to original implementation
    fi
}
```

## Message Clarity Testing

The module includes a clarity scoring system:

```bash
# Test message clarity (returns score out of 10)
score=$(test_message_clarity "Your error message")

# Scoring criteria:
# +2 points: Avoids technical jargon
# +2 points: Contains actionable guidance
# +2 points: Includes examples
# +2 points: Explains why the error occurred
# +2 points: Appropriate length (10-100 words)
```

## Interactive Features

When in user-friendly mode, the system can offer interactive resolution:

```bash
# Enable interactive prompts
offer_interactive_resolution "ERROR_CODE" "$RECOVERY_STRATEGY"

# Shows prompts like:
# 🔄 Would you like to retry this operation? (y/n):
# 📚 Would you like to see detailed troubleshooting steps? (y/n):
```

## Progress Context

Provide context before operations that might fail:

```bash
# Show progress for multi-step operations
show_error_context_progress "Launching EC2 instance" 2 5

# Warn about high-risk operations
provide_operation_context "Attempting spot instance launch" "high"
```

## Best Practices

1. **Always use clear language**: Avoid technical jargon unless in technical mode
2. **Be specific**: Include actual values (instance types, regions, etc.) in messages
3. **Provide examples**: Show exact commands users can run
4. **Categorize properly**: Use appropriate recovery strategies
5. **Test clarity**: Run clarity tests on new messages
6. **Consider context**: Add tips specific to common scenarios

## Integration with Existing Code

The clear messages module integrates seamlessly with existing error handling:

1. It extends (not replaces) the existing error system
2. Falls back gracefully if clear messages aren't available
3. Preserves all structured logging functionality
4. Maintains backward compatibility

## Demonstration

Run the demo to see the improvements:

```bash
./archive/demos/demo-clear-errors.sh
```

## Testing

Run the comprehensive test suite:

```bash
./tests/test-error-message-clarity.sh
```

## Environment Variables

- `ERROR_MESSAGE_CLARITY`: Set clarity level (0-2)
- `ERROR_MESSAGE_LANGUAGE`: Future support for localization (currently English only)

## Performance

The clear message system adds minimal overhead:
- Message formatting: <10ms per error
- No impact on error detection or logging
- Lazy loading of message templates
- Efficient clarity scoring algorithm