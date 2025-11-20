#!/bin/bash
# Deploy script for AWS ECS with GPU support
# Usage: ./deploy.sh <aws-region> <aws-account-id>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION=${1:-us-east-1}
AWS_ACCOUNT_ID=${2}
ECR_REPOSITORY="photo-validator"
IMAGE_TAG="latest"
CLUSTER_NAME="photo-validator-gpu-cluster"
SERVICE_NAME="photo-validator-service"
TASK_FAMILY="photo-validator-gpu"

if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo -e "${RED}Error: AWS Account ID is required${NC}"
    echo "Usage: ./deploy.sh <aws-region> <aws-account-id>"
    exit 1
fi

ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"

echo -e "${GREEN}Starting deployment to AWS ECS with GPU support${NC}"
echo "Region: $AWS_REGION"
echo "Account: $AWS_ACCOUNT_ID"
echo "ECR Repository: $ECR_URI"

# Step 1: Create ECR repository if it doesn't exist
echo -e "\n${YELLOW}Step 1: Creating ECR repository...${NC}"
aws ecr describe-repositories --repository-names $ECR_REPOSITORY --region $AWS_REGION 2>/dev/null || \
    aws ecr create-repository --repository-name $ECR_REPOSITORY --region $AWS_REGION

# Step 2: Login to ECR
echo -e "\n${YELLOW}Step 2: Logging in to ECR...${NC}"
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI

# Step 3: Build Docker image with GPU support
echo -e "\n${YELLOW}Step 3: Building Docker image with GPU support...${NC}"
docker build -f Dockerfile.gpu -t $ECR_REPOSITORY:$IMAGE_TAG .

# Step 4: Tag image for ECR
echo -e "\n${YELLOW}Step 4: Tagging image...${NC}"
docker tag $ECR_REPOSITORY:$IMAGE_TAG $ECR_URI:$IMAGE_TAG

# Step 5: Push image to ECR
echo -e "\n${YELLOW}Step 5: Pushing image to ECR...${NC}"
docker push $ECR_URI:$IMAGE_TAG

# Step 6: Update task definition with correct values
echo -e "\n${YELLOW}Step 6: Updating task definition...${NC}"
TASK_DEF_JSON=$(cat aws/ecs-task-definition.json | \
    sed "s/YOUR_ACCOUNT_ID/$AWS_ACCOUNT_ID/g" | \
    sed "s/YOUR_REGION/$AWS_REGION/g")

# Create CloudWatch log group if it doesn't exist
aws logs create-log-group --log-group-name /ecs/photo-validator-gpu --region $AWS_REGION 2>/dev/null || true

# Register new task definition
echo -e "\n${YELLOW}Step 7: Registering task definition...${NC}"
TASK_REVISION=$(echo "$TASK_DEF_JSON" | \
    aws ecs register-task-definition --region $AWS_REGION --cli-input-json file:///dev/stdin | \
    jq -r '.taskDefinition.revision')

echo "Registered task definition: $TASK_FAMILY:$TASK_REVISION"

# Step 8: Update ECS service (if it exists)
echo -e "\n${YELLOW}Step 8: Updating ECS service...${NC}"
SERVICE_EXISTS=$(aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION 2>/dev/null | jq -r '.services[0].status // "MISSING"')

if [ "$SERVICE_EXISTS" != "MISSING" ] && [ "$SERVICE_EXISTS" != "INACTIVE" ]; then
    aws ecs update-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --task-definition $TASK_FAMILY:$TASK_REVISION \
        --force-new-deployment \
        --region $AWS_REGION
    
    echo -e "${GREEN}Service updated successfully!${NC}"
    echo "Waiting for service to stabilize..."
    aws ecs wait services-stable --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION
else
    echo -e "${YELLOW}Service does not exist. You need to create it first using the infrastructure setup.${NC}"
    echo "Run: ./setup-infrastructure.sh"
fi

echo -e "\n${GREEN}Deployment completed!${NC}"
echo "Task Definition: $TASK_FAMILY:$TASK_REVISION"
echo "ECR Image: $ECR_URI:$IMAGE_TAG"
