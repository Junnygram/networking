Below is a **clean, copy-paste ready Markdown (`.md`) file** you can save as something like
`linux-network-namespaces-lab.md`.

It includes:

* Full step-by-step setup
* The **root cause explanation** exactly as you requested
* The **short, safe naming convention** applied consistently

---

````md
# Linux Network Namespaces Lab

This lab simulates a microservices architecture using **Linux network namespaces**, a **Linux bridge**, and **veth pairs**, similar to how Docker and Kubernetes networking works internally.

---

## Task 1.1: Create Network Namespaces

Each namespace represents an isolated service with its own network stack.

```bash
sudo ip netns add nginx-lb
sudo ip netns add api-gateway
sudo ip netns add product-service
sudo ip netns add order-service
sudo ip netns add redis-cache
sudo ip netns add postgres-db
````

Verify:

```bash
ip netns list
```

---

## Task 1.2: Create a Virtual Bridge Network

The bridge acts as a **Layer 2 virtual switch** connecting all services.

```bash
sudo ip link add br-app type bridge
sudo ip addr add 10.0.0.1/16 dev br-app
sudo ip link set br-app up
```

* Bridge IP (`10.0.0.1`) acts as the default gateway
* Subnet: `10.0.0.0/16`

---

## Task 1.2: Connect Namespaces to the Bridge

Each namespace is connected using a **veth pair**:

* One end inside the namespace
* One end attached to the bridge

---

### Naming Convention (IMPORTANT)

To avoid kernel limitations, **short interface names are mandatory**.

| Service  | Namespace       | veth     | bridge veth |
| -------- | --------------- | -------- | ----------- |
| nginx    | nginx-lb        | veth-ng  | veth-ng-br  |
| api      | api-gateway     | veth-api | veth-api-br |
| product  | product-service | veth-pr  | veth-pr-br  |
| order    | order-service   | veth-or  | veth-or-br  |
| redis    | redis-cache     | veth-rd  | veth-rd-br  |
| postgres | postgres-db     | veth-pg  | veth-pg-br  |

---

### nginx-lb (10.0.0.10)

```bash
sudo ip link add veth-ng type veth peer name veth-ng-br
sudo ip link set veth-ng netns nginx-lb
sudo ip link set veth-ng-br master br-app
sudo ip link set veth-ng-br up

sudo ip netns exec nginx-lb ip addr add 10.0.0.10/16 dev veth-ng
sudo ip netns exec nginx-lb ip link set veth-ng up
sudo ip netns exec nginx-lb ip link set lo up
sudo ip netns exec nginx-lb ip route add default via 10.0.0.1
```

---

### api-gateway (10.0.0.20)

```bash
sudo ip link add veth-api type veth peer name veth-api-br
sudo ip link set veth-api netns api-gateway
sudo ip link set veth-api-br master br-app
sudo ip link set veth-api-br up

sudo ip netns exec api-gateway ip addr add 10.0.0.20/16 dev veth-api
sudo ip netns exec api-gateway ip link set veth-api up
sudo ip netns exec api-gateway ip link set lo up
sudo ip netns exec api-gateway ip route add default via 10.0.0.1
```

---

### product-service (10.0.0.30)

```bash
sudo ip link add veth-pr type veth peer name veth-pr-br
sudo ip link set veth-pr netns product-service
sudo ip link set veth-pr-br master br-app
sudo ip link set veth-pr-br up

sudo ip netns exec product-service ip addr add 10.0.0.30/16 dev veth-pr
sudo ip netns exec product-service ip link set veth-pr up
sudo ip netns exec product-service ip link set lo up
sudo ip netns exec product-service ip route add default via 10.0.0.1
```

---

### order-service (10.0.0.40)

```bash
sudo ip link add veth-or type veth peer name veth-or-br
sudo ip link set veth-or netns order-service
sudo ip link set veth-or-br master br-app
sudo ip link set veth-or-br up

sudo ip netns exec order-service ip addr add 10.0.0.40/16 dev veth-or
sudo ip netns exec order-service ip link set veth-or up
sudo ip netns exec order-service ip link set lo up
sudo ip netns exec order-service ip route add default via 10.0.0.1
```

---

### redis-cache (10.0.0.50)

```bash
sudo ip link add veth-rd type veth peer name veth-rd-br
sudo ip link set veth-rd netns redis-cache
sudo ip link set veth-rd-br master br-app
sudo ip link set veth-rd-br up

sudo ip netns exec redis-cache ip addr add 10.0.0.50/16 dev veth-rd
sudo ip netns exec redis-cache ip link set veth-rd up
sudo ip netns exec redis-cache ip link set lo up
sudo ip netns exec redis-cache ip route add default via 10.0.0.1
```

---

### postgres-db (10.0.0.60)

```bash
sudo ip link add veth-pg type veth peer name veth-pg-br
sudo ip link set veth-pg netns postgres-db
sudo ip link set veth-pg-br master br-app
sudo ip link set veth-pg-br up

