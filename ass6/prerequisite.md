# General Project Prerequisites

This document lists common software requirements for various assignments in this project. Please ensure these are installed on your system(s) as needed.

---

## 1. Docker Engine and Docker Compose

**Requirement for:** Assignment 5 (Docker Migration), Assignment 6 (Multi-Host Networking)

**Installation Instructions:**
You **MUST** install Docker Engine on your host machine(s) manually. This script assumes Docker is already present. Docker Compose is usually included with Docker Engine v2+ (`docker compose` command) or can be installed separately for older versions.

**Follow the official Docker installation guide for your specific OS/distribution:**
*   [Docker Engine Installation Guides](https://docs.docker.com/engine/install/)
*   [Docker Compose Installation Guide](https://docs.docker.com/compose/install/)

**Example for Ubuntu (common in EC2 environments):**
```bash
# Update package list
sudo apt-get update

# Install necessary packages for Docker installation
sudo apt-get install -y ca-certificates curl gnupg

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository to Apt sources
echo \
  "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  \"$(. /etc/os-release && echo \"$VERSION_CODENAME\")\" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update Apt package list again with Docker repo
sudo apt-get update

# Install Docker Engine, CLI, Containerd, Buildx, and Compose Plugin
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Post-installation step: Add your user to the 'docker' group
# This allows you to run docker commands without 'sudo'.
# IMPORTANT: You must log out and log back in for this change to take effect!
sudo usermod -aG docker $USER

# Verify Docker installation (after logging out/in if you added yourself to 'docker' group)
docker run hello-world
```

---

## 2. Other Common System Packages

**Requirement for:** Assignment 1, 2, 3, 4

**Installation Instructions (for Debian/Ubuntu):**
```bash
sudo apt-get update
sudo apt-get install -y iproute2 # Provides 'ip' command
sudo apt-get install -y nginx # For web server
sudo apt-get install -y redis-tools # Provides redis-server and redis-cli
sudo apt-get install -y python3 python3-pip # Python and its package manager
sudo apt-get install -y postgresql-client # For psql, useful for postgres connectivity
sudo apt-get install -y apache2-utils # Provides 'ab' (ApacheBench) for benchmarking
sudo apt-get install -y tcpdump # For network traffic analysis
sudo apt-get install -y conntrack # For connection tracking analysis
```

---

## 3. Python Libraries

**Requirement for:** Assignment 2, 3, 4, 5

**Installation Instructions:**
```bash
# Install these globally or within a virtual environment.
# Using --user to avoid permission issues if not using a virtual environment or sudo.
pip3 install --user Flask requests psycopg2-binary redis
```
