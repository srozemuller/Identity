function Get-AccessToken {
  [CmdletBinding()]
  param (
      [Parameter()]
      [string]
      $TenantName,

      [Parameter()]
      [string]
      $Scope,

      [Parameter()]
      [string]
      $ClientId
  )
    # Creating the body for the refresh token request
  $clientBody = @{
    client_id = $ClientId
    tenant    = $TenantName
    scope     = $Scope 
  }
  
  # Writing output for traceability in the code
  Write-Output "The client_id in the body is: $ClientId"
  Write-Output "The tenant in the body is: $TenantName"
  
  # Making the code request for the refresh token
  $graphCodeRequest = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$($TenantName)/oauth2/v2.0/devicecode" -Body $clientBody
  # This part of the code will print the link of the site that needs to be visited and the code that needs to be filled in on the forum
  Write-Output "`n$($graphCodeRequest.message)"
  
  # Create the body for the token request, where the device code from the previous request will be used in the call
  $tokenBody = @{
    grant_type = "urn:ietf:params:oauth:grant-type:device_code"
    code       = $graphCodeRequest.device_code
    client_id  = $ClientId
  }
  
  # Get OAuth Token
  while ([string]::IsNullOrEmpty($tokenRequest.access_token)) {
    $tokenRequest = try {
        Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$TenantName/oauth2/token" -Body $tokenBody
    }
    catch {
        $errorMessage = $_.ErrorDetails.Message | ConvertFrom-Json
        # If not waiting for auth, throw error
        if ($errorMessage.error -ne "authorization_pending") {
            throw "Authorization is pending."
        }
    }
  }
  $graphHeader = @{
      'Content-Type' = 'application/json'
      Authorization  = "Bearer {0}" -f $tokenRequest.access_token
  }
  
  return $graphHeader
}
