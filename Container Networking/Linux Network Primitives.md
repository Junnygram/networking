# Linux Network Primitives

> The kernel technologies powering every container network — from a simple `docker run` to a production [[Kubernetes]] cluster.
>
> Part of [[Container Networking]]

---

## Overview

Every container network is built on these [[Linux]] kernel primitives:

| Primitive | What it does | Analogy |
|-----------|-------------|---------|
| [[Network Namespace]] | Isolated network stack | An apartment — own rooms, doors, address |
| [[veth pair]] | Virtual cable between namespaces | A doorway between two rooms |
| [[Linux Bridge]] | Virtual Layer 2 switch | The hallway connecting all apartments |
| [[NAT]] / [[iptables]] | Internet access + traffic control | Building receptionist rewriting mail addresses |
| [[DNS]] | Name → IP resolution | Phone book |
| [[VXLAN]] | Overlay network across hosts | Tunnel between buildings |

---

## Network Namespaces

A [[Network Namespace]] provides a completely **isolated network stack** — its own interfaces, [[routing]] table, [[iptables]] rules, and [[ARP]] table.

```bash
# Create a namespace
sudo ip netns add my-container

# See what's inside — only loopback, completely isolated
sudo ip netns exec my-container ip addr show

# Run any command inside the namespace
sudo ip netns exec my-container ping 127.0.0.1

# List all namespaces
ip netns list

# Delete
sudo ip netns delete my-container
```

### Proving isolation

Two namespaces on the same host **cannot communicate** unless explicitly connected:

```bash
# Start a web server on the host
python3 -m http.server 8080 &

# Accessible from the host
curl http://localhost:8080  # ✅ Works

# But NOT from a namespace — different network stack
sudo ip netns add isolated
sudo ip netns exec isolated curl http://localhost:8080  # ❌ Connection refused

# Even though both use "localhost", they're in separate worlds
sudo ip netns delete isolated
```

---

## Virtual Ethernet (veth) Pairs

A ==veth pair== is a virtual cable. Packets sent into one end come out the other. They connect [[Network Namespace]]s together.

```bash
# Create two namespaces
sudo ip netns add red
sudo ip netns add blue

# Create a veth pair
sudo ip link add veth-red type veth peer name veth-blue

# Move each end into its namespace
sudo ip link set veth-red netns red
sudo ip link set veth-blue netns blue

# Assign IP addresses
sudo ip netns exec red ip addr add 10.0.0.1/24 dev veth-red
sudo ip netns exec blue ip addr add 10.0.0.2/24 dev veth-blue

# Bring both ends up
sudo ip netns exec red ip link set veth-red up
sudo ip netns exec red ip link set lo up
sudo ip netns exec blue ip link set veth-blue up
sudo ip netns exec blue ip link set lo up

# Now they can communicate
sudo ip netns exec red ping -c 2 10.0.0.2   # ✅
sudo ip netns exec blue ping -c 2 10.0.0.1  # ✅

# Cleanup
sudo ip netns delete red
sudo ip netns delete blue
```

### The scaling problem

veth pairs only connect **two** namespaces. For 6 containers to all talk to each other, you'd need 15 pairs. This doesn't scale — you need a **switch**.

---

## Linux Bridge — Virtual Switch

A [[Linux Bridge]] is a **virtual Layer 2 switch**. It connects multiple veth pairs so all attached namespaces can communicate.

```bash
# Create a bridge
sudo ip link add br0 type bridge
sudo ip addr add 10.0.0.1/24 dev br0
sudo ip link set br0 up
```

**How it works:**
- Learns [[MAC Address]]es of connected interfaces
- When a frame arrives → checks forwarding table
- Known destination → forward to that port
- Unknown destination → flood to all ports

The bridge IP (`10.0.0.1`) serves as the **default gateway** for containers.

### Attaching namespaces to the bridge

```bash
# Create a namespace
sudo ip netns add web

# Create a veth pair
sudo ip link add veth-web type veth peer name veth-web-br

# One end → bridge
sudo ip link set veth-web-br master br0
sudo ip link set veth-web-br up

# Other end → namespace
sudo ip link set veth-web netns web
sudo ip netns exec web ip addr add 10.0.0.10/24 dev veth-web
sudo ip netns exec web ip link set veth-web up
sudo ip netns exec web ip link set lo up
sudo ip netns exec web ip route add default via 10.0.0.1
```

Repeat for more namespaces — they all communicate through the bridge.

---

## NAT and iptables — Internet Access

