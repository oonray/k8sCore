#!/bin/bash
set -e
set -o noglob

if [ "$EUID" -ne 0 ]
  then echo "Please run with sudo"
  exit
fi

KMNT="k8s"
ARG_S='hsa3t:k:m'
ARG_H="USAGE: $(pwd)/$(basename $0) [-h]help [-s]server [-a]agent [-3]k3s [-t]token [-m]master_addr"

STORE_D="/mnt/storage"
MNTS_D="$(sudo lsblk | grep "$STORE_D")"

MNTL_DEV=$(sudo lsblk | grep -E "50G.*disk" | awk '{print $1}')
MNTK_D="$STORE_D/$KMNT" #69

CNT_D="$MNTK_D/containerd"
CNT_C="/etc/containerd/config.toml"

DATA_D="$MNTK_D/data"
L_DATA_D="$MNTK_D/local"
ARGO_D="$MNTK_D/argocd"

MNTL_DEV=$(sudo lsblk | grep -E "100G.*disk" | awk '{print $1}')
MNTL_D="/mnt/storage/longhorn" #69
LONG_D="$MNTL_D/longhorn/data" #69

SERVER=false
AGENT=false
APPLY=false
UNINSTALL=false
K3S=false

G_URL="https://github.com/oonray/k8sCore"

BIN_DIR=/usr/local/bin
SYSTEMD_DIR=/etc/systemd/system

CNT_S="unix:///var/run/containerd/containerd.sock"
CNT_F="/etc/containerd/config.toml"

ARCH=$(uname -m)
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

function mount(){
    if [! -d "$STORE_D" ]; then
        echo "$STORE_D not found! making it"
        sudo mkdir -p $STORE_D
    fi

    if [ -z $MNTS_D ]; then
        echo "$STORE_D has no disks mounted. mounting ..."

        if [ -z $MNTK_DEV ];then
            echo "NO 50G Disk found to mount at $MNTK_D"
            exit 1
        else
            local MNTK_DEV_P="/dev/${MNTK_DEV}1"
            local MNTK_UUID=$(sudo blkid $MNTK_DEV_P | awk '{print $2}')
            if [ -z $MNTK_UUID ]; then
                echo "$MNTL_DEV_P Not found"
                exit 1
            else
                if [! -z $(sudo grep -E "$MNTK_UUID")]; then
                    sudo dd status=none oflag=append of=/etc/fstab <<EOF
$MNTK_UUID $MNTK_D  ext4 errors=remount-ro 0 1
EOF
                fi
            fi
        fi
        if [ -z $MNTL_DEV ];then
            echo "NO 100G Disk found to mount at $MNTL_D"
            exit 1
        else
            local MNTL_DEV_P="/dev/${MNTK_DEV}1"
            local MNTL_UUID=$(sudo blkid $MNTL_DEV_P | awk '{print $2}')
            if [ -z $MNTL_UUID ]; then
                echo "$MNTL_DEV_P Not found"
                exit 1
            else
                if [! -z $(sudo grep -E "$MNTL_UUID")]; then
                    sudo dd status=none oflag=append of=/etc/fstab <<EOF
$MNTK_UUID $MNTK_D  ext4 errors=remount-ro 0 1
EOF
                fi
            fi
        fi
    fi
    sudo mount -a
}

function dirs(){
    mount

    if [ -d "$STORE_D" ]
    then
        sudo mkdir -p $CNT_D
        sudo mkdir -p $DATA_D
        sudo mkdir -p $L_DATA_D
        sudo mkdir -p $LONG_D #69
        if $SERVER
        then
            sudo mkdir -p $ARGO_D
        fi
    else
        mkdir -p "$STORE_D"
    fi
}

function help(){
    echo $ARG_H
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
    dirs
    server_k8s
}

function server_k3s(){
    echo "USING k3s"
    curl -sfL "https://get.k3s.io" | sh -s - \
        server --data-dir $DATA_D --secrets-encryption \
        --cluster-domain kube --default-local-storage-path $L_DATA_D \
        --node-label type=server \
        --node-label name=$(uname -n) \
        --node-label os=$(uname -s) \
        --node-label platform=$(uname -m)

}


