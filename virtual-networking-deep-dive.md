# Container Virtual Networking Deep Dive

## Table of Contents

1. [Introduction to Virtual Networking](#introduction)
2. [Linux Network Namespaces](#network-namespaces)
3. [Virtual Ethernet Devices (veth pairs)](#veth-pairs)
4. [Linux Bridges](#linux-bridges)
5. [Network Address Translation (NAT)](#nat)
6. [iptables and Packet Filtering](#iptables)
7. [Container Network Models](#container-network-models)
8. [Overlay Networks (VXLAN)](#overlay-networks)
9. [DNS in Container Networks](#dns)
10. [Complete Working Examples](#complete-examples)

---

## Introduction to Virtual Networking

Container networking relies on Linux kernel features to create isolated, virtual network environments. Each container can have its own network stack while sharing the host's physical network interface.

### Core Linux Networking Constructs

```
┌─────────────────────────────────────────────────────────────┐
│                  LINUX NETWORKING STACK                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Application Layer (socket API)                             │
│  ────────────────────────────────────────────────────       │
│                      ↕                                      │
│  Transport Layer (TCP/UDP)                                  │
│  ────────────────────────────────────────────────────       │
│                      ↕                                      │
│  Network Layer (IP routing, iptables)                       │
│  ────────────────────────────────────────────────────       │
│                      ↕                                      │
│  Link Layer (Ethernet, ARP)                                 │
│  ────────────────────────────────────────────────────       │
│                      ↕                                      │
│  Physical/Virtual Network Devices                           │
│  (eth0, veth0, br0, docker0)                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘

Key Components for Container Networking:
1. Network Namespaces - Isolated network stacks
2. veth pairs - Virtual Ethernet cables
3. Bridges - Virtual switches
4. iptables - Packet filtering and NAT
5. Routing tables - Packet forwarding
```

---

## Network Namespaces

Network namespaces provide complete isolation of network resources. Each namespace has its own:

- Network interfaces
- Routing tables
- iptables rules
- Sockets
- Network statistics

### Namespace Structure

```
┌─────────────────────────────────────────────────────────────┐
│              ROOT NETWORK NAMESPACE (Host)                  │
│                                                             │
│  Network Interfaces:                                        │
│  ├── lo (127.0.0.1)                                         │
│  ├── eth0 (192.168.1.100) ← Physical interface             │
│  └── docker0 (172.17.0.1) ← Bridge                          │
│                                                             │
│  Routing Table:                                             │
│  ├── default via 192.168.1.1 dev eth0                       │
│  └── 172.17.0.0/16 dev docker0                              │
│                                                             │
│  iptables Rules: (NAT, FILTER, etc.)                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│          CONTAINER NETWORK NAMESPACE                        │
│                                                             │
│  Network Interfaces:                                        │
│  ├── lo (127.0.0.1)                                         │
│  └── eth0 (172.17.0.2) ← Connected to host via veth        │
│                                                             │
│  Routing Table:                                             │
│  └── default via 172.17.0.1 dev eth0                        │
│                                                             │
│  iptables Rules: (inherited or custom)                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Practical Example: Creating Network Namespaces

```bash
# List all network namespaces
ip netns list

# Create a new network namespace
sudo ip netns add red
sudo ip netns add blue

# List network interfaces in a namespace (initially only loopback)
sudo ip netns exec red ip link list

# Expected output:
# 1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN mode DEFAULT
#     link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00

# View routing table in namespace (empty initially)
sudo ip netns exec red ip route

# View IP addresses in namespace
sudo ip netns exec red ip addr

# Enable loopback interface in namespace
sudo ip netns exec red ip link set lo up

# Test connectivity within namespace
sudo ip netns exec red ping 127.0.0.1
```

### Namespace Isolation Demo

```bash
# In root namespace, start a web server on port 8080
python3 -m http.server 8080 &
ROOT_PID=$!

# Try to access from root namespace (works)
curl localhost:8080

# Create and enter a network namespace
sudo ip netns add isolated

# Try to access the server from isolated namespace (fails - no connection)
sudo ip netns exec isolated curl localhost:8080
# Error: Connection refused (different network stack!)

# Even though both use "localhost", they're in different namespaces
# The server in root namespace is invisible to the isolated namespace

# Cleanup
kill $ROOT_PID
sudo ip netns del isolated
```

---

## Virtual Ethernet Devices (veth pairs)

veth pairs are like virtual network cables connecting two network namespaces. What goes in one end comes out the other.

### veth Pair Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    VETH PAIR CONCEPT                        │
└─────────────────────────────────────────────────────────────┘

Think of veth as a virtual ethernet cable:

    Namespace A              Namespace B
    ┌──────────┐            ┌──────────┐
    │          │            │          │
    │  veth0   │============│  veth1   │
    │  (end A) │  "cable"   │  (end B) │
    │          │            │          │
    └──────────┘            └──────────┘

Properties:
- Packet sent to veth0 arrives at veth1
- Packet sent to veth1 arrives at veth0
- Acts like a physical ethernet cable
- Can be placed in different namespaces
```

### Creating and Using veth Pairs

```bash
# Create two network namespaces
sudo ip netns add red
sudo ip netns add blue

# Create a veth pair
sudo ip link add veth-red type veth peer name veth-blue

# At this point, both ends are in the root namespace
# Verify:
ip link list | grep veth
# veth-blue@veth-red: ...
# veth-red@veth-blue: ...

# Move one end to the 'red' namespace
sudo ip link set veth-red netns red

# Move the other end to the 'blue' namespace
sudo ip link set veth-blue netns blue

# Now veth-red is only visible in 'red' namespace
sudo ip netns exec red ip link list
# Will show veth-red

# veth-blue is only visible in 'blue' namespace
sudo ip netns exec blue ip link list
# Will show veth-blue

# Assign IP addresses
sudo ip netns exec red ip addr add 10.0.0.1/24 dev veth-red
sudo ip netns exec blue ip addr add 10.0.0.2/24 dev veth-blue

# Bring the interfaces up
sudo ip netns exec red ip link set veth-red up
sudo ip netns exec red ip link set lo up
sudo ip netns exec blue ip link set veth-blue up
sudo ip netns exec blue ip link set lo up

# Test connectivity - ping from red to blue
sudo ip netns exec red ping -c 3 10.0.0.2
# Success! Packets flow through the veth pair

# Test reverse - ping from blue to red
sudo ip netns exec blue ping -c 3 10.0.0.1
# Also works!

# View the connection
sudo ip netns exec red ip route
# 10.0.0.0/24 dev veth-red proto kernel scope link src 10.0.0.1
```

### Packet Flow Visualization

```
┌─────────────────────────────────────────────────────────────┐
│              PACKET FLOW THROUGH VETH PAIR                  │
└─────────────────────────────────────────────────────────────┘

Red Namespace                                 Blue Namespace
┌─────────────────────┐                     ┌─────────────────────┐
│                     │                     │                     │
│  Application        │                     │  Application        │
│  (ping 10.0.0.2)    │                     │  (receives ping)    │
│         │           │                     │         ↑           │
│         ↓           │                     │         │           │
│  TCP/IP Stack       │                     │  TCP/IP Stack       │
│  (10.0.0.1)         │                     │  (10.0.0.2)         │
│         │           │                     │         ↑           │
│         ↓           │                     │         │           │
│  veth-red           │                     │  veth-blue          │
│  10.0.0.1           │═══════════════════▶ │  10.0.0.2           │
│                     │  kernel forwards    │                     │
│                     │  packet instantly   │                     │
└─────────────────────┘                     └─────────────────────┘

ICMP Echo Request:
src: 10.0.0.1  dst: 10.0.0.2
        │
        ├─→ veth-red (red namespace)
        │
        └─→ veth-blue (blue namespace)
                │
                └─→ IP stack processes packet
                        │
                        └─→ Send ICMP Echo Reply
                                │
                                └─→ Reverse path
```

### Advanced veth Example: Web Server Communication

```bash
# Setup namespaces with veth pair (reusing previous setup)
# In blue namespace, start a simple web server
sudo ip netns exec blue python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(b'Hello from BLUE namespace!')
    def log_message(self, format, *args):
        pass

HTTPServer(('10.0.0.2', 8080), Handler).serve_forever()
" &

BLUE_PID=$!

# Access the web server from red namespace
sudo ip netns exec red curl http://10.0.0.2:8080
# Output: Hello from BLUE namespace!

# Monitor traffic on the veth interface
sudo ip netns exec red tcpdump -i veth-red -n
# You'll see the HTTP traffic flowing through the veth pair

# Cleanup
sudo kill $BLUE_PID
sudo ip netns del red
sudo ip netns del blue
```

---

## Linux Bridges

A Linux bridge acts as a virtual network switch, connecting multiple network interfaces together.

### Bridge Concepts

```
┌─────────────────────────────────────────────────────────────┐
│                    LINUX BRIDGE                             │
└─────────────────────────────────────────────────────────────┘

Physical Switch Analogy:
         ┌─────────────────────┐
         │   Network Switch    │
         │   (8 ports)         │
         └─┬─┬─┬─┬─┬─┬─┬─┬─────┘
           │ │ │ │ │ │ │ │
     ┌─────┘ │ │ │ │ │ │ └─────┐
     │       │ │ │ │ │ │       │
   PC1     PC2│ │ │ │ PC7    PC8
             PC3│ │ PC6
               PC4 PC5


Linux Bridge (Virtual):
         ┌─────────────────────┐
         │    br0 (bridge)     │
         │    172.17.0.1       │
         └─┬─┬─┬─┬─┬─┬─┬───────┘
           │ │ │ │ │ │ │
     ┌─────┘ │ │ │ │ │ └────────┐
     │       │ │ │ │ │          │
   veth0  veth1│ │ │ veth6   veth7
            veth2│ │veth5
                veth3veth4
                  │
            To containers

Features:
- Layer 2 (MAC-based) forwarding
- Learning bridge (builds MAC table)
- Broadcast domain
- Can have its own IP address
```

### Creating a Bridge

```bash
# Create a bridge
sudo ip link add br0 type bridge

# Verify bridge creation
ip link show br0

# Assign IP address to bridge
sudo ip addr add 192.168.100.1/24 dev br0

# Bring bridge up
sudo ip link set br0 up

# View bridge details
ip addr show br0

# Bridge starts with no connected interfaces
bridge link show
```

### Connecting Namespaces via Bridge

```bash
# Create three network namespaces (containers)
sudo ip netns add container1
sudo ip netns add container2
sudo ip netns add container3

# Create bridge
sudo ip link add br0 type bridge
sudo ip addr add 10.0.0.1/24 dev br0
sudo ip link set br0 up

# Create veth pairs for each container
sudo ip link add veth1 type veth peer name veth1-br
sudo ip link add veth2 type veth peer name veth2-br
sudo ip link add veth3 type veth peer name veth3-br

# Move one end of each veth pair into containers
sudo ip link set veth1 netns container1
sudo ip link set veth2 netns container2
sudo ip link set veth3 netns container3

# Attach the bridge-side veth ends to the bridge
sudo ip link set veth1-br master br0
sudo ip link set veth2-br master br0
sudo ip link set veth3-br master br0

# Bring up bridge-side interfaces
sudo ip link set veth1-br up
sudo ip link set veth2-br up
sudo ip link set veth3-br up

# Configure container-side interfaces
sudo ip netns exec container1 ip addr add 10.0.0.2/24 dev veth1
sudo ip netns exec container1 ip link set veth1 up
sudo ip netns exec container1 ip link set lo up
sudo ip netns exec container1 ip route add default via 10.0.0.1

sudo ip netns exec container2 ip addr add 10.0.0.3/24 dev veth2
sudo ip netns exec container2 ip link set veth2 up
sudo ip netns exec container2 ip link set lo up
sudo ip netns exec container2 ip route add default via 10.0.0.1

sudo ip netns exec container3 ip addr add 10.0.0.4/24 dev veth3
sudo ip netns exec container3 ip link set veth3 up
sudo ip netns exec container3 ip link set lo up
sudo ip netns exec container3 ip route add default via 10.0.0.1

# Verify bridge connections
bridge link show br0
# Should show three veth interfaces attached

# Test connectivity between containers
sudo ip netns exec container1 ping -c 2 10.0.0.3  # container1 → container2
sudo ip netns exec container2 ping -c 2 10.0.0.4  # container2 → container3
sudo ip netns exec container3 ping -c 2 10.0.0.2  # container3 → container1

# All containers can reach each other through the bridge!
```

### Bridge Packet Flow

```
┌─────────────────────────────────────────────────────────────┐
│          PACKET FLOW THROUGH BRIDGE                         │
└─────────────────────────────────────────────────────────────┘

Scenario: container1 (10.0.0.2) pings container3 (10.0.0.4)

container1 NS          Host NS                    container3 NS
┌──────────┐       ┌────────────┐                ┌──────────┐
│          │       │            │                │          │
│ 10.0.0.2 │       │   Bridge   │                │10.0.0.4  │
│          │       │   (br0)    │                │          │
│  veth1   │       │ 10.0.0.1   │                │  veth3   │
└────┬─────┘       └─────┬──────┘                └────┬─────┘
     │                   │                            │
     │    veth1-br       │      veth3-br              │
     └─────────┬─────────┼─────────┬──────────────────┘
               │         │         │
               └─────────┴─────────┘

Step-by-step:
1. container1 sends ICMP packet to 10.0.0.4
   - Packet enters veth1 in container1 namespace
   
2. Packet exits veth1-br in host namespace
   - Arrives at bridge br0
   
3. Bridge examines destination MAC address
   - Bridge has learned that 10.0.0.4 is on veth3-br
   - (Learning via previous ARP exchanges)
   
4. Bridge forwards packet to veth3-br
   - Packet enters veth3-br in host namespace
   
5. Packet exits veth3 in container3 namespace
   - Delivered to 10.0.0.4

6. Reply follows reverse path

MAC Learning Table (simplified):
┌─────────────────┬──────────────────┬──────────┐
│ MAC Address     │ Interface        │ Age      │
├─────────────────┼──────────────────┼──────────┤
│ aa:bb:cc:00:01  │ veth1-br         │ 10s      │
│ aa:bb:cc:00:02  │ veth2-br         │ 15s      │
│ aa:bb:cc:00:03  │ veth3-br         │ 5s       │
└─────────────────┴──────────────────┴──────────┘
```

### Inspecting Bridge State

```bash
# Show bridge forwarding database (MAC address table)
bridge fdb show br br0

# Show bridge details with statistics
ip -s link show br0

# Show which interfaces are connected to bridge
bridge link show

# Monitor bridge traffic
sudo tcpdump -i br0 -n

# View ARP table in container
sudo ip netns exec container1 ip neigh show
```

---

## Network Address Translation (NAT)

NAT allows containers with private IP addresses to access external networks through the host's IP address.

### NAT Concepts

```
┌─────────────────────────────────────────────────────────────┐
│                  NAT FUNDAMENTALS                           │
└─────────────────────────────────────────────────────────────┘

Source NAT (SNAT/MASQUERADE):
Changes source IP of outgoing packets

Container Network          Host               Internet
(Private IPs)         (Public IP)
┌──────────────┐    ┌─────────────┐       ┌──────────┐
│ Container    │    │             │       │  Google  │
│ 172.17.0.2   │───▶│  NAT/SNAT   │──────▶│8.8.8.8   │
│              │    │             │       │          │
└──────────────┘    └─────────────┘       └──────────┘
                    192.168.1.100

Outgoing packet transformation:
┌─────────────────────────────────────────────┐
│ Before NAT (leaving container):             │
│ SRC: 172.17.0.2:45678                       │
│ DST: 8.8.8.8:53                             │
├─────────────────────────────────────────────┤
│ After NAT (leaving host):                   │
│ SRC: 192.168.1.100:35000 ← Changed!         │
│ DST: 8.8.8.8:53                             │
└─────────────────────────────────────────────┘

Host maintains NAT translation table:
┌────────────────────┬─────────────────────┐
│ Internal           │ External            │
├────────────────────┼─────────────────────┤
│ 172.17.0.2:45678   │ 192.168.1.100:35000 │
│ 172.17.0.3:52341   │ 192.168.1.100:35001 │
│ 172.17.0.2:45679   │ 192.168.1.100:35002 │
└────────────────────┴─────────────────────┘

Return packet:
┌─────────────────────────────────────────────┐
│ Before NAT (entering host):                 │
│ SRC: 8.8.8.8:53                             │
│ DST: 192.168.1.100:35000                    │
├─────────────────────────────────────────────┤
│ After NAT (forwarded to container):         │
│ SRC: 8.8.8.8:53                             │
│ DST: 172.17.0.2:45678 ← Changed back!       │
└─────────────────────────────────────────────┘


Destination NAT (DNAT):
Changes destination IP of incoming packets (Port forwarding)

Internet            Host                 Container
                (Public IP)          (Private IP)
┌──────────┐    ┌─────────────┐     ┌──────────────┐
│  Client  │───▶│  DNAT       │────▶│  Web Server  │
│          │    │  (iptables) │     │  172.17.0.2  │
└──────────┘    └─────────────┘     └──────────────┘
              192.168.1.100:8080    :80

Incoming packet transformation:
┌─────────────────────────────────────────────┐
│ Before DNAT (arriving at host):             │
│ SRC: 203.0.113.50:52341                     │
│ DST: 192.168.1.100:8080                     │
├─────────────────────────────────────────────┤
│ After DNAT (forwarded to container):        │
│ SRC: 203.0.113.50:52341                     │
│ DST: 172.17.0.2:80 ← Port mapped!           │
└─────────────────────────────────────────────┘
```

### Implementing NAT with iptables

```bash
# First, let's create a container network with NAT
# Create namespace
sudo ip netns add webserver

# Create veth pair
sudo ip link add veth0 type veth peer name veth0-br

# Create and configure bridge
sudo ip link add br0 type bridge
sudo ip addr add 172.18.0.1/16 dev br0
sudo ip link set br0 up

# Connect veth to bridge
sudo ip link set veth0-br master br0
sudo ip link set veth0-br up

# Move veth into namespace and configure
sudo ip link set veth0 netns webserver
sudo ip netns exec webserver ip addr add 172.18.0.2/16 dev veth0
sudo ip netns exec webserver ip link set veth0 up
sudo ip netns exec webserver ip link set lo up
sudo ip netns exec webserver ip route add default via 172.18.0.1

# At this point, container cannot reach internet
# Test (will fail):
sudo ip netns exec webserver ping -c 2 8.8.8.8
# No response - packets have no route back

# Enable IP forwarding on host (required for NAT)
sudo sysctl -w net.ipv4.ip_forward=1
# Or permanently: echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf

# View current value
sysctl net.ipv4.ip_forward

# Add MASQUERADE rule (SNAT for outgoing packets)
# This tells the host to replace container IPs with host IP
sudo iptables -t nat -A POSTROUTING -s 172.18.0.0/16 ! -o br0 -j MASQUERADE

# Explanation of the rule:
# -t nat                    : Use NAT table
# -A POSTROUTING            : Append to POSTROUTING chain (after routing decision)
# -s 172.18.0.0/16          : Match packets from container network
# ! -o br0                  : NOT going out the bridge (going to internet)
# -j MASQUERADE             : Use MASQUERADE (dynamic SNAT)

# Now test internet connectivity
sudo ip netns exec webserver ping -c 3 8.8.8.8
# Success! Packets are NAT'd

# Test DNS
sudo ip netns exec webserver ping -c 2 google.com
# Works if DNS is configured

# View NAT table
sudo iptables -t nat -L -n -v

# View active connections and NAT translations
sudo conntrack -L | grep 172.18.0.2
```

### Port Forwarding (DNAT) Example

```bash
# Start a web server in the container
sudo ip netns exec webserver python3 -c "
from http.server import HTTPServer, SimpleHTTPRequestHandler
import os
os.chdir('/')
HTTPServer(('0.0.0.0', 80), SimpleHTTPRequestHandler).serve_forever()
" &

WEBSERVER_PID=$!

# At this point, web server is only accessible from bridge network
# Test from host:
curl http://172.18.0.2:80
# Works

# But external clients cannot reach it
# Let's add port forwarding: host:8080 → container:80

# Add DNAT rule (PREROUTING - before routing decision)
sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 172.18.0.2:80

# Also need to allow forwarding in FILTER table
sudo iptables -A FORWARD -p tcp -d 172.18.0.2 --dport 80 -j ACCEPT
sudo iptables -A FORWARD -p tcp -s 172.18.0.2 --sport 80 -j ACCEPT

# Now external clients can access via host IP on port 8080
# Test from host (simulating external client)
curl http://localhost:8080
# Works! Request is forwarded to container

# View the NAT rule
sudo iptables -t nat -L PREROUTING -n -v --line-numbers

# Cleanup
sudo kill $WEBSERVER_PID
```

### Complete NAT Packet Flow

```
┌─────────────────────────────────────────────────────────────┐
│          COMPLETE NAT PACKET FLOW                           │
└─────────────────────────────────────────────────────────────┘

Scenario: Container accesses external website

Container NS              Host System                  Internet
┌──────────────┐         ┌────────────────┐         ┌──────────┐
│              │         │                │         │          │
│  Application │         │   iptables     │         │  Website │
│  (curl)      │         │   NAT Engine   │         │          │
│              │         │                │         │          │
│  172.18.0.2  │         │ 192.168.1.100  │         │8.8.8.8   │
└──────┬───────┘         └────────┬───────┘         └────┬─────┘
       │                          │                      │
       │ 1. SRC: 172.18.0.2:5000  │                      │
       │    DST: 8.8.8.8:80       │                      │
       └─────────────────────────▶│                      │
                                  │                      │
                                  │ 2. iptables NAT      │
                                  │    POSTROUTING       │
                                  │    MASQUERADE        │
                                  │                      │
                                  │ 3. SRC: 192.168.1.100:35000
                                  │    DST: 8.8.8.8:80   │
                                  └─────────────────────▶│
                                                         │
                                  ┌──────────────────────┘
                                  │ 4. Response
                                  │ SRC: 8.8.8.8:80
                                  │ DST: 192.168.1.100:35000
       ┌──────────────────────────┘
       │                          │ 5. iptables NAT
       │ 6. SRC: 8.8.8.8:80       │    conntrack lookup
       │    DST: 172.18.0.2:5000  │    reverse translation
       │◀─────────────────────────┘
       │
       ▼
   Application receives response

Connection Tracking Table (conntrack):
┌────────────────────────────────────────────────────────────┐
│ Protocol │ Internal           │ External               │ST│
├──────────┼────────────────────┼────────────────────────┼──┤
│ TCP      │ 172.18.0.2:5000    │ 192.168.1.100:35000    │ES│
│          │                    │ → 8.8.8.8:80           │TA│
│          │                    │                        │ B │
└──────────┴────────────────────┴────────────────────────┴──┘
(ESTAB = Established connection)
```

---

## iptables and Packet Filtering

iptables is the Linux firewall that controls packet filtering, NAT, and packet mangling.

### iptables Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  IPTABLES TABLES & CHAINS                   │
└─────────────────────────────────────────────────────────────┘

                        ┌───────────────┐
                        │   Network     │
                        │   Packet      │
                        └───────┬───────┘
                                │
                                ↓
                    ┌───────────────────────┐
                    │   PREROUTING Chain    │
                    │  (nat, mangle, raw)   │
                    │  - DNAT happens here  │
                    └───────────┬───────────┘
                                │
                        Routing Decision
                                │
                    ┌───────────┴───────────┐
                    │                       │
         ┌──────────▼──────────┐   ┌────────▼────────┐
         │  INPUT Chain        │   │ FORWARD Chain   │
         │  (filter, nat)      │   │ (filter)        │
         │  - For local        │   │ - For routed    │
         │    delivery         │   │   packets       │
         └──────────┬──────────┘   └────────┬────────┘
                    │                       │
              Local Process            Routing
                    │                       │
         ┌──────────▼──────────┐   ┌────────▼────────┐
         │  OUTPUT Chain       │   │ POSTROUTING     │
         │  (filter, nat)      │   │ (nat, mangle)   │
         │  - From local       │   │ - SNAT/         │
         │    process          │   │   MASQUERADE    │
         └──────────┬──────────┘   └────────┬────────┘
                    │                       │
                    └───────────┬───────────┘
                                │
                                ↓
                        ┌───────────────┐
                        │   Network     │
                        └───────────────┘


Tables (in order of packet traversal):
1. raw    - Connection tracking exemptions
2. mangle - Packet alteration (TOS, TTL, etc.)
3. nat    - Network Address Translation
4. filter - Packet filtering (ACCEPT/DROP)


Common Chains:
- PREROUTING:  Before routing (DNAT, port forwarding)
- INPUT:       Packets destined for local system
- FORWARD:     Packets being routed through system
- OUTPUT:      Packets originating from local system
- POSTROUTING: After routing (SNAT, MASQUERADE)
```

### iptables Rules for Container Networking

```bash
# View all iptables rules
sudo iptables -L -n -v

# View NAT rules specifically
sudo iptables -t nat -L -n -v

# View rules with line numbers
sudo iptables -L --line-numbers

# EXAMPLE 1: Allow container to access specific port on host
# Allow container to access host's SSH (port 22)
sudo iptables -A INPUT -s 172.18.0.0/16 -p tcp --dport 22 -j ACCEPT

# EXAMPLE 2: Block container from accessing specific network
# Block container from accessing internal network 10.0.0.0/8
sudo iptables -A FORWARD -s 172.18.0.0/16 -d 10.0.0.0/8 -j DROP

# EXAMPLE 3: Rate limiting
# Limit container to 100 connections per minute to prevent DoS
sudo iptables -A FORWARD -s 172.18.0.0/16 -m limit --limit 100/minute -j ACCEPT
sudo iptables -A FORWARD -s 172.18.0.0/16 -j DROP

# EXAMPLE 4: Logging dropped packets
# Log packets that are about to be dropped
sudo iptables -A FORWARD -s 172.18.0.0/16 -j LOG --log-prefix "Container-Traffic: "

# EXAMPLE 5: Allow only specific protocols
# Allow only HTTP(S) and DNS from container
sudo iptables -A FORWARD -s 172.18.0.0/16 -p tcp --dport 80 -j ACCEPT
sudo iptables -A FORWARD -s 172.18.0.0/16 -p tcp --dport 443 -j ACCEPT
sudo iptables -A FORWARD -s 172.18.0.0/16 -p udp --dport 53 -j ACCEPT
sudo iptables -A FORWARD -s 172.18.0.0/16 -j DROP

# Delete a specific rule (by line number)
sudo iptables -D FORWARD 3  # Deletes 3rd rule in FORWARD chain

# Delete a specific rule (by specification)
sudo iptables -D INPUT -s 172.18.0.0/16 -p tcp --dport 22 -j ACCEPT

# Flush all rules in a chain
sudo iptables -F FORWARD

# Flush all rules in all chains
sudo iptables -F
sudo iptables -t nat -F

# Save iptables rules (persistence)
sudo iptables-save > /etc/iptables/rules.v4
# Or on some systems:
sudo service iptables save
```

### Docker's iptables Rules

```bash
# When Docker is running, view its iptables rules
sudo iptables -t nat -L DOCKER -n -v
sudo iptables -t filter -L DOCKER -n -v

# Docker creates custom chains:
# - DOCKER (filter table): Container isolation
# - DOCKER (nat table): Port publishing
# - DOCKER-ISOLATION: Inter-network isolation
# - DOCKER-USER: User-defined rules

# Example of Docker-created rules:
# Port publishing: -p 8080:80
# Creates DNAT rule:
# -A DOCKER ! -i docker0 -p tcp -m tcp --dport 8080 -j DNAT --to-destination 172.17.0.2:80

# Container internet access:
# -A POSTROUTING -s 172.17.0.0/16 ! -o docker0 -j MASQUERADE
```

---

## Container Network Models

### Bridge Network (Default)

```
┌─────────────────────────────────────────────────────────────┐
│               DOCKER BRIDGE NETWORK MODEL                   │
└─────────────────────────────────────────────────────────────┘

Host Machine
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  ┌────────────┐    ┌────────────┐    ┌────────────┐        │
│  │Container 1 │    │Container 2 │    │Container 3 │        │
│  │172.17.0.2  │    │172.17.0.3  │    │172.17.0.4  │        │
│  │            │    │            │    │            │        │
│  │  eth0      │    │  eth0      │    │  eth0      │        │
│  └─────┬──────┘    └─────┬──────┘    └─────┬──────┘        │
│        │veth_xxx         │veth_yyy         │veth_zzz       │
│        └─────────┬───────┴─────────┬───────┘               │
│                  │                 │                        │
│            ┌─────┴─────────────────┴─────┐                 │
│            │      docker0 bridge          │                 │
│            │      172.17.0.1/16           │                 │
│            └──────────────┬───────────────┘                 │
│                           │                                 │
│                    iptables NAT                              │
│                           │                                 │
│                  ┌────────┴────────┐                        │
│                  │  eth0 (host)    │                        │
│                  │  192.168.1.100  │                        │
│                  └────────┬────────┘                        │
└───────────────────────────┼─────────────────────────────────┘
                            │
                        Internet


Characteristics:
- Containers on same bridge can communicate directly
- Containers have private IPs (172.17.0.0/16)
- NAT provides internet access
- Port publishing for external access
- Default Docker network mode
```

### Creating Custom Bridge Network

```bash
# Create custom bridge network
docker network create \
  --driver bridge \
  --subnet 172.20.0.0/16 \
  --gateway 172.20.0.1 \
  --opt "com.docker.network.bridge.name=br-custom" \
  my-network

# Inspect the network
docker network inspect my-network

# This creates:
# 1. A new bridge interface (br-custom)
ip link show br-custom

# 2. iptables rules for the network
sudo iptables -t nat -L -n -v | grep 172.20.0.0

# Run containers on custom network
docker run -d --name web1 --network my-network nginx
docker run -d --name web2 --network my-network nginx

# Containers can reach each other by name (DNS)
docker exec web1 ping web2

# Containers can also reach by IP
docker exec web1 ping 172.20.0.3

# View network connections
docker network inspect my-network

# Behind the scenes (equivalent commands):
# Bridge creation
sudo ip link add br-custom type bridge
sudo ip addr add 172.20.0.1/16 dev br-custom
sudo ip link set br-custom up

# For each container:
# - Create veth pair
# - Attach one end to bridge
# - Move other end to container namespace
# - Configure IP and routing
```

### Host Network Mode

```
┌─────────────────────────────────────────────────────────────┐
│                 HOST NETWORK MODE                           │
└─────────────────────────────────────────────────────────────┘

Container shares host's network namespace directly

Host Network Stack
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  ┌──────────────────────────────────────────┐               │
│  │         Container Process                │               │
│  │  (No network isolation!)                 │               │
│  │  Shares all host network interfaces      │               │
│  └──────────────────────────────────────────┘               │
│                                                              │
│  Network Interfaces:                                         │
│  ├── lo (127.0.0.1)                                          │
│  ├── eth0 (192.168.1.100)                                    │
│  └── docker0 (172.17.0.1)                                    │
│                                                              │
│  Ports used by container directly bind to host              │
│  Container listening on port 80 = Host:80                    │
│                                                              │
└──────────────────────────────────────────────────────────────┘

Use cases:
- Maximum network performance (no veth overhead)
- Need to bind to host interfaces directly
- Network tools that need raw access
- Not recommended for isolation/security
```

```bash
# Run container with host networking
docker run --network host nginx

# Container's nginx listens on host's port 80 directly
# Access via: http://localhost:80

# View processes and network
# From host:
ss -tlnp | grep 80
# Shows nginx process with host PID

# No veth pairs created
ip link | grep veth
# No results
```

### None Network Mode

```
┌─────────────────────────────────────────────────────────────┐
│                  NONE NETWORK MODE                          │
└─────────────────────────────────────────────────────────────┘

Container has no network connectivity

Container Network Namespace
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  ┌──────────────────────────────────────────┐               │
│  │         Container Process                │               │
│  │  (Completely isolated)                   │               │
│  └──────────────────────────────────────────┘               │
│                                                              │
│  Network Interfaces:                                         │
│  └── lo (127.0.0.1) only                                     │
│                                                              │
│  No external connectivity                                    │
│  Can only communicate with itself                            │
│                                                              │
└──────────────────────────────────────────────────────────────┘

Use cases:
- Maximum isolation
- Containers that don't need network
- Custom network configuration (add manually)
- Testing/development
```

```bash
# Run container with no network
docker run --network none alpine

# Inside container:
docker exec <container> ip addr
# Only shows loopback (lo)

docker exec <container> ping 8.8.8.8
# Fails - no network connectivity
```

### Container Network Mode

```
┌─────────────────────────────────────────────────────────────┐
│            CONTAINER NETWORK MODE (Shared)                  │
└─────────────────────────────────────────────────────────────┘

Multiple containers share same network namespace

Shared Network Namespace
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  ┌─────────────────────┐      ┌─────────────────────┐       │
│  │   Container 1       │      │   Container 2       │       │
│  │   (nginx:80)        │      │   (app:3000)        │       │
│  └─────────────────────┘      └─────────────────────┘       │
│                                                              │
│  Shared Network Stack:                                       │
│  ├── eth0 (172.17.0.2)                                       │
│  └── lo (127.0.0.1)                                          │
│                                                              │
│  Containers communicate via localhost!                       │
│  curl localhost:80 from container2 reaches container1        │
│                                                              │
└──────────────────────────────────────────────────────────────┘

Use cases:
- Sidecar pattern (service mesh)
- Closely coupled containers
- Monitoring/logging containers
- Similar to Kubernetes pods
```

```bash
# Create first container with network
docker run -d --name app1 nginx

# Create second container sharing app1's network
docker run -d --name app2 --network container:app1 alpine sleep 3600

# From app2, access app1 via localhost
docker exec app2 wget -qO- localhost:80
# Works! Returns nginx default page

# Both containers see same network interfaces
docker exec app1 ip addr
docker exec app2 ip addr
# Identical output!
```

---

## Overlay Networks (VXLAN)

Overlay networks connect containers across multiple hosts using VXLAN (Virtual Extensible LAN).

### VXLAN Concepts

```
┌─────────────────────────────────────────────────────────────┐
│                      VXLAN OVERVIEW                         │
└─────────────────────────────────────────────────────────────┘

VXLAN = Virtual Extensible LAN
- Layer 2 over Layer 3 tunneling protocol
- Encapsulates Ethernet frames in UDP packets
- Enables container networking across hosts
- 24-bit VNI (VXLAN Network Identifier) = 16 million networks

Physical Network (Layer 3)
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  Host A (10.0.1.10)              Host B (10.0.1.20)          │
│  ┌─────────────────┐            ┌─────────────────┐         │
│  │ Container 1     │            │ Container 3     │         │
│  │ 192.168.1.10    │            │ 192.168.1.30    │         │
│  └────────┬────────┘            └────────┬────────┘         │
│           │                              │                  │
│      ┌────┴────┐                    ┌────┴────┐             │
│      │ Bridge  │                    │ Bridge  │             │
│      └────┬────┘                    └────┬────┘             │
│           │                              │                  │
│      ┌────┴────────┐              ┌──────┴────────┐         │
│      │ VXLAN Device│              │ VXLAN Device  │         │
│      │ vxlan100    │══════════════│ vxlan100      │         │
│      │ VNI: 100    │   Tunnel     │ VNI: 100      │         │
│      └────┬────────┘              └──────┬────────┘         │
│           │                              │                  │
│       eth0 (10.0.1.10)              eth0 (10.0.1.20)        │
│                                                              │
└──────────────────────────────────────────────────────────────┘
                              │
                    Physical Network
                   (10.0.1.0/24)
```

### VXLAN Packet Encapsulation

```
┌─────────────────────────────────────────────────────────────┐
│                VXLAN PACKET STRUCTURE                       │
└─────────────────────────────────────────────────────────────┘

Original Packet (Container 1 → Container 3):
┌────────────────────────────────────────────────────────┐
│ Ethernet Header (Container)                            │
│ SRC MAC: aa:bb:cc:00:00:01 (Container 1)               │
│ DST MAC: aa:bb:cc:00:00:03 (Container 3)               │
├────────────────────────────────────────────────────────┤
│ IP Header (Container)                                  │
│ SRC IP: 192.168.1.10                                   │
│ DST IP: 192.168.1.30                                   │
├────────────────────────────────────────────────────────┤
│ TCP/Application Data                                   │
└────────────────────────────────────────────────────────┘

After VXLAN Encapsulation:
┌────────────────────────────────────────────────────────┐
│ Outer Ethernet Header (Physical)                       │
│ SRC MAC: Host A eth0 MAC                               │
│ DST MAC: Host B eth0 MAC                               │
├────────────────────────────────────────────────────────┤
│ Outer IP Header (Physical)                             │
│ SRC IP: 10.0.1.10 (Host A)                             │
│ DST IP: 10.0.1.20 (Host B)                             │
├────────────────────────────────────────────────────────┤
│ Outer UDP Header                                       │
│ SRC Port: 54321 (ephemeral)                            │
│ DST Port: 4789 (VXLAN default)                         │
├────────────────────────────────────────────────────────┤
│ VXLAN Header                                           │
│ VNI: 100 (identifies virtual network)                  │
│ Flags: 0x08 (valid VNI)                                │
├────────────────────────────────────────────────────────┤
│ Original Packet (from above)                           │
│ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓ ↓                            │
└────────────────────────────────────────────────────────┘

The entire original packet is preserved and tunneled!
```

### Setting Up VXLAN Network

```bash
# This example creates a VXLAN network between two hosts
# Note: You need two physical/virtual machines to test this fully

# ===== ON HOST A (10.0.1.10) =====

# Create bridge
sudo ip link add br0 type bridge
sudo ip addr add 192.168.1.1/24 dev br0
sudo ip link set br0 up

# Create VXLAN device
sudo ip link add vxlan100 type vxlan \
  id 100 \
  remote 10.0.1.20 \
  dstport 4789 \
  dev eth0

# Explanation:
# id 100          : VNI (VXLAN Network Identifier)
# remote 10.0.1.20: Other host's IP address
# dstport 4789    : Standard VXLAN UDP port
# dev eth0        : Physical interface to use

# Attach VXLAN device to bridge
sudo ip link set vxlan100 master br0
sudo ip link set vxlan100 up

# Create container namespace
sudo ip netns add container1

# Create veth pair
sudo ip link add veth1 type veth peer name veth1-br

# Connect to bridge
sudo ip link set veth1-br master br0
sudo ip link set veth1-br up

# Move to container namespace
sudo ip link set veth1 netns container1
sudo ip netns exec container1 ip addr add 192.168.1.10/24 dev veth1
sudo ip netns exec container1 ip link set veth1 up
sudo ip netns exec container1 ip link set lo up

# ===== ON HOST B (10.0.1.20) =====

# Mirror the setup on Host B
sudo ip link add br0 type bridge
sudo ip addr add 192.168.1.1/24 dev br0
sudo ip link set br0 up

sudo ip link add vxlan100 type vxlan \
  id 100 \
  remote 10.0.1.10 \
  dstport 4789 \
  dev eth0

sudo ip link set vxlan100 master br0
sudo ip link set vxlan100 up

sudo ip netns add container3
sudo ip link add veth3 type veth peer name veth3-br
sudo ip link set veth3-br master br0
sudo ip link set veth3-br up

sudo ip link set veth3 netns container3
sudo ip netns exec container3 ip addr add 192.168.1.30/24 dev veth3
sudo ip netns exec container3 ip link set veth3 up
sudo ip netns exec container3 ip link set lo up

# ===== TEST CONNECTIVITY =====

# From Host A, container1:
sudo ip netns exec container1 ping -c 3 192.168.1.30
# Success! Packet travels through VXLAN tunnel

# Monitor VXLAN traffic on Host A:
sudo tcpdump -i eth0 -n port 4789
# You'll see UDP packets on port 4789 with VXLAN encapsulation

# View VXLAN forwarding database (MAC learning):
bridge fdb show dev vxlan100
# Shows learned MAC addresses and their tunnel endpoints
```

### VXLAN with Multicast

```bash
# Instead of static remote endpoints, use multicast for discovery

# On both hosts:
sudo ip link add vxlan100 type vxlan \
  id 100 \
  group 239.1.1.1 \
  dstport 4789 \
  dev eth0

# Explanation:
# group 239.1.1.1: Multicast group address
# All hosts in same VXLAN network join this group
# Automatic discovery of other endpoints

# The kernel automatically handles:
# - BUM traffic (Broadcast, Unknown unicast, Multicast)
# - MAC address learning
# - ARP resolution across hosts
```

### Docker Swarm Overlay Network

```bash
# Initialize Docker Swarm (creates overlay network capability)
docker swarm init

# Create overlay network
docker network create \
  --driver overlay \
  --subnet 10.20.0.0/16 \
  --attachable \
  my-overlay

# Inspect the overlay network
docker network inspect my-overlay

# Behind the scenes, Docker creates:
# 1. VXLAN device (VNI from network ID)
# 2. Bridge (br-<network-id>)
# 3. iptables rules
# 4. Encryption (optional, with --opt encrypted)

# Run containers on overlay network
docker run -d --name web1 --network my-overlay nginx
docker run -d --name web2 --network my-overlay nginx

# Containers can communicate across hosts!
# Even though they're on different physical machines

# View VXLAN interfaces
ip -d link show | grep vxlan
# Shows: vxlan interface with VNI

# View overlay network routing
docker exec web1 ip route
# 10.20.0.0/16 dev eth0 (overlay network)
```

---

## DNS in Container Networks

Container networks provide built-in DNS resolution for service discovery.

### Embedded DNS Server

```
┌─────────────────────────────────────────────────────────────┐
│              CONTAINER DNS ARCHITECTURE                     │
└─────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  Container                                                   │
│  ┌────────────────────────────────────────────────────┐     │
│  │ /etc/resolv.conf                                   │     │
│  │ nameserver 127.0.0.11  ← Docker's embedded DNS     │     │
│  │ options ndots:0                                    │     │
│  └────────────────────────────────────────────────────┘     │
│                           │                                  │
│                           ↓                                  │
│  ┌────────────────────────────────────────────────────┐     │
│  │ Docker Embedded DNS Server (127.0.0.11:53)         │     │
│  │                                                    │     │
│  │ Resolves:                                          │     │
│  │ - Container names → IPs                            │     │
│  │ - Service names → IPs (load balanced)              │     │
│  │ - Network aliases                                  │     │
│  │                                                    │     │
│  │ Falls back to:                                     │     │
│  │ - Host's DNS servers                               │     │
│  │ - For external domains                             │     │
│  └────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────┘

DNS Resolution Flow:
1. App queries "web-server"
2. Query sent to 127.0.0.11:53
3. Docker DNS looks up "web-server" in network
4. Returns IP (e.g., 172.20.0.3)
5. App connects to 172.20.0.3
```

### DNS Resolution Examples

```bash
# Create custom network with containers
docker network create my-net

docker run -d --name web --network my-net nginx
docker run -d --name db --network my-net postgres
docker run -it --name client --network my-net alpine sh

# Inside client container:
# Resolve container name to IP
nslookup web
# Returns IP address (e.g., 172.21.0.2)

ping web
# Works! DNS resolves to container IP

# View DNS configuration
cat /etc/resolv.conf
# nameserver 127.0.0.11
# options ndots:0

# Try external domain
nslookup google.com
# Also works - forwarded to host's DNS

# Docker maintains DNS mappings:
# web → 172.21.0.2
# db  → 172.21.0.3
# These are updated dynamically as containers start/stop
```

### Network Aliases

```bash
# Create container with multiple network aliases
docker run -d \
  --name api-server \
  --network my-net \
  --network-alias api \
  --network-alias backend \
  --network-alias api-v1 \
  nginx

# All these names resolve to same container:
docker run --rm --network my-net alpine nslookup api
docker run --rm --network my-net alpine nslookup backend
docker run --rm --network my-net alpine nslookup api-v1
# All return same IP!

# Useful for:
# - API versioning
# - Service migration
# - Load balancing
```

### Service Discovery and Load Balancing

```bash
# Create multiple containers with same alias (service name)
docker run -d --name web1 --network my-net --network-alias web nginx
docker run -d --name web2 --network my-net --network-alias web nginx
docker run -d --name web3 --network my-net --network-alias web nginx

# Query DNS for "web"
docker run --rm --network my-net alpine nslookup web

# Returns ALL IPs:
# Name:      web
# Address 1: 172.21.0.2
# Address 2: 172.21.0.3
# Address 3: 172.21.0.4

# Applications get round-robin DNS load balancing
for i in {1..6}; do
  docker run --rm --network my-net alpine wget -qO- http://web/ | grep title
done

# Requests distributed across web1, web2, web3
```

---

## Complete Working Examples

### Example 1: Multi-Tier Application

```bash
#!/bin/bash
# Complete setup for a 3-tier application
# Frontend → Backend → Database

# Create network
docker network create app-network

# Start database
docker run -d \
  --name database \
  --network app-network \
  -e POSTGRES_PASSWORD=secret \
  postgres:15

# Start backend API
docker run -d \
  --name backend \
  --network app-network \
  -e DATABASE_URL=postgresql://postgres:secret@database:5432/app \
  your-backend-api:latest

# Start frontend
docker run -d \
  --name frontend \
  --network app-network \
  -e API_URL=http://backend:8080 \
  -p 80:80 \
  your-frontend:latest

# Test connectivity
echo "Testing frontend → backend"
docker exec frontend curl -s http://backend:8080/health

echo "Testing backend → database"
docker exec backend pg_isready -h database -U postgres

# View network topology
docker network inspect app-network

# All DNS resolution automatic:
# - frontend can reach "backend"
# - backend can reach "database"
# - No hardcoded IPs needed!
```

### Example 2: Service Mesh with Envoy

```bash
#!/bin/bash
# Sidecar pattern: Application + Envoy proxy

# Create shared network namespace approach
docker run -d --name app-container alpine sleep infinity

# Add Envoy proxy sharing app's network
docker run -d \
  --name envoy-proxy \
  --network container:app-container \
  -v ./envoy.yaml:/etc/envoy/envoy.yaml \
  envoyproxy/envoy:v1.27-latest

# Both containers share same network stack:
# - Envoy listens on 0.0.0.0:8080
# - App accesses Envoy via localhost:8080
# - Envoy proxies to upstream services

# Benefits:
# - Service mesh capabilities
# - Traffic encryption
# - Observability
# - No application code changes
```

### Example 3: Custom Container Network from Scratch

```bash
#!/bin/bash
# Build a complete container network using only Linux primitives

set -e

echo "=== Creating Container Network from Scratch ==="

# Cleanup function
cleanup() {
    echo "Cleaning up..."
    sudo ip netns del web 2>/dev/null || true
    sudo ip netns del app 2>/dev/null || true
    sudo ip link del br-custom 2>/dev/null || true
    sudo iptables -t nat -D POSTROUTING -s 10.10.0.0/16 ! -o br-custom -j MASQUERADE 2>/dev/null || true
}

trap cleanup EXIT

# 1. Create bridge
echo "1. Creating bridge..."
sudo ip link add br-custom type bridge
sudo ip addr add 10.10.0.1/16 dev br-custom
sudo ip link set br-custom up

# 2. Create network namespaces (containers)
echo "2. Creating network namespaces..."
sudo ip netns add web
sudo ip netns add app

# 3. Create veth pairs
echo "3. Creating veth pairs..."
sudo ip link add veth-web type veth peer name veth-web-br
sudo ip link add veth-app type veth peer name veth-app-br

# 4. Attach veth to bridge
echo "4. Connecting to bridge..."
sudo ip link set veth-web-br master br-custom
sudo ip link set veth-app-br master br-custom
sudo ip link set veth-web-br up
sudo ip link set veth-app-br up

# 5. Move veth to namespaces
echo "5. Moving interfaces to namespaces..."
sudo ip link set veth-web netns web
sudo ip link set veth-app netns app

# 6. Configure container interfaces
echo "6. Configuring container interfaces..."
sudo ip netns exec web ip addr add 10.10.0.10/16 dev veth-web
sudo ip netns exec web ip link set veth-web up
sudo ip netns exec web ip link set lo up
sudo ip netns exec web ip route add default via 10.10.0.1

sudo ip netns exec app ip addr add 10.10.0.20/16 dev veth-app
sudo ip netns exec app ip link set veth-app up
sudo ip netns exec app ip link set lo up
sudo ip netns exec app ip route add default via 10.10.0.1

# 7. Enable IP forwarding
echo "7. Enabling IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

# 8. Setup NAT
echo "8. Setting up NAT..."
sudo iptables -t nat -A POSTROUTING -s 10.10.0.0/16 ! -o br-custom -j MASQUERADE

# 9. Start services in namespaces
echo "9. Starting services..."

# Web server in 'web' namespace
sudo ip netns exec web python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'Hello from WEB container!\n')
    def log_message(self, *args): pass
HTTPServer(('0.0.0.0', 80), Handler).serve_forever()
" &

WEB_PID=$!
sleep 2

# 10. Test connectivity
echo ""
echo "=== Testing Connectivity ==="

echo "Test 1: app → web (container to container)"
sudo ip netns exec app curl -s http://10.10.0.10
# Expected: Hello from WEB container!

echo "Test 2: web → internet (container to external)"
sudo ip netns exec web ping -c 2 8.8.8.8
# Expected: Successful ping

echo "Test 3: Bridge inspection"
echo "Connected interfaces:"
bridge link show br-custom

echo ""
echo "Test 4: Routing tables"
echo "Web container routes:"
sudo ip netns exec web ip route

echo ""
echo "App container routes:"
sudo ip netns exec app ip route

echo ""
echo "=== Network Setup Complete ==="
echo "Web server running at 10.10.0.10:80"
echo "Press Enter to cleanup..."
read

kill $WEB_PID 2>/dev/null || true
```

### Example 4: Network Debugging Tools

```bash
#!/bin/bash
# Comprehensive network debugging

# 1. Inspect container network interfaces
echo "=== Container Network Interfaces ==="
docker exec <container> ip addr show

# 2. View routing table
echo "=== Routing Table ==="
docker exec <container> ip route

# 3. Check DNS resolution
echo "=== DNS Resolution ==="
docker exec <container> nslookup google.com
docker exec <container> cat /etc/resolv.conf

# 4. Test connectivity
echo "=== Connectivity Tests ==="
docker exec <container> ping -c 3 8.8.8.8  # Internet
docker exec <container> ping -c 3 gateway  # Gateway
docker exec <container> ping -c 3 other-container  # Other container

# 5. Check listening ports
echo "=== Listening Ports ==="
docker exec <container> netstat -tlnp

# 6. Trace packet path
echo "=== Packet Trace ==="
docker exec <container> traceroute google.com

# 7. Monitor traffic
echo "=== Traffic Monitoring ==="
docker exec <container> tcpdump -i eth0 -c 10

# 8. View ARP table
echo "=== ARP Table ==="
docker exec <container> ip neigh show

# 9. Test specific port connectivity
echo "=== Port Connectivity ==="
docker exec <container> nc -zv other-container 80

# 10. Bandwidth test
echo "=== Bandwidth Test ==="
# Install iperf3 in containers first
docker exec server iperf3 -s &
docker exec client iperf3 -c server

# 11. View iptables rules affecting container
echo "=== iptables Rules ==="
sudo iptables -L -n -v | grep 172.17.0.2  # Replace with container IP

# 12. Check bridge state
echo "=== Bridge State ==="
bridge link show
bridge fdb show

# 13. Monitor connection tracking
echo "=== Connection Tracking ==="
sudo conntrack -L | grep 172.17.0.2

# 14. View network statistics
echo "=== Network Statistics ==="
docker stats <container> --no-stream
```

---

## Summary

This deep dive covered:

1. **Network Namespaces** - Complete network stack isolation per container
2. **veth Pairs** - Virtual ethernet cables connecting namespaces
3. **Linux Bridges** - Virtual switches for container interconnection
4. **NAT** - Enabling internet access via IP masquerading and port forwarding
5. **iptables** - Packet filtering, forwarding, and network security
6. **Network Models** - Bridge, host, none, and container modes
7. **VXLAN** - Overlay networks for multi-host container communication
8. **DNS** - Built-in service discovery and name resolution

All container networking is built on these Linux kernel primitives, whether using Docker, Kubernetes, or other container runtimes.
