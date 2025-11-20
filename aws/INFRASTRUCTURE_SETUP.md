# AWS ECS GPU Infrastructure Setup Guide

Complete guide for deploying the Photo Validator API on AWS ECS with GPU-enabled EC2 instances.

## 📋 Prerequisites

- AWS Account with appropriate permissions
- AWS CLI configured (`aws configure`)
- Docker installed locally
- An EC2 Key Pair for SSH access

## 💰 Cost Estimation

**Estimated Monthly Cost: ~$450-600**
- g4dn.xlarge instance: ~$380/month (24/7)
- Application Load Balancer: ~$20/month
- Data transfer & storage: ~$20-50/month
- NAT Gateway: ~$30/month

**Cost Optimization:**
- Use Spot Instances for 70% savings
- Scale down during low traffic periods
- Use smaller instance (g4dn.medium) for testing

---

## 🚀 Step-by-Step Setup

### Phase 1: Prepare Your Container

#### 1.1 Build and Test Locally
```bash
# Build GPU-enabled Docker image
docker build -f Dockerfile.gpu -t photo-validator:gpu .

# Test locally (requires NVIDIA Docker)
docker run --gpus all -p 8000:8000 photo-validator:gpu

# Verify API works
curl http://localhost:8000/api/v1/health
```

---

### Phase 2: AWS Infrastructure Setup

#### 2.1 Create IAM Roles

**A. ECS Task Execution Role**
1. Go to IAM Console → Roles → Create Role
2. Select "Elastic Container Service Task"
3. Attach policy: `AmazonECSTaskExecutionRolePolicy`
4. Name: `ecsTaskExecutionRole`
5. Copy ARN for later

**B. ECS Task Role**
1. Create another role for "Elastic Container Service Task"
2. Attach policies (if needed):
   - `AmazonS3ReadOnlyAccess` (if using S3)
   - Custom policies for other AWS services
3. Name: `ecsTaskRole`
4. Copy ARN

#### 2.2 Create VPC and Networking

**Option A: Use Default VPC (Quick Start)**
- Your default VPC already has internet gateway
- Note your VPC ID and subnet IDs

**Option B: Create Custom VPC (Recommended for Production)**

1. **Create VPC**
   - VPC Console → Create VPC
   - Name: `photo-validator-vpc`
   - IPv4 CIDR: `10.0.0.0/16`
   - Enable DNS hostnames

2. **Create Subnets** (Create 2 in different AZs)
   - Public Subnet 1: `10.0.1.0/24` (us-east-1a)
   - Public Subnet 2: `10.0.2.0/24` (us-east-1b)
   - Private Subnet 1: `10.0.10.0/24` (us-east-1a)
   - Private Subnet 2: `10.0.20.0/24` (us-east-1b)

3. **Create Internet Gateway**
   - Name: `photo-validator-igw`
   - Attach to VPC

4. **Create NAT Gateway** (for private subnets)
   - Place in Public Subnet 1
   - Allocate Elastic IP

5. **Configure Route Tables**
   - Public route table: `0.0.0.0/0` → Internet Gateway
   - Private route table: `0.0.0.0/0` → NAT Gateway

#### 2.3 Create Security Groups

**A. ALB Security Group**
```bash
aws ec2 create-security-group \
  --group-name photo-validator-alb-sg \
  --description "Security group for Photo Validator ALB" \
  --vpc-id vpc-xxxxx

# Allow HTTP/HTTPS from internet
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol tcp --port 443 --cidr 0.0.0.0/0
```

**B. ECS Instance Security Group**
```bash
aws ec2 create-security-group \
  --group-name photo-validator-ecs-sg \
  --description "Security group for ECS instances" \
  --vpc-id vpc-xxxxx

# Allow traffic from ALB
aws ec2 authorize-security-group-ingress \
  --group-id sg-yyyyy \
  --protocol tcp --port 8000 \
  --source-group sg-xxxxx

# Allow SSH (optional, for debugging)
aws ec2 authorize-security-group-ingress \
  --group-id sg-yyyyy \
  --protocol tcp --port 22 --cidr YOUR_IP/32
```

#### 2.4 Create Application Load Balancer

1. **Create Target Group**
   - EC2 Console → Target Groups → Create
   - Type: IP addresses (for awsvpc networking)
   - Protocol: HTTP, Port: 8000
   - VPC: Select your VPC
   - Health check path: `/api/v1/health`
   - Health check interval: 30s
   - Healthy threshold: 2
   - Unhealthy threshold: 3
   - Name: `photo-validator-tg`

2. **Create Load Balancer**
   - Type: Application Load Balancer
   - Name: `photo-validator-alb`
   - Scheme: Internet-facing
   - IP address type: IPv4
   - Select 2 public subnets
   - Security group: ALB security group
   - Listener: HTTP:80 → Target Group
   - Copy ALB DNS name for testing

#### 2.5 Create ECS Cluster

```bash
aws ecs create-cluster \
  --cluster-name photo-validator-gpu-cluster \
  --region us-east-1
```

---

### Phase 3: Launch GPU-Enabled EC2 Instances

#### 3.1 Find ECS-Optimized GPU AMI

```bash
# Get latest ECS GPU-optimized AMI ID
aws ssm get-parameters \
  --names /aws/service/ecs/optimized-ami/amazon-linux-2/gpu/recommended \
  --region us-east-1 \
  --query 'Parameters[0].Value' | jq -r . | jq -r .image_id
```

