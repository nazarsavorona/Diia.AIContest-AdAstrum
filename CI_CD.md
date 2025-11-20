# CI/CD Setup Guide

This repository includes a GitHub Actions workflow (`.github/workflows/deploy.yml`) that automatically builds and deploys the application to AWS whenever changes are pushed to the `main` branch.

## Prerequisites

Before the CI/CD pipeline can run successfully, you need to configure the following **Secrets** in your GitHub repository settings.

### 1. Go to Repository Settings
1. Navigate to your repository on GitHub.
2. Click on **Settings** > **Secrets and variables** > **Actions**.
3. Click **New repository secret**.

### 2. Add Required Secrets

Add the following secrets:

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `AWS_ACCESS_KEY_ID` | Your AWS Access Key ID | `AKIAIOSFODNN7EXAMPLE` |
| `AWS_SECRET_ACCESS_KEY` | Your AWS Secret Access Key | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |

### 3. Configuration (Optional)

The workflow uses the following default environment variables defined in `.github/workflows/deploy.yml`. You can modify them in the file if needed:

- `AWS_REGION`: `eu-central-1` (Default)
- `STACK_NAME`: `AdAstrumStack`
- `KEY_NAME`: `adastrum` (Must match the key pair created in AWS)

## Workflow Steps

When you push to `main`, the workflow performs the following:

1.  **Checkout Code**: Pulls the latest code.
2.  **Configure AWS**: Sets up credentials using the secrets provided.
3.  **Login to ECR**: Authenticates with Amazon Elastic Container Registry.
4.  **Build & Push**: Builds the Docker image using `Dockerfile.gpu` and pushes it to ECR with the commit SHA tag.
5.  **Deploy Infrastructure**: Updates the CloudFormation stack with the new image tag and ensures the infrastructure is in the desired state.
6.  **Update Service**: Forces ECS to redeploy the service with the new image.

## Troubleshooting

- **Permission Errors**: Ensure the IAM user associated with the Access Keys has permissions for `EC2`, `ECS`, `ECR`, `CloudFormation`, `IAM`, and `SSM`.
- **Stack Failures**: Check the CloudFormation console in AWS for detailed error messages if the deployment fails.
