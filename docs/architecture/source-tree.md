# Source Tree

```
project-root/
├── deploy.sh                          # Main deployment orchestrator
├── Makefile                           # Build and deployment targets
├── README.md                          # Project documentation
├── docs/
│   ├── architecture.md                # This architecture document
│   ├── prd.md                         # Product requirements document
│   ├── coding-standards.md            # Coding standards and conventions
│   ├── deployment-guide.md            # Deployment instructions
│   └── troubleshooting.md             # Troubleshooting guide
├── lib/
│   ├── modules/
│   │   ├── core/                      # Core utilities and foundations
│   │   │   ├── variables.sh           # Variable management and persistence
│   │   │   ├── logging.sh             # Structured logging system
│   │   │   ├── errors.sh              # Base error handling
│   │   │   ├── validation.sh          # Input validation
│   │   │   ├── registry.sh            # Resource registry management
│   │   │   ├── dependency-groups.sh   # Library dependency management
│   │   │   └── instance-utils.sh      # Instance utility functions
│   │   ├── infrastructure/            # AWS infrastructure management
│   │   │   ├── vpc.sh                 # VPC and networking
│   │   │   ├── ec2.sh                 # EC2 instance management
│   │   │   ├── alb.sh                 # Application Load Balancer
│   │   │   ├── cloudfront.sh          # CDN distribution
│   │   │   ├── efs.sh                 # EFS filesystem management
│   │   │   ├── iam.sh                 # IAM roles and policies
│   │   │   └── security.sh            # Security groups
│   │   ├── compute/                   # EC2 compute operations
│   │   │   ├── ami.sh                 # AMI selection and validation
│   │   │   ├── spot_optimizer.sh      # Spot instance optimization
│   │   │   ├── provisioner.sh         # Instance provisioning
│   │   │   ├── autoscaling.sh         # Auto-scaling groups
│   │   │   ├── launch.sh              # Launch template management
│   │   │   ├── lifecycle.sh           # Instance lifecycle
│   │   │   └── security.sh            # Compute security config
│   │   ├── application/               # Application deployment
│   │   │   ├── base.sh                # Base application utilities
│   │   │   ├── docker_manager.sh      # Docker management
│   │   │   ├── ai_services.sh         # AI service stack setup
│   │   │   ├── health_monitor.sh      # Health monitoring
│   │   │   └── service_config.sh      # Service configuration
│   │   ├── deployment/                # Deployment orchestration
│   │   │   ├── orchestrator.sh        # Main deployment flow
│   │   │   ├── state.sh               # State management
│   │   │   ├── rollback.sh            # Rollback mechanisms
│   │   │   └── userdata.sh            # EC2 user data generation
│   │   ├── monitoring/                # Monitoring and health
│   │   │   ├── health.sh              # Health checks
│   │   │   └── metrics.sh             # Metrics collection
│   │   ├── errors/                    # Error handling
│   │   │   ├── error_types.sh         # Error type definitions
│   │   │   └── clear_messages.sh      # Clear error messages
│   │   └── cleanup/                   # Resource cleanup
│   │       └── resources.sh           # Resource cleanup operations
│   └── utils/                         # Shared utilities
│       ├── progress.sh                # Progress indicators
│       └── cli.sh                     # CLI utilities
├── config/
│   ├── defaults.yml                   # Default configuration
│   ├── deployment-types.yml           # Deployment type definitions
│   └── environments/                  # Environment-specific configs
│       ├── development.yml
│       ├── staging.yml
│       └── production.yml
├── scripts/
│   ├── setup.sh                       # Environment setup
│   ├── cleanup.sh                     # Resource cleanup
│   └── validate.sh                    # Configuration validation
├── tests/
│   ├── unit/                          # Unit tests
│   │   ├── test-core.sh
│   │   ├── test-infrastructure.sh
│   │   └── test-deployment.sh
│   ├── integration/                   # Integration tests
│   │   ├── test-deployment-flow.sh
│   │   └── test-rollback.sh
│   └── e2e/                           # End-to-end tests
│       └── test-full-deployment.sh
├── logs/                              # Deployment logs
├── terraform/                         # Infrastructure as Code
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
└── docker-compose.yml                 # Local development environment
``` 