# Assignment 5: Docker Migration and Optimization

This document details the migration of the entire microservices application from a setup based on Linux primitives to a fully containerized architecture orchestrated by Docker Compose. This marks a critical step towards a modern, portable, and scalable deployment strategy.

## 1. Original Plan

The original plan for Day 5 involved a manual, step-by-step process:
*   Manually installing Docker, Docker Compose, and other tool-related dependencies.
*   Manually creating individual `Dockerfile`s for each of the four main services.
*   Manually writing a `docker-compose.yml` file to define the services and their networks.
*   Copying the application code from previous assignments, which lacked resilience against the startup timing issues (race conditions) common in containerized environments.
*   Running a separate, manual benchmark test.

This approach, while educational, was not automated, repeatable, or robust.

## 2. Actual Implementation (`assignment5.sh`)

The implementation transformed the manual checklist into a powerful, self-contained toolkit, `assignment5.sh`. This script automates the entire migration and management process, embodying infrastructure-as-code principles.

The script provides the following commands:
*   `sudo ./ass5.sh start`: Builds the Docker images and starts the entire application stack using Docker Compose.
*   `sudo ./ass5.sh stop`: Stops and removes all containers, networks, and volumes defined in the Compose file.
*   `sudo ./ass5.sh benchmark`: Runs a performance benchmark against the running Dockerized application.
*   `sudo ./ass5.sh clean`: Deletes all script-generated files.

## 3. Key Changes and Justifications

The final implementation is vastly superior to the original plan, focusing on automation, resilience, and user experience.

| Feature                 | Original Plan                                                                | Actual Implementation (`assignment5.sh`)                                                                                                                                                                                            | Justification                                                                                                                                                                                                                             |
| ----------------------- | ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Setup & Dependencies**| Manual installation of all prerequisites.                                    | **Fully automated**. The script attempts to install Docker, Docker Compose, and `apache2-utils` (`ab`) if they are missing. It even adds the user to the `docker` group and prompts for a shell restart. | This dramatically improves the user experience and reduces setup friction. It addresses the most common and frustrating setup issues that users encounter with Docker.                                                              |
| **File Management**     | Manual creation of multiple `Dockerfile`s and a `docker-compose.yml`.        | **All files are generated dynamically**. The script creates all `Dockerfile`s, the `docker-compose.yml`, `nginx.conf`, and even the Python application source files on the fly.                                         | This makes the entire migration process self-contained and perfectly reproducible. There are no external file dependencies, which eliminates a major source of potential errors.                                                        |
| **Startup Reliability** | No strategy for handling dependency startup order (race conditions).           | **Two layers of defense against race conditions**: <br> 1. **Docker Healthchecks**: The `docker-compose.yml` uses detailed `healthcheck` instructions for every service. <br> 2. **`depends_on` with `service_healthy`**: Containers wait for their dependencies to be healthy before starting. | This is a critical feature for production-like stability. It guarantees that the database and cache are ready before the application services attempt to connect to them, eliminating crashes on startup. |
| **Application Code**    | Assumed code from previous assignments would be used as-is.                  | **More resilient application code**. The generated Python services include `wait_for_db()` and `wait_for_redis()` functions, providing an extra layer of robustness inside the application itself.        | This "belt-and-suspenders" approach (application-level waits + orchestrator-level healthchecks) ensures the system is exceptionally stable and resilient to timing issues during startup.                                                      |
| **Orchestration**       | A basic `docker-compose.yml`.                                                | A production-ready `docker-compose.yml` that defines networks, volumes, environment variables, health checks, and service dependencies in a single, declarative file.                                     | This leverages the full power of Docker Compose to create a well-structured, maintainable, and observable application stack. Docker's internal DNS allows services to communicate using their names (e.g., `http://product-service:5000`). |

## 4. Final Dockerized Architecture

The `assignment5.sh` script deploys the exact same logical architecture as the segmented network from Assignment 4, but uses Docker's native networking and orchestration instead of manual bridge and namespace creation.

*   **Services**: Each service runs in its own container.
*   **Networking**: Four separate `bridge` networks (`frontend_net`, `backend_net`, `cache_net`, `database_net`) provide the same network segmentation and security.
*   **Service Discovery**: Docker's built-in DNS allows containers to discover and communicate with each other using their service names (e.g., `redis-cache`, `postgres-db`).
*   **Data Persistence**: A named volume (`postgres_data`) is used to ensure that PostgreSQL data survives container restarts.

<!-- Image Placeholder: Docker Architecture Diagram -->
A visual diagram depicting the Dockerized architecture would go here.
For CLI verification of the deployed Docker services and networks after running `sudo ./ass5.sh start`:

```bash
# 1. List all running Docker containers
docker ps

# 2. List all Docker networks
docker network ls

# 3. List all Docker volumes
docker volume ls
```
<!-- Image Placeholder: Output of `docker compose up` -->
To see the output of the Docker Compose services after they have been started by `sudo ./ass5.sh start`:

```bash
# First, ensure services are started
sudo ./ass5.sh start

# Then, navigate to the directory where docker-compose.yml was generated (usually the current directory)
# cd .

# View the logs of all services
docker compose logs
```

images/log.png
images/log2.png
<!-- Image Placeholder: Output of Benchmark Comparison -->
To run the performance benchmark against the Dockerized application:

```bash
# Ensure services are started before benchmarking
sudo ./ass5.sh start

images/first.png
images/second.png

# Run the benchmark
sudo ./ass5.sh benchmark
```


images/benchmark.png


images/clean.png