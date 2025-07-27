# GeuseMaker Makefile
# Modular deployment automation and development tools

.PHONY: help setup clean test lint deploy destroy validate docs

# Color definitions
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m

# Default target
help: ## Show this help message
	@echo "GeuseMaker - Modular AI Infrastructure Platform"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Quick Start:"
	@echo "  1. make setup                              # Initial setup"
	@echo "  2. make deploy-simple STACK_NAME=dev      # Deploy development stack"
	@echo "  3. make status STACK_NAME=dev              # Check deployment status"
	@echo "  4. make destroy STACK_NAME=dev             # Clean up resources"

# =============================================================================
# SETUP AND DEPENDENCIES
# =============================================================================

setup: check-deps setup-secrets ## Complete initial setup with security
	@echo "$(GREEN)✓ Setup complete with security configurations$(NC)"

check-deps: ## Check if all dependencies are available
	@echo "$(BLUE)Checking dependencies...$(NC)"
	@chmod +x scripts/security-validation.sh
	@scripts/security-validation.sh
	@echo "$(GREEN)✓ Dependencies check complete$(NC)"

install-deps: ## Install required dependencies
	@echo "$(BLUE)Installing dependencies...$(NC)"
	@chmod +x tools/install-deps.sh
	@tools/install-deps.sh
	@echo "$(GREEN)✓ Dependencies installed$(NC)"

setup-secrets: ## Setup secrets for secure deployment
	@echo "$(BLUE)Setting up secrets...$(NC)"
	@chmod +x scripts/setup-secrets.sh
	@scripts/setup-secrets.sh setup
	@echo "$(GREEN)✓ Secrets setup complete$(NC)"

setup-parameter-store: ## Setup AWS Parameter Store
	@echo "$(BLUE)Setting up Parameter Store...$(NC)"
	@chmod +x scripts/setup-parameter-store.sh
	@scripts/setup-parameter-store.sh
	@echo "$(GREEN)✓ Parameter Store setup complete$(NC)"

dev-setup: setup install-deps ## Full development environment setup
	@echo "$(GREEN)🚀 Development environment ready!$(NC)"

# =============================================================================
# TESTING AND VALIDATION
# =============================================================================

test: ## Run comprehensive test suite
	@echo "$(BLUE)Running comprehensive test suite...$(NC)"
	@chmod +x tools/test-runner.sh
	@tools/test-runner.sh
	@echo "$(GREEN)✓ All tests complete$(NC)"

test-unit: ## Run unit tests only
	@echo "$(BLUE)Running unit tests...$(NC)"
	@chmod +x tools/test-runner.sh
	@tools/test-runner.sh unit
	@echo "$(GREEN)✓ Unit tests complete$(NC)"

test-integration: ## Run integration tests only
	@echo "$(BLUE)Running integration tests...$(NC)"
	@chmod +x tools/test-runner.sh
	@tools/test-runner.sh integration
	@echo "$(GREEN)✓ Integration tests complete$(NC)"

test-security: ## Run security tests
	@echo "$(BLUE)Running security tests...$(NC)"
	@chmod +x tools/test-runner.sh
	@tools/test-runner.sh security
	@echo "$(GREEN)✓ Security tests complete$(NC)"

test-modular: ## Test modular system components
	@echo "$(BLUE)Testing modular system...$(NC)"
	@chmod +x tests/test-modular-v2.sh
	@tests/test-modular-v2.sh
	@echo "$(GREEN)✓ Modular system tests complete$(NC)"

test-infrastructure: ## Test infrastructure modules
	@echo "$(BLUE)Testing infrastructure modules...$(NC)"
	@chmod +x tests/test-infrastructure-modules.sh
	@tests/test-infrastructure-modules.sh
	@echo "$(GREEN)✓ Infrastructure tests complete$(NC)"

test-local: ## Test deployment logic without AWS (no costs)
	@echo "$(BLUE)Testing deployment logic locally...$(NC)"
	@chmod +x scripts/simple-demo.sh
	@scripts/simple-demo.sh
	@chmod +x scripts/test-intelligent-selection.sh
	@scripts/test-intelligent-selection.sh
	@echo "$(GREEN)✓ Local tests complete$(NC)"

final-validation: ## Run comprehensive system validation
	@echo "$(BLUE)Running final system validation...$(NC)"
	@chmod +x tests/final-validation.sh
	@tests/final-validation.sh
	@echo "$(GREEN)✓ Final validation complete$(NC)"

lint: ## Run linting and code quality checks
	@echo "$(BLUE)Running linting...$(NC)"
	@chmod +x scripts/security-validation.sh
	@scripts/security-validation.sh
	@echo "$(GREEN)✓ Linting complete$(NC)"

