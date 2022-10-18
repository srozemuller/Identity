function Get-KvSecret {
    param (
        [Parameter(Mandatory)]
        [string]$KeyVaultUri,
        [Parameter(Mandatory)]
        [string]$KeyVaultSecret
    )
    $secretUri = "{0}/secrets/{1}?api-version=7.3" -f $KeyVaultUri, $KeyVaultSecret
    $secretParameters = @{
        uri     = $secretUri
        method  = "GET"
        headers = $headers
    }
    $secret = Invoke-RestMethod @secretParameters
    $secret.value
}
function Set-KvSecret {
    param (
        [Parameter(Mandatory)]
        [string]$KeyVaultUri,
        [Parameter(Mandatory)]
        [string]$KeyVaultSecret,
        [Parameter(Mandatory)]
        [string]$KeyVaultSecretValue
    )

    $secretUri = "{0}/secrets/{1}?api-version=7.3" -f $KeyVaultUri, $KeyVaultSecret
    $secretBody = @{
        value = $KeyVaultSecretValue
    } | ConvertTo-Json -Depth 5

    $secretParameters = @{
        uri     = $secretUri
        method  = "PUT"
        headers = $headers
        body    = $secretBody
    }
    $secret = Invoke-RestMethod @secretParameters
    $secret.value
}

## Log in as a managed identity and get a token for Azure Key Vault
Connect-AzAccount -Identity
$vaultUrl = "https://vault.azure.net"
$context = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile.DefaultContext
$token = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id.ToString(), $null, [Microsoft.Azure.Commands.Common.Authentication.ShowDialog]::Never, $null, $vaultUrl).AccessToken
$tenantId = $context.Tenant.Id
$headers = @{
    'Content-Type' = 'application/json'
    Authorization  = 'Bearer ' + $token
}
$kvUri = "https://kv-hidden-api.vault.azure.net"
$kvSecretName = "RefreshToken"
$refreshToken = Get-KvSecret -KeyVaultUri $kvUri -KeyVaultSecret $kvSecretName 
if ($refreshToken) {
    try {
        write-verbose "checking provided refresh token and updating it"
        $response = (Invoke-RestMethod "https://login.windows.net/$tenantId/oauth2/token" -Method POST -Body "grant_type=refresh_token&refresh_token=$refreshToken" -ErrorAction Stop)
        $refreshToken = $response.refresh_token
        Set-KvSecret -KeyVaultUri $kvUri -KeyVaultSecret $kvSecretName -KeyVaultSecretValue $refreshToken
        write-verbose "refresh and access token updated"
    }
    catch {
        Write-Output "Failed to use cached refresh token, need interactive login or token from cache"   
        $refreshToken = $False 
    }
}

try {
    write-verbose "update token for supplied resource"
    $response = (Invoke-RestMethod "https://login.windows.net/$tenantId/oauth2/token" -Method POST -Body "resource=74658136-14ec-4630-ad9b-26e160ff0fc6&grant_type=refresh_token&refresh_token=$refreshToken&client_id=$clientId&scope=openid" -ErrorAction Stop)
    $resourceToken = $response.access_token
    write-verbose "token translated to $resource"
}
catch {
    Throw "Failed to translate access token to $resource , cannot continue"
}

$headers = @{
    "Authorization"          = "Bearer " + $resourceToken
    "Content-type"           = "application/json"
    "X-Requested-With"       = "XMLHttpRequest"
    "x-ms-client-request-id" = [guid]::NewGuid()
    "x-ms-correlation-id"    = [guid]::NewGuid()
}

$uri = "https://main.iam.ad.ext.azure.com/api/AccountSkus?backfillTenants=true"
Invoke-RestMethod -Method get -uri $uri -header $headers
