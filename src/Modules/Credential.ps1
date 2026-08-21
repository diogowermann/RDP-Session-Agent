function Protect-AgentSecret {
    param(
        [Parameter(Mandatory=$true)][string]$RootPath,
        [Parameter(Mandatory=$true)][string]$Secret
    )

    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($Secret)
    $protectedBytes = [System.Security.Cryptography.ProtectedData]::Protect(
        $plainBytes,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::LocalMachine
    )
    $credentialPath = Join-Path $RootPath 'credential.dat'
    [System.IO.File]::WriteAllText($credentialPath, [Convert]::ToBase64String($protectedBytes))
}

function Get-AgentSecret {
    param([Parameter(Mandatory=$true)][string]$RootPath)

    $credentialPath = Join-Path $RootPath 'credential.dat'
    if (-not (Test-Path -LiteralPath $credentialPath)) {
        throw "Agent credential not found: $credentialPath"
    }

    $protectedBytes = [Convert]::FromBase64String(([System.IO.File]::ReadAllText($credentialPath)).Trim())
    $plainBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $protectedBytes,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::LocalMachine
    )
    return [System.Text.Encoding]::UTF8.GetString($plainBytes)
}
