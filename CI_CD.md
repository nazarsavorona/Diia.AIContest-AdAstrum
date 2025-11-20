# CI/CD Setup Guide

This repository includes a GitHub Actions workflow (`.github/workflows/deploy.yml`) that automatically builds and deploys the application to AWS whenever changes are pushed to the `main` branch.

## Prerequisites

The CI/CD pipeline uses **OpenID Connect (OIDC)** for secure authentication with AWS. This means you **do not** need to manage long-lived AWS Access Keys in GitHub Secrets.

The necessary OIDC Provider and IAM Role have been provisioned via the `aws/github-oidc.yaml` CloudFormation stack.

### Configuration (Optional)

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
