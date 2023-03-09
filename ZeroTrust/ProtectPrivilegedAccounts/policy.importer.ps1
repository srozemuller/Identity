$files = Get-ChildItem -Path './Identity/ZeroTrust/ProtectPrivilegedAccounts' -Filter *.json
foreach ($file in $files) {
    $caPolUrl = "https://graph.microsoft.com/beta/identity/conditionalAccess/policies"
    $params = @{
        uri = $caPolUrl
        method = "POST"
        headers = $graphHeader
        body = get-content $file
    }
    Invoke-RestMethod @params
}