# GeuseMaker Makefile
# Build automation and development tools

.PHONY: help setup clean test lint deploy destroy validate docs

# Default target
help: ## Show this help message
	@echo "GeuseMaker - Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# =============================================================================
# SETUP AND DEPENDENCIES
# =============================================================================

## Security targets
.PHONY: setup-secrets security-check security-validate

setup-secrets: ## Setup secrets for secure deployment
	@echo "$(BLUE)Setting up secrets...$(NC)"
	@chmod +x scripts/setup-secrets.sh
	@scripts/setup-secrets.sh setup

security-check: ## Run comprehensive security validation
	@echo "$(BLUE)Running security validation...$(NC)"
	@chmod +x scripts/security-validation.sh
	@scripts/security-validation.sh || (echo "$(RED)Security validation failed$(NC)" && exit 1)
	@echo "$(GREEN)✓ Security validation passed$(NC)"

security-validate: setup-secrets security-check ## Complete security setup and validation
	@echo "$(GREEN)✓ Security setup complete$(NC)"

rotate-secrets: ## Rotate all secrets
	@echo "$(YELLOW)Rotating secrets...$(NC)"
	@scripts/setup-secrets.sh backup
	@scripts/setup-secrets.sh regenerate
	@echo "$(GREEN)✓ Secrets rotated successfully$(NC)"

# Update setup target to include security
setup: check-deps setup-secrets ## Complete initial setup with security
	@echo "$(GREEN)✓ Setup complete with security configurations$(NC)"

install-deps: ## Install required dependencies
	@echo "Installing dependencies..."
	@./tools/install-deps.sh
	@echo "✅ Dependencies installed"

check-deps: ## Check if all dependencies are available
	@echo "Checking dependencies..."
	@./scripts/security-validation.sh
	@echo "✅ Dependencies check complete"

# =============================================================================
# DEVELOPMENT
# =============================================================================

dev-setup: setup install-deps ## Full development setup
	@echo "🚀 Development environment ready!"

validate: ## Validate all configurations
	@echo "Validating configurations..."
	@./tools/validate-config.sh
	@echo "✅ Configuration validation complete"

lint: ## Run linting on all code
	@echo "Running linters..."
	@./tools/lint.sh
	@echo "✅ Linting complete"

format: ## Format all code
	@echo "Formatting code..."
	@./tools/format.sh
	@echo "✅ Code formatting complete"

# =============================================================================
# TESTING
# =============================================================================

test: ## Run all tests
	@echo "Running tests..."
	@./tools/test-runner.sh
	@echo "✅ Tests complete"

test-unit: ## Run unit tests only
	@echo "Running unit tests..."
	@python -m pytest tests/unit/ -v

test-integration: ## Run integration tests only
	@echo "Running integration tests..."
	@python -m pytest tests/integration/ -v

test-security: ## Run security tests
	@echo "Running security tests..."
	@./tools/security-scan.sh

# =============================================================================
# DEPLOYMENT
# =============================================================================

plan: ## Show deployment plan
	@echo "Showing deployment plan..."
	@./scripts/aws-deployment-unified.sh --validate-only $(STACK_NAME)

deploy: validate ## Deploy infrastructure (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required. Use: make deploy STACK_NAME=my-stack"; exit 1; fi
	@echo "Deploying stack: $(STACK_NAME)"
	@FORCE_YES=true ./scripts/aws-deployment-unified.sh $(STACK_NAME)

deploy-spot: ## Deploy with spot instances (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@echo "Deploying spot instance with stack name: $(STACK_NAME)"
	@echo "📋 Real-time provisioning logs will be shown during deployment"
	@FORCE_YES=true FOLLOW_LOGS=true ./scripts/aws-deployment-unified.sh -t spot $(STACK_NAME)

deploy-ondemand: validate ## Deploy with on-demand instances (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@FORCE_YES=true ./scripts/aws-deployment-unified.sh -t ondemand $(STACK_NAME)

deploy-simple: validate ## Deploy simple development instance (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@FORCE_YES=true ./scripts/aws-deployment-unified.sh -t simple $(STACK_NAME)

