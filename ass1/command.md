# Assignment 1: Manual Network Setup Commands

This document provides the step-by-step commands to manually create the network infrastructure, as an alternative to running the `assignment1.sh` script.

---

## 1. Enable IP Forwarding

Allow the host machine to act as a router.
```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

## 2. Create the Network Bridge

This bridge will act as a virtual switch for all our services.
```bash
# Create the bridge
sudo ip link add br0 type bridge

# Assign an IP address to the bridge
sudo ip addr add 10.0.0.1/24 dev br0

# Bring the bridge interface up
sudo ip link set br0 up
```

## 3. Create Network Namespaces

Create an isolated network namespace for each service.
```bash
sudo ip netns add api-gateway
sudo ip netns add postgres-db
sudo ip netns add nginx-lb
sudo ip netns add order-service
sudo ip netns add product-service
sudo ip netns add redis-cache
```

Verify creation:
```bash
ip netns list
```

## 4. Create Veth Pairs and Connect Namespaces

For each namespace, you will create a virtual Ethernet (veth) pair to connect it to the bridge. Repeat these steps for each service, substituting the correct names and IP addresses.

### Example: Connecting `nginx-lb`

1.  **Create the veth pair:**
    ```bash
    sudo ip link add veth-lb type veth peer name veth-lb-br
    ```

2.  **Attach one end to the bridge:**
    ```bash
    sudo ip link set veth-lb-br master br0
    ```

3.  **Move the other end into the namespace:**
    ```bash
    sudo ip link set veth-lb netns nginx-lb
    ```

4.  **Configure the interface inside the namespace:**
    ```bash
    # Assign IP address
    sudo ip netns exec nginx-lb ip addr add 10.0.0.10/24 dev veth-lb

    # Bring up the interface
    sudo ip netns exec nginx-lb ip link set dev veth-lb up

    # Bring up the loopback interface
    sudo ip netns exec nginx-lb ip link set dev lo up
    ```

5.  **Add a default route inside the namespace:**
    ```bash
    sudo ip netns exec nginx-lb ip route add default via 10.0.0.1
    ```

6.  **Bring up the bridge-facing end of the veth pair:**
    ```bash
    sudo ip link set dev veth-lb-br up
    ```

---
**Repeat the process for all other services with their respective details:**

| Namespace         | Veth Name | Veth Bridge Name | IP Address   |
| ----------------- | --------- | ---------------- | ------------ |
| `api-gateway`     | `veth-api`  | `veth-api-br`    | `10.0.0.20/24` |
| `product-service` | `veth-prod` | `veth-prod-br`   | `10.0.0.30/24` |
| `order-service`   | `veth-ord`  | `veth-ord-br`    | `10.0.0.40/24` |
| `redis-cache`     | `veth-cache`| `veth-cache-br`  | `10.0.0.50/24` |
| `postgres-db`     | `veth-pg`   | `veth-pg-br`     | `10.0.0.60/24` |
---

## 5. Configure NAT for Internet Access

Set up `iptables` rules to allow traffic from the namespaces to reach the internet.

1.  **Find your host's default network interface:**
    ```bash
    # This command finds the interface used to route to Google's DNS
    DEFAULT_IFACE=$(ip route get 8.8.8.8 | awk -- '{printf $5}')
    echo "Default interface is: $DEFAULT_IFACE"
    ```

2.  **Add the NAT (Masquerade) rule:**
    This rule rewrites the source IP address of packets from your namespaces to your host's IP address.
    ```bash
    sudo iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o $DEFAULT_IFACE -j MASQUERADE
    ```

3.  **Add FORWARD rules:**
    These rules explicitly permit traffic to be forwarded to and from the bridge.
    ```bash
    sudo iptables -A FORWARD -i br0 -j ACCEPT
    sudo iptables -A FORWARD -o br0 -j ACCEPT
    ```

## 6. Verify Connectivity

1.  **Test intra-namespace connectivity:**
    ```bash
    sudo ip netns exec nginx-lb ping -c 2 10.0.0.20
    ```

2.  **Test internet connectivity (by IP):**
    ```bash
    sudo ip netns exec product-service ping -c 2 8.8.8.8
    ```

3.  **Test internet connectivity (by domain name):**
    This requires setting up DNS within the namespace.
    ```bash
    sudo ip netns exec product-service bash -c "echo 'nameserver 8.8.8.8' > /etc/resolv.conf && ping -c 2 google.com"
    ```

## 7. Cleanup

To tear down the manual setup, delete the bridge and the namespaces. The `iptables` rule will also need to be deleted.

```bash
# Delete the NAT rule
DEFAULT_IFACE=$(ip route get 8.8.8.8 | awk -- '{printf $5}')
sudo iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o $DEFAULT_IFACE -j MASQUERADE

# Delete the bridge
sudo ip link delete br0 type bridge

# Delete the namespaces
for ns in api-gateway postgres-db nginx-lb order-service product-service redis-cache; do
    sudo ip netns delete $ns
done
```