sudo ip netns exec postgres-db ip addr add 10.0.0.60/16 dev veth-pg
sudo ip netns exec postgres-db ip link set veth-pg up
sudo ip netns exec postgres-db ip link set lo up
sudo ip netns exec postgres-db ip route add default via 10.0.0.1
```

---

## Connectivity Verification

```bash
sudo ip netns exec product-service ping -c 3 10.0.0.60
sudo ip netns exec redis-cache ping -c 3 10.0.0.10
```

---

## Root Cause (Very Important Lesson)

Linux network interface names are limited to **15 characters maximum**.

This limit comes from:

```
IFNAMSIZ = 16 bytes
```

* 15 characters for the name
* 1 byte for the null terminator

Example of an invalid name:

```
veth-postgres-br  (16 characters ❌)
```

Because the veth pair is **never created**, all subsequent commands fail with:

* `name not a valid ifname`
* `Cannot find device`
* `Invalid gateway`

### Solution

Always use **short, predictable interface names**, especially when automating or working at scale.

---

Yes — **that is exactly what it means** ✅
And your interpretation is **correct at a networking-fundamentals level**, not just “it works”.

Let’s break it down cleanly so you can **explain it confidently**.

---

## What This Command Means (Precisely)

```bash
sudo ip netns exec product-service ping -c 3 10.0.0.60
```

### Translation in plain English

> “From inside the **product-service network namespace**, send ICMP packets to the host with IP **10.0.0.60** (postgres-db).”

If this succeeds:

✔ `product-service` can reach `postgres-db`
✔ Layer 2 (bridge switching) works
✔ Layer 3 (IP routing) works
✔ veth pairs are correctly wired
✔ IP addressing is correct

---

## Second Command

```bash
sudo ip netns exec redis-cache ping -c 3 10.0.0.10
```

### Translation

> “From inside the **redis-cache namespace**, reach **nginx-lb**.”

If this succeeds:

✔ redis-cache → nginx-lb connectivity is established
✔ All namespaces are on the **same virtual L2 network**

---

## What This Proves About Your Architecture

### 1️⃣ All services share the same virtual LAN

Your bridge (`br-app`) is behaving like a **real Ethernet switch**.

```
br-app (10.0.0.1)
 ├── product-service (10.0.0.30)
 ├── postgres-db     (10.0.0.60)
 ├── redis-cache     (10.0.0.50)
 └── nginx-lb        (10.0.0.10)
```

---

### 2️⃣ There is no NAT involved here

Important detail:

* These pings **do NOT use iptables NAT**
* This is **pure L2 + L3 internal traffic**
* The bridge forwards frames based on **MAC learning**

NAT only matters when traffic leaves `10.0.0.0/16`.

---

### 3️⃣ This is identical to container networking

What you built is **structurally the same** as:

| Your Lab    | Docker / Kubernetes         |
| ----------- | --------------------------- |
| namespace   | container network namespace |
| veth pair   | container NIC               |
| bridge      | docker0 / CNI bridge        |
| 10.0.0.0/16 | pod CIDR                    |

You are effectively pinging:

* pod → pod
* service → service

---

## One-Sentence Explanation (Interview / Evaluation Gold)

> “Yes, it means the product-service namespace can directly reach postgres-db over the same Linux bridge, proving correct L2 switching, L3 addressing, and veth connectivity between isolated network namespaces.”

That sentence alone shows **deep understanding**.

---

## What This Does *Not* Mean (Also Important)

❌ It does **not** mean application traffic is allowed
❌ It does **not** enforce any security boundaries
❌ It does **not** imply firewall rules exist

Right now:

* Everything can talk to everything
* This is an **open flat network**

Later, you’d restrict this with:

* iptables rules
* eBPF
* Kubernetes NetworkPolicies

---

## Optional Extra Test (If You Want to Be 100% Sure)

```bash
sudo ip netns exec postgres-db ping -c 3 10.0.0.30
```

This confirms **bi-directional connectivity**.

---

## Summary

✔ Yes — product-service can reach postgres-db
✔ Yes — redis-cache can reach nginx-lb
✔ Your virtual network is working exactly as designed
✔ You’ve successfully built a real multi-service network











Let’s break it down cleanly so you can **explain it confidently**.

---

## What This Command Means (Precisely)

```bash
sudo ip netns exec product-service ping -c 3 10.0.0.60
```

### Translation in plain English

> “From inside the **product-service network namespace**, send ICMP packets to the host with IP **10.0.0.60** (postgres-db).”

If this succeeds:

✔ `product-service` can reach `postgres-db`
✔ Layer 2 (bridge switching) works
✔ Layer 3 (IP routing) works
✔ veth pairs are correctly wired
✔ IP addressing is correct

---

## Second Command

```bash
sudo ip netns exec redis-cache ping -c 3 10.0.0.10
```

### Translation

> “From inside the **redis-cache namespace**, reach **nginx-lb**.”

If this succeeds:

✔ redis-cache → nginx-lb connectivity is established
✔ All namespaces are on the **same virtual L2 network**

---

## What This Proves About Your Architecture

### 1️⃣ All services share the same virtual LAN

Your bridge (`br-app`) is behaving like a **real Ethernet switch**.

```
br-app (10.0.0.1)
 ├── product-service (10.0.0.30)
 ├── postgres-db     (10.0.0.60)
 ├── redis-cache     (10.0.0.50)
 └── nginx-lb        (10.0.0.10)