#### 3.2 Create Launch Template

1. **EC2 Console → Launch Templates → Create**
2. Configuration:
   - Name: `photo-validator-gpu-lt`
   - AMI: (Use AMI ID from above)
   - Instance type: `g4dn.xlarge`
   - Key pair: Select your key
   - Network: VPC, Public subnet
   - Security group: ECS instance SG
   - IAM instance profile: `ecsInstanceRole` (create if needed)

3. **User Data** (Add to Advanced Details):
```bash
#!/bin/bash
echo ECS_CLUSTER=photo-validator-gpu-cluster >> /etc/ecs/ecs.config
echo ECS_ENABLE_GPU_SUPPORT=true >> /etc/ecs/ecs.config
```

4. **Advanced Details → IAM Instance Profile**
   - Attach policy: `AmazonEC2ContainerServiceforEC2Role`

#### 3.3 Create Auto Scaling Group

1. **EC2 Console → Auto Scaling Groups → Create**
2. Configuration:
   - Name: `photo-validator-asg`
   - Launch template: Select created template
   - VPC: Your VPC
   - Subnets: Select 2 public subnets
   - Load balancing: Attach to existing ALB target group
   - Health check type: ELB
   - Health check grace period: 300 seconds
   - Group size:
     - Desired: 1
     - Minimum: 1
     - Maximum: 3
   - Scaling policies: Target tracking
     - Metric: Average CPU utilization
     - Target: 70%

---

### Phase 4: Deploy Application

#### 4.1 Update Task Definition

Edit `aws/ecs-task-definition.json`:
```json
{
  "executionRoleArn": "arn:aws:iam::123456789012:role/ecsTaskExecutionRole",
  "taskRoleArn": "arn:aws:iam::123456789012:role/ecsTaskRole",
  "image": "123456789012.dkr.ecr.us-east-1.amazonaws.com/photo-validator:latest"
}
```

#### 4.2 Build and Push to ECR

```bash
# Make scripts executable
chmod +x aws/deploy.sh aws/setup-infrastructure.sh

# Deploy (replace with your account ID)
./aws/deploy.sh us-east-1 123456789012
```

#### 4.3 Create ECS Service

```bash
aws ecs create-service \
  --cluster photo-validator-gpu-cluster \
  --service-name photo-validator-service \
  --task-definition photo-validator-gpu:1 \
  --desired-count 1 \
  --launch-type EC2 \
  --load-balancers targetGroupArn=arn:aws:elasticloadbalancing:...,containerName=photo-validator,containerPort=8000 \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx,subnet-yyy],securityGroups=[sg-zzz],assignPublicIp=ENABLED}" \
  --region us-east-1
```

---

### Phase 5: Verify Deployment

#### 5.1 Check Service Status
```bash
aws ecs describe-services \
  --cluster photo-validator-gpu-cluster \
  --services photo-validator-service \
  --region us-east-1
```

#### 5.2 Test API
```bash
# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names photo-validator-alb \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

# Test health endpoint
curl http://$ALB_DNS/api/v1/health

# Test with sample image
curl -X POST http://$ALB_DNS/api/v1/validate/photo \
  -H "Content-Type: application/json" \
  -d @test_image.json
```

#### 5.3 Check Logs
```bash
aws logs tail /ecs/photo-validator-gpu --follow --region us-east-1
```

---

## 🔧 Troubleshooting

### Issue: Container not starting
- Check CloudWatch logs: `/ecs/photo-validator-gpu`
- Verify GPU support: SSH into instance, run `nvidia-smi`
- Check ECS agent config: `cat /etc/ecs/ecs.config`

### Issue: No GPU detected
- Ensure AMI is GPU-optimized: Check AMI ID
- Verify instance type: Must be g4dn/g5/p3 family
- Check user data executed: `cat /var/log/cloud-init-output.log`

### Issue: Service not registering with ALB
- Check security group allows ALB → ECS traffic
- Verify health check path returns 200
- Ensure task network mode is `awsvpc`

### Issue: High costs
- Use Spot Instances (70% savings)
- Scale to zero during non-business hours
- Use g4dn.medium for testing

---

## 📊 Monitoring

### CloudWatch Metrics
- ECS Service CPU/Memory utilization
- ALB request count and latency
- Target health status

### Set Up Alarms
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name photo-validator-high-cpu \
  --metric-name CPUUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold
```

---

## 🔄 Updates and Rollbacks

### Deploy New Version
```bash
./aws/deploy.sh us-east-1 123456789012
```

### Rollback
```bash
aws ecs update-service \
  --cluster photo-validator-gpu-cluster \
  --service photo-validator-service \
  --task-definition photo-validator-gpu:PREVIOUS_REVISION
```

---

## 🧹 Cleanup

To avoid charges, delete resources in this order:
1. Delete ECS Service
2. Delete Auto Scaling Group
3. Terminate EC2 instances
4. Delete Load Balancer
5. Delete Target Group
6. Delete ECS Cluster
7. Delete NAT Gateway & Elastic IPs
8. Delete VPC

```bash
# Quick cleanup script
aws ecs delete-service --cluster photo-validator-gpu-cluster --service photo-validator-service --force
aws ecs delete-cluster --cluster photo-validator-gpu-cluster
# ... continue with other resources
```

---

## 📚 Additional Resources

- [ECS GPU Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-gpu.html)
- [g4dn Instance Specs](https://aws.amazon.com/ec2/instance-types/g4/)
- [ECS Task Definition Parameters](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html)
