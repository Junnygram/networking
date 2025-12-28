# Bonus 5: CI/CD Pipeline Sample

This directory contains a sample file for a **CI/CD (Continuous Integration / Continuous Deployment)** pipeline using **GitHub Actions**.

A CI/CD pipeline automates the process of testing your code, building artifacts (like Docker images), and deploying them to your servers.

## Components

1.  **`sample-github-actions.yml`**: This is a workflow file that can be used with GitHub Actions. It defines a pipeline that triggers on every push to the `main` branch.

## How to Use

To use this file in a real project on GitHub:

1.  Create a directory path `.github/workflows/` in the root of your repository.
2.  Copy the contents of `sample-github-actions.yml` into a new file named `main.yml` inside that directory (`.github/workflows/main.yml`).
3.  Commit and push the file to your GitHub repository.
4.  Go to the "Actions" tab in your GitHub repository to see the pipeline run.

**Note:** This sample pipeline is for demonstration. For it to work, you would need to:
- Have actual tests that can be run with a command like `npm test` or `pytest`.
- Configure repository secrets (like `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`) in your GitHub repository settings to allow pushing images to a registry.
- Have a deployment environment (like a server with SSH access) configured with secrets (`SSH_HOST`, `SSH_USERNAME`, `SSH_KEY`) to receive the new image.

## The Pipeline Explained

The provided `.yml` file defines the following stages:

1.  **Trigger:** The pipeline starts automatically on a `push` to the `main` branch.

2.  **Jobs:** The pipeline has one job called `build-and-deploy`.

3.  **Steps within the job:**
    - **`Checkout code`**: Pulls your repository's code into the runner environment.
    - **`Run tests`**: Executes a placeholder command for your tests. If this step fails, the pipeline stops.
    - **`Login to Docker Hub`**: Securely logs into a container registry using credentials stored as GitHub secrets.
    - **`Build and push Docker image`**: Builds a Docker image from your project's `Dockerfile` and pushes it to the registry. The image is tagged with the unique Git commit SHA for versioning.
    - **`Deploy to server`**: A placeholder step that shows how you could SSH into a server to pull the new image and restart a service.

## Key Concepts Demonstrated

- **Infrastructure as Code:** The entire CI/CD process is defined in a simple, version-controlled YAML file.
- **Automation:** The pipeline runs automatically, reducing manual effort and errors.
- **Secrets Management:** Using encrypted secrets for sensitive information like passwords and API keys.
- **Build, Test, Deploy:** The three fundamental stages of a modern software delivery lifecycle.
