# Self-Hosted Kubernetes Cluster with Kubeadm and Terraform on AWS

This project provides a Terraform configuration to deploy a self-hosted Kubernetes cluster on AWS using `kubeadm`. The cluster consists of one master node and two worker nodes.

## Prerequisites

- [Terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli) (v1.0.0 or later)
- An [AWS account](https://aws.amazon.com/premiumsupport/knowledge-center/create-and-activate-aws-account/)

## Configuration

1.  **Clone the repository:**
    ```bash
    git clone <repository-url>
    cd <repository-directory>
    ```

2.  **Configure AWS Credentials:**
    Create a file named `terraform.tfvars` and add your AWS access key and secret key:
    ```
    access_key = "YOUR_AWS_ACCESS_KEY"
    secret_key = "YOUR_AWS_SECRET_KEY"
    ```
    You can also configure the AWS region in this file:
    ```
    aws-region = "us-east-1"
    ```

## Deployment

1.  **Initialize Terraform:**
    ```bash
    terraform init
    ```

2.  **Apply the configuration:**
    ```bash
    terraform apply -var-file=terraform.tfvars
    ```
    This will provision the VPC, EC2 instances, and all other necessary resources. The process will take a few minutes.

## Connecting to the Cluster

1.  **Get the master node's public IP and the private key:**
    After the `terraform apply` command completes, the master node's public IP and the private key will be saved to the `master_public_ip` and `k8s-key` files respectively.

2.  **Set permissions for the private key:**
    ```bash
    chmod 400 k8s-key
    ```

3.  **SSH into the master node:**
    ```bash
    ssh -i k8s-key ubuntu@$(cat master_public_ip)
    ```

4.  **Get the kubeconfig file:**
    Once you are on the master node, you can find the `kubeconfig` file at `/home/ubuntu/.kube/config`. You can view it by running:
    ```bash
    cat /home/ubuntu/.kube/config
    ```

5.  **Configure kubectl on your local machine:**
    Copy the content of the `kubeconfig` file from the master node and save it to a file on your local machine (e.g., `~/.kube/config`).

6.  **Verify the cluster:**
    After you have set up the `kubeconfig` on your local machine, you can run `kubectl get nodes` to see the status of your nodes:
    ```bash
    kubectl get nodes
    ```

## Scaling the Cluster

This Terraform configuration is designed to be flexible. You can easily scale the number of worker nodes in your cluster by modifying the `main.tf` file.

### Adding or Removing Worker Nodes

1.  **Open the `main.tf` file.**
2.  **Locate the `aws_instance` resource named `worker`:**
    ```terraform
    resource "aws_instance" "worker" {
      count         = 3
      ami           = data.aws_ami.ubuntu.id
      instance_type = "t3.medium"
      # ... other configuration
    }
    ```
3.  **Change the `count` parameter to the desired number of worker nodes.**
4.  **Apply the changes:**
    ```bash
    terraform apply
    ```

Terraform will automatically create or destroy worker nodes to match the number you specified in the `count` parameter.

## Destruction

To destroy the cluster and all its resources, run the following command:
```bash
terraform destroy -var-file=terraform.tfvars
```
