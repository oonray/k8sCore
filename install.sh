#!/bin/bash
set -e
set -o noglob

CNT_D="/mnt/storage/k8s/containerd"
DATA_D="/mnt/storage/k8s/data"
L_DATA_D="/mnt/storage/k8s/local"
ARGO_D="/mnt/storage/k8s/argocd"
LONG_D="/mnt/storage/longhorn/data" #69

SERVER=false
AGENT=false
APPLY=false
G_URL="https://github.com/oonray/k8sCore"

BIN_DIR=/usr/local/bin
SYSTEMD_DIR=/etc/systemd/system
ARCH=$(uname -m)

CNT_S="unix:///var/run/containerd/containerd.sock"
CNT_F="/etc/containerd/config.toml"

INET="$(ip a | grep 'inet ' | grep -v 127 | awk '{print $2}' | sed 's:[/.]: :g')"
EXT_NET=$( echo $INET | awk '{print $1 "." $2 "." $3 ".0/" $5}' )

#
# CAN be set by ENV
#
if [ ! -n $SYSTEM_NAME]; then
DNS_NAME="kube"
fi
if [ ! -n $SYSTEM_NAME]; then
SYSTEM_NAME=$(hostname)
fi
if [ ! -n $MASTER_DNS]; then
MASTER_DNS=${SYSTEM_NAME}.${DNS_NAME}
fi
if [ ! -n $MASTER]; then
MASTER=$( echo $INET | awk '{print $1 "." $2 "." $3 "." $4}' )
fi

#-------------------------
#FROM "https://get.k3s.io"
#-------------------------
info()
{
    echo '[INFO] ' "$@"
}
warn()
{
    echo '[WARN] ' "$@" >&2
}
fatal()
{
    echo '[ERROR] ' "$@" >&2
    exit 1
}
#-------------------------
#END
#-------------------------

function fix_name(){
    echo "$@" | sed -e 's/[][!#$%&()*;<=>?\_`{|}/[:space:]]//g;'
}

function dirs(){
    if [ -d "/mnt/storage" ]
    then
        sudo mkdir -p $CNT_D
        sudo mkdir -p $DATA_D
        sudo mkdir -p $L_DATA_D
        sudo mkdir -p $LONG_D #69
        if $SERVER
        then
            sudo mkdir -p $ARGO_D
        fi
    fi
}

function help(){
    echo "USAGE: $(pwd)/$(basename $0) [-h]help [-s]server [-w]worker [-t]token [-m]master_addr"
    exit 2
}

function agent(){
    echo "Installing agent"
    dirs
    curl -sfL "https://get.k3s.io" | sh -s - \
        agent --token $1 --server https://$2:6443 --data-dir $DATA_D \
        --node-label type=agent \
        --node-label name=$(uname -n) \
        --node-label os=$(uname -s) \
        --node-label platform=$(uname -m) 
}

function server(){
    echo "Installing server"
    dirs
    server_k8s
}

function server_k3s(){
    curl -sfL "https://get.k3s.io" | sh -s - \
        server --data-dir $DATA_D --secrets-encryption \
        --cluster-domain kube --default-local-storage-path $L_DATA_D \
        --node-label type=server \
        --node-label name=$(uname -n) \
        --node-label os=$(uname -s) \
        --node-label platform=$(uname -m)

}


function server_k8s(){
    sudo apt-get install -y containerd sudo \
         apt-transport-https ca-certificates curl gpg 

    containerd config default | sudo tee /etc/containerd/config.tom

    sudo tee $CNT_F <<EOF
version = 2

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    [plugins."io.containerd.grpc.v1.cri".cni]
      bin_dir = "/usr/lib/cni"
      conf_dir = "/etc/cni/net.d"
  [plugins."io.containerd.internal.v1.opt"]
    path = "$CNT_D" 
EOF

    sudo systemctl restart containerd
    sudo systemctl enable containerd

    FORWARD=$(grep -oE 'net.ipv4.ip_forward = 1' /etc/sysctl.conf)
    if [[ ! $FORWARD =~ 'net.ipv4.ip_forward = 1' ]];then
        sudo echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
        sudo sysctl -p
    fi

    sudo swapoff -a
    #sudo cat /etc/fstab > .fstab.bak
    #sudo cat /etc/fstab | sed "s:^UUID.*swap.*::" > .fstab.new
    #sudo cp .fstab.new /etc/fstab
    #sudo systemctl daemon-reload

    if [ ! -s "/etc/apt/keyrings/kubernetes-apt-keyring.gpg" ];then
        curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key \
            | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    fi

    if [ ! -s "/etc/apt/sources.list.d/kubernetes.list" ];then
        echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' \
            | sudo tee /etc/apt/sources.list.d/kubernetes.list
    fi

    ARCH=$(uname -m)
    case $ARCH in
        armv7*) ARCH="arm";;
        aarch64) ARCH="arm64";;
        x86_64) ARCH="amd64";;
    esac
    mkdir -p /opt/cni/bin
    curl -o /tmp/cni-plugin.tgz -L https://github.com/containernetworking/plugins/releases/download/v1.7.1/cni-plugins-linux-$ARCH-v1.7.1.tgz
    tar -C /opt/cni/bin -xzf /tmp/cni-plugin.tgz

    sudo apt-get update
    sudo apt-get install -y kubelet kubeadm kubectl wget curl vim git
    sudo apt-mark hold kubelet kubeadm kubectl

    sudo tee /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

    sudo modprobe overlay
    sudo modprobe br_netfilter

    sudo tee /etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

    sudo systemctl enable kubelet
    sudo kubeadm config images pull

    kubeadm init --pod-network-cidr 10.244.0.0/16
        #--apiserver-advertise-address=$MASTER \
        #--node-ip $MASTER \
        #--control-plane-endpoint=$MASTER \

    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    kubectl label nodes --all node.kubernetes.io/exclude-from-external-load-balancers-

    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
}


while getopts "saht:k:m:" opt; do
    case "$opt" in
        m) MASTER=$OPTARG ;;
        t) TOKEN=$OPTARG ;;
        s) SERVER=true ;;
        a) AGENT=true ;;
        k) APPLY=true ;;
        h) ;&
        *) help;;
    esac
done
if $AGENT && $SERVER; then echo "Cannot be both server and agent"; help; fi
if $SERVER
then
    echo "Installing Server"
    server
    if $APPLY
    then 
        kubectl apply -k $G_URL
    fi
fi
if $AGENT
then
    echo "Installing Agent"
    if [ -z $TOKEN ]; then echo "Needs token"; help; fi
    if [ -z $MASTER ]; then echo "Needs master"; help; fi
    agent $TOKEN $MASTER
fi
