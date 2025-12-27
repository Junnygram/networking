# Assignment 4: Advanced Networking - Service Discovery, Security, and Architectural Evolution

Assignment 4 introduces a significant fork in the project's development, moving from simple enhancements to a major architectural redesign. This document covers both paths taken:
1.  **Part A:** Enhancing the original flat network with a service registry and firewall policies.
2.  **Part B:** A complete architectural overhaul to introduce network segmentation and load balancing.

---

## Part A: Enhancements to the Flat Network

This part of the assignment focused on adding service discovery and security to the existing single-bridge network from Assignments 1-3.

### 1. Original Plan

The plan was to create two separate, manual scripts:
*   A Python script for a simple service registry.
*   A shell script to apply a list of `iptables` rules.

This approach was manual and lacked robust error handling or lifecycle management.

### 2. Actual Implementation (`assignment4.sh`)

The implementation consolidated these features into a single, professional toolkit, `assignment4.sh`, with clear subcommands.

*   **`start-registry` / `stop-registry`**: Manages the lifecycle of a dynamically generated Flask-based service registry. It runs on the host and serves as a central point for service discovery.
*   **`apply-policies` / `remove-policies` / `show-policies`**: Manages the lifecycle of the firewall rules.

### 3. Key Changes and Justifications

| Feature                 | Original Plan                          | Actual Implementation (`assignment4.sh`)                                                                         | Justification                                                                                                                                                                                 |
| ----------------------- | -------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Script Organization** | Separate, disconnected scripts.        | A single, unified toolkit with clear subcommands.                                                                | This provides a much cleaner, more manageable, and user-friendly interface for advanced network functions.                                                                                    |
| **Dependency Management** | Manual installation.                   | **Automated prerequisite checks** and integration with the shared Python virtual environment from Assignment 2.    | This ensures the toolkit is self-contained and runs reliably without manual setup, which is a superior engineering practice.                                                                  |
| **Security Policies**   | A static list of `iptables` rules.     | A complete implementation that correctly sets a **default `DROP` policy** on the `FORWARD` chain before adding `ACCEPT` rules. It also includes a rule for `ESTABLISHED,RELATED` traffic. | This is the correct way to implement a "default deny" firewall. The original plan was insecure because it didn't block unspecified traffic. The inclusion of the conntrack rule is essential for stateful connections to work. |

<!-- Image Placeholder: Service Registry Output -->
To demonstrate the service registry:

```bash
# 1. Start the service registry (runs in background)
sudo ./assignment4.sh start-registry
images/registry

# 2. Register a dummy service (example)
curl -X POST -H "Content-Type: application/json" -d '{"name": "test-service", "ip": "10.0.0.99", "port": 1234}' http://127.0.0.1:8500/register

# 3. List all registered services (this is what the screenshot would capture)
curl http://127.0.0.1:8500/services

# (Optional: stop the registry after testing)
# sudo ./assignment4.sh stop-registry
```
<!-- Image Placeholder: iptables Security Policy Rules -->
To apply and then inspect the iptables security policies:

```bash
# 1. Apply the security policies (sets default DROP and adds ACCEPT rules)
sudo ./assignment4.sh apply-policies

# 2. Show the active FORWARD chain iptables rules (this is what the screenshot would capture)
sudo ./assignment4.sh show-policies


images/policy.png

# (Optional: remove policies after testing)
# sudo ./assignment4.sh remove-policies
```

---

## Part B: A New Architecture - Segmentation & Load Balancing

This part of the assignment represents a fundamental evolution of the project's architecture. Instead of patching the old flat network, a new, more realistic, and scalable design was implemented from the ground up in the `modified_setup/` directory.

### 1. Original Plan

The plan was to manually add more service instances and multiple bridges to the existing setup, a complex and error-prone task.

### 2. Actual Implementation (`modified_setup/` scripts)

The implementation consists of two new, fully automated scripts that build the advanced architecture from scratch:

*   **`assignment4-network.sh`**: Creates a segmented network with three distinct bridges:
    *   `br-frontend` (`172.20.0.0/24`): For the Nginx load balancer.
    *   `br-backend` (`172.21.0.0/24`): For the application services.
    *   `br-database` (`172.22.0.0/24`): For the Redis and PostgreSQL data stores.
    It also creates a multi-homed `api-gateway` with interfaces on both the frontend and backend networks, allowing it to act as a secure router between them.

*   **`assignment4-services.sh`**: Deploys the services onto this new network.
    *   **Load Balancing**: It starts three replicas of the `product-service`.
    *   **New API Gateway**: It deploys a new `api-gateway-lb.py` that includes a round-robin load balancer to distribute traffic across the `product-service` replicas.
    *   **Updated Services**: The service code is updated to work with the new IP ranges and to report which replica served a request, making it easy to verify that the load balancer is working.

<!-- Image Placeholder: Diagram of New Segmented Network Architecture -->
A visual diagram would illustrate the segmented network. For CLI verification of the segmented network after running `sudo ./modified_setup/assignment4-network.sh`:

```bash
# 1. List all created bridges
ip link show type bridge

# 2. Show IP addresses for each bridge
ip addr show br-frontend
ip addr show br-backend
ip addr show br-database

# 3. Show IP addresses for the multi-homed api-gateway namespace
sudo ip netns exec api-gateway ip addr

# 4. Show IP address for a product service replica
sudo ip netns exec product-service-1 ip addr

# 5. Show IP address for the redis-cache namespace
sudo ip netns exec redis-cache ip addr
```

### 3. Key Changes and Justifications

This new architecture is a massive improvement over the original flat network for several reasons:

| Feature                   | Original Flat Network                                     | New Segmented Architecture                                                                                                     | Justification                                                                                                                                                                                          |
| ------------------------- | --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Security**              | All services on one bridge; security depends on `iptables`. | **Network Segmentation**. The database is on a completely separate network from the frontend, preventing direct access. Security is enforced by network topology itself. | This is a core principle of "defense in depth." An attacker who compromises the frontend cannot directly attack the database.                                                                    |
| **Scalability**           | Single instance of each service.                          | **Load Balancing**. Multiple replicas of the `product-service` are run, and the API Gateway distributes traffic among them.   | This allows the application to handle significantly more traffic and is a foundational pattern for building scalable microservices.                                                          |
| **Organization & Isolation** | All services mixed together.                              | **Tiered Architecture**. Services are organized into logical tiers (frontend, backend, data), which is a standard and well-understood pattern for application architecture. | This improves maintainability and makes it easier to reason about the system. It also contains the "blast radius" of failures; a problem in one tier is less likely to affect another. |
| **Automation**            | Manual, step-by-step changes.                             | **Fully Automated Deployment**. The new scripts can create and destroy the entire advanced environment with just two commands.     | This level of automation is essential for modern infrastructure management, enabling consistent, repeatable, and reliable deployments.                                                          |

<!-- Image Placeholder: Output of Load Balancer Distributing Requests -->
To demonstrate the load balancer distributing requests across product service replicas after starting the segmented network and services:

```bash
# 1. Ensure the segmented network is up (run this first if not already done)
# sudo ./modified_setup/assignment4-network.sh

# 2. Start the services on the segmented network
sudo ./modified_setup/assignment4-services.sh start

# 3. Repeatedly curl the API Gateway (via Nginx) to observe load balancing
# The 'served_by' IP in the response will cycle through the product-service replicas.
for i in {1..7}; do
    curl -s http://172.20.0.10/api/products | grep -o '"served_by": "[^"]*"'
    sleep 0.5
done
```
