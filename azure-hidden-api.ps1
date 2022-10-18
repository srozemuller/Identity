Param(
    [Parameter(Mandatory)][string]$KeyVaultUri, # Like https://myOwnKeyVault.vault.azure.net
    [Parameter(Mandatory)][string]$KeyVaultSecretName,
    [Parameter()]$refreshToken,
    [Parameter(Mandatory)][string]$TenantId,
    $resource = "https://main.iam.ad.ext.azure.com",
    $clientId = "1950a258-227b-4e31-a9cf-717495945fc2" #use 1b730954-1685-4b74-9bfd-dac224a7b894 for audit/sign in logs or other things that only work through the AzureAD module, use d1ddf0e4-d672-4dae-b554-9d5bdfd93547 for Intune
)

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

if ($refreshToken) {
    try {
        write-verbose "checking provided refresh token and updating it"
        $response = (Invoke-RestMethod "https://login.windows.net/$tenantId/oauth2/token" -Method POST -Body "grant_type=refresh_token&refresh_token=$refreshToken" -ErrorAction Stop)
        $refreshToken = $response.refresh_token
        write-verbose "refresh and access token updated"
    }
    catch {
        Write-Output "Failed to use cached refresh token, need interactive login or token from cache"   
        $refreshToken = $False 
    }
}

if ($KeyVaultUri -and $refreshToken) {
    try {
        write-verbose "getting refresh token from cache"
        $refreshToken = Get-Content $refreshTokenCachePath -ErrorAction Stop | ConvertTo-SecureString -ErrorAction Stop
        $refreshToken = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($refreshToken)
        $refreshToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($refreshToken)
        $response = (Invoke-RestMethod "https://login.windows.net/$tenantId/oauth2/token" -Method POST -Body "grant_type=refresh_token&refresh_token=$refreshToken" -ErrorAction Stop)
        $refreshToken = $response.refresh_token
        write-verbose "tokens updated using cached token"
    }
    catch {
        Write-Output "Failed to use cached refresh token, need interactive login"
        $refreshToken = $False
    }
}

if (!$refreshToken) {
    Write-Verbose "No cache file exists and no refresh token supplied, we have to perform interactive logon"
    if ([Environment]::UserInteractive) {
        foreach ($arg in [Environment]::GetCommandLineArgs()) {
            if ($arg -like '-NonI*') {
                Throw "Interactive login required, but script is not running interactively. Run once interactively or supply a refresh token with -refreshToken"
            }
        }
    }

    try {
        Write-Verbose "Attempting device sign in method"
        $response = Invoke-RestMethod -Method POST -UseBasicParsing -Uri "https://login.microsoftonline.com/$tenantId/oauth2/devicecode" -ContentType "application/x-www-form-urlencoded" -Body "resource=https%3A%2F%2Fmain.iam.ad.ext.azure.com&client_id=$clientId"
        Write-Output $response.message
        $waited = 0
        while ($true) {
            try {
                $authResponse = Invoke-RestMethod -uri "https://login.microsoftonline.com/$tenantId/oauth2/token" -ContentType "application/x-www-form-urlencoded" -Method POST -Body "grant_type=device_code&resource=https%3A%2F%2Fmain.iam.ad.ext.azure.com&code=$($response.device_code)&client_id=$clientId" -ErrorAction Stop
                $refreshToken = $authResponse.refresh_token
                break
            }
            catch {
                if ($waited -gt 300) {
                    Write-Verbose "No valid login detected within 5 minutes"
                    Throw
                }
                #try again
                Start-Sleep -s 5
                $waited += 5
            }
        }
    }
    catch {
        Throw "Interactive login failed, cannot continue"
    }
}

if ($KeyVaultUri -and $refreshToken) {
    write-verbose "caching refresh token"
    try {
        Set-KvSecret -KeyVaultUri $KeyVaultUri -KeyVaultSecret $KeyVaultSecretName -KeyVaultSecretValue $refreshToken
        write-verbose "refresh token stored in Key Vault"
    }
    catch {
        Write-Output "Not able to write secret to Key Vault"
    }
}
else {
    Throw "No refresh token found in cache and no valid refresh token passed or received after login, cannot continue"
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

return $headers