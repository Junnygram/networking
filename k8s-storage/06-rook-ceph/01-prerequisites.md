# Rook-Ceph Prerequisites

## Environment Setup

This guide covers setting up a proper environment for Rook-Ceph learning. Since KinD doesn't support the raw block devices Ceph needs, we'll use alternatives.

---

## Option 1: Vagrant + VirtualBox (Recommended for Learning)

### Install Dependencies

```bash
# macOS
brew install vagrant virtualbox

# Ubuntu/Debian
sudo apt-get install vagrant virtualbox
```

### Vagrantfile

Create a `Vagrantfile`:

```ruby
# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"

  # Common provisioning
  config.vm.provision "shell", inline: <<-SHELL
    apt-get update
    apt-get install -y docker.io
    systemctl enable docker
    systemctl start docker
  SHELL

  # Control plane node
  config.vm.define "control" do |control|
    control.vm.hostname = "control"
    control.vm.network "private_network", ip: "192.168.56.10"
    control.vm.provider "virtualbox" do |vb|
      vb.memory = "4096"
      vb.cpus = 2
    end
  end

  # Worker nodes with extra disks for Ceph
  (1..3).each do |i|
    config.vm.define "worker#{i}" do |worker|
      worker.vm.hostname = "worker#{i}"
      worker.vm.network "private_network", ip: "192.168.56.#{10 + i}"
      worker.vm.provider "virtualbox" do |vb|
        vb.memory = "4096"
        vb.cpus = 2

        # Add a second disk for Ceph OSD (20GB)
        disk_file = "./worker#{i}_disk.vdi"
        unless File.exist?(disk_file)
          vb.customize ['createhd', '--filename', disk_file, '--size', 20480]
        end
        vb.customize ['storageattach', :id, '--storagectl', 'SCSI',
                      '--port', 2, '--device', 0, '--type', 'hdd',
                      '--medium', disk_file]
      end
    end
  end
end
```

### Create VMs

```bash
vagrant up

# Verify disks exist on workers
vagrant ssh worker1 -c "lsblk"
# Should see /dev/sdc as a raw device
```

---

## Option 2: Cloud Environment (AWS)

### Terraform for AWS

```hcl
# main.tf
provider "aws" {
  region = "us-west-2"
}

resource "aws_instance" "k8s_node" {
  count         = 4  # 1 control + 3 workers
  ami           = "ami-0c55b159cbfafe1f0"  # Ubuntu 22.04
  instance_type = "t3.medium"

  tags = {
    Name = count.index == 0 ? "control" : "worker-${count.index}"
  }
}

# EBS volumes for Ceph (attach to workers only)
resource "aws_ebs_volume" "ceph_disk" {
  count             = 3
  availability_zone = aws_instance.k8s_node[count.index + 1].availability_zone
  size              = 50  # GB
  type              = "gp3"

  tags = {
    Name = "ceph-disk-${count.index + 1}"
  }
}

resource "aws_volume_attachment" "ceph_attach" {
  count       = 3
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.ceph_disk[count.index].id
  instance_id = aws_instance.k8s_node[count.index + 1].id
}
```

---

## Option 3: Minikube with Extra Disks

```bash
# Create minikube with extra disk space
minikube start \
  --nodes=3 \
  --cpus=2 \
  --memory=4096 \
  --disk-size=50g

# Note: Minikube still uses loopback, but some configurations work
# You may need to create loop devices manually
```

---

## Kubernetes Cluster Setup

After VMs are ready, install Kubernetes:

### Using kubeadm

```bash
# On all nodes
sudo apt-get update
sudo apt-get install -y apt-transport-https curl

# Add Kubernetes repo
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl containerd
sudo apt-mark hold kubelet kubeadm kubectl

# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Enable required modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Sysctl params
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

### Initialize Control Plane

```bash
# On control node
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# Save the join command for workers
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install CNI (Calico)
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
```

### Join Workers

```bash
# On each worker (use the join command from kubeadm init output)
sudo kubeadm join 192.168.56.10:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>
```

---

## Verify Raw Devices

Before installing Rook, verify each worker has raw devices:

```bash
# SSH to each worker
for i in 1 2 3; do
  echo "=== Worker $i ==="
  vagrant ssh worker$i -c "lsblk -f"
done
```

Expected output (device with no FSTYPE):
```
NAME   FSTYPE  MOUNTPOINT
sda
└─sda1 ext4    /
sdc             <- Raw device for Ceph!
```

---

## Next Steps

Once your environment is ready:
1. Return to the main README.md
2. Follow the Quick Start guide
3. Deploy Rook operator and Ceph cluster
