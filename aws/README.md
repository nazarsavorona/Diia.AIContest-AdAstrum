# AWS Deployment - Photo Validator API

Complete AWS deployment resources for GPU-enabled ECS infrastructure.

## 📁 Files Overview

- **`Dockerfile.gpu`**: NVIDIA CUDA-based Docker image for GPU support
- **`ecs-task-definition.json`**: ECS task definition with GPU resource requirements
- **`deploy.sh`**: Automated deployment script (build, push, update)
- **`setup-infrastructure.sh`**: Infrastructure setup helper
- **`cloudformation-template.yaml`**: Complete infrastructure as code (IaC)
- **`INFRASTRUCTURE_SETUP.md`**: Detailed manual setup guide
- **`CLOUDFORMATION.md`**: CloudFormation deployment guide
- **IAM Task Role Enhancements**: Conditional S3 & Secrets Manager access via parameters

## 🚀 Quick Start (Recommended)

### Option 1: CloudFormation (Automated - 15 minutes)

```bash
# Prerequisites: AWS CLI configured, EC2 key pair created

# Deploy infrastructure
aws cloudformation create-stack \
  --stack-name photo-validator-gpu \
  --template-body file://cloudformation-template.yaml \
  --parameters ParameterKey=KeyName,ParameterValue=your-key-name \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# Wait for completion
aws cloudformation wait stack-create-complete \
  --stack-name photo-validator-gpu \
  --region us-east-1

# Deploy application
./deploy.sh us-east-1 YOUR_ACCOUNT_ID
```

### 🔒 HTTPS Support

To enable HTTPS, you need an ACM Certificate ARN.

```bash
# Deploy with HTTPS
export CERT_ARN="arn:aws:acm:region:account:certificate/id"
./deploy.sh
```

**See `CLOUDFORMATION.md` for detailed instructions.**

### Option 2: Manual Setup (Step-by-step - 1 hour)

Follow the comprehensive guide in `INFRASTRUCTURE_SETUP.md` for:
- VPC and networking setup
- Security groups configuration
- Application Load Balancer creation
- ECS cluster with GPU instances
- Auto Scaling configuration

## 📋 Deployment Steps

### 1. Prepare Your Environment

```bash
# Install AWS CLI
# Windows (PowerShell as Administrator)
msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi

# Configure credentials
aws configure
# AWS Access Key ID: YOUR_ACCESS_KEY
# AWS Secret Access Key: YOUR_SECRET_KEY
# Default region: us-east-1
# Default output format: json

# Verify Docker is running
docker --version
```

### 2. Create EC2 Key Pair (if needed)

```bash
aws ec2 create-key-pair \
  --key-name photo-validator-key \
  --query 'KeyMaterial' \
  --output text > photo-validator-key.pem

# Windows: Save as .pem file
```

### 3. Deploy Infrastructure

**Choose your path:**

**A. CloudFormation (Automated):**
```bash
cd aws
aws cloudformation create-stack \
  --stack-name photo-validator-gpu \
  --template-body file://cloudformation-template.yaml \
  --parameters ParameterKey=KeyName,ParameterValue=photo-validator-key \
  --capabilities CAPABILITY_NAMED_IAM
```

**B. Manual Setup:**
Follow steps in `INFRASTRUCTURE_SETUP.md`

### 4. Deploy Application

```bash
# Make scripts executable (Git Bash on Windows)
chmod +x deploy.sh setup-infrastructure.sh

# Build and deploy
./deploy.sh us-east-1 123456789012  # Replace with your AWS account ID

# Or manually:
# 1. Build: docker build -f Dockerfile.gpu -t photo-validator .
# 2. Tag: docker tag photo-validator:latest ACCOUNT.dkr.ecr.REGION.amazonaws.com/photo-validator:latest
# 3. Push: docker push ACCOUNT.dkr.ecr.REGION.amazonaws.com/photo-validator:latest
# 4. Update ECS service to force new deployment
```

### 5. Verify Deployment

```bash
# Get ALB DNS name (from CloudFormation outputs or console)
ALB_DNS="your-alb-xxxxx.us-east-1.elb.amazonaws.com"

# Test health endpoint
curl http://$ALB_DNS/api/v1/health

# Test validation with sample image
curl -X POST http://$ALB_DNS/api/v1/validate/photo \
  -H "Content-Type: application/json" \
  -d '{
    "image": "BASE64_ENCODED_IMAGE_DATA",
    "mode": "full"
  }'
```

## 🏗️ Architecture Overview

```
Internet
    ↓
Application Load Balancer (Port 80/443)
    ↓
Target Group (Port 8000)
    ↓
ECS Service (awsvpc network mode)
    ↓
ECS Tasks on GPU EC2 Instances (g4dn.xlarge)
    ↓
Docker Container (NVIDIA CUDA + PyTorch)
```

**Key Components:**
- **VPC**: Isolated network with 2 public subnets across 2 AZs
- **ALB**: Distributes traffic and performs health checks
- **ECS Cluster**: Manages container orchestration
- **Auto Scaling Group**: Scales instances based on CPU (target: 70%)
- **ECR**: Stores Docker images
- **CloudWatch**: Logs and monitoring

## 💰 Cost Breakdown

