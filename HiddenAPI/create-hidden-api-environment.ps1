<#
    .SYNOPSIS
    This script can be used to create an invironment to store refresh token into an Azure Key Vault. The script creates a resource group and a Key Vault.

    This script is without warranty and not for commercial use without prior consent from the author. It is meant for scenario's where you need an Azure token to automate something that cannot yet be done with service principals.
 
    .EXAMPLE
    create-hidden-api-environment.ps1 -Location "WestEurope" -ResourceGroupName "hidden-resourcegroup" -KeyVaultName "hidden-kv" -PrincipalId "xxxx-xxxx"
    .PARAMETER Location
    The resource's location
    .PARAMETER ResourceGroupName
    The resource group to create
    .PARAMETER KeyVaultName
    The key vault name to create
    .PARAMETER PrincipalId
    The resource's system identity id that needs to be assigned to the RBAC role.
    .NOTES
    author: Sander Rozemuller
    blog: www.rozemuller.com
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]$Location,
    [parameter()]
    [string]$ResourceGroupName,
    [parameter()]
    [string]$KeyVaultName,
    [parameter()]
    [string]$PrincipalId
)

$mainUrl = "https://management.azure.com"
$method = "PUT"
try {
    $context = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile.DefaultContext
    $token = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id.ToString(), $null, [Microsoft.Azure.Commands.Common.Authentication.ShowDialog]::Never, $null, $mainUrl).AccessToken
    $headers = @{
        'Content-Type' = 'application/json'
        Authorization  = 'Bearer ' + $token
    }
    $tenantId = $context.Tenant.Id
    $subscriptionId = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile.DefaultContext.Subscription.Id
}
catch {
    Write-Output "Failed to find context. use Connect-AzAccount to login"   
}

try {
    ## Create the resource group first, if its not there allready.
    $rgUri = "{0}/subscriptions/{1}/resourcegroups/{2}?api-version=2021-04-01" -f $mainUrl, $subscriptionId, $resourceGroupName
    $rgBody = @{
        location = $location
    } | ConvertTo-Json -Depth 5
    $rgParameters = @{
        uri     = $rgUri
        method  = $method
        headers = $headers
        body    = $rgBody
    }
    $rg = Invoke-RestMethod @rgParameters
    $rg
}
catch {
    Write-Output "Failed to create resource group $ResourceGroupName, $_"   
}

## Create Key Vault
try {
    $uri = "{0}/subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.KeyVault/vaults/{3}?api-version=2021-10-01" -f $mainUrl, $subscriptionId, $resourceGroupName, $vaultName
    $kvBody = @{
        location   = $Location
        properties = @{
            enablePurgeProtection   = $true
            enableRbacAuthorization = $true
            publicNetworkAccess     = "Disabled"
            tenantId                = $tenantId
            sku                     = @{
                family = "A"
                name   = "standard"
            }
        }
    } | ConvertTo-Json -Depth 5

    $keyVaultParameters = @{
        uri     = $uri
        method  = $method
        headers = $headers
        body    = $kvBody
    }
    $kv = Invoke-RestMethod @keyVaultParameters
    $kv
}
catch {
    Write-Output "Failed to create key vault $KeyVaultName, $_"   
}
try {
    $roleGuid = (New-Guid).Guid
    $roleUri = "{0}/{1}/providers/Microsoft.Authorization/roleAssignments/{2}?api-version=2018-01-01-preview" -f $mainUrl, $kv.id, $roleGuid
    $roleBody = @{
        properties = @{
            roleDefinitionId = "/subscriptions/{0}/providers/Microsoft.Authorization/roleDefinitions/b86a8fe4-44ce-4948-aee5-eccb2c155cd7" -f $subscriptionId ## b86a8fe4... guid is the buildin role ID Key Vault Secrets Officer
            principalId      = $PrincipalId ## This is the system identity id or the resource
        }
    } | ConvertTo-Json -Depth 5

    $roleParameters = @{
        uri     = $roleUri
        method  = $method
        headers = $headers
        body    = $roleBody
    }
    $role = Invoke-RestMethod @roleParameters
    $role
}
catch {
    Write-Output "Failed to assign the Key Vault Secrets Officer RBAC role to $KeyVaultName, $_"   
}