Containers use private IPs (`10.0.0.x`) that aren't routable on the internet. [[NAT]] (Network Address Translation) rewrites packet headers to enable internet access.

### Enabling internet for containers

```bash
# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Find the host's outbound interface
DEFAULT_IFACE=$(ip route get 8.8.8.8 | awk '{printf $5}')

# MASQUERADE: rewrite source IP for outgoing traffic
sudo iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o $DEFAULT_IFACE -j MASQUERADE

# Allow forwarded traffic
sudo iptables -A FORWARD -i br0 -j ACCEPT
sudo iptables -A FORWARD -o br0 -j ACCEPT

# Configure DNS
sudo ip netns exec web bash -c "echo 'nameserver 8.8.8.8' > /etc/resolv.conf"

# Test
sudo ip netns exec web ping -c 2 google.com  # ✅
```

### What happens when a container pings 8.8.8.8

1. Packet leaves container (`src: 10.0.0.10`) → veth → bridge
2. Host's routing sends it to the outbound interface
3. [[iptables]] MASQUERADE rewrites `src` to the host's public IP
4. Response returns → [[conntrack]] maps it back to `10.0.0.10`
5. Packet delivered to the container

---

## iptables Deep Dive

[[iptables]] is the [[Linux]] kernel's packet filtering framework — used for [[NAT]], firewalls, port forwarding, and traffic control.

### Tables and chains

| Table | Purpose | Key Chains |
|-------|---------|------------|
| `filter` | Allow/deny packets | INPUT, OUTPUT, **FORWARD** |
| `nat` | Address translation | PREROUTING, **POSTROUTING** |
| `mangle` | Packet alteration | All chains |

### Packet flow

```
Incoming packet
  → PREROUTING (nat) — DNAT, port forwarding
    → Routing decision
      → If for this host: INPUT (filter)
      → If forwarded: FORWARD (filter) → POSTROUTING (nat) — SNAT/MASQUERADE
```

### Essential rules for container networking

```bash
# Internet access via NAT
iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE

# Allow forwarded traffic
iptables -A FORWARD -i br0 -j ACCEPT

# Port forwarding (expose container port on host)
iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to 10.0.0.10:80

# Security: default deny + allow only established
iptables -P FORWARD DROP
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i br-frontend -o br-backend -j ACCEPT

# View rules
iptables -L -n -v
iptables -t nat -L -n -v
```

> [!important]
> Always add a [[conntrack]] rule for `ESTABLISHED,RELATED` when using a default `DROP` policy. Without it, even allowed connections break because response packets get dropped.

---

## VXLAN — Overlay Networks

When containers need to communicate **across different physical hosts**, you need [[VXLAN]] (Virtual Extensible LAN).

```
Host A                              Host B
┌──────────┐                        ┌──────────┐
│Container1│                        │Container2│
│ 10.0.0.2 │                        │ 10.0.0.3 │
└────┬─────┘                        └────┬─────┘
     │                                   │
┌────┴──────────┐                  ┌─────┴─────────┐
│ VXLAN tunnel  │ ═══UDP:4789═══>  │ VXLAN tunnel   │
│ (encapsulate) │                  │ (decapsulate)  │
└───────────────┘                  └────────────────┘
```

**How it works:**
1. Original Layer 2 frame is **encapsulated** inside a UDP packet (port 4789)
2. Sent across the physical network to the other host
3. Receiving host **decapsulates** and delivers the original frame

Each overlay network gets a **VNI** (VXLAN Network Identifier) for isolation.

[[Docker Swarm]] and [[Kubernetes]] automate VXLAN setup — you declare an overlay network and the orchestrator handles everything.

---

## Container Network Models

[[Docker]] provides four network modes:

| Mode | Description | Use Case |
|------|-------------|----------|
| **Bridge** | Private network with NAT (default) | Most containers |
| **Host** | Shares the host's network stack directly | Performance-critical apps |
| **None** | No networking at all | Security-sensitive workloads |
| **Container** | Shares another container's namespace | Sidecar patterns (like [[Kubernetes]] pods) |

```bash
docker run --network=bridge nginx        # Default — private IP
docker run --network=host nginx          # Binds directly to host ports
docker run --network=none nginx          # Fully isolated
docker run --network=container:app1 nginx # Shares app1's network
```

---

## Next Steps

With these primitives understood, move on to [[Building a Container Network]] to put them all together into a working multi-service system.

---

#linux #networking #namespaces #iptables #veth #bridge #container-networking