function server_k8s(){
    echo "USING k8s"
    sudo apt-get install -y containerd sudo \
         apt-transport-https ca-certificates curl gpg 

    if [ ! $(sudo sysctl net.ipv4.ip_forward | awk '{print $3}') ];
    then
        sudo dd status=none of=/etc/sysctl.d/forward.conf <<EOF
net.ipv4.ip_forward=1
net.netfilter.nf_conntrack_max=1048576
EOF
    else
        echo "net.ipv4.ip_forward IS ENABLED"
    fi

    containerd config default \
        | sudo dd status=none of=$CNT_C

    sed -i -e \
        's/SystemdCgroup = false/SystemdCgroup = true/g' \
        $CNT_C

    sed -i -e \
        's/registry.k8s.io\/pause:3.6/registry.k8s.io\/pause:3.9/g' \
        $CNT_C

    sudo systemctl daemon-reload

    sudo dd status=none of=$CNT_F <<EOF
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

    sudo swapoff -a
    sudo systemctl daemon-reload

    sudo dd status=none of=/etc/sysctl.d/kubernetes.conf<<EOF
net.ipv4.ip_forward = 1
net.netfilter.nf_conntrack_max=1048576
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

    sudo systemctl daemon-reload


    echo "Adding plugins"
    ARCH=$(uname -m)
    case $ARCH in
        armv7*) ARCH="arm";;
        aarch64) ARCH="arm64";;
        x86_64) ARCH="amd64";;
    esac

    sudo mkdir -p /opt/cni/bin
    sudo curl -o /tmp/cni-plugin.tgz -L https://github.com/containernetworking/plugins/releases/download/v1.7.1/cni-plugins-linux-$ARCH-v1.7.1.tgz
    sudo tar -C /opt/cni/bin -xzf /tmp/cni-plugin.tgz

    echo "Installing kubernetes"
    if [ ! -s "/etc/apt/keyrings/kubernetes-apt-keyring.gpg" ];then
        curl -fsSL \
             https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key \
            | sudo gpg --dearmor \
            -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    fi

    if [ ! -s "/etc/apt/sources.list.d/kubernetes.list" ];then
        sudo dd status=none of=/etc/apt/sources.list.d/kubernetes.list << EOF
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /
EOF
    fi

    sudo systemctl daemon-reload
    sudo apt-get update \
        && apt-get install -y kubeadm kubectl kubelet \
            kubernetes-cni kube \
            wget curl vim git \
        && apt-mark hold kubelet kubeadm kubectl

    echo "Adding modules"
    sudo dd status=none of=/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

    sudo systemctl daemon-reload \
        && modprobe overlay \
        && modprobe br_netfilter 


    echo "Enabeling kubelet"
    sudo systemctl enable kubelet
    sudo kubeadm config images pull

    echo "Cluster INIT"
    kubeadm init --pod-network-cidr 10.244.0.0/16
        #--apiserver-advertise-address=$MASTER \
        #--node-ip $MASTER \
        #--control-plane-endpoint=$MASTER \

}

function server_k8s_uninstall(){
    echo "Resetting kubeadm"
    sudo kubeadm reset

    echo "Uninstalling kubernetes and containerd"
    sudo apt-get purge kubeadm kubectl kubelet kubernetes-cni kube containerd \
         && apt autoremove \
         && apt clean

    echo "Removing folders"
    sudo rm -rf ~/.kube \
        /etc/cni \
        /etc/kubernetes \
        /etc/apparmor.d/docker \
        /etc/systemd/system/etcd* \
        /var/lib/dockershim \
        /var/lib/etcd \
        /var/lib/kubelet \
        /var/lib/etcd2/ \
        /var/run/kubernetes

    echo "Resetting iptables"
    sudo iptables -F \
        && iptables -X \
        && iptables -t nat -F \
        && iptables -t nat -X \
        && iptables -t raw -F \
        && iptables -t raw -X \
        && iptables -t mangle -F \
        && iptables -t mangle -X

        echo "Reloading"
        sudo systemctl daemon-reload
}

function main(){
    echo "Kubernetes installer for Linux"

    while getopts "$ARG_S" opt; do
        case "$opt" in
            s) SERVER=true ;;
            a) AGENT=true ;;
            t) TOKEN=$OPTARG ;;
            3) KMNT="k3s";K3S=true ;;
            m) MASTER=$OPTARG ;;
            k) APPLY=true ;;
            u) UNINSTALL=true ;;
            h) ;&
            *) help;;
        esac
    done

    if $AGENT && $SERVER;
    then
        echo "Cannot be both server and agent"
        help
    fi

    if $SERVER
    then
        echo "Installing Server"
        server
    fi

    if $AGENT
    then
        echo "Installing Agent"
        if [ -z $TOKEN ]; then echo "Needs token"; help; fi
        if [ -z $MASTER ]; then echo "Needs master"; help; fi
        agent $TOKEN $MASTER
    fi

    if $APPLY
    then
        echo "Configuring Server and Applying core features"
        mkdir -p $HOME/.kube
        sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
        sudo chown $(id -u):$(id -g) $HOME/.kube/config

        kubectl taint nodes --all node-role.kubernetes.io/control-plane-
        kubectl label nodes --all node.kubernetes.io/exclude-from-external-load-balancers-

        kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
        kubectl apply -k $G_URL
    fi

    if $UNINSTALL
    then
        echo "Uninstalling Server"
        server_k8s_uninstall
    fi
}

main
