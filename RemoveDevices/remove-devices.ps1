[CmdletBinding()]
param (
    [Parameter()]
    [string]$PathToCsv,
    [Parameter()]
    [string]$Delimiter = ","
)

try {
    Install-Module MSAL.PS -Force
    Import-Module -Name MSAL.PS
} catch {
    Write-Host "MSAL.PS not imported, $_"
    exit
}

$clientId = "14d82eec-204b-4c2f-b7e8-296a70dab67e"
$Scopes = "https://graph.microsoft.com/DeviceManagementManagedDevices.ReadWrite.All","https://graph.microsoft.com/Directory.ReadWrite.All","https://graph.microsoft.com/Directory.AccessAsUser.All"
$token = Get-Msaltoken -ClientId $clientId -Scopes $Scopes
$authHeader = @{
    Authorization  = 'Bearer ' + $token.AccessToken
}

$csv = Import-Csv -Path $PathToCsv -delimiter $Delimiter
foreach ($row in $csv) {
	try {
		$deleteDeviceIntuneUrl = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('{0}')" -f $row.Id
		$deviceInfo = Invoke-RestMethod -Method Get -Uri $deleteDeviceIntuneUrl -Headers $AuthHeader
        if ($deviceInfo){
            Write-Information "Deleting device $($row.Id) from Intune" -InformationAction Continue
            Invoke-RestMethod -Method Delete -Uri $deleteDeviceIntuneUrl -Headers $AuthHeader
        }
	} catch {
		Write-Host "Error removing device $($row.Id) from Intune"
	}
	try {
		$getAadDeviceUrl = "https://graph.microsoft.com/beta/devices?`$filter=deviceId eq '{0}'" -f $deviceInfo.azureADDeviceId
		$deviceAadInfo = Invoke-RestMethod -Method Get -Uri $getAadDeviceUrl -Headers $AuthHeader
		$deleteAadDeviceUrl = "https://graph.microsoft.com/beta/devices/{0}" -f $deviceAadInfo.value.id
        if ($deviceAadInfo.value){
            Write-Information "Deleting device $($row.Id) from Azure AD" -InformationAction Continue
            Invoke-RestMethod -Method Delete -Uri $deleteAadDeviceUrl -Headers $AuthHeader
        }
	} catch {
		Write-Host "Error removing device $($row.Id) from Azure AD, maybe it was already removed"
	}

}