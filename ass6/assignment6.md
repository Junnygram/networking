# Assignment 6: Multi-Host Networking (Optional Advanced)

This assignment delves into multi-host networking, allowing services to communicate across different physical or virtual machines. It is an advanced topic and **requires at least two Linux hosts or Virtual Machines** to fully implement.

---

## ⚠️ Step 0: Prerequisites (On ALL Hosts)

**1. Docker Engine and Docker Compose (REQUIRED BEFORE RUNNING SCRIPT):**
Ensure Docker Engine and Docker Compose are installed and running on **both (or all) hosts**.
**Refer to `prerequisite.md` in the project root for detailed installation instructions.**

```bash
# Verify Docker installation (after following prerequisite.md instructions)
docker run hello-world
```

**2. IP Connectivity:**
Ensure your hosts can ping each other using their primary IP addresses.
*   **Host A:** `ping <HOST_B_IP>`
*   **Host B:** `ping <HOST_A_IP>`

**3. Firewalls:**
Ensure necessary ports are open (e.g., TCP 2377 for Swarm management, TCP 7946 for overlay, UDP 4789 for overlay, UDP 4789 for VXLAN, TCP 22 for SSH). For simplicity in a lab, you might temporarily disable firewalls if you encounter issues.

---

## Task 6.1: Setup VXLAN Overlay

VXLAN (Virtual Extensible LAN) is a tunneling protocol that allows you to create a virtual Layer 2 network over an existing Layer 3 network. This means services on different hosts can appear to be on the same Ethernet segment.

**Architecture:**

```
    +-----------------+                     +-----------------+ 
    |     Host A      |                     |     Host B      | 
    |  (192.168.1.10) |                     |  (192.168.1.20) | 
    |                 |                     |                 | 
    |  +-----------+  |                     |  +-----------+  | 
    |  |  Service  |  |                     |  |  Service  |  | 
    |  | (10.0.0.x) <-------------------------> (10.0.0.y) |  |  <- VXLAN Overlay
    |  +-----+-----+  |                     |  +-----+-----+  | 
    |        |        |                     |        |        | 
    |  +-----v-----+  |                     |  +-----v-----+  | 
    |  |  br-app   |  |                     |  |  br-app   |  |  <- Linux Bridge
    |  | (10.0.0.1) |  |                     |  | (10.0.0.1) |  | 
    |  +-----+-----+  |                     |  +-----+-----+  | 
    |        |        |                     |        |        | 
    |  +-----v-----+  |                     |  +-----v-----+  | 
    |  |  vxlan100 |  |                     |  |  vxlan100 |  |  <- VXLAN Interface
    |  +-----------+  |                     |  +-----------+  | 
    |        |        |                     |        |        | 
    |  +-----v-----+  |                     |  +-----v-----+  | 
    |  |   eth0    |  |                     |  |   eth0    |  |  <- Physical Interface
    |  +-----------+  |                     |  +-----------+  | 
    +-----------------+                     +-----------------+ 
```

### Steps (Perform on Each Host)

**Important:** Replace `<HOST_A_IP>` and `<HOST_B_IP>` with the actual primary IP addresses of your hosts.

**1. Create VXLAN Interface:**

```bash
# On Host A (e.g., 192.168.1.10)
sudo ip link add vxlan100 type vxlan id 100 remote <HOST_B_IP> dstport 4789 dev eth0
sudo ip link set vxlan100 up

# On Host B (e.g., 192.168.1.20)
sudo ip link add vxlan100 type vxlan id 100 remote <HOST_A_IP> dstport 4789 dev eth0
sudo ip link set vxlan100 up
```
*   `id 100`: VXLAN Network Identifier (VNI). Must be the same on all hosts.
*   `remote`: The IP address of the peer host.
*   `dstport 4789`: Standard VXLAN UDP port.
*   `dev eth0`: The physical interface to send VXLAN traffic over. Adjust if your primary interface is different.

**2. Attach VXLAN to a Linux Bridge:**
You will need a Linux bridge on each host. If you have `br0` from Assignment 1, you can use that. Otherwise, create one.

