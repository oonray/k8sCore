param {
    [string]$startup='Automatic'
    [string]$status='Running'
    [string]$master=''
    [string]$token=''
    [bool]$ssh
    [bool]$kube
}

$url=@{
    containerd="https://raw.githubusercontent.com/kubernetes-sigs/sig-windows-tools/master/hostprocess/Install-Containerd.ps1",
    prepare="https://raw.githubusercontent.com/kubernetes-sigs/sig-windows-tools/master/hostprocess/PrepareNode.ps1"
}

if($ssh){
    Set-Service sshd -StartupType $startup -Status $status
    Set-Service ssh-agent -StartupType $startup -Status $running

    New-NetFirewallRule -Name sshd -DisplayName 'SSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
}

if($kube){
    iex (iwr -UseBasicParsing $url.containerd)
    iex (iwr -UseBasicParsing $url.prepare)

    if(![string]::IsNullOrEmpty($master)){
        if(![string]::IsNullOrEmpty($token)){
            kubeadm join --token $token $master:6443
        }
        else{
            Write-Host "Must Specify Token"
        }
    }
    else{
        Write-Host "Must Specify Master addr"
    }
}
