# CloudFormation Deployment Guide

Automated infrastructure deployment using AWS CloudFormation.

## Quick Deploy

```bash
# 1. Set your parameters
export AWS_REGION="us-east-1"
export STACK_NAME="photo-validator-gpu"
export KEY_NAME="your-ec2-key-pair"

# 2. Deploy the stack
aws cloudformation create-stack \
  --stack-name $STACK_NAME \
  --template-body file://cloudformation-template.yaml \
  --parameters \
    ParameterKey=KeyName,ParameterValue=$KEY_NAME \
    ParameterKey=InstanceType,ParameterValue=g4dn.xlarge \
    ParameterKey=DesiredCapacity,ParameterValue=1 \
    ParameterKey=MaxSize,ParameterValue=3 \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $AWS_REGION

# 3. Wait for stack creation (takes ~10-15 minutes)
aws cloudformation wait stack-create-complete \
  --stack-name $STACK_NAME \
  --region $AWS_REGION

# 4. Get outputs
aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query 'Stacks[0].Outputs' \
  --region $AWS_REGION
```

## Deploy Application

After infrastructure is ready:

```bash
# Get ECR repository URI from CloudFormation outputs
ECR_URI=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryURI`].OutputValue' \
  --output text \
  --region $AWS_REGION)

# Build and push image
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_URI

docker build -f Dockerfile.gpu -t photo-validator:latest .
docker tag photo-validator:latest $ECR_URI:latest
docker push $ECR_URI:latest

# Force new deployment
CLUSTER_NAME=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query 'Stacks[0].Outputs[?OutputKey==`ECSClusterName`].OutputValue' \
  --output text)

SERVICE_NAME=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query 'Stacks[0].Outputs[?OutputKey==`ServiceName`].OutputValue' \
  --output text)

aws ecs update-service \
  --cluster $CLUSTER_NAME \
  --service $SERVICE_NAME \
  --force-new-deployment \
  --region $AWS_REGION
```

## Test Deployment

```bash
# Get ALB DNS name
ALB_DNS=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' \
  --output text)

# Test health endpoint
curl http://$ALB_DNS/api/v1/health

# Test validation
curl -X POST http://$ALB_DNS/api/v1/validate/photo \
  -H "Content-Type: application/json" \
  -d @test_image.json
```

## Update Stack

```bash
aws cloudformation update-stack \
  --stack-name $STACK_NAME \
  --template-body file://cloudformation-template.yaml \
  --parameters \
    ParameterKey=KeyName,UsePreviousValue=true \
    ParameterKey=InstanceType,ParameterValue=g4dn.2xlarge \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $AWS_REGION
```

## Delete Stack

```bash
aws cloudformation delete-stack \
  --stack-name $STACK_NAME \
  --region $AWS_REGION

# Wait for deletion
aws cloudformation wait stack-delete-complete \
  --stack-name $STACK_NAME \
  --region $AWS_REGION
```

## What Gets Created

- VPC with 2 public subnets across 2 AZs
- Internet Gateway and route tables
- Security groups for ALB and ECS
- Application Load Balancer with target group
- ECS Cluster (EC2 launch type)
- Auto Scaling Group with g4dn.xlarge instances
- ECR repository for Docker images
- IAM roles and instance profile
- CloudWatch log group
- ECS Task Definition with GPU support
- ECS Service with ALB integration

## Estimated Cost

- **g4dn.xlarge**: ~$380/month (24/7 operation)
- **ALB**: ~$20/month
- **Data transfer**: ~$20-50/month
- **NAT Gateway**: Not included (using public subnets)
- **Total**: ~$420-450/month

Reduce costs by:
- Using Spot Instances (add to launch template)
- Scaling to 0 during off-hours
- Using smaller instance for testing