security-check: ## Run comprehensive security validation
	@echo "$(BLUE)Running security validation...$(NC)"
	@chmod +x scripts/security-validation.sh
	@scripts/security-validation.sh || (echo "$(RED)Security validation failed$(NC)" && exit 1)
	@echo "$(GREEN)✓ Security validation passed$(NC)"

validate: security-check ## Validate all configurations and security
	@echo "$(GREEN)✓ Validation complete$(NC)"

# =============================================================================
# DEPLOYMENT (MODULAR ARCHITECTURE)
# =============================================================================

deploy-simple: validate ## Deploy simple development stack (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "$(RED)❌ Error: STACK_NAME is required. Use: make deploy-simple STACK_NAME=my-stack$(NC)"; exit 1; fi
	@echo "$(BLUE)Deploying simple development stack: $(STACK_NAME)$(NC)"
	@chmod +x scripts/aws-deployment-v2-simple.sh
	@scripts/aws-deployment-v2-simple.sh $(STACK_NAME)
	@echo "$(GREEN)✓ Simple deployment complete$(NC)"

deploy-spot: validate ## Deploy with cost-optimized spot instances (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "$(RED)❌ Error: STACK_NAME is required$(NC)"; exit 1; fi
	@echo "$(BLUE)💰 Deploying cost-optimized spot instance: $(STACK_NAME)$(NC)"
	@chmod +x scripts/aws-deployment-modular.sh
	@scripts/aws-deployment-modular.sh --spot $(STACK_NAME)
	@echo "$(GREEN)✓ Spot deployment complete$(NC)"

deploy-enterprise: validate ## Deploy enterprise multi-AZ with ALB (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "$(RED)❌ Error: STACK_NAME is required$(NC)"; exit 1; fi
	@echo "$(BLUE)🏢 Deploying enterprise multi-AZ stack: $(STACK_NAME)$(NC)"
	@chmod +x scripts/aws-deployment-modular.sh
	@scripts/aws-deployment-modular.sh --multi-az --alb --spot $(STACK_NAME)
	@echo "$(GREEN)✓ Enterprise deployment complete$(NC)"

deploy-full: validate ## Deploy with all enterprise features (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "$(RED)❌ Error: STACK_NAME is required$(NC)"; exit 1; fi
	@echo "$(BLUE)🚀 Deploying full enterprise stack with CDN: $(STACK_NAME)$(NC)"
	@chmod +x scripts/aws-deployment-modular.sh
	@scripts/aws-deployment-modular.sh --multi-az --private-subnets --nat-gateway --alb --spot $(STACK_NAME)
	@echo "$(GREEN)✓ Full enterprise deployment complete$(NC)"

# Legacy deployment aliases for backward compatibility
deploy: deploy-simple ## Deploy infrastructure (legacy alias, requires STACK_NAME)

deploy-ondemand: validate ## Deploy with on-demand instances (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "$(RED)❌ Error: STACK_NAME is required$(NC)"; exit 1; fi
	@echo "$(BLUE)Deploying on-demand instance: $(STACK_NAME)$(NC)"
	@chmod +x scripts/aws-deployment-modular.sh
	@scripts/aws-deployment-modular.sh --on-demand $(STACK_NAME)
	@echo "$(GREEN)✓ On-demand deployment complete$(NC)"

deploy-spot-cdn: validate ## Deploy spot with CloudFront CDN (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "$(RED)❌ Error: STACK_NAME is required$(NC)"; exit 1; fi
	@echo "$(BLUE)🌐 Deploying spot instance with CDN: $(STACK_NAME)$(NC)"
	@chmod +x scripts/aws-deployment-modular.sh
	@scripts/aws-deployment-modular.sh --spot --alb --cloudfront $(STACK_NAME)
	@echo "$(GREEN)✓ Spot CDN deployment complete$(NC)"

destroy: ## Destroy infrastructure (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "$(RED)❌ Error: STACK_NAME is required$(NC)"; exit 1; fi
	@echo "$(YELLOW)⚠️  WARNING: This will destroy all resources for $(STACK_NAME)$(NC)"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ]
	@chmod +x scripts/aws-deployment-v2-simple.sh
	@scripts/aws-deployment-v2-simple.sh --cleanup-only $(STACK_NAME)
	@echo "$(GREEN)✓ Resources destroyed$(NC)"

cleanup: ## Cleanup failed deployments and orphaned resources
	@echo "$(BLUE)Cleaning up failed deployments...$(NC)"
	@chmod +x scripts/cleanup-consolidated.sh
	@scripts/cleanup-consolidated.sh --mode failed-deployments
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

# =============================================================================
# MONITORING AND OPERATIONS
# =============================================================================

