# Assignment 6: Multi-Host Deployment with Docker Swarm

This assignment marks the final evolution of the project, moving from a single-host Docker Compose setup to a true multi-host environment orchestrated by Docker Swarm. This enables high availability, scalability, and resilience by distributing services across multiple machines.

## 1. Original Plan

The original plan for Day 6 proposed two potential paths for multi-host networking:
1.  **Manual VXLAN Overlay:** A low-level approach requiring manual creation of VXLAN tunnels to connect Docker networks on different hosts.
2.  **Docker Swarm:** A higher-level, integrated solution that provides clustering and overlay networking natively.

The final implementation focuses exclusively on Docker Swarm, as it is the industry-standard, more robust, and far simpler way to manage multi-host containerized applications.

## 2. Implemented Architecture: A Multi-Host, Replicated Application Stack

The final implementation provides a complete, realistic workflow for setting up and managing a multi-host Docker Swarm cluster. It is divided into two main parts: one-time cluster setup and application lifecycle management.

Two distinct implementation patterns were developed:
*   **A "Production" Workflow:** This uses `host-a-manager.sh` and `host-b-worker.sh` to build a cluster, and then deploys a full, replicated application stack from pre-built Docker Hub images defined in `docker-compose.yml`. **This is the definitive implementation for this assignment.**
*   **A "Development" Workflow:** This uses a simplified, self-contained `manager.sh` script to demonstrate Swarm principles on a single node using locally-built images.

### a. The Definitive "Production" Workflow

This workflow uses a set of scripts and a detailed Compose file to create a true multi-host environment.

**Cluster Setup (`host-a-manager.sh` & `host-b-worker.sh`):**
*   **`host-a-manager.sh`**: This script runs on the first host and initializes it as the Swarm manager. It provides the secret token required for other nodes to join. It also includes robust checks for Docker permissions and provides user-friendly instructions.
*   **`host-b-worker.sh`**: This script runs on the second (and any subsequent) hosts. It interactively prompts the user to paste the join token from the manager, securely adding the host to the Swarm as a worker node. It even includes logic to install Docker if it's not already present.

**Application Stack (`docker-compose.yml`):**
Once the cluster is formed, the `docker-compose.yml` file is used to deploy the full application stack. This file defines the desired state of the multi-host deployment:

*   **Pre-built Images:** It uses pre-built images from a container registry (e.g., `junioroyewunmi/api-gateway:1.0`), which is standard practice for CI/CD and production deployments.
*   **Service Replicas:** It deploys multiple replicas of key services to ensure high availability and scalability:
    *   `api-gateway`: 2 replicas
    *   `product-service`: 3 replicas
    *   `order-service`: 2 replicas
*   **Overlay Networking:** It defines four `overlay` networks (`frontend_net`, `backend_net`, etc.), which Docker Swarm automatically extends across all hosts in the cluster, allowing containers to communicate seamlessly no matter which node they are running on.
*   **Placement Constraints:** It uses `deploy.placement.constraints` to intelligently place services, such as ensuring the PostgreSQL database runs on a manager node.

<!-- Image Placeholder: Docker Swarm Multi-Host Architecture Diagram -->

### b. The "Development" Workflow (`manager.sh`)

The `ass6` directory also contains a `manager.sh` script. This represents a simplified, self-contained workflow suitable for local development or for demonstrating Swarm principles on a single machine.

*   **Self-Contained:** It generates its own source code, `Dockerfile`s, and `docker-compose.yml` (via a heredoc).
*   **Local Build:** It builds Docker images locally (`api-gateway:local`).
*   **Single-Node Deployment:** It deploys a simplified, two-service stack and pins both services to the manager node.

This script is a valuable tool for quick iteration but was superseded by the more robust, multi-host "production" workflow described above.

## 3. Key Changes and Justifications

| Feature                 | Single-Host Docker Compose (Ass5)                               | Multi-Host Docker Swarm (Ass6)                                                                                                    | Justification                                                                                                                                                                                                                                                                                                                       |
| ----------------------- | --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Orchestration**       | Single host, controlled by `docker compose`.                    | **Multi-host cluster**, controlled by `docker swarm`.                                                                             | This is the core evolution. Swarm allows the application to transcend a single machine, providing a foundation for true high availability and scalability.                                                                                                                                                                   |
| **Networking**          | `bridge` networks, limited to a single host.                    | **`overlay` networks**, automatically managed and extended by Swarm across all hosts.                                             | Overlay networking is Docker's native solution for multi-host communication. It handles all the underlying complexity of routing and tunneling (like VXLAN) automatically, which is far simpler and more robust than a manual setup. |
| **High Availability & Scalability** | Single instance of each service. A single point of failure. | **Multiple replicas** of stateless services (`api-gateway`, `product-service`). Swarm automatically load-balances traffic and can restart failed containers on healthy nodes. | This is the primary benefit of a cluster orchestrator. If a worker node goes down, Swarm can reschedule its containers on the manager node. Multiple replicas allow the application to handle more load and survive individual container failures. |
| **Deployment Model**    | All images built and run from the local filesystem.             | The definitive workflow uses **pre-built images from a container registry**, decoupling the build process from the deployment process. | This is how modern CI/CD pipelines work. It ensures that the exact same tested image is deployed to all environments, from staging to production.                                                                                                |

<!-- Image Placeholder: Output of `docker node ls` showing manager and worker -->
<!-- Image Placeholder: Output of `docker service ls` showing replicated services -->