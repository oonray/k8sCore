#!/bin/bash
DATA_D="/mnt/storage/k3s/data"
L_DATA_D="/mnt/storage/k3s/local"
ARGO_D="/mnt/storage/argocd"
SERVER=false
AGENT=false

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


while getopts "saht:m:" opt; do
    case "$opt" in
        m) MASTER=$OPTARG ;;
        t) TOKEN=$OPTARG ;;
        s) SERVER=true ;;
        a) AGENT=true ;;
        h) ;&
        *) help;;
    esac
done
if $AGENT && $SERVER; then echo "Cannot be both server and agent"; help; fi
if $SERVER
then
    if [ -z $TOKEN ]; then echo "Needs token"; help; fi
    server $TOKEN
fi
if $CLIENT
then
    if [ -z $TOKEN ]; then echo "Needs token"; help; fi
    if [ -z $MASTER ]; then echo "Needs master"; help; fi
    agent $TOKEN $MASTER
fi
