param (
    [string]$startup='Automatic',
    [string]$key='sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIGTCxFD2UzUYYWAuDnFzwMmeWsVkPZLNfObG3hJZ4GuKAAAABHNzaDo=',
    [string]$status='Running',
    [string]$master='',
    [string]$token='',
    [switch]$ssh,
    [switch]$kube
)

$config="$env:ProgramData\ssh\sshd_config"
$authorized_keys="$env:ProgramData\ssh\administrators_authorized_keys"

$SetPowershell = @{
    Path         = "HKLM:\SOFTWARE\OpenSSH"
    Name         = "DefaultShell"
    Value        = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    PropertyType = "String"
    Force        = $true
}

$url=@{
    containerd="https://raw.githubusercontent.com/kubernetes-sigs/sig-windows-tools/master/hostprocess/Install-Containerd.ps1"
    prepare="https://raw.githubusercontent.com/kubernetes-sigs/sig-windows-tools/master/hostprocess/PrepareNode.ps1"
    pwsh="https://github.com/PowerShell/PowerShell/releases/download/v7.5.3/PowerShell-7.5.3-win-x64.msi"
}

if($ssh){
    Set-Service sshd -StartupType $startup -Status $status
    Set-Service ssh-agent -StartupType $startup -Status $status

    Add-Content -Force -Path $authorized_keys -Value "$key"
    icacls.exe $authorized_keys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"

    Add-Content -Force -Path $config -Value "AllowAgentForwarding yes"
    Add-Content -Force -Path $config -Value "PasswordAuthentication no"
    Add-Content -Force -Path $config -Value "PermitEmptyPasswords no"
    Add-Content -Force -Path $config -Value "PubkeyAuthentication yes"

    New-ItemProperty @SetPowershell

    iwr -OutFile .\Downloads\pwsh.msi $url.pwsh
    msiexec.exe /package .\Downloads\pwsh.msi /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1 ADD_PATH=1

   if (!(Get-NetFirewallRule -Name "sshd" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -Name sshd -DisplayName 'SSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
    }
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