status: ## Check deployment status (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "$(RED)❌ Error: STACK_NAME is required$(NC)"; exit 1; fi
	@echo "$(BLUE)Checking status for: $(STACK_NAME)$(NC)"
	@chmod +x scripts/check-instance-status.sh
	@scripts/check-instance-status.sh $(STACK_NAME)

health-check: ## Basic health check of services (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "$(RED)❌ Error: STACK_NAME is required$(NC)"; exit 1; fi
	@echo "$(BLUE)🏥 Running basic health check for: $(STACK_NAME)$(NC)"
	@chmod +x scripts/validate-environment.sh
	@scripts/validate-environment.sh $(STACK_NAME) || echo "$(YELLOW)⚠️  Some services may be unhealthy$(NC)"
	@echo "$(GREEN)✓ Health check complete$(NC)"

health-check-advanced: ## Comprehensive health diagnostics (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "$(RED)❌ Error: STACK_NAME is required$(NC)"; exit 1; fi
	@echo "$(BLUE)🏥 Running advanced health diagnostics for: $(STACK_NAME)$(NC)"
	@chmod +x scripts/health-check-advanced.sh
	@scripts/health-check-advanced.sh $(STACK_NAME)
	@echo "$(GREEN)✓ Advanced health check complete$(NC)"

logs: ## View application logs (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "$(RED)❌ Error: STACK_NAME is required$(NC)"; exit 1; fi
	@echo "$(BLUE)Viewing logs for: $(STACK_NAME)$(NC)"
	@chmod +x tools/view-logs.sh
	@tools/view-logs.sh $(STACK_NAME)

monitor: ## Open monitoring dashboard
	@echo "$(BLUE)Opening monitoring dashboard...$(NC)"
	@chmod +x tools/open-monitoring.sh
	@tools/open-monitoring.sh

backup: ## Create backup (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "$(RED)❌ Error: STACK_NAME is required$(NC)"; exit 1; fi
	@echo "$(BLUE)Creating backup for: $(STACK_NAME)$(NC)"
	@chmod +x tools/backup.sh
	@tools/backup.sh $(STACK_NAME)
	@echo "$(GREEN)✓ Backup complete$(NC)"

check-quotas: ## Check AWS service quotas
	@echo "$(BLUE)Checking AWS service quotas...$(NC)"
	@chmod +x scripts/check-quotas.sh
	@scripts/check-quotas.sh
	@echo "$(GREEN)✓ Quota check complete$(NC)"

# =============================================================================
# CONFIGURATION MANAGEMENT
# =============================================================================

config-generate: ## Generate configuration files (requires ENV)
	@if [ -z "$(ENV)" ]; then echo "$(RED)❌ Error: ENV is required. Use: make config-generate ENV=development$(NC)"; exit 1; fi
	@echo "$(BLUE)Generating configuration for environment: $(ENV)$(NC)"
	@chmod +x scripts/config-manager.sh
	@scripts/config-manager.sh generate $(ENV)
	@echo "$(GREEN)✓ Configuration files generated$(NC)"

config-validate: ## Validate configuration (requires ENV)
	@if [ -z "$(ENV)" ]; then echo "$(RED)❌ Error: ENV is required. Use: make config-validate ENV=development$(NC)"; exit 1; fi
	@echo "$(BLUE)Validating configuration for: $(ENV)$(NC)"
	@chmod +x scripts/config-manager.sh
	@scripts/config-manager.sh validate $(ENV)
	@echo "$(GREEN)✓ Configuration validation complete$(NC)"

config-show: ## Show configuration summary (requires ENV)
	@if [ -z "$(ENV)" ]; then echo "$(RED)❌ Error: ENV is required. Use: make config-show ENV=development$(NC)"; exit 1; fi
	@echo "$(BLUE)Configuration summary for: $(ENV)$(NC)"
	@chmod +x scripts/config-manager.sh
	@scripts/config-manager.sh show $(ENV)

config-test: ## Test configuration management
	@echo "$(BLUE)Testing configuration management...$(NC)"
	@chmod +x tests/test-config-management.sh
	@tests/test-config-management.sh
	@echo "$(GREEN)✓ Configuration tests complete$(NC)"

# =============================================================================
# UTILITIES
# =============================================================================

clean: ## Clean up temporary files and caches
	@echo "$(BLUE)Cleaning up temporary files...$(NC)"
	@rm -rf test-reports/
	@rm -f *.log *.tmp *.temp
	@find . -name "*.backup.*" -delete 2>/dev/null || true
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

update-deps: ## Update Docker images and dependencies
	@echo "$(BLUE)Updating dependencies...$(NC)"
	@chmod +x scripts/simple-update-images.sh
	@scripts/simple-update-images.sh
	@echo "$(GREEN)✓ Dependencies updated$(NC)"

