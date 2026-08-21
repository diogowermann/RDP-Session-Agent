param(
    [Parameter(Mandatory=$true)][string]$ApiBaseUrl,
    [Parameter(Mandatory=$true)][string]$ServerId,
    [Parameter(Mandatory=$true)][string]$AgentSecret,
    [string]$InstallRoot = 'C:\ProgramData\RdpSessionAgent'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 3) {
    throw 'PowerShell 3.0 or newer is required.'
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repositoryRoot 'src'
$versionPath = Join-Path $repositoryRoot 'VERSION'
if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw 'src directory was not found next to the installer.'
}

New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $InstallRoot 'spool') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $InstallRoot 'logs') -Force | Out-Null

$installedSource = Join-Path $InstallRoot 'src'
if (Test-Path -LiteralPath $installedSource) {
    Remove-Item -LiteralPath $installedSource -Recurse -Force
}
Copy-Item -LiteralPath $sourcePath -Destination $installedSource -Recurse -Force
Copy-Item -LiteralPath $versionPath -Destination (Join-Path $InstallRoot 'VERSION') -Force

$config = [ordered]@{
    api_base_url = $ApiBaseUrl.TrimEnd('/')
    server_id = $ServerId
    event_log_name = 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'
    initial_lookback_minutes = 60
    max_events_per_batch = 200
    include_local_sessions = $false
}
$config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $InstallRoot 'config.json') -Encoding UTF8

. (Join-Path $installedSource 'Modules\Credential.ps1')
Protect-AgentSecret -RootPath $InstallRoot -Secret $AgentSecret

$acl = Get-Acl -LiteralPath $InstallRoot
$acl.SetAccessRuleProtection($true, $false)
foreach ($rule in @($acl.Access)) {
    [void]$acl.RemoveAccessRule($rule)
}
$inheritance = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
$propagation = [System.Security.AccessControl.PropagationFlags]::None
$fullControl = [System.Security.AccessControl.FileSystemRights]::FullControl
$allow = [System.Security.AccessControl.AccessControlType]::Allow
$systemAccount = (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')).Translate([System.Security.Principal.NTAccount]).Value
$administratorsAccount = (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')).Translate([System.Security.Principal.NTAccount]).Value
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($systemAccount, $fullControl, $inheritance, $propagation, $allow)))
$acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($administratorsAccount, $fullControl, $inheritance, $propagation, $allow)))
Set-Acl -LiteralPath $InstallRoot -AclObject $acl

Write-Host "Agent files installed at $InstallRoot"
Write-Host 'No Scheduled Task was created in this release.'
Write-Host "Run manually as Administrator: powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$InstallRoot\src\Agent.ps1`""
