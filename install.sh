#!/bin/bash
set -o noglob

if [[ "$EUID" -ne 0 ]]
  then printf "\nPlease run with sudo\n"
  exit
fi

ARCH=$(uname -m)

KMNT="k8s"
ARG_S="hsaukKt:m:"
ARG_H="USAGE: $(pwd)/$(basename $0) [-h]help [-s]server [-a]agent [-u]uninstall [-k]apply [-K]k3s [-t]token [-m]master_addr"
STORE_D="/mnt/storage"
MNTS_D="$(sudo lsblk | grep "$STORE_D")"

MNTK_DEV=$(sudo lsblk | grep -E "50G.*disk" | awk '{print $1}')
MNTK_D="$STORE_D/$KMNT"
CNT_D="$MNTK_D/containerd"
DATA_D="$MNTK_D/data"
L_DATA_D="$MNTK_D/local"
ARGO_D="$MNTK_D/argocd"

CNT_C="/etc/containerd/config.toml"
CNT_S="unix:///var/run/containerd/containerd.sock"
CNT_F="$CNT_C"

MNTL_DEV=$(sudo lsblk | grep -E "100G.*disk" | awk '{print $1}')
MNTL_D="/mnt/storage/longhorn" #69
LONG_D="$MNTL_D/data" #69

SERVER=false
AGENT=false
APPLY=false
UNINSTALL=false
K3S=true
HELP=false
INSTALL=false

G_URL="https://github.com/oonray/k8sCore"

BIN_DIR=/usr/local/bin
SYSTEMD_DIR=/etc/systemd/system

INET="$(ip a | grep 'inet ' | grep -v 127 | awk '{print $2}' | sed 's:[/.]: :g')"
EXT_NET=$( printf $INET | awk '{print $1 "." $2 "." $3 ".0/\n" $5}' )

TOKEN=""

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
MASTER=$( printf $INET | awk '{print $1 "." $2 "." $3 ".\n" $4}' )
fi

function help(){
    printf "\n%s\n" $ARG_H
    exit 2
}

function fix_name(){
    printf "\n$@\n" | sed -e 's/[][!#$%&()*;<=>?\_`{|}/[:space:]]//g;'
}

