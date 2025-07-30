# GeuseMaker Setup Suite

The Setup Suite is a consolidated tool that combines all setup operations for GeuseMaker into a single, user-friendly interface. It replaces the previous individual setup scripts with a unified approach.

## Overview

The Setup Suite consolidates four previously separate setup scripts:
- `setup-docker.sh` - Docker daemon configuration
- `setup-parameter-store.sh` - AWS Parameter Store setup
- `setup-secrets.sh` - Local secrets generation
- `config-manager.sh` - Configuration file generation

## Location

```bash
lib/modules/config/setup-suite.sh
```

## Features

- **Interactive Mode**: User-friendly prompts for configuration
- **Component-based Setup**: Setup individual components or all at once
- **Comprehensive Validation**: Validate all configurations before deployment
- **Verbose Mode**: Detailed output for debugging
- **Automated Setup**: Non-interactive mode for CI/CD pipelines
- **Backward Compatibility**: Legacy scripts still work as wrappers

## Usage

### Basic Usage

```bash
# Interactive setup of all components
./lib/modules/config/setup-suite.sh --interactive

# Setup specific component
./lib/modules/config/setup-suite.sh --component docker

# Validate existing setup
./lib/modules/config/setup-suite.sh --validate

# Verbose output
./lib/modules/config/setup-suite.sh --component secrets --verbose
```

### Command Line Options

| Option | Description |
|--------|-------------|
| `--component COMPONENT` | Setup specific component (docker, secrets, parameter-store, config, all) |
| `--interactive` | Enable interactive mode with user prompts |
| `--verbose` | Enable verbose output for debugging |
| `--validate` | Run validation only without setup |
| `--help` | Show help message |

### Components

#### Docker Component
- Validates Docker installation
- Creates optimized daemon configuration
- Starts and enables Docker service
- Sets up user permissions
- Waits for daemon readiness

#### Parameter Store Component
- Checks AWS permissions
- Creates database parameters
- Creates n8n configuration parameters
- Creates API key placeholders
- Sets up webhook configuration

#### Secrets Component
- Creates secure directory structure
- Generates database passwords
- Generates encryption keys
- Generates JWT secrets
- Creates API key templates

#### Config Component
- Generates environment files
- Creates Docker Compose overrides
- Sets up configuration for different environments
- Validates generated configurations

## Interactive Mode

When run with `--interactive`, the setup suite will:
1. Show progress indicators
2. Prompt for user input when needed
3. Confirm before regenerating existing secrets
4. Provide clear feedback on each step

Example:
```bash
$ ./lib/modules/config/setup-suite.sh --interactive
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                GeuseMaker Setup Suite
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Running in interactive mode

[25%] Setting up Docker...
[50%] Setting up Parameter Store...
AWS Region [us-east-1]: us-west-2
[75%] Setting up Secrets...
Secrets already exist. Regenerate? (y/N): n
[100%] Setting up Configuration...
Environment (development/staging/production) [development]: development

✅ All components setup completed successfully!
```

## Automated Mode

For CI/CD pipelines, run without `--interactive`:

```bash
# Setup all components with defaults
./lib/modules/config/setup-suite.sh

# Setup specific component
./lib/modules/config/setup-suite.sh --component parameter-store

# Validate only
./lib/modules/config/setup-suite.sh --validate
```

## Validation

The setup suite includes comprehensive validation:

```bash
$ ./lib/modules/config/setup-suite.sh --validate

Running comprehensive validation...
✓ Docker validation passed
✓ Parameter Store validation passed
✓ Secrets validation passed
✓ Configuration files found (3 environments)

All validations passed!
```

## Return Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Setup failed |
| 2 | Validation failed |

## Migration from Legacy Scripts

The legacy scripts now act as compatibility wrappers:

```bash
# Old way (still works but shows deprecation notice)
./scripts/setup-docker.sh

# New way
./lib/modules/config/setup-suite.sh --component docker
```

### Mapping Legacy Commands

| Legacy Command | New Command |
|----------------|-------------|
| `./scripts/setup-docker.sh` | `setup-suite.sh --component docker` |
| `./scripts/setup-parameter-store.sh` | `setup-suite.sh --component parameter-store` |
| `./scripts/setup-secrets.sh` | `setup-suite.sh --component secrets` |
| `./scripts/config-manager.sh generate ENV` | `setup-suite.sh --component config` |

## Best Practices

1. **First Time Setup**: Run with `--interactive` for guided setup
2. **CI/CD**: Use automated mode with specific components
3. **Validation**: Always validate before deployment
4. **Verbose Mode**: Use for troubleshooting issues
5. **Component Order**: The suite handles dependencies automatically

## Troubleshooting

### Docker Setup Fails
- Ensure you have sudo permissions
- Check if Docker is already installed
- Verify systemd is available

### Parameter Store Setup Fails
- Verify AWS credentials are configured
- Check IAM permissions for SSM
- Ensure correct AWS region

### Secrets Already Exist
- Use interactive mode to choose regeneration
- Backup existing secrets before regenerating
- Check file permissions (should be 600)

### Configuration Issues
- Verify environment name is valid
- Check write permissions in project directory
- Ensure no syntax errors in generated files

## Security Considerations

1. **Secrets**: All secrets are generated with cryptographically secure random values
2. **Permissions**: Secret files are created with 600 permissions
3. **Parameter Store**: Uses SecureString type for sensitive values
4. **Backup**: Create backups before regenerating secrets

## Examples

### Complete Setup for New Installation
```bash
# Interactive setup with all components
./lib/modules/config/setup-suite.sh --interactive --verbose
```

### Setup for CI/CD Pipeline
```bash
# Non-interactive setup with validation
./lib/modules/config/setup-suite.sh --component all
./lib/modules/config/setup-suite.sh --validate
```

### Development Environment Setup
```bash
# Setup secrets and config for development
./lib/modules/config/setup-suite.sh --component secrets
./lib/modules/config/setup-suite.sh --component config --verbose
```

### Troubleshooting Failed Setup
```bash
# Verbose validation to identify issues
./lib/modules/config/setup-suite.sh --validate --verbose
```