```bash
# If not already done from Assignment 1
sudo ip link add br0 type bridge
sudo ip addr add 10.0.0.1/24 dev br0
sudo ip link set br0 up

# Attach VXLAN interface to the bridge
sudo ip link set vxlan100 master br0
```

**3. Configure Namespaces (Optional, for testing):**
Now, you can create namespaces on each host and connect them to `br0`. They will be able to communicate across hosts.

```bash
# On Host A
sudo ip netns add client-a
sudo ip link add veth-a type veth peer name veth-a-br
sudo ip link set veth-a netns client-a
sudo ip link set veth-a-br master br0
sudo ip link set veth-a-br up
sudo ip netns exec client-a ip addr add 10.0.0.100/24 dev veth-a
sudo ip netns exec client-a ip link set veth-a up
sudo ip netns exec client-a ip link set lo up
sudo ip netns exec client-a ip route add default via 10.0.0.1

# On Host B
sudo ip netns add client-b
sudo ip link add veth-b type veth peer name veth-b-br
sudo ip link set veth-b netns client-b
sudo ip link set veth-b-br master br0
sudo ip link set veth-b-br up
sudo ip netns exec client-b ip addr add 10.0.0.101/24 dev veth-b
sudo ip netns exec client-b ip link set veth-b up
sudo ip netns exec client-b ip link set lo up
sudo ip netns exec client-b ip route add default via 10.0.0.1
```

### Verification

**From client-a on Host A, ping client-b on Host B:**

```bash
sudo ip netns exec client-a ping -c 3 10.0.0.101
```
If successful, you have a working multi-host VXLAN overlay!

---

## Task 6.2: Docker Swarm Setup

Docker Swarm provides native clustering for Docker. It uses an overlay network to enable containers to communicate across different Swarm nodes. This is a much simpler way to achieve multi-host container networking than manual VXLAN.

### Steps (Perform on Each Host)

**Important:** This assumes Docker is installed and your user can run `docker` commands without `sudo`.

**1. Initialize Swarm (On Host A - Manager Node):**

```bash
# On Host A (e.g., 192.168.1.10)
docker swarm init --advertise-addr <HOST_A_IP>
```
This command will output a `docker swarm join` command. Copy this command.

**2. Join Swarm (On Host B - Worker Node):**

```bash
# On Host B (e.192.168.1.20)
# Paste the 'docker swarm join ...' command copied from Host A
docker swarm join --token SWMTKN-1-<TOKEN> <HOST_A_IP>:2377
```

**3. Verify Swarm Status (On Host A - Manager Node):**

```bash
docker node ls
```
You should see both Host A and Host B listed.

**4. Deploy Application (On Host A - Manager Node):**
You can now use your `docker-compose.yml` from Assignment 5 to deploy services across your Swarm. Docker automatically handles the overlay networking.

```bash
# On Host A
# Ensure you have your docker-compose.yml and Dockerfiles
docker stack deploy -c docker-compose.yml myapp
```

### Verification

**Check services (On Host A - Manager Node):**

```bash
docker service ls
docker ps # On both Host A and Host B to see where containers are running
```

**Access the application (from any host where port 8080 is exposed):**

```bash
curl http://localhost:8080/api/products # If nginx-lb maps to localhost:8080
```
Docker Swarm should be distributing your product service replicas across both hosts, and they should be communicating seamlessly.

---

## Cleanup (On Each Host)

### Manual VXLAN Cleanup (If implemented)

```bash
# On Host A and Host B
sudo ip link set vxlan100 down
sudo ip link delete vxlan100
# If br0 was created specifically for this, and no other uses:
sudo ip link set br0 down
sudo ip link delete br0
# Delete any client namespaces created
sudo ip netns delete client-a 2>/dev/null || true # And client-b on Host B
```

### Docker Swarm Cleanup

```bash
# On Swarm Manager (Host A):
docker stack rm myapp
docker swarm leave --force

# On Swarm Worker (Host B):
docker swarm leave
```