```

---

### 2️⃣ There is no NAT involved here

Important detail:

* These pings **do NOT use iptables NAT**
* This is **pure L2 + L3 internal traffic**
* The bridge forwards frames based on **MAC learning**

NAT only matters when traffic leaves `10.0.0.0/16`.

---

### 3️⃣ This is identical to container networking

What you built is **structurally the same** as:

| Your Lab    | Docker / Kubernetes         |
| ----------- | --------------------------- |
| namespace   | container network namespace |
| veth pair   | container NIC               |
| bridge      | docker0 / CNI bridge        |
| 10.0.0.0/16 | pod CIDR                    |

You are effectively pinging:

* pod → pod
* service → service

---

## One-Sentence Explanation (Interview / Evaluation Gold)

> “Yes, it means the product-service namespace can directly reach postgres-db over the same Linux bridge, proving correct L2 switching, L3 addressing, and veth connectivity between isolated network namespaces.”

That sentence alone shows **deep understanding**.

---

## What This Does *Not* Mean (Also Important)

❌ It does **not** mean application traffic is allowed
❌ It does **not** enforce any security boundaries
❌ It does **not** imply firewall rules exist

Right now:

* Everything can talk to everything
* This is an **open flat network**

Later, you’d restrict this with:

* iptables rules
* eBPF
* Kubernetes NetworkPolicies

---

## Optional Extra Test (If You Want to Be 100% Sure)

```bash
sudo ip netns exec postgres-db ping -c 3 10.0.0.30
```

This confirms **bi-directional connectivity**.











## 1️⃣ Internal Service-to-Service Connectivity (Completed)

### Command you ran

```bash
sudo ip netns exec postgres-db ping -c 3 10.0.0.20
```

### What this proves

* `postgres-db` can reach `api-gateway`
* All namespaces are connected via the same Linux bridge
* Traffic is **east–west**, not using NAT
* Bridge is correctly switching frames
* Routing tables inside namespaces are correct

✅ **Deliverable satisfied:**
“Proof of connectivity (ping tests between all namespaces)”

---

## 2️⃣ Enable IP Forwarding (Host Becomes a Router)

### Command

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

### What this does

* Tells the Linux kernel:

  > “I am allowed to forward packets between interfaces.”
* Without this, traffic **cannot leave** `br-app`
* Required for **internet access** from namespaces

📌 This is a **Layer 3 routing requirement**, not NAT yet.

---

## 3️⃣ Enable NAT (MASQUERADE)

### Command

```bash
sudo iptables -t nat -A POSTROUTING -s 10.0.0.0/16 ! -o br-app -j MASQUERADE
```

### What this does (very important)

* Rewrites source IP:

  ```
  10.0.0.x  →  host’s public IP
  ```
* Makes private IPs routable on the internet
* Hides internal topology from external networks

This is **exactly how containers access the internet**.

---

## 4️⃣ Internet Connectivity Test (Critical Deliverable)

### Command

```bash
sudo ip netns exec product-service ping -c 3 8.8.8.8
```

### What this proves

✔ `product-service` can access the internet
✔ IP forwarding is working
✔ NAT is working
✔ Default route via `10.0.0.1` is correct
✔ Host acts as a gateway

📸 **Screenshot requirement met:**
“Test internet connectivity from each namespace”

---

## 5️⃣ Port Forwarding (DNAT)

### Commands

```bash
sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 \
  -j DNAT --to-destination 10.0.0.10:80

sudo iptables -A FORWARD -p tcp -d 10.0.0.10 --dport 80 -j ACCEPT
```

---

## What Port Forwarding Achieves

### Traffic flow explanation

```
External Client
    |
Host:8080
    |
DNAT (PREROUTING)
    |
