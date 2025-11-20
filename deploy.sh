#!/bin/bash
set -e

REGION=${1:-eu-central-1}
STACK_NAME="AdAstrumStack"
REPO_NAME="photo-validator"
KEY_NAME="adastrum"

echo "Deploying to region: $REGION"

# Check credentials
aws sts get-caller-identity > /dev/null || { echo "AWS credentials not found. Please run 'aws configure'."; exit 1; }

# Get Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

# 1. Key Pair
echo "Checking Key Pair..."
aws ec2 describe-key-pairs --key-names $KEY_NAME --region $REGION > /dev/null 2>&1 || {
    echo "Creating Key Pair '$KEY_NAME'..."
    aws ec2 create-key-pair --key-name $KEY_NAME --region $REGION --query "KeyMaterial" --output text > ${KEY_NAME}-${REGION}.pem
    chmod 400 ${KEY_NAME}-${REGION}.pem
    echo "Key Pair created and saved to ${KEY_NAME}-${REGION}.pem"
}

# 2. ECR Repo
echo "Checking ECR Repository..."
aws ecr describe-repositories --repository-names $REPO_NAME --region $REGION > /dev/null 2>&1 || {
    echo "Creating ECR Repository '$REPO_NAME'..."
    aws ecr create-repository --repository-name $REPO_NAME --region $REGION
}

# 3. Docker Build & Push
echo "Logging in to ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

echo "Building Docker image..."
docker build -t $REPO_NAME -f Dockerfile.gpu .

echo "Tagging and Pushing image..."
docker tag $REPO_NAME:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest

# 3.5 Fetch AMI ID
echo "Fetching latest ECS GPU AMI..."
export MSYS_NO_PATHCONV=1
AMI_ID=$(aws ssm get-parameter --name /aws/service/ecs/optimized-ami/amazon-linux-2/gpu/recommended/image_id --region $REGION --query "Parameter.Value" --output text)
echo "Using AMI: $AMI_ID"

# Check for Certificate ARN
CERT_ARN=${CERT_ARN:-""}
if [ -n "$CERT_ARN" ]; then
    echo "Enabling HTTPS with Certificate: $CERT_ARN"
else
    echo "No Certificate ARN provided. HTTPS will be disabled."
fi

# 4. CloudFormation Deploy
echo "Deploying CloudFormation Stack..."
aws cloudformation deploy \
    --template-file aws/cloudformation-template.yaml \
    --stack-name $STACK_NAME \
    --region $REGION \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
        KeyName=$KEY_NAME \
        ECSAMI=$AMI_ID \
        CertificateArn=$CERT_ARN \
        InstanceType=g4dn.xlarge \
        DesiredCapacity=1 \
        MaxSize=3

echo "Deployment Complete!"
aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION --query "Stacks[0].Outputs" --output table
