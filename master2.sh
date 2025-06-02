#!/bin/bash
set -e

# Set hostname
echo "-------------Setting hostname-------------"
hostnamectl set-hostname $1

# Disable swap
echo "-------------Disabling swap-------------"
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo "--------Enable IPv4 packet forwarding----"
#To manually enable IPv4 packet forwarding:
# sysctl params required by setup, params persist across reboots

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system
# Apply sysctl params without reboot

 
echo "-------------Installing Containerd-------------"
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
 sudo apt-get install containerd.io -y
 echo "Containerd installed Successfully"
 containerd config default > /etc/containerd/config.toml
 sed -i 's|registry.k8s.io/pause:3.8|registry.k8s.io/pause:3.10|' /etc/containerd/config.toml
 sed -i 's|SystemdCgroup = false|SystemdCgroup = true|' /etc/containerd/config.toml
 sudo systemctl restart containerd

echo "-------------installing kubeadm, kubelet, kubectl-------------"

sudo apt-get update
# apt-transport-https may be a dummy package; if so, you can skip that package
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

echo "Printing kubeadm , kubectl , kubelet versions"
kubeadm version
kubectl version --client
kubelet --version

echo "-------------Running Kubeadm init command-------------"
PRIVATE_IP=$(hostname -I | awk '{print $1}')
kubeadm init --apiserver-advertise-address=$PRIVATE_IP --pod-network-cidr=10.244.0.0/16 --cri-socket unix:///var/run/containerd/containerd.sock

echo "-------------Copying Kubeconfig-------------"
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config

REGULAR_USER="ubuntu" #Replace ubuntu with your actual regular username if different.
mkdir -p /home/${REGULAR_USER}/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/${REGULAR_USER}/.kube/config
sudo chown ${REGULAR_USER}:${REGULAR_USER} /home/${REGULAR_USER}/.kube/config


echo "-------------Deploying Weavenet Pod Networking-------------"
kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s-1.11.yaml
#use-- kubectl apply -f https://reweave.azurewebsites.net/k8s/v1.29/net.yaml 
#if you are facing any problem 

echo "-------------Creating file with join command-------------"
echo `kubeadm token create --print-join-command` > ./join-command.sh
