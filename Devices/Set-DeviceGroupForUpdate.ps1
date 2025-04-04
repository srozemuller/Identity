[CmdletBinding(DefaultParameterSetName = 'Id')]
param (
    [parameter(ValueFromPipelineByPropertyName, Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$UserGroupName,

    [parameter(ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string]$DeviceGroupName,

    [parameter(ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [Validateset('Windows', 'macOS', 'iOS', 'Android', 'WindowsPhone')]
    [string]$DeviceType = 'Windows',

    [parameter(ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [switch]$MakeDeviceGroupEmpty,

    [parameter(ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string]$BackupPath = './',

    [parameter(ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string]$AccessToken
)

$modules = @(
    "MSGraph"
)
$modules.Foreach({
        # Check if the module is installed
        $module = Get-Module -ListAvailable -Name $_
        # If the module is not found, install it
        if (-not $module) {
            Write-Host "Module $_ is not found. Installing..."
            try {
                Install-Module -Name $_ -Force -Scope CurrentUser
                Write-Host "Module $moduleName installed successfully."
                Import-Module -Name $_ -Force
            }
            catch {
                Write-Error "Failed to install module $_. Error: $_"
            }
        }
        else {
            Import-Module -Name $_ -Force
            Write-Host "Module $_ is already installed."
        }
    })

Import-Module ./create-UrlListBatchOutput.ps1

if ($AccessToken) {
    Connect-MgGraph -AccessToken $AccessToken -Scopes "https://graph.microsoft.com/.default"
}
else {
    Connect-MgGraph -Scopes "https://graph.microsoft.com/.default"
}

try {
    $userGroup = Invoke-MgGraphRequest -Method GET -Uri "beta/groups?`$filter=displayName eq '$UserGroupName'" -OutputType Json | ConvertFrom-Json
    if ($userGroup.value.Count -eq 0) {
        Write-Error "Group $UserGroupName not found"
        return
    }
    $userGroupMembers = Invoke-MgGraphRequest -Method GET -Uri "beta/groups/$($userGroup.value.id)/members" -OutputType Json | ConvertFrom-Json
    if ($userGroupMembers.value.Count -eq 0) {
        Write-Error "Group $UserGroupName has no members"
        return
    }
}
catch {
    Write-Error "Failed to get group $UserGroupName"
    return
}
try {
    $deviceGroup = Invoke-MgGraphRequest -Method GET -Uri "beta/groups?`$filter=displayName eq '$DeviceGroupName'" -OutputType Json | ConvertFrom-Json
    if ($deviceGroup.value.Count -eq 0) {
        Write-Error "Group $DeviceGroupName not found"
        return
    }
    $deviceGroupMembers = Invoke-MgGraphRequest -Method GET -Uri "beta/groups/$($deviceGroup.value.id)/members" -OutputType Json | ConvertFrom-Json
}
catch {
    Write-Error "Failed to get group $DeviceGroupName"
    return
}

try {
    $memberList = [System.Collections.Generic.List[string]]::new()
    $ownedDevicesUrlList = [System.Collections.Generic.List[string]]::new()
    # Fetch all owned devices of the users in the user group
    $userGroupMembers.value | Where-Object {$_.'@odata.type' -eq '#microsoft.graph.user'} | ForEach-Object {
        $user = $_
        $ownedDevicesUrlList.Add("/users/$($user.id)/ownedDevices")
    }
    $deviceGroupMembers.value | Where-Object {$_.'@odata.type' -eq '#microsoft.graph.device'}  | ForEach-Object {
        $member = $_
        $memberList.Add("https://graph.microsoft.com/beta/directoryObjects/$($member.id)")
    }
    # Making a backup of the members of the device group
    if ($memberList.Count -gt 0) {
        Write-Information "Backing up members of group $DeviceGroupName, putting values in $BackupPath/membersBackup.json" -InformationAction Continue
        $memberBatchBackup = Create-BodyList -bodyList $memberList

        $jsonOutput = @{
            memberBatches = $memberBatchBackup 
        } | Convertto-Json -Depth 99
        $jsonOutput | Out-File -path ("{0}/{1}" -f $BackupPath, "membersBackup.json")
    }

    if ($MakeDeviceGroupEmpty.IsPresent -and $memberList.Count -gt 0) {
        try {
            Write-Warning "Removing members from group $DeviceGroupName"
            $memberBatch = Create-UrlListBatchOutput -Method DELETE -urlList $memberList
            $memberBatch.ForEach({
                    Invoke-MgGraphRequest -Method POST -Body $_ -Uri "beta/`$batch"
                })
        }
        catch {
            Write-Error "Failed to remove members from group $DeviceGroupName"
        }
    }
    else {
        Write-Information "Adding devices to group $DeviceGroupName" -InformationAction Continue
        $devicesBatch = Create-UrlListBatchOutput -Method GET -urlList $ownedDevicesUrlList
        $devicesResponseList = [System.Collections.ArrayList]@()
        $devicesList = [System.Collections.Generic.List[string]]::new()
        $devicesBatch.ForEach({
                $body = $_
                $response = Invoke-MgGraphRequest -Method POST -Body $body -Uri "beta/`$batch" -OutputType PSObject
                $devicesResponseList.Add($response) >> $null
            })
        $devicesResponseList.responses | Where-Object {$_.status -eq 200} | ForEach-Object {
            $deviceResponse = $_.body.value
            $deviceToAdd = $deviceResponse | Where-Object {($_.isManaged) -and ($_.approximateLastSignInDateTime -gt (Get-Date).AddDays(-29)) -and ($_.operatingSystem -eq $DeviceType)}
            foreach ($device in $deviceToAdd) {
                $devicesList.Add("https://graph.microsoft.com/beta/directoryObjects/$($device.id)") >> $null
            }
        }
        $deviceBatch = Create-BodyList -bodyList $devicesList
        $deviceBatch.ForEach({
            $body = $_
            Invoke-MgGraphRequest -Method PATCH -Body $body -Uri "/beta/groups/$($deviceGroup.value.id)"
        })
    }
}
catch {
    Write-Error "Preparing device group members failed. Error: $_"
    return

}