| Resource | Cost/Month | Notes |
|----------|-----------|-------|
| g4dn.xlarge (1 instance) | ~$380 | 1 GPU, 4 vCPU, 16 GB RAM |
| Application Load Balancer | ~$20 | Includes hourly + LCU charges |
| Data Transfer | ~$20-50 | Varies by traffic |
| CloudWatch Logs | ~$5 | 7-day retention |
| **Total** | **~$425-455** | For 24/7 operation |

**Cost Optimization:**
- Use Spot Instances: Save 70% (~$115/month for instances)
- Scale to 0 during off-hours: Save proportionally
- Use g4dn.medium for testing: ~$0.23/hr vs $0.53/hr

## 🔧 Configuration

### Environment Variables

Add to `ecs-task-definition.json`:
```json
"environment": [
  {"name": "LOG_LEVEL", "value": "INFO"},
  {"name": "MAX_WORKERS", "value": "1"},
  {"name": "CUDA_VISIBLE_DEVICES", "value": "0"}
]

### IAM Task Role Usage (Recommended)

The stack now supports granting least-privilege access to AWS services without embedding static credentials:

Parameters:
- `S3BucketName`: When provided (non-empty), an inline policy is attached allowing `s3:ListBucket` and `s3:GetObject` on that bucket.
- `SecretsManagerSecretArn`: When provided, grants `secretsmanager:GetSecretValue` on the secret for secure retrieval of JWT or other sensitive config.

Example stack creation with IAM task role permissions:
```bash
aws cloudformation create-stack \
  --stack-name photo-validator-gpu \
  --template-body file://cloudformation-template.yaml \
  --parameters \
    ParameterKey=KeyName,ParameterValue=photo-validator-key \
    ParameterKey=S3BucketName,ParameterValue=your-photo-bucket \
    ParameterKey=SecretsManagerSecretArn,ParameterValue=arn:aws:secretsmanager:eu-central-1:123456789012:secret:jwtSecret-AbCdEf \
  --capabilities CAPABILITY_NAMED_IAM \
  --region eu-central-1
```

After deployment you can verify the role-based credentials inside the container:
```bash
curl http://<ALB_DNS>/api/v1/aws/identity
```
Response example:
```json
{"account":"123456789012","arn":"arn:aws:sts::123456789012:assumed-role/photo-validator-gpu-task/abcdef","user_id":"ABCDEF1234567890:photo-validator-gpu-task"}
```

Remove static keys from `.env` (leave them blank) once task role is active.

To fetch a secret at runtime (example):
```python
import boto3, os
secret_arn = os.getenv("SECRETS_MANAGER_SECRET_ARN")
if secret_arn:
    val = boto3.client("secretsmanager").get_secret_value(SecretId=secret_arn)
    jwt_secret = val.get("SecretString")
```
```

### Scaling Configuration

Modify Auto Scaling policy:
```bash
# Update desired capacity
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name photo-validator-asg \
  --desired-capacity 2

# Change target tracking threshold
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name photo-validator-asg \
  --policy-name cpu-target-tracking \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration file://scaling-config.json
```

### Update Application

```bash
# Deploy new version
./deploy.sh us-east-1 YOUR_ACCOUNT_ID

# Rollback to previous version
aws ecs update-service \
  --cluster photo-validator-gpu-cluster \
  --service photo-validator-service \
  --task-definition photo-validator-gpu:PREVIOUS_REVISION
```

## 📊 Monitoring

### CloudWatch Dashboards

```bash
# View logs
aws logs tail /ecs/photo-validator-gpu --follow

# Check service metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=photo-validator-service \
  --start-time 2025-11-19T00:00:00Z \
  --end-time 2025-11-19T23:59:59Z \
  --period 3600 \
  --statistics Average
```

### Health Checks

- **ECS Task Health**: Checks `/api/v1/health` every 30s
- **ALB Target Health**: HTTP 200 from health endpoint
- **Auto Scaling Health**: ELB health check type

## 🔐 Security Best Practices

1. **Restrict SSH Access**: Update security group to your IP only
2. **Use HTTPS**: Add SSL certificate to ALB (AWS Certificate Manager)
3. **Secrets Management**: Use AWS Secrets Manager for sensitive data
4. **IAM Roles**: Follow least-privilege principle
5. **VPC**: Use private subnets for ECS tasks (add NAT Gateway)
6. **CloudTrail**: Enable for audit logging

## 🧹 Cleanup

### Delete CloudFormation Stack
```bash
aws cloudformation delete-stack \
  --stack-name photo-validator-gpu \
  --region us-east-1
```

### Manual Cleanup
1. Delete ECS Service
2. Delete ECS Cluster
3. Deregister Task Definitions
4. Delete Auto Scaling Group
5. Terminate EC2 Instances
6. Delete Load Balancer & Target Group
7. Delete ECR Images
8. Delete VPC & Associated Resources

## 📚 Additional Resources

- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [GPU Instance Types](https://aws.amazon.com/ec2/instance-types/g4/)
- [ECS GPU Support](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-gpu.html)
- [ALB Documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)

## 🆘 Troubleshooting

See `INFRASTRUCTURE_SETUP.md` for detailed troubleshooting steps.

Common issues:
- **Container not starting**: Check CloudWatch logs
- **No GPU detected**: Verify AMI is GPU-optimized
- **Service not healthy**: Check security groups and health check path
- **High costs**: Enable Spot Instances or scale down

## 📞 Support

For issues specific to:
- **AWS Infrastructure**: See `INFRASTRUCTURE_SETUP.md`
- **CloudFormation**: See `CLOUDFORMATION.md`
- **Application**: Check main project README.md
