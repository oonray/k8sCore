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
    profile=@{
        path=$PROFILE
        data=@"
install-Module -Name "PSReadLine" -NoClobber -Force
Import-Module "PSReadLine" -NoClobber

$readline_opts = @{
        EditMode = "VI"
        HistoryNoDuplicates = $true
        HistorySearchCursorMovesToEnd = $true
        ViModeIndicator = "Prompt"
        PredictionViewStyle = "ListView"
        ExtraPromptLineCount = 2
        Colors =  @{
            Error = [ConsoleColor]::Red
            String = [ConsoleColor]::Green
            Default = "White"
            Type = [ConsoleColor]::Magenta
            Member = [ConsoleColor]::Cyan
            Number = [ConsoleColor]::Yellow
            Comment = [ConsoleColor]::Gray
            Command = [ConsoleColor]::Yellow
            Keyword = [ConsoleColor]::Blue
            Operator = [ConsoleColor]::Magenta
            Variable = [ConsoleColor]::Yellow
            Parameter = [ConsoleColor]::Yellow
        }}

Set-PSReadLineOption @readline_opts

$PSStyle.Progress.Style="$($PSStyle.Bold)$($PSStyle.Foreground.White)"
$PSStyle.Formatting.Error="$($PSStyle.Bold)$($PSStyle.Foreground.Red)"
$PSStyle.Formatting.TableHeader="$($PSStyle.Bold)$($PSStyle.Foreground.Green)"
$PSStyle.Formatting.CustomTableHeaderLabel="$($PSStyle.Bold)$($PSStyle.Foreground.Yellow)"
$PSStyle.FileInfo.Directory = $PSStyle.Foreground.Cyan
$PSStyle.FileInfo.SymbolicLink= $PSStyle.Foreground.BrightCyan
$PSStyle.FileInfo.Executable= $PSStyle.Foreground.Magenta

foreach($file in @(".zip",".tgz",".gz",".tar",".nupkg",".cap",".7z")){
    $PSStyle.FileInfo.Extension[$file]=$PSStyle.Foreground.White
}
foreach($file in @(".ps1",".psd1",".psm1",".ps1xml")){
    $PSStyle.FileInfo.Extension[$file]=$PSStyle.Foreground.BrightYellow
}
foreach($file in @(".json")){
    $PSStyle.FileInfo.Extension[$file]=$PSStyle.Foreground.Green
}
foreach($file in @(".dll",".o",".md")){
    $PSStyle.FileInfo.Extension[$file]=$PSStyle.Foreground.Magenta
}
foreach($file in @(".c",".cpp",".js",".php",".go",".ts")){
    $PSStyle.FileInfo.Extension[$file]=$PSStyle.Foreground.Cyan
}
foreach($file in @(".xls",".xlsx")){
    $PSStyle.FileInfo.Extension[$file]=$PSStyle.Foreground.BrightGreen
}
foreach($file in @(".doc",".docx")){
    $PSStyle.FileInfo.Extension[$file]=$PSStyle.Foreground.BrightBlue
}
foreach($file in @(".ppt",".pptx",".pdf",".xml",".html")){
    $PSStyle.FileInfo.Extension[$file]=$PSStyle.Foreground.Red
}
}
function Prompt {
"$($PSStyle.Foreground.BrightBlack)|=[$($PSStyle.Foreground.Yellow)$($PSStyle.Bold)$(Get-Date -f "dd-MM-yy:HH:mm")$($PSStyle.Foreground.BrightBlack)]=[$($PSStyle.Foreground.Reset)$($PSStyle.Foreground.Cyan)$($PSStyle.Bold)$($env:COMPUTERNAME) $($PSStyle.Foreground.BrightGreen)$($PSStyle.Bold)$($env:USERNAME)$($PSStyle.Foreground.BrightBlack)]=|$($PSStyle.Reset)`n`r$($PSStyle.Foreground.Cyan)PS$($PSStyle.Foreground.White) $($executionContext.SessionState.Path.CurrentLocation)> $($PSStyle.Reset)"
}
"@
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

    Set-Content -Force -Path $config.profile.path -Value $config.profile.data

    $config.powershell.Value = "C:\Program Files\PowerShell\7\pwsh.exe"
    New-ItemProperty @config:powershell
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

    New-ItemProperty @config:powershell

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
