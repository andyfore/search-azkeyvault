[cmdletbinding()]
param (
    [string] $KeyVaultName = "",
    [string] $SecretNameRegex = ".*",
    [string] $SecretValueRegex = ".*",
    [string] $Subscription = ""
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

$azAccount = Connect-AzAccount
$azContext = $azAccount.Context
$Subscription = (Get-AzContext).Subscription.Name
if (($null -eq $Subscription) -or ($Subscription -eq "")) {
    Write-Error "Subscription ID cannot be empty or null." -Category InvalidData
    Write-Warning "Please contact your Azure Administrator."
    exit
}

Write-Host "Connected as: $($azContext.Account.Id)" -ForegroundColor Cyan

# $secretdata = @{}
$vaultsAndSecretNames = @{}

if ($KeyVaultName -eq "") {
    $vaultsAndSecretNames = Get-AccessibleKeyVaultsAndSecretNames
    Write-Host "Found [$($vaultsAndSecretNames.Keys.Count)] accessible key vaults`n" -ForegroundColor Cyan
    # Write-Host "Accessible key vaults`n" 
    $menu = @{}

    $vaultsAndSecretNames.GetEnumerator() | Sort-Object Name| ForEach-Object -Begin {$counter = 1} -Process {
        Write-Output "$counter. $($_.Name)"
        $menu.Add($counter,$($_.Name))
        $counter++
    }

    [int]$ans = Read-Host "`nSelect the key vault to search (enter to parse all accessible)"
    $selection = $menu.Item($ans)
    $KeyVaultName  = $selection
    Write-Output "$KeyVaultName"

    $searchvalue =  Read-Host -Prompt 'Enter the search string'


    # while ($vaultsAndSecretNames.Keys -notcontains $KeyVaultName) {
    #     Write-Host "`nAccessible key vaults:`n$($vaultsAndSecretNames.Keys -join [Environment]::NewLine)" -ForegroundColor Cyan
    #     $KeyVaultName = Read-Host "`nEnter the key vault name to search"
    # }

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

        if ($searchvalue -eq "" ) {
            Write-Output $result | Format-Table -Wrap -Autosize
        }
        else {
            # Write-Output $result | Format-Table -Wrap -Autosize | Select-String -AllMatches -Pattern "$searchvalue"
            # Write-Output $result | Select-String -AllMatches -Pattern $searchvalue | Format-Table -Wrap -Autosize
            # ((Get-Content $file) -join "`n") + "`n" | Set-Content -NoNewline $file
            if ($result.SecretName.ToLower().Contains($searchvalue)) {
                Write-Output $result | Format-Table -Wrap -Autosize
            }
            elseif ($result.SecretValue.ToLower().Contains($searchvalue)) {
                Write-Output $result | Format-Table -Wrap -Autosize
            }
        }
    }
    $secretIndex++
    $percentComplete = [int](($secretIndex / $matchingVaultSecretsCount) * 100)
}