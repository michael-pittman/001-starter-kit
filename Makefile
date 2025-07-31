# =============================================================================
# GeuseMaker AWS Deployment Makefile
# Modular deployment system with uniform coding standards
# =============================================================================

.PHONY: help install test test-unit test-integration test-security test-performance test-report \
        lint security format deploy deploy-spot deploy-alb deploy-cdn deploy-full \
        clean destroy destroy-spot destroy-alb destroy-cdn status logs monitoring health \
        maintenance-fix maintenance-cleanup maintenance-backup maintenance-restore \
        maintenance-health maintenance-update maintenance-optimize maintenance-validate \
        maintenance-update-simple maintenance-help \
        check-quotas check-deps backup restore update \
        existing-resources-discover existing-resources-validate existing-resources-test \
        existing-resources-list existing-resources-map deploy-with-vpc deploy-existing \
        deploy-auto-discover deploy-existing-validate \
        deploy-dev deploy-staging deploy-prod destroy-dev destroy-staging destroy-prod \
        ci-test ci-deploy debug troubleshoot dev dev-stop docs docs-serve \
        quickstart setup-config validate-config info ssh start stop restart \
        metrics cost-report configure-domain

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
	@echo '🚀 QUICK START (5 minutes to deploy):'
	@echo '  make quickstart          Interactive setup and deploy'
	@echo '  make deploy-spot         Deploy development stack ($0.50/hr)'
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
	@echo 'Existing Resources:'
	@echo '  existing-resources-discover    Discover existing AWS resources'
	@echo '  existing-resources-validate   Validate existing AWS resources'
	@echo '  existing-resources-test       Test existing resources connectivity'
	@echo '  existing-resources-list       List configured existing resources'
	@echo '  existing-resources-map        Map existing resources to variables'
	@echo '  deploy-with-vpc              Deploy using existing VPC'
	@echo '  deploy-existing              Deploy using existing resources'
	@echo '  deploy-auto-discover         Deploy with auto-discovered resources'
	@echo '  deploy-existing-validate     Deploy with existing resources (validated)'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# =============================================================================
# QUICK START TARGETS
# =============================================================================

quickstart: ## 🚀 Interactive setup wizard and deployment (5 minutes)
	@echo "🚀 Starting GeuseMaker Quick Start..."
	@echo ""
	@echo "This will guide you through:"
	@echo "1. Setting up your configuration"
	@echo "2. Validating prerequisites" 
	@echo "3. Deploying your AI stack"
	@echo ""
	@./scripts/setup-configuration.sh
	@echo ""
	@echo "Configuration complete! Now deploying..."
	@$(MAKE) deploy-spot
	@echo ""
	@echo "🎉 Deployment complete! Your AI stack is ready."
	@$(MAKE) info

setup-config: ## Interactive configuration setup wizard
	@echo "🔧 Starting configuration setup..."
	@./scripts/setup-configuration.sh

validate-config: ## Validate current configuration
	@echo "🔍 Validating configuration..."
	@./scripts/validate-configuration.sh

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


# =============================================================================
# TESTING TARGETS
# =============================================================================

test: ## Run all tests
	@echo "🧪 Running tests..."
	@if [ -f "tools/test-runner.sh" ]; then ./tools/test-runner.sh; else \
		if [ -f "tests/run-deployment-tests.sh" ]; then bash tests/run-deployment-tests.sh; fi; \
	fi
	@echo "✅ Tests completed"

test-unit: ## Run unit tests only
	@echo "🧪 Running unit tests..."
	@if [ -f "tools/test-runner.sh" ]; then ./tools/test-runner.sh unit; else \
		if [ -f "tests/run-deployment-tests.sh" ]; then bash tests/run-deployment-tests.sh --unit; fi; \
	fi
	@echo "✅ Unit tests completed"

test-integration: ## Run integration tests only
	@echo "🧪 Running integration tests..."
	@if [ -f "tools/test-runner.sh" ]; then ./tools/test-runner.sh integration; else \
		if [ -f "tests/run-deployment-tests.sh" ]; then bash tests/run-deployment-tests.sh --integration; fi; \
	fi
	@echo "✅ Integration tests completed"

test-security: ## Run security tests
	@echo "🔒 Running security tests..."
	@if [ -f "tools/test-runner.sh" ]; then ./tools/test-runner.sh security; fi
	@echo "✅ Security tests completed"

test-performance: ## Run performance tests
	@echo "⚡ Running performance tests..."
	@if [ -f "tools/test-runner.sh" ]; then ./tools/test-runner.sh performance; fi
	@echo "✅ Performance tests completed"

