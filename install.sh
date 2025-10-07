#!/bin/bash
set -e
set -o noglob

CNT_D="/mnt/storage/k3s/containerd"
DATA_D="/mnt/storage/k3s/data"
L_DATA_D="/mnt/storage/k3s/local"
ARGO_D="/mnt/storage/k3s/argocd"
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

    sudo cat<<EOF | sudo tee $CNT_F
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

    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key \
        | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' \
        | sudo tee /etc/apt/sources.list.d/kubernetes.list

    sudo apt-get update
    sudo apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
    sudo systemctl enable --now kubelet

    kubeadm init --control-plane-endpoint=$MASTER_DNS \
        --apiserver-advertise-address=$MASTER \
        --node-name $(fix_name $SYSTEM_NAME) \
        --upload-certs

    kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    kubectl label nodes --all node.kubernetes.io/exclude-from-external-load-balancers-
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
