# CI/CD Pipeline for Microservices with Terraform and Docker

This directory contains a complete CI/CD pipeline setup using GitHub Actions. The pipeline manages infrastructure on AWS with Terraform and deploys a containerized microservices application using Docker Compose.

The setup includes:
- **Two microservices:** a `frontend-app` and a `backend-service` that communicate with each other.
- **Infrastructure as Code:** A Terraform setup to provision an EC2 instance pre-configured with Docker and Docker Compose, and AWS Elastic Container Registry (ECR) repositories for your Docker images.
- **Automated Workflows:** Two GitHub Actions workflows for infrastructure and application deployment.
- **Intelligent Rebuilds:** The deployment workflow automatically detects which services have changed and only rebuilds the necessary Docker images, saving time and resources.

---

## Workflows

1.  **`infra.yml` (Infrastructure Management):** Provisions and manages the AWS EC2 instance and ECR repositories.
2.  **`deploy.yml` (Application Deployment):** Builds Docker images for changed services, pushes them to AWS ECR, and deploys them to the EC2 instance using Docker Compose.

---

## How to Use

### 1. Prerequisites: Create Required Secrets

Before running the workflows, you must create the following secrets in your GitHub repository's settings (`Settings > Secrets and variables > Actions`):

#### Secrets:

*   `AWS_ACCESS_KEY_ID`: Your AWS access key ID. This user needs permissions to manage EC2, S3 (for Terraform state), and ECR.
*   `AWS_SECRET_ACCESS_KEY`: Your AWS secret access key.
*   `S3_BUCKET_NAME`: The name of an S3 bucket you own. Terraform will use it to store its state file. **You must create this S3 bucket manually in your AWS account beforehand.**
*   `SSH_PRIVATE_KEY`: The private SSH key that corresponds to a public key in your EC2 Key Pairs. The default key name is `deployer-key` (see `terraform/variables.tf`).

### 2. No Manual Docker Compose File Update Needed

The `bonus/5-cicd-pipeline/docker-compose.yml` file uses generic image names (e.g., `frontend-app:latest`). The deployment workflow will automatically prepend the ECR registry URL during the deployment process.

---

### 3. Run the Infrastructure Workflow

This workflow provisions the EC2 server and ECR repositories.

1.  Navigate to the **Actions** tab of your GitHub repository.
2.  Select the **"Infrastructure Management (Terraform)"** workflow.
3.  Click **"Run workflow"**, select `apply`, and run it.

This creates the EC2 instance and ECR repositories, and saves the EC2 instance's public IP address as an artifact for the deployment workflow.

---

### 4. Run the Deployment Workflow

The deployment workflow runs automatically when you push a change to the `bonus/5-cicd-pipeline/` directory on the `main` branch.

After the infrastructure is ready, push a change to one of the microservices (e.g., edit a file in `frontend-app`) to trigger the workflow.

The workflow will:
1.  Detect which service directory (`frontend-app` or `backend-service`) changed.
2.  Build a new Docker image for that service.
3.  Push the new image to your AWS ECR repository.
4.  SSH into the EC2 instance.
5.  Log in to ECR on the EC2 instance.
6.  Run `docker-compose pull` and `docker-compose up -d` to pull the new image and restart the services.

After the workflow completes, visit the public IP address of your EC2 instance. You will see the frontend, which can fetch messages from the backend, demonstrating a complete, containerized microservices deployment.