function mount(){
    if [ ! -d "$STORE_D" ]; then
        printf "\n$STORE_D not found! making it\n"
        sudo mkdir -p $STORE_D
    fi

    if [ -z $MNTS_D ]; then
        printf "\n$STORE_D has no disks mounted. mounting ...\n"

        if [ -z $MNTK_DEV ];then
            printf "\nNO 50G Disk found to mount at $MNTK_D\n"
            exit 1
        else
            local MNTK_DEV_P="/dev/${MNTK_DEV}1"
            local MNTK_UUID=$(sudo blkid $MNTK_DEV_P | awk '{print $2}')
            if [ -z $MNTK_UUID ]; then
                printf "\n$MNTL_DEV_P Not found\n"
                exit 1
            else
                if [ ! -z $(sudo grep -E "$MNTK_UUID") ]; then
                    sudo dd status=none oflag=append of=/etc/fstab <<EOF
$MNTK_UUID $MNTK_D  ext4 errors=remount-ro 0 1
EOF
                fi
            fi
        fi
        if [ -z $MNTL_DEV ];then
            printf "\nNO 100G Disk found to mount at $MNTL_D\n"
        else
            local MNTL_DEV_P="/dev/${MNTK_DEV}1"
            local MNTL_UUID=$(sudo blkid $MNTL_DEV_P | awk '{print $2}')
            if [ -z $MNTL_UUID ]; then
                printf "\n$MNTL_DEV_P Not found\n"
                exit 1
            else
                if [ ! -z $(sudo grep -E "$MNTL_UUID") ]; then
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

    printf "\nAdding folders\n"
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

function rmdirs(){
    printf "\nRemoving folders\n"
    if [ -d "$STORE_D" ]
    then
        sudo rm -rf $CNT_D
        sudo rm -rf $DATA_D
        sudo rm -rf $L_DATA_D
        sudo rm -rf $LONG_D #69
        if $SERVER
        then
            sudo rm -rf $ARGO_D
        fi
    fi
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

    sudo ls -lah $MNTK_D
    sudo ls -lah $MNTL_D
}


function server(){
    dirs
    if $KMNT; then
    server_k3s_install
    else
    server_k8s_install
    fi
}

function agent(){
    dirs
    if $KMNT; then
    agent_k3s_install
    else
    agent_k8s_install
    fi
}

function uninstall(){
    if $KMNT; then
    server_k3s_uninstall
    else
    server_k8s_uninstall
    fi
    rmdirs
}

function agent_k3s_install(){
    printf "\nInstalling agent\n"
    dirs
    curl -sfL "https://get.k3s.io" | sh -s - \
        agent --token $TOKEN --server https://$2:6443 --data-dir $DATA_D \
        --node-label type=agent \
        --node-label name=$(uname -n) \
        --node-label os=$(uname -s) \
        --node-label platform=$(uname -m)
}

function server_k3s_install(){
    printf "\nUSING k3s\n"
    curl -sfL "https://get.k3s.io" | sh -s - \
        server --data-dir $DATA_D\
        --secrets-encryption \
        --cluster-domain kube  \
        --default-local-storage-path $L_DATA_D \
        --node-label type=server \
        --node-label name=$(uname -n) \
        --node-label os=$(uname -s) \
        --node-label platform=$(uname -m) \
        --disable-cloud-controller
}


function server_k3s_uninstall(){
    k3s-killall.sh
    k3s-uninstall.sh
}

function install_containerd(){
    printf "\nInstalling containerd\n"
    sudo apt-get install -y containerd sudo \
         apt-transport-https ca-certificates curl gpg 

    containerd config default \
        | sudo dd status=none of=$CNT_C

    sed -i -e \
        's/SystemdCgroup = false/SystemdCgroup = true/g' \
        $CNT_C

    sed -i -e \
        's/registry.k8s.io\/pause:3.6/registry.k8s.io\/pause:3.9/g' \
        $CNT_C

    sudo systemctl daemon-reload
    sudo systemctl enable containerd
    sudo systemctl restart containerd
}

function uninstall_containerd(){
    printf "\nUnInstalling containerd\n"
    sudo systemctl stop containerd
    sudo systemctl disable containerd

    sudo apt-get purge -y containerd
    sudo rm -rf $CNT_C
}

function disable_apparmour(){
    printf "\nDisabeling apparmor\n"
    sudo systemctl stop apparmor
    sudo systemctl disable apparmor
    sudo systemctl daemon-reload
}

function set_forward(){
    if [ ! $(sudo sysctl net.ipv4.ip_forward | awk '{print $3}') ];
    then
        sudo dd status=none of=/etc/sysctl.d/forward.conf <<EOF
net.ipv4.ip_forward=1
net.netfilter.nf_conntrack_max=1048576
EOF
    else
        printf "\nnet.ipv4.ip_forward IS ENABLED\n"
    fi

    sudo dd status=none of=/etc/sysctl.d/kubernetes.conf<<EOF
net.ipv4.ip_forward = 1
net.netfilter.nf_conntrack_max=1048576
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

    sudo systemctl daemon-reload
}

function install_kubernetes(){
    printf "\nInstalling kubernetes\n"
    printf "\nAdding plugins\n"
    ARCH=$(uname -m)
    case $ARCH in
        armv7*) ARCH="arm";;
        aarch64) ARCH="arm64";;
        x86_64) ARCH="amd64";;
    esac

    sudo mkdir -p /opt/cni/bin
    sudo curl -o /tmp/cni-plugin.tgz -L https://github.com/containernetworking/plugins/releases/download/v1.7.1/cni-plugins-linux-$ARCH-v1.7.1.tgz
    sudo tar -C /opt/cni/bin -xzf /tmp/cni-plugin.tgz

    printf "\nAdding repo\n"
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

    printf "\nInstalling\n"
    sudo apt-get update \
        && apt-get install -y open-iscsi kubeadm kubectl kubelet \
            kubernetes-cni wget curl vim git dmsetup \
        && apt-mark hold kubelet kubeadm kubectl

    sudo systemctl enable iscsid \
        && systemctl start iscsid

    printf "\nAdding modules\n"
    sudo dd status=none of=/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

    sudo systemctl daemon-reload \
        && modprobe overlay \
        && modprobe br_netfilter 

    printf "\nEnabeling kubelet\n"
    sudo systemctl enable kubelet
    sudo kubeadm config images pull
}

