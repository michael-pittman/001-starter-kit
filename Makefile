# =============================================================================
# GeuseMaker AWS Deployment Makefile
# Modular deployment system with uniform coding standards
# =============================================================================

.PHONY: help install test lint security deploy clean destroy status logs monitoring \
        maintenance-fix maintenance-cleanup maintenance-backup maintenance-restore \
        maintenance-health maintenance-update maintenance-optimize maintenance-validate \
        maintenance-update-simple maintenance-help

# =============================================================================
# CONFIGURATION
# =============================================================================

# Default environment
ENV ?= dev
PROFILE ?= $(ENV)
REGION ?= us-east-1
STACK_NAME ?= geusemaker-$(ENV)

# Deployment types
DEPLOYMENT_TYPES := spot alb cdn full

# =============================================================================
# HELP TARGET
# =============================================================================

help: ## Show this help message
	@echo 'GeuseMaker AWS Deployment System'
	@echo '================================'
	@echo ''
	@echo 'Usage: make [target] [ENV=environment] [STACK_NAME=name]'
	@echo ''
	@echo 'Environment Variables:'
	@echo '  ENV         Environment name (dev, staging, prod) [default: dev]'
	@echo '  PROFILE     AWS profile to use [default: ENV]'
	@echo '  REGION      AWS region [default: us-east-1]'
	@echo '  STACK_NAME  Stack name [default: geusemaker-ENV]'
	@echo ''
	@echo 'Deployment Types:'
	@echo '  spot        Deploy EC2 spot instance with EFS (single AZ)'
	@echo '  alb         Deploy ALB with spot instances, CDN, and EFS (single AZ)'
	@echo '  cdn         Deploy CloudFront CDN with ALB and EFS (single AZ)'
	@echo '  full        Deploy complete stack with all features (single AZ)'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# =============================================================================
# SETUP TARGETS
# =============================================================================

install: ## Install dependencies and setup environment
	@echo "🔧 Installing dependencies..."
	@if [ -f "package.json" ]; then npm ci; fi
	@if [ -f "requirements.txt" ]; then pip install -r requirements.txt; fi
	@if [ -f "Pipfile" ]; then pipenv install; fi
	@echo "✅ Dependencies installed"

setup: ## Setup AWS configuration and validate environment
	@echo "🔧 Setting up AWS configuration..."
	@./deploy.sh --setup --env $(ENV) --profile $(PROFILE) --region $(REGION)
	@echo "✅ AWS configuration setup completed"

validate: ## Validate deployment configuration
	@echo "🔍 Validating deployment configuration..."
	@./deploy.sh --validate --env $(ENV) --profile $(PROFILE) --region $(REGION)
	@echo "✅ Configuration validation passed"

# =============================================================================
# TESTING TARGETS
# =============================================================================

test: ## Run all tests
	@echo "🧪 Running tests..."
	@if [ -f "package.json" ]; then npm test; fi
	@if [ -f "pytest.ini" ] || [ -f "tests/" ]; then python -m pytest tests/; fi
	@if [ -f "tests/" ]; then bash tests/run-deployment-tests.sh; fi
	@echo "✅ Tests completed"

test-unit: ## Run unit tests only
	@echo "🧪 Running unit tests..."
	@if [ -f "package.json" ]; then npm run test:unit; fi
	@if [ -f "pytest.ini" ]; then python -m pytest tests/unit/; fi
	@echo "✅ Unit tests completed"

test-integration: ## Run integration tests only
	@echo "🧪 Running integration tests..."
	@if [ -f "package.json" ]; then npm run test:integration; fi
	@if [ -f "pytest.ini" ]; then python -m pytest tests/integration/; fi
	@bash tests/run-deployment-tests.sh --integration
	@echo "✅ Integration tests completed"

# =============================================================================
# CODE QUALITY TARGETS
# =============================================================================

lint: ## Run linting and code quality checks
	@echo "🔍 Running linting..."
	@if [ -f "package.json" ]; then npm run lint; fi
	@if [ -f ".eslintrc" ]; then npx eslint .; fi
	@if [ -f "flake8" ] || [ -f "setup.cfg" ]; then flake8 .; fi
	@if [ -f "black" ]; then black --check .; fi
	@if [ -f "shellcheck" ]; then find . -name "*.sh" -exec shellcheck {} \; || true; fi
	@echo "✅ Linting completed"

security: ## Run security scans
	@echo "🔒 Running security scans..."
	@if [ -f "package.json" ]; then npm audit; fi
	@if [ -f "safety" ]; then safety check; fi
	@if [ -f "bandit" ]; then bandit -r .; fi
	@if [ -f "tfsec" ]; then tfsec .; fi
	@if [ -f "checkov" ]; then checkov -d .; fi
	@echo "✅ Security scans completed"

