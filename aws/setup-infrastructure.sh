#!/bin/bash
# Setup AWS infrastructure for ECS with GPU support
# Usage: ./setup-infrastructure.sh <aws-region> <aws-account-id>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

AWS_REGION=${1:-us-east-1}
AWS_ACCOUNT_ID=${2}

if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo -e "${RED}Error: AWS Account ID is required${NC}"
    echo "Usage: ./setup-infrastructure.sh <aws-region> <aws-account-id>"
    exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   AWS ECS GPU Infrastructure Setup - Photo Validator      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Region: $AWS_REGION"
echo "Account: $AWS_ACCOUNT_ID"
echo ""

# Configuration
CLUSTER_NAME="photo-validator-gpu-cluster"
SERVICE_NAME="photo-validator-service"
VPC_NAME="photo-validator-vpc"
INSTANCE_TYPE="g4dn.xlarge"  # 1 GPU, 4 vCPUs, 16 GB RAM - ~$0.526/hour
KEY_NAME="photo-validator-key"

echo -e "${YELLOW}This script will create the following AWS resources:${NC}"
echo "  • VPC with public/private subnets"
echo "  • Internet Gateway and NAT Gateway"
echo "  • Security Groups (ALB, ECS)"
echo "  • Application Load Balancer"
echo "  • ECS Cluster with GPU-enabled EC2 instances"
echo "  • IAM Roles and Policies"
echo "  • Auto Scaling Group"
echo ""
echo -e "${RED}Estimated cost: ~$0.60/hour per instance + ALB costs${NC}"
echo ""
read -p "Do you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Deployment cancelled."
    exit 0
fi

echo -e "\n${GREEN}Starting infrastructure setup...${NC}"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    exit 1
fi

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}MANUAL STEPS REQUIRED:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "This setup requires several manual steps in the AWS Console."
echo "Please follow the detailed guide in: aws/INFRASTRUCTURE_SETUP.md"
echo ""
echo -e "${YELLOW}Quick Summary:${NC}"
echo "1. Create VPC with 2 public and 2 private subnets"
echo "2. Create Application Load Balancer"
echo "3. Create ECS Cluster with EC2 launch type"
echo "4. Launch GPU-enabled EC2 instances (g4dn.xlarge)"
echo "5. Configure Auto Scaling"
echo "6. Deploy service using: ./deploy.sh $AWS_REGION $AWS_ACCOUNT_ID"
echo ""
echo -e "${GREEN}For automated setup, use CloudFormation:${NC}"
echo "  aws cloudformation create-stack \\"
echo "    --stack-name photo-validator-gpu \\"
echo "    --template-body file://cloudformation-template.yaml \\"
echo "    --parameters ParameterKey=KeyName,ParameterValue=$KEY_NAME \\"
echo "    --capabilities CAPABILITY_NAMED_IAM \\"
echo "    --region $AWS_REGION"
echo ""