security-scan: ## Run comprehensive security scan
	@echo "$(BLUE)Running security scan...$(NC)"
	@chmod +x scripts/security-check.sh
	@scripts/security-check.sh
	@echo "$(GREEN)✓ Security scan complete$(NC)"

rotate-secrets: ## Rotate all secrets
	@echo "$(YELLOW)Rotating secrets...$(NC)"
	@chmod +x scripts/setup-secrets.sh
	@scripts/setup-secrets.sh backup
	@scripts/setup-secrets.sh regenerate
	@echo "$(GREEN)✓ Secrets rotated successfully$(NC)"

fix-deployment: ## Fix common deployment issues (requires STACK_NAME and REGION)
	@if [ -z "$(STACK_NAME)" ] || [ -z "$(REGION)" ]; then echo "$(RED)❌ Error: Both STACK_NAME and REGION are required$(NC)"; exit 1; fi
	@echo "$(BLUE)Fixing deployment issues for $(STACK_NAME) in $(REGION)...$(NC)"
	@chmod +x scripts/fix-deployment-issues.sh
	@scripts/fix-deployment-issues.sh $(STACK_NAME) $(REGION)
	@echo "$(GREEN)✓ Deployment fixes applied$(NC)"

# =============================================================================
# DOCUMENTATION
# =============================================================================

docs: ## Generate documentation
	@echo "$(BLUE)Generating documentation...$(NC)"
	@chmod +x tools/generate-docs.sh
	@tools/generate-docs.sh
	@echo "$(GREEN)✓ Documentation generated in docs/$(NC)"

docs-serve: ## Serve documentation locally
	@echo "$(BLUE)Starting documentation server at http://localhost:8080$(NC)"
	@cd docs && python3 -m http.server 8080 || python -m http.server 8080

# =============================================================================
# EXAMPLES AND QUICK START
# =============================================================================

quick-start: ## Show quick start guide
	@echo "$(GREEN)🚀 GeuseMaker Quick Start Guide$(NC)"
	@echo ""
	@echo "$(BLUE)Development Deployment:$(NC)"
	@echo "  1. make setup                              # Initial setup"
	@echo "  2. make deploy-simple STACK_NAME=dev      # Deploy development"
	@echo "  3. make status STACK_NAME=dev              # Check status"
	@echo "  4. make health-check STACK_NAME=dev        # Verify services"
	@echo ""
	@echo "$(BLUE)Production Deployment:$(NC)"
	@echo "  1. make deploy-spot STACK_NAME=prod        # Cost-optimized production"
	@echo "  2. make deploy-enterprise STACK_NAME=prod  # High-availability production"
	@echo ""
	@echo "$(BLUE)Testing (No AWS Costs):$(NC)"
	@echo "  1. make test-local                         # Test logic locally"
	@echo "  2. make test                               # Run all tests"
	@echo "  3. make final-validation                   # Comprehensive validation"
	@echo ""
	@echo "$(BLUE)Cleanup:$(NC)"
	@echo "  1. make destroy STACK_NAME=stack-name      # Destroy resources"
	@echo ""
	@echo "$(BLUE)For all commands:$(NC) make help"

example-dev: ## Deploy example development environment
	@$(MAKE) deploy-simple STACK_NAME=example-dev-$(shell whoami)

example-prod: ## Deploy example production environment  
	@$(MAKE) deploy-spot STACK_NAME=example-prod-$(shell date +%Y%m%d)

# =============================================================================
# TROUBLESHOOTING
# =============================================================================

troubleshoot: ## Show troubleshooting information
	@echo "$(BLUE)GeuseMaker Troubleshooting$(NC)"
	@echo ""
	@echo "$(YELLOW)Common Issues:$(NC)"
	@echo "  • Disk space full:     make fix-deployment STACK_NAME=X REGION=Y"
	@echo "  • Services not starting: make health-check-advanced STACK_NAME=X"
	@echo "  • Spot capacity issues: Scripts automatically try fallback regions"
	@echo "  • Variable errors:     Use modular deployment scripts"
	@echo ""
	@echo "$(YELLOW)Debug Commands:$(NC)"
	@echo "  • make status STACK_NAME=X                 # Check deployment"
	@echo "  • make logs STACK_NAME=X                   # View logs"
	@echo "  • make test-local                          # Test without AWS"
	@echo ""
	@echo "$(YELLOW)Documentation:$(NC)"
	@echo "  • docs/guides/troubleshooting.md           # Detailed solutions"
	@echo "  • docs/guides/deployment.md                # Deployment guide"
	@echo "  • docs/guides/architecture.md              # System architecture"

.DEFAULT_GOAL := help