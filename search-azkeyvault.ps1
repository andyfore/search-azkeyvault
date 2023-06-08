[cmdletbinding()]
param (
    [string] $KeyVaultName = "",
    [string] $SecretNameRegex = ".*",
    [string] $SecretValueRegex = ".*",
    [string] $Subscription = "it-shared-001"
)

Write-Verbose "Importing or installing the Az module"
try {
    Import-Module -Name Az -Force -ErrorAction Stop -DisableNameChecking
}
catch {
    Install-Module -Name Az -Force -AllowClobber
}

Write-Verbose "Importing or installing the Az.KeyVault module"
try {
    Import-Module -Name Az.KeyVault -Force -ErrorAction Stop -DisableNameChecking
}
catch {
    Install-Module -Name Az.KeyVault -Force -AllowClobber
}

function Get-AccessibleKeyVaultsAndSecretNames {
    [cmdletbinding()]
    param ()
    
    Write-Verbose "Retrieving all key vaults to determine accessibility"
    $allVaults = Get-AzKeyVault | Select-Object -ExpandProperty VaultName
    $allVaultsCount = $allVaults.Length
    Write-Verbose "Found [$allVaultsCount] total key vaults"

    $accessibleVaults = @{}

    $vaultIndex = 0
    $vaultTestPercentComplete = 0
    $allVaults | ForEach-Object {
        $vaultName = $_
        Write-Progress -Activity "Determining Accessible Key Vaults" -Status "$vaultTestPercentComplete% Complete:" -PercentComplete $vaultTestPercentComplete
    
        $error.Clear()
        Write-Verbose "Testing access to key vault: $vaultName"

        $vaultSecrets = Get-AzKeyVaultSecret -VaultName $vaultName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
        if ($error.Count -eq 0) {
            Write-Verbose "*** Adding accessible key vault: $vaultName"
            $accessibleVaults.Add($vaultName, $vaultSecrets)
        }
        $vaultIndex++
        $vaultTestPercentComplete = [int](($vaultIndex / $allVaultsCount) * 100)
    }

    return $accessibleVaults
}

$azContext = Get-AzContext
if (!$azContext) {
    Write-Verbose "Connecting Azure account (check for a browser window)"
    $azAccount = Connect-AzAccount -Subscription $Subscription
    $azContext = $azAccount.Context
}
Write-Host "Connected as: $($azContext.Account.Id)" -ForegroundColor Cyan

$vaultsAndSecretNames = @{}
if ($KeyVaultName -eq "") {
    $vaultsAndSecretNames = Get-AccessibleKeyVaultsAndSecretNames
    Write-Host "Found [$($vaultsAndSecretNames.Keys.Count)] accessible key vaults"

    while ($vaultsAndSecretNames.Keys -notcontains $KeyVaultName) {
        Write-Host "`nAccessible key vaults:`n$($vaultsAndSecretNames.Keys -join [Environment]::NewLine)" -ForegroundColor Cyan
        $KeyVaultName = Read-Host "`nEnter the key vault name to search"
    }
}
else {
    $vaultSecrets = Get-AzKeyVaultSecret -VaultName $KeyVaultName -ErrorAction Stop | Select-Object -ExpandProperty Name
    $vaultsAndSecretNames.Add($KeyVaultName, $vaultSecrets)
}

$matchingVaultSecrets = $vaultsAndSecretNames[$KeyVaultName] | Where-Object { $_ -match $SecretNameRegex }
$matchingVaultSecretsCount = $matchingVaultSecrets.Length
Write-Verbose "Found [$matchingVaultSecretsCount] matching secret names in key vault: $KeyVaultName"

$secretIndex = 0
$percentComplete = 0
$matchingVaultSecrets | ForEach-Object {
    Write-Progress -Activity "Enumerating Azure Key Vault Secrets" -Status "$percentComplete% Complete:" -PercentComplete $percentComplete
    $secretName = $_
    $secretValue = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $secretName -AsPlainText
    if ($secretValue -match $SecretValueRegex) {
        $result = [PSCustomObject]@{
            SecretName = $secretName
            SecretValue = $secretValue 
        }
        # Write-Output $result | Select-String -AllMatches -Pattern "nw01" |Format-Table -Wrap -Autosize
        Write-Output $result | Format-Table -Wrap -Autosize
    }
    $secretIndex++
    $percentComplete = [int](($secretIndex / $matchingVaultSecretsCount) * 100)
}