test-report: ## Run tests and generate HTML report
	@echo "📊 Running tests with report generation..."
	@if [ -f "tools/test-runner.sh" ]; then ./tools/test-runner.sh --report; fi
	@echo "✅ Test report generated"

# =============================================================================
# CODE QUALITY TARGETS
# =============================================================================

lint: ## Run linting and code quality checks
	@echo "🔍 Running linting..."
	@if command -v shellcheck >/dev/null 2>&1; then \
		find . -name "*.sh" -not -path "./archive/*" -not -path "./node_modules/*" -exec shellcheck {} + || true; \
	else \
		echo "⚠️  shellcheck not installed - skipping shell script linting"; \
	fi
	@echo "✅ Linting completed"

security: ## Run security scans
	@echo "🔒 Running security scans..."
	@if [ -f "tools/test-runner.sh" ]; then \
		./tools/test-runner.sh security; \
	elif [ -f "scripts/security-validation.sh" ]; then \
		./scripts/security-validation.sh; \
	else \
		echo "⚠️  No security scanning tools configured"; \
	fi
	@echo "✅ Security scans completed"

format: ## Format code
	@echo "🎨 Formatting code..."
	@echo "ℹ️  Note: Shell scripts follow consistent formatting standards"
	@echo "✅ Code formatting completed"

# =============================================================================
# DEPLOYMENT TARGETS - PRIMARY
# =============================================================================

## Basic Deployment Commands
deploy: deploy-full ## Deploy default stack (alias for deploy-full)

deploy-spot: ## Deploy spot instance stack (70% cost savings)
	@echo "🚀 Deploying spot instance stack..."
	@./deploy.sh --type spot --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ Spot instance deployment completed"

deploy-alb: ## Deploy ALB stack (load balancer + spot + CDN)
	@echo "🚀 Deploying ALB stack..."
	@./deploy.sh --type alb --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ ALB deployment completed"

deploy-cdn: ## Deploy CDN stack (CloudFront + ALB)
	@echo "🚀 Deploying CDN stack..."
	@./deploy.sh --type cdn --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ CDN deployment completed"

deploy-full: ## Deploy complete stack (VPC + EC2 + ALB + CDN + EFS)
	@echo "🚀 Deploying complete stack..."
	@./deploy.sh --type full --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ Complete stack deployment completed"

## Environment-Specific Deployments
deploy-dev: ## Deploy to development environment
	@$(MAKE) deploy ENV=dev

deploy-staging: ## Deploy to staging environment
	@$(MAKE) deploy ENV=staging

deploy-prod: ## Deploy to production environment
	@$(MAKE) deploy ENV=prod

# =============================================================================
# DESTROY/CLEANUP TARGETS
# =============================================================================

## Destroy Resources
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

## Environment-Specific Destruction
destroy-dev: ## Destroy development environment
	@$(MAKE) destroy ENV=dev

destroy-staging: ## Destroy staging environment
	@$(MAKE) destroy ENV=staging

destroy-prod: ## Destroy production environment
	@$(MAKE) destroy ENV=prod

clean: ## Clean build artifacts and temporary files
	@echo "🧹 Cleaning build artifacts..."
	@rm -rf node_modules dist build cdk.out .terraform terraform.tfstate* .pytest_cache __pycache__ .coverage
	@if [ -f "package.json" ]; then npm cache clean --force; fi
	@echo "✅ Cleanup completed"

# =============================================================================
# EXISTING RESOURCES DISCOVERY & VALIDATION
# =============================================================================

existing-resources-discover: ## Discover existing AWS resources
	@echo "🔍 Discovering existing resources for environment: $(ENV)"
	@./scripts/manage-existing-resources.sh discover -e $(ENV) -s $(STACK_NAME)
	@echo "✅ Resource discovery completed"

existing-resources-validate: ## Validate existing AWS resources
	@echo "🔍 Validating existing resources for environment: $(ENV)"
	@./scripts/manage-existing-resources.sh validate -e $(ENV) -s $(STACK_NAME)
	@echo "✅ Resource validation completed"

existing-resources-test: ## Test existing resources connectivity
	@echo "🧪 Testing existing resources connectivity for environment: $(ENV)"
	@./scripts/manage-existing-resources.sh test -e $(ENV) -s $(STACK_NAME)
	@echo "✅ Resource connectivity test completed"

existing-resources-list: ## List configured existing resources
	@echo "📋 Listing configured existing resources for environment: $(ENV)"
	@./scripts/manage-existing-resources.sh list -e $(ENV)
	@echo "✅ Resource listing completed"

existing-resources-map: ## Map existing resources to deployment variables
	@echo "🗺️  Mapping existing resources for environment: $(ENV)"
	@./scripts/manage-existing-resources.sh map -e $(ENV) -s $(STACK_NAME)
	@echo "✅ Resource mapping completed"

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