nginx-lb:80 (10.0.0.10)
```

### In simple terms

* Requests to **host port 8080**
* Are redirected to **nginx-lb port 80**
* The namespace never exposes a public IP
* This mimics:

  * Docker `-p 8080:80`
  * Kubernetes NodePort

---

## 6️⃣ iptables Rules Documentation (Final Deliverable)

### DNAT Rule

```bash
-t nat -A PREROUTING -p tcp --dport 8080 \
-j DNAT --to-destination 10.0.0.10:80
```

**Purpose**

* Redirect inbound traffic
* Expose internal service externally

---

### FORWARD Rule

```bash
-A FORWARD -p tcp -d 10.0.0.10 --dport 80 -j ACCEPT
```

**Purpose**

* Allows forwarded packets to reach nginx-lb
* Required because traffic crosses namespaces

---

### MASQUERADE Rule

```bash
-t nat -A POSTROUTING -s 10.0.0.0/16 ! -o br-app -j MASQUERADE
```

**Purpose**

* Enables outbound internet access
* Translates private IPs to host IP

---

## 7️⃣ Final Architecture (Conceptual)

```
Internet
   |
Host (iptables + NAT)
   |
br-app (10.0.0.1)
 |   |    |     |     |
ng  api  pr    or    rd    pg
```

---

## ✅ Assignment Status

| Task                 | Status |
| -------------------- | ------ |
| Namespaces created   | ✅      |
| Bridge configured    | ✅      |
| Inter-namespace ping | ✅      |
| Internet access      | ✅      |
| Port forwarding      | ✅      |
| iptables documented  | ✅      |

---

## 🧠 One-Line Summary You Can Use Anywhere

> “I built a multi-service virtual network using Linux namespaces, a bridge for L2 connectivity, NAT for outbound internet access, and DNAT to expose an internal load balancer—mirroring real container networking.”

That is **production-level Linux networking knowledge**.

---









# 🌐 Demo: Internet Access from Namespaces

## 1️⃣ Step 1 — Test Internet Access (Expected to Fail)

```bash
# Example with product-service
sudo ip netns exec product-service ping -c 3 google.com
```

**Expected Output:**

```
ping: google.com: Temporary failure in name resolution
```

**What to Explain:**

* The namespace can reach IPs (test with `ping 8.8.8.8`)
* But **domain names fail** because DNS is missing or points to `127.0.0.53` (systemd stub resolver)
* Systemd resolver **only works inside the host namespace**, not isolated network namespaces

✅ This shows the “problem” clearly to your audience.

---

## 2️⃣ Step 2 — Show `/etc/resolv.conf` Inside Namespace

```bash
sudo ip netns exec product-service cat /etc/resolv.conf
```

**Output:**

```
nameserver 127.0.0.53
options edns0 trust-ad
search ec2.internal
```

**Explain:**

* Stub resolver `127.0.0.53` is not usable inside namespaces
* This is why DNS fails

---

## 3️⃣ Step 3 — Fix DNS for All Namespaces

```bash
for ns in nginx-lb api-gateway product-service order-service redis-cache postgres-db; do
  sudo mkdir -p /etc/netns/$ns
  echo "nameserver 8.8.8.8" | sudo tee /etc/netns/$ns/resolv.conf
done
```

**Explain:**

* We add a **real public DNS** to each namespace
* `8.8.8.8` is Google DNS
* This allows all services to resolve domain names

---

## 4️⃣ Step 4 — Test Internet Access Again (Expected to Pass)

```bash
for ns in nginx-lb api-gateway product-service order-service redis-cache postgres-db; do
  echo "Testing $ns"
  sudo ip netns exec $ns ping -c 2 google.com
done
```

**Expected Output:**

```
64 bytes from google.com (...): icmp_seq=1 ttl=105 time=2.5 ms
64 bytes from google.com (...): icmp_seq=2 ttl=105 time=2.6 ms
```

**Explain:**

* DNS resolution works for all namespaces
* NAT and IP forwarding already allow traffic to the internet
* Now **all services have full internet access**, just like a container in Docker or Kubernetes

---

## 5️⃣ Optional: Verify Internet Access by IP

```bash
sudo ip netns exec product-service ping -c 3 8.8.8.8
```

* Confirms **NAT and routing** work even without DNS
* Can explain the difference between **IP connectivity** and **DNS resolution**

---

## ✅ Summary for Demo

1. Show the failure (`ping google.com` fails)
2. Explain why (`127.0.0.53` stub resolver doesn’t work)
3. Apply fix (add real nameserver)
4. Show success (`ping google.com` works)
5. Optional: show IP ping to confirm NAT

---



The ID in parentheses is an internal kernel namespace reference.

Linux assigns a unique numeric ID each time a namespace is created, starting from 0.