format: ## Format code
	@echo "🎨 Formatting code..."
	@if [ -f "package.json" ]; then npm run format; fi
	@if [ -f "prettier" ]; then npx prettier --write .; fi
	@if [ -f "black" ]; then black .; fi
	@if [ -f "isort" ]; then isort .; fi
	@echo "✅ Code formatting completed"

# =============================================================================
# DEPLOYMENT TARGETS
# =============================================================================

deploy: ## Deploy default stack (full)
	@echo "🚀 Deploying full stack..."
	@./deploy.sh --full --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ Full stack deployment completed"

deploy-spot: ## Deploy spot instance stack
	@echo "🚀 Deploying spot instance stack..."
	@./deploy.sh --type spot --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ Spot instance deployment completed"

deploy-alb: ## Deploy ALB stack
	@echo "🚀 Deploying ALB stack..."
	@./deploy.sh --type alb --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ ALB deployment completed"

deploy-cdn: ## Deploy CDN stack
	@echo "🚀 Deploying CDN stack..."
	@./deploy.sh --type cdn --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ CDN deployment completed"

deploy-full: ## Deploy complete stack (VPC + EC2 + ALB + CDN)
	@echo "🚀 Deploying complete stack..."
	@./deploy.sh --type full --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ Complete stack deployment completed"

# =============================================================================
# MANAGEMENT TARGETS
# =============================================================================

status: ## Show deployment status
	@echo "📊 Deployment status for stack: $(STACK_NAME)"
	@./deploy.sh --status --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)

logs: ## View application logs
	@echo "📋 Viewing application logs..."
	@./deploy.sh --logs --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)

monitoring: ## Open monitoring dashboard
	@echo "📊 Opening monitoring dashboard..."
	@./deploy.sh --monitoring --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)

health: ## Check deployment health
	@echo "🏥 Checking deployment health..."
	@./deploy.sh --health --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)

# =============================================================================
# CLEANUP TARGETS
# =============================================================================

clean: ## Clean build artifacts and temporary files
	@echo "🧹 Cleaning build artifacts..."
	@rm -rf node_modules dist build cdk.out .terraform terraform.tfstate* .pytest_cache __pycache__ .coverage
	@if [ -f "package.json" ]; then npm cache clean --force; fi
	@echo "✅ Cleanup completed"

destroy: ## Destroy all resources for the stack
	@echo "🗑️  Destroying stack: $(STACK_NAME)"
	@read -p "Are you sure you want to destroy all resources? (yes/no): " confirm && [ "$$confirm" = "yes" ]
	@./deploy.sh --destroy --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ Stack destruction completed"

destroy-spot: ## Destroy spot instance resources
	@echo "🗑️  Destroying spot instance resources..."
	@./deploy.sh --destroy-spot --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ Spot instance destruction completed"

destroy-alb: ## Destroy ALB resources
	@echo "🗑️  Destroying ALB resources..."
	@./deploy.sh --destroy-alb --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ ALB destruction completed"

destroy-cdn: ## Destroy CDN resources
	@echo "🗑️  Destroying CDN resources..."
	@./deploy.sh --destroy-cdn --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ CDN destruction completed"

# =============================================================================
# DEVELOPMENT TARGETS
# =============================================================================

dev: ## Start development environment
	@echo "🛠️  Starting development environment..."
	@if [ -f "docker-compose.yml" ]; then docker-compose up -d; fi
	@if [ -f "package.json" ]; then npm run dev; fi
	@echo "✅ Development environment started"

dev-stop: ## Stop development environment
	@echo "🛑 Stopping development environment..."
	@if [ -f "docker-compose.yml" ]; then docker-compose down; fi
	@if [ -f "package.json" ]; then npm run dev:stop; fi
	@echo "✅ Development environment stopped"

# =============================================================================
# DOCUMENTATION TARGETS
# =============================================================================

docs: ## Generate documentation
	@echo "📚 Generating documentation..."
	@if [ -f "package.json" ]; then npm run docs; fi
	@if [ -f "mkdocs.yml" ]; then mkdocs build; fi
	@if [ -f "sphinx" ]; then make -C docs html; fi
	@echo "✅ Documentation generated"

docs-serve: ## Serve documentation locally
	@echo "📚 Serving documentation..."
	@if [ -f "mkdocs.yml" ]; then mkdocs serve; fi
	@if [ -f "sphinx" ]; then make -C docs serve; fi
	@echo "✅ Documentation server started"

# =============================================================================
# MAINTENANCE TARGETS
# =============================================================================

maintenance-fix: ## Fix deployment issues
	@echo "🔧 Running deployment fixes..."
	@. lib/modules/maintenance/maintenance-suite.sh && \
		run_maintenance --operation=fix --target=deployment --stack-name=$(STACK_NAME) --region=$(REGION)
	@echo "✅ Deployment fixes completed"

