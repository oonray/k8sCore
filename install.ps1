param (
    [string]$startup='Automatic',
    [string]$key='sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIGTCxFD2UzUYYWAuDnFzwMmeWsVkPZLNfObG3hJZ4GuKAAAABHNzaDo=',
    [string]$status='Running',
    [string]$master='',
    [string]$token='',
    [switch]$ssh,
    [switch]$pwsh,
    [switch]$kube
)

$config= @{
    path= "$env:ProgramData\ssh\sshd_config"
    data= @"
Port 22
ListenAddress 0.0.0.0
PubkeyAuthentication yes
AuthorizedKeysFile      .ssh/authorized_keys
IgnoreUserKnownHosts no
PasswordAuthentication yes
PermitEmptyPasswords no
AllowAgentForwarding yes
PrintMotd no
Banner none
Subsystem       sftp    sftp-server.exe

AllowGroups administrators "openssh users"
AllowUsers administrator

Match Group administrators
       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
"@
    powershell=@{
        Path         = "HKLM:\SOFTWARE\OpenSSH"
        Name         = "DefaultShell"
        Value        = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
        PropertyType = "String"
        Force        = $true
    }
}

$admin_authorized_keys="$env:ProgramData\ssh\administrators_authorized_keys"
$authorized_keys="$env:USERPROFILE\.ssh\authorized_keys"

$url=@{
    containerd="https://raw.githubusercontent.com/kubernetes-sigs/sig-windows-tools/master/hostprocess/Install-Containerd.ps1"
    prepare="https://raw.githubusercontent.com/kubernetes-sigs/sig-windows-tools/master/hostprocess/PrepareNode.ps1"
    pwsh="https://github.com/PowerShell/PowerShell/releases/download/v7.5.3/PowerShell-7.5.3-win-x64.msi"
}

if($pwsh){
    iwr -OutFile pwsh.msi $url.pwsh
    msiexec.exe /package pwsh.msi /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1 ADD_PATH=1

    $config.powershell.Value = "C:\Program Files\PowerShell\7\pwsh.exe"
    New-ItemProperty @config.powershell
}

if($ssh){
    mkdir $env:USERPROFILE\.ssh\
    ssh-add $env:USERPROFILE\.ssh\id_ecdsa

    Set-Service sshd -StartupType $startup -Status $status
    Set-Service ssh-agent -StartupType $startup -Status $status

    Add-Content -Force -Path $admin_authorized_keys -Value "$key"
    Add-Content -Force -Path $authorized_keys -Value "$key"
    icacls.exe $admin_authorized_keys /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"

    Set-Content -Force -Path $config.path -Value $config.data

    New-ItemProperty @config.powershell

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