destroy: ## Destroy infrastructure (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@echo "⚠️  WARNING: This will destroy all resources for $(STACK_NAME)"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ]
	@./scripts/aws-deployment-unified.sh --cleanup $(STACK_NAME)

# =============================================================================
# TERRAFORM (ALTERNATIVE DEPLOYMENT)
# =============================================================================

tf-init: ## Initialize Terraform
	@cd terraform && terraform init

tf-plan: ## Show Terraform plan (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@cd terraform && terraform plan -var="stack_name=$(STACK_NAME)"

tf-apply: ## Apply Terraform configuration (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@cd terraform && terraform apply -var="stack_name=$(STACK_NAME)"

tf-destroy: ## Destroy Terraform resources (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@cd terraform && terraform destroy -var="stack_name=$(STACK_NAME)"

# =============================================================================
# MONITORING AND OPERATIONS
# =============================================================================

status: ## Check deployment status (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@./tools/check-status.sh $(STACK_NAME)

logs: ## View application logs (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@./tools/view-logs.sh $(STACK_NAME)

monitor: ## Open monitoring dashboard
	@./tools/open-monitoring.sh

health-check: ## Basic health check of services (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@echo "🏥 Checking service health..."
	@./scripts/validate-deployment.sh $(STACK_NAME) || echo "⚠️  Some services may be unhealthy"

health-check-advanced: ## Comprehensive health diagnostics (requires deployed instance)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@echo "🏥 Running advanced health diagnostics..."
	@./scripts/health-check-advanced.sh

backup: ## Create backup (requires STACK_NAME)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@./tools/backup.sh $(STACK_NAME)

# =============================================================================
# DOCUMENTATION
# =============================================================================

docs: ## Generate documentation
	@echo "Generating documentation..."
	@./tools/generate-docs.sh
	@echo "✅ Documentation generated in docs/"

docs-serve: ## Serve documentation locally
	@echo "Starting documentation server..."
	@cd docs && python -m http.server 8080

# =============================================================================
# UTILITIES
# =============================================================================

clean: ## Clean up temporary files and caches
	@echo "Cleaning up..."
	@rm -rf .pytest_cache/
	@rm -rf __pycache__/
	@rm -f *.log
	@rm -f *.tmp
	@find . -name "*.pyc" -delete
	@find . -name "*.pyo" -delete
	@echo "✅ Cleanup complete"

cost-estimate: ## Estimate deployment costs (requires STACK_NAME and HOURS)
	@if [ -z "$(STACK_NAME)" ]; then echo "❌ Error: STACK_NAME is required"; exit 1; fi
	@python scripts/cost-optimization.py estimate $(STACK_NAME) $(HOURS)

security-scan: ## Run comprehensive security scan
	@echo "Running security scan..."
	@./tools/security-scan.sh
	@echo "✅ Security scan complete"

update-deps: ## Update dependencies
	@echo "Updating dependencies..."
	@./tools/update-deps.sh
	@echo "✅ Dependencies updated"

# =============================================================================
# EXAMPLES AND QUICK START
# =============================================================================

example-dev: ## Deploy example development environment
	@$(MAKE) deploy-simple STACK_NAME=GeuseMaker-dev-$(shell whoami)

example-prod: ## Deploy example production environment
	@$(MAKE) deploy-ondemand STACK_NAME=GeuseMaker-prod-$(shell date +%Y%m%d)

quick-start: ## Quick start guide
	@echo "🚀 GeuseMaker Quick Start"
	@echo ""
	@echo "1. Setup:           make setup"
	@echo "2. Install deps:    make install-deps"  
	@echo "3. Deploy dev:      make deploy-simple STACK_NAME=my-dev-stack"
	@echo "4. Check status:    make status STACK_NAME=my-dev-stack"
	@echo "5. View logs:       make logs STACK_NAME=my-dev-stack"
	@echo "6. Cleanup:         make destroy STACK_NAME=my-dev-stack"
	@echo ""
	@echo "For more commands:  make help"