maintenance-cleanup: ## Clean up resources
	@echo "🧹 Running resource cleanup..."
	@. lib/modules/maintenance/maintenance-suite.sh && \
		run_maintenance --operation=cleanup --scope=stack --stack-name=$(STACK_NAME) $(if $(FORCE),--force) $(if $(DRY_RUN),--dry-run)
	@echo "✅ Resource cleanup completed"

maintenance-backup: ## Create maintenance backup
	@echo "💾 Creating maintenance backup..."
	@. lib/modules/maintenance/maintenance-suite.sh && \
		run_maintenance --operation=backup --backup-type=$(or $(TYPE),full) $(if $(COMPRESS),--compress)
	@echo "✅ Maintenance backup completed"

maintenance-restore: ## Restore from maintenance backup
	@echo "🔄 Restoring from maintenance backup..."
	@. lib/modules/maintenance/maintenance-suite.sh && \
		run_maintenance --operation=restore --backup-file=$(BACKUP_FILE) $(if $(VERIFY),--verify)
	@echo "✅ Maintenance restore completed"

maintenance-health: ## Run health checks
	@echo "🏥 Running health checks..."
	@. lib/modules/maintenance/maintenance-suite.sh && \
		run_maintenance --operation=health --stack-name=$(STACK_NAME) $(if $(VERBOSE),--verbose) $(if $(FIX),--auto-fix)
	@echo "✅ Health checks completed"

maintenance-update: ## Update system components
	@echo "🔄 Updating system components..."
	@. lib/modules/maintenance/maintenance-suite.sh && \
		run_maintenance --operation=update --component=docker --environment=$(or $(ENV),development) $(if $(USE_LATEST),--use-latest)
	@echo "✅ System update completed"

maintenance-optimize: ## Optimize system performance
	@echo "⚡ Optimizing system performance..."
	@. lib/modules/maintenance/maintenance-suite.sh && \
		run_maintenance --operation=optimize --target=$(or $(TARGET),all)
	@echo "✅ System optimization completed"

maintenance-validate: ## Validate system configuration
	@echo "🔍 Validating system configuration..."
	@. lib/modules/maintenance/maintenance-suite.sh && \
		run_maintenance --operation=validate --validation-type=$(or $(TYPE),all) $(if $(FIX),--fix-issues)
	@echo "✅ System validation completed"

maintenance-update-simple: ## Quick update to latest Docker images
	@echo "🐳 Updating Docker images to latest..."
	@. lib/modules/maintenance/maintenance-suite.sh && \
		run_maintenance --operation=update --component=docker --use-latest --simple-mode
	@echo "✅ Docker images updated"

maintenance-help: ## Show maintenance suite help
	@. lib/modules/maintenance/maintenance-suite.sh && run_maintenance --help

# =============================================================================
# UTILITY TARGETS
# =============================================================================

backup: ## Create backup of current deployment
	@echo "💾 Creating backup..."
	@./deploy.sh --backup --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ Backup completed"

restore: ## Restore from backup
	@echo "🔄 Restoring from backup..."
	@./deploy.sh --restore --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ Restore completed"

update: ## Update deployment configuration
	@echo "🔄 Updating deployment configuration..."
	@./deploy.sh --update --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ Update completed"

# =============================================================================
# ENVIRONMENT-SPECIFIC TARGETS
# =============================================================================

deploy-dev: ## Deploy to development environment
	@$(MAKE) deploy ENV=dev

deploy-staging: ## Deploy to staging environment
	@$(MAKE) deploy ENV=staging

deploy-prod: ## Deploy to production environment
	@$(MAKE) deploy ENV=prod

destroy-dev: ## Destroy development environment
	@$(MAKE) destroy ENV=dev

destroy-staging: ## Destroy staging environment
	@$(MAKE) destroy ENV=staging

destroy-prod: ## Destroy production environment
	@$(MAKE) destroy ENV=prod

# =============================================================================
# CI/CD TARGETS
# =============================================================================

ci-test: ## Run CI test suite
	@echo "🔍 Running CI tests..."
	@$(MAKE) test
	@$(MAKE) lint
	@$(MAKE) security
	@echo "✅ CI tests completed"

ci-deploy: ## Run CI deployment
	@echo "🚀 Running CI deployment..."
	@$(MAKE) validate
	@$(MAKE) deploy
	@$(MAKE) health
	@echo "✅ CI deployment completed"

# =============================================================================
# TROUBLESHOOTING TARGETS
# =============================================================================

debug: ## Enable debug mode and show detailed output
	@echo "🐛 Enabling debug mode..."
	@export DEBUG=1 && ./deploy.sh --debug --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)

troubleshoot: ## Run troubleshooting diagnostics
	@echo "🔧 Running troubleshooting diagnostics..."
	@./deploy.sh --troubleshoot --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)

# =============================================================================
# DEFAULT TARGET
# =============================================================================

.DEFAULT_GOAL := help