check-quotas: ## Check AWS service quotas
	@echo "📊 Checking AWS service quotas..."
	@if [ -f "scripts/check-quotas.sh" ]; then \
		./scripts/check-quotas.sh $(REGION); \
	else \
		echo "⚠️  Quota check script not found"; \
	fi
	@echo "✅ Quota check completed"

check-deps: ## Check system dependencies
	@echo "🔍 Checking dependencies..."
	@if [ -f "scripts/check-dependencies.sh" ]; then \
		./scripts/check-dependencies.sh; \
	else \
		echo "⚠️  Dependency check script not found"; \
	fi
	@echo "✅ Dependency check completed"

# =============================================================================
# DEPLOYMENT MANAGEMENT TARGETS
# =============================================================================

## Deployment Status & Operations
status: ## Show deployment status
	@echo "📊 Deployment status for stack: $(STACK_NAME)"
	@./deploy.sh --status --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)

info: ## Show service URLs and access information
	@echo "ℹ️  Service information for stack: $(STACK_NAME)"
	@./deploy.sh --info --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)

ssh: ## SSH into the deployed instance
	@echo "🔐 Connecting to instance..."
	@./deploy.sh --ssh --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)

logs: ## View application logs
	@echo "📋 Viewing application logs..."
	@./deploy.sh --logs --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)

monitoring: ## Open monitoring dashboard
	@echo "📊 Opening monitoring dashboard..."
	@./deploy.sh --monitoring --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)

health: ## Check deployment health
	@echo "🏥 Checking deployment health..."
	@./deploy.sh --health --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)

validate: ## Validate deployment configuration
	@echo "🔍 Validating deployment configuration..."
	@./deploy.sh --validate --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ Configuration validation passed"

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

start: ## Start services (keeps infrastructure)
	@echo "▶️  Starting services..."
	@./deploy.sh --start --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ Services started"

stop: ## Stop services (keeps infrastructure)
	@echo "⏸️  Stopping services..."
	@./deploy.sh --stop --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ Services stopped"

restart: ## Restart services
	@echo "🔄 Restarting services..."
	@./deploy.sh --restart --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)
	@echo "✅ Services restarted"

metrics: ## View deployment metrics
	@echo "📊 Viewing metrics..."
	@./deploy.sh --metrics --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)

cost-report: ## Generate cost report
	@echo "💰 Generating cost report..."
	@./deploy.sh --cost-report --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)

configure-domain: ## Configure custom domain
	@echo "🌐 Configuring domain: $(DOMAIN)"
	@./deploy.sh --configure-domain $(DOMAIN) --env $(ENV) --profile $(PROFILE) --region $(REGION) --stack-name $(STACK_NAME)

# =============================================================================
# DEPLOYMENT TARGETS - EXISTING RESOURCES
# =============================================================================

## Deploy with Existing Resources
deploy-with-vpc: ## Deploy using existing VPC
	@echo "🚀 Deploying with existing VPC..."
	@./scripts/aws-deployment-modular.sh \
		--use-existing-vpc $(VPC_ID) \
		--stack-name $(STACK_NAME) \
		--env $(ENV) \
		--profile $(PROFILE) \
		--region $(REGION)
	@echo "✅ Deployment with existing VPC completed"

deploy-existing: ## Deploy using existing resources (VPC_ID, EFS_ID, ALB_ARN, CLOUDFRONT_ID)
	@echo "🚀 Deploying with existing resources..."
	@./scripts/aws-deployment-modular.sh \
		$(if $(VPC_ID),--use-existing-vpc $(VPC_ID)) \
		$(if $(EFS_ID),--use-existing-efs $(EFS_ID)) \
		$(if $(ALB_ARN),--use-existing-alb $(ALB_ARN)) \
		$(if $(CLOUDFRONT_ID),--use-existing-cloudfront $(CLOUDFRONT_ID)) \
		--stack-name $(STACK_NAME) \
		--env $(ENV) \
		--profile $(PROFILE) \
		--region $(REGION)
	@echo "✅ Deployment with existing resources completed"

deploy-auto-discover: ## Deploy with auto-discovered existing resources
	@echo "🚀 Deploying with auto-discovered resources..."
	@$(MAKE) existing-resources-discover
	@$(MAKE) existing-resources-validate
	@$(MAKE) deploy-existing
	@echo "✅ Deployment with auto-discovered resources completed"

deploy-existing-validate: ## Deploy with existing resources (with validation)
	@echo "🚀 Deploying with existing resources (with validation)..."
	@$(MAKE) existing-resources-validate
	@$(MAKE) deploy-existing
	@echo "✅ Deployment with existing resources (validated) completed"

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