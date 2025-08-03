# Prerequisites

> System requirements and setup for GeuseMaker deployment

## System Requirements

### Operating System Support
- **macOS**: macOS 10.14+ (Mojave and later)
- **Linux**: Ubuntu 18.04+, CentOS 7+, Amazon Linux 2
- **Windows**: Windows 10+ with WSL 2

### Shell Requirements
- **bash**: Version 3.2+ (compatible with all bash versions)
- **No specific bash version requirements** - works with any bash installation

## AWS Requirements

### AWS Account Setup
1. **AWS Account**: Active AWS account with billing enabled
2. **IAM Permissions**: Sufficient permissions for resource creation
3. **Service Quotas**: Adequate quotas for your deployment scale

### Required AWS Permissions

Create an IAM policy with these permissions:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:*",
                "vpc:*",
                "iam:CreateRole",
                "iam:CreateInstanceProfile",
                "iam:AddRoleToInstanceProfile",
                "iam:AttachRolePolicy",
                "iam:PassRole",
                "elasticloadbalancing:*",
                "cloudfront:*",
                "efs:*",
                "ssm:GetParameter",
                "ssm:PutParameter"
            ],
            "Resource": "*"
        }
    ]
}
```

### AWS CLI Configuration

1. **Install AWS CLI v2**:
   ```bash
   # macOS
   brew install awscli
   
   # Linux
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install
   
   # Windows (WSL)
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install
   ```

2. **Configure credentials**:
   ```bash
   aws configure
   ```
   
   Or use environment variables:
   ```bash
   export AWS_ACCESS_KEY_ID=your-access-key
   export AWS_SECRET_ACCESS_KEY=your-secret-key
   export AWS_DEFAULT_REGION=us-east-1
   ```

3. **Verify configuration**:
   ```bash
   aws sts get-caller-identity
   ```

## SSH Key Pair

### Create SSH Key Pair in AWS
```bash
# Create key pair
aws ec2 create-key-pair \
  --key-name geusemaker-key \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/geusemaker-key.pem

# Set permissions
chmod 400 ~/.ssh/geusemaker-key.pem
```

### Or upload existing key
```bash
aws ec2 import-key-pair \
  --key-name geusemaker-key \
  --public-key-material fileb://~/.ssh/id_rsa.pub
```

## Required Tools

### Core Tools
These tools are typically pre-installed on macOS and Linux:

```bash
# Check if tools are available
which bash    # Should show /bin/bash or similar
which jq      # JSON processor
which curl    # HTTP client
which git     # Version control
```

### Install Missing Tools

**macOS**:
```bash
# Using Homebrew
brew install jq curl git

# Or using MacPorts
port install jq curl git
```

**Ubuntu/Debian**:
```bash
sudo apt update
sudo apt install jq curl git bash
```

**CentOS/RHEL**:
```bash
sudo yum install jq curl git bash
# Or on newer versions
sudo dnf install jq curl git bash
```

**Amazon Linux**:
```bash
sudo yum install jq curl git
```

## AWS Service Quotas

### Check Current Quotas
```bash
# EC2 quotas
aws service-quotas list-service-quotas --service-code ec2

# VPC quotas  
aws service-quotas list-service-quotas --service-code vpc

# ELB quotas
aws service-quotas list-service-quotas --service-code elasticloadbalancing
```

### Required Minimum Quotas

| Service | Resource | Minimum Required |
|---------|----------|------------------|
| EC2 | Running On-Demand instances | 5 |
| EC2 | Running Spot instances | 5 |
| VPC | VPCs per region | 2 |
| VPC | Subnets per VPC | 10 |
| VPC | Security groups per VPC | 10 |
| ELB | Application Load Balancers | 2 |
| EFS | File systems | 2 |

### Request Quota Increases
If you need higher quotas:

```bash
# Request quota increase
aws service-quotas request-service-quota-increase \
  --service-code ec2 \
  --quota-code L-1216C47A \
  --desired-value 10
```

## Network Requirements

### Internet Access
- **Outbound HTTPS (443)**: For AWS API calls
- **Outbound HTTP (80)**: For package downloads
- **Outbound SSH (22)**: For Git operations

### Corporate Networks
If behind a corporate firewall:

1. **Proxy Configuration**:
   ```bash
   export HTTP_PROXY=http://proxy.company.com:8080
   export HTTPS_PROXY=http://proxy.company.com:8080
   export NO_PROXY=169.254.169.254
   ```

2. **AWS CLI Proxy**:
   ```bash
   aws configure set default.proxy_url http://proxy.company.com:8080
   ```

## GPU Requirements (Optional)

For AI workloads with GPU acceleration:

### Instance Types
- **Development**: g4dn.xlarge (1 NVIDIA T4, 16GB GPU memory)
- **Production**: g4dn.2xlarge (1 NVIDIA T4, 32GB GPU memory)
- **High Performance**: p3.2xlarge (1 NVIDIA V100, 16GB GPU memory)

### GPU Quota Check
```bash
# Check GPU instance quotas
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-DB2E81BA  # G4dn instances
```

## Storage Requirements

### Local Development
- **Disk Space**: 10GB minimum for deployment scripts and logs
- **Memory**: 4GB minimum for running deployment tools

### AWS Storage
- **EBS**: 100GB minimum for EC2 instance storage
- **EFS**: Scales automatically (pay for usage)

## Security Considerations

### IAM Best Practices
1. **Use IAM roles** instead of access keys when possible
2. **Enable MFA** on AWS accounts
3. **Use least privilege** principle for permissions
4. **Rotate credentials** regularly

### Network Security
1. **Restrict SSH access** to specific IP ranges
2. **Use VPC endpoints** for AWS service access
3. **Enable VPC Flow Logs** for network monitoring
4. **Configure security groups** restrictively

## Validation Checklist

Run these commands to verify your setup:

```bash
# 1. Check AWS CLI
aws --version
aws sts get-caller-identity

# 2. Check required tools
bash --version
jq --version
curl --version
git --version

# 3. Check AWS permissions
aws ec2 describe-regions
aws iam get-user

# 4. Check SSH key
aws ec2 describe-key-pairs --key-names geusemaker-key

# 5. Check quotas
aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A
```

## Troubleshooting

### Common Issues

1. **AWS CLI not found**:
   ```bash
   # Add to PATH
   export PATH=$PATH:/usr/local/bin
   ```

2. **Permission denied**:
   ```bash
   # Check IAM policies
   aws iam list-attached-user-policies --user-name your-username
   ```

3. **Region issues**:
   ```bash
   # Set default region
   aws configure set default.region us-east-1
   ```

4. **SSH key issues**:
   ```bash
   # Check key permissions
   ls -la ~/.ssh/geusemaker-key.pem
   # Should show -r--------
   ```

### Support

If you encounter issues:
1. Check the [Troubleshooting Guide](../guides/troubleshooting.md)
2. Review AWS CloudTrail logs for API errors
3. Verify quotas and permissions
4. Check the Unity logs: `logs/unity/core.log`

## Next Steps

Once prerequisites are met:
1. Continue to [Quick Start Guide](quick-start.md)
2. Review [Deployment Guide](../guides/deployment.md)
3. Check [Unity Documentation](../unity/)

---

**Ready to deploy?** → [Quick Start Guide](quick-start.md)