function uninstall_kubernetes(){
    printf "\nUninstalling kubernetes\n"
    sudo kubeadm reset

    sudo apt-get purge -y --allow-change-held-packages \
            kubeadm kubectl kubelet \
            kubernetes-cni containerd \
         && apt-get autoremove -y \
         && apt-get clean -y
}

function reset_iptables(){
    printf "\nResetting iptables\n"
    sudo iptables -F \
        && iptables -X \
        && iptables -t nat -F \
        && iptables -t nat -X \
        && iptables -t raw -F \
        && iptables -t raw -X \
        && iptables -t mangle -F \
        && iptables -t mangle -X
}

function server_k8s_install(){
    printf "\nUSING k8s\n"

    disable_apparmour
    set_forward

    install_containerd

    sudo swapoff -a
    sudo systemctl daemon-reload

    install_kubernetes

    printf "\nCluster INIT\n"
    kubeadm init \
        --pod-network-cidr 10.244.0.0/16 \
        --service-cidr=10.243.0.0/16 \
        --apiserver-advertise-address=$MASTER
        #--control-plane-endpoint=$MASTER \ 
}

function server_k8s_uninstall(){
    printf "\nResetting kubeadm\n"

    uninstall_kubernetes
    uninstall_containerd

    reset_iptables

    printf "\nReloading\n"
    sudo systemctl daemon-reload
}

function agent_k8s_install(){
    printf "\nUSING k8s\n"

    disable_apparmour
    set_forward

    install_containerd

    sudo swapoff -a
    sudo systemctl daemon-reload

    install_kubernetes
}

#MAIN
while getopts "$ARG_S" opt; do
    case "$opt" in
        h) HELP=true ;;
        s) SERVER=true ;;
        a) AGENT=true ;;
        u) UNINSTALL=true ;;
        k) APPLY=true ;;
        I) INSTALL=true ;;
        K) KMNT="k3s";K3S=true ;;
        t) TOKEN=$OPTARG ;;
        m) MASTER=$OPTARG ;;
        *) HELP=true ;;
    esac
done

printf "\nKubernetes installer for Linux\n"
if $HELP
then
    help
    exit 0
fi

if $UNINSTALL
then
    printf "\nUninstalling Server\n"
    uninstall
    exit 0
fi

if (! $AGENT) && (! $SERVER) && (! $UNINSTALL) && (! $APPLY)
then
    printf "\nNO OPTIONS. Must be agent, server, apply or uninstall \n"
    help
    exit 2
fi

if $AGENT && $SERVER
then
    printf "\nCannot be both server and agent\n"
    help
    exit 2
fi

if $AGENT || $SERVER || $INSTALL
then
  sudo apt-get install -y util-linux \
      tmux jq yq neovim vim
fi

if $SERVER
then
    printf "\nInstalling Server\n"
    server
fi

if $AGENT
then
    printf "\nInstalling Agent\n"
    agent
fi

if $APPLY
then
    printf "\nConfiguring Server and Applying core features\n"
    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    #kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    #kubectl label nodes --all node.kubernetes.io/exclude-from-external-load-balancers-

    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    kubectl apply -f https://github.com/kubernetes-sigs/sig-windows-tools/releases/download/v0.1.6/kube-flannel-rbac.yml

    kubectl apply -f https://github.com/kubernetes-sigs/sig-windows-tools/releases/download/v0.1.6/flannel-overlay.yml

    kubectl apply -f https://raw.githubusercontent.com/oonray/k8sCore/refs/heads/main/traefik/traefik.yaml

    kubectl get configmap kube-proxy -n kube-system -o yaml | \
    sed -e "s/strictARP: false/strictARP: true/" | \
    kubectl apply -f - -n kube-system
fi

printf "\nNo more Tasks!\n"
