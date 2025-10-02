#!/bin/bash
DATA_D="/opt/storage/k3s/data"
L_DATA_D="/opt/storage/k3s/local"
ARGO_D="/mnt/storage/k3s/argocd"
SERVER=false
AGENT=false
APPLY=false
G_URL="https://github.com/oonray/k8sCore"

function dirs(){
    if [ -d "/mnt/storage" ]
    then
        mkdir -p $DATA_D
        mkdir -p $L_DATA_D
        if $SERVER
        then
            mkdir -p $ARGO_D
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
    curl -sfL "https://get.k3s.io" | sh -s - \
        server --agent-token $1 --data-dir $DATA_D --secrets-encryption \
        --cluster-domain kube --default-local-storage-path $L_DATA_D \
        --node-label type=server \
        --node-label name=$(uname -n) \
        --node-label os=$(uname -s) \
        --node-label platform=$(uname -m)
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
    echo "Token: $TOKEN"
    if [ -z $TOKEN ]; then echo "Needs token"; help; fi
    server $TOKEN
    if $?
    then 
        kubectl apply -k $G_URL
    fi
fi
if $CLIENT
then
    echo "Installing Agent"
    echo "Token: $TOKEN"
    if [ -z $TOKEN ]; then echo "Needs token"; help; fi
    if [ -z $MASTER ]; then echo "Needs master"; help; fi
    agent $TOKEN $MASTER
fi
