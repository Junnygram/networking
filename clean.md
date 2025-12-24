Below is a **clean, reusable Markdown file** you can save as
`linux-network-cleanup.md`.

It documents **exactly how to reset the system safely**, why each step exists, and how to verify the environment is clean before restarting the lab.

---

````md
# Linux Network Namespace Lab — Cleanup & Reset Guide

This document describes how to **fully clean and reset** a Linux system after working with:
- Network namespaces
- Linux bridges
- veth pairs
- iptables NAT and forwarding rules

Use this before **redoing the lab** or when the network state becomes inconsistent.

---

## 1. Remove the Bridge and Attached veth Interfaces

Bring the bridge down and delete it.

```bash
sudo ip link set br-app down
sudo ip link delete br-app
````

### Why

* Deleting the bridge automatically removes all attached `veth-*-br` interfaces
* Prevents orphaned virtual Ethernet devices

---

## 2. Delete All Network Namespaces

```bash
sudo ip netns delete nginx-lb
sudo ip netns delete api-gateway
sudo ip netns delete product-service
sudo ip netns delete order-service
sudo ip netns delete redis-cache
sudo ip netns delete postgres-db
```

### Verify

```bash
ip netns list
```

Expected output:

```
<empty>
```

---

## 3. Flush iptables Rules Added by the Lab

Flush NAT rules:

```bash
sudo iptables -t nat -F
```

Flush forwarding rules:

```bash
sudo iptables -F FORWARD
```

### Why

* Removes DNAT and MASQUERADE rules
* Restores default packet flow behavior

---

## 4. Disable IP Forwarding

```bash
sudo sysctl -w net.ipv4.ip_forward=0
```

### Verify

```bash
sysctl net.ipv4.ip_forward
```

Expected output:

```
net.ipv4.ip_forward = 0
```

---

## 5. Final System Verification (Must Be Clean)

Run all checks below. All outputs should be empty or default.

### Network namespaces

```bash
ip netns list
```

Expected:

```
<empty>
```

---

### Bridges

```bash
ip link show type bridge
```

Expected:

```
<empty>
```

---

### veth interfaces

```bash
ip link show | grep veth
```

Expected:

```
<no output>
```

---

### NAT table

```bash
sudo iptables -t nat -L -n
```

Expected:

```
Chain PREROUTING (policy ACCEPT)
Chain INPUT (policy ACCEPT)
Chain OUTPUT (policy ACCEPT)
Chain POSTROUTING (policy ACCEPT)
```

---

## Cleanup Confirmation

If all verification steps pass:

* No namespaces exist
* No bridges exist
* No veth interfaces exist
* No NAT or forwarding rules exist
* IP forwarding is disabled

> **The system is fully clean and safe to redo the assignment from the beginning.**

---

## Recommended Next Step

Proceed with:

* Namespace creation
* Bridge setup
* veth connections
* NAT configuration
* Port forwarding

as documented in the main lab guide.

---

End of cleanup guide.

```

