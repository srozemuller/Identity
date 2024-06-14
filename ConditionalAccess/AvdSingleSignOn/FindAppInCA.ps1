[CmdletBinding(DefaultParameterSetName = 'Id')]
param (
    [parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string]$ApplicationName = "Microsoft Remote Desktop",

    [parameter(ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [switch]$UpdatePolicies = $false,

    [parameter(ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [switch]$ForceChange = $false,

    [parameter(ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [switch]$MakeBackup,

    [parameter(ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string]$AccessToken
)

function Get-YesNoResponse {
    param (
        [string]$Prompt = "Please enter 'Yes' or 'No'"
    )

    while ($true) {
        $response = Read-Host $Prompt

        if ($response -eq "Yes" -or $response -eq "No") {
            return $response
        }
        else {
            Write-Host "Invalid response. Please enter 'Yes' or 'No'."
        }
    }
}

# Search for the application ID of the provided application name
function Get-AppId {
    param (
        [string]$AppName
    )
    $appInfo = Invoke-MgGraphRequest -Method GET -Uri "beta/servicePrincipals?`$select=id,appId,displayname,Description,CreatedDateTime&`$filter=displayName eq '$AppName'" -OutputType Json | ConvertFrom-Json
    return $appInfo.value.appId
}

if ($AccessToken) {
    Connect-MgGraph -AccessToken $AccessToken -Scopes "https://graph.microsoft.com/.default"
}
else {
    Connect-MgGraph -Scopes "https://graph.microsoft.com/.default"
}

# Windows Cloud Login must be added to the policy, if Micoroosft Remote Desktop is assigned already
$WindowsCloudLoginApp = "Windows Cloud Login"
$applicationId = Get-AppId -AppName $WindowsCloudLoginApp

$caPolicies = Invoke-MgGraphRequest -Method GET -Uri "beta/identity/conditionalAccess/policies/" -OutputType Json | ConvertFrom-Json
$caPolicies.value | ForEach-Object {
    $policy = $_
    Write-Information "Checking policy $($policy.displayName)" -InformationAction Continue

    # Finding all applications that are excluded or included in the policy
    $excludedApps = $policy.Conditions.applications.excludeApplications
    $includedApps = $policy.Conditions.applications.includeApplications
    
    # Check if the provided application name is included in the policy
    if (($includedApps -ne "All") -and ($includedApps -ne "None")) {
        $currentIdsInString = "(" + (($includedApps | ForEach-Object { "'$_'" }) -join ",") + ")"
        $appInfo = Invoke-MgGraphRequest -Method GET -Uri "beta/servicePrincipals?`$select=id,displayname,Description,CreatedDateTime&`$filter=appId in $($currentIdsInString)" -OutputType Json | ConvertFrom-Json
        if (($appInfo.value.DisplayName -in $ApplicationName) -and ($appInfo.value.DisplayName -notcontains $WindowsCloudLoginApp)) {
            Write-Warning "Application $ApplicationName is assigned but $($WindowsCloudLoginApp ) is not found $($policy.displayName)"
            # If the -UpdatePolicies switch is provided, update the policy, otherwise it only shows the warning
            if ($UpdatePolicies.IsPresent) {
                # If the -MakeBackup switch is provided, create a backup of the policy, default it does.
                if ($MakeBackup.IsPresent) {
                    $policy | ConvertTo-Json | Out-File ".\policyBackup-$($policy.displayName).json"
                }
                Write-Host "Updating policy $($policy.displayName)"
                # In the case of automation, the -ForceChange switch can be used to automatically add the application to the policy
                if (!$ForceChange.IsPresent) {
                    Write-Host "Force change is enabled. Adding ($WindowsCloudLoginApp) to included apps for policy $($policy.displayName)"
                    $policy.Conditions.applications.excludeApplications += $applicationId
                    try {
                        $body = @{
                            conditions = $policy.conditions
                        }
                        $body | ConvertTo-Json -Depth 99 | Invoke-MgGraphRequest -Method PATCH -Uri "beta/identity/conditionalAccess/policies/$($policy.id)" -OutputType Json
                    
                    }
                    catch {
                        Write-Error "Failed to update policy $($policy.displayName)"
                    }
                }
                else {
                    $response = Get-YesNoResponse -Prompt "Do you want to add the ($WindowsCloudLoginApp) into included apps? (Yes/No)"
                }
                # For manual intervention, the script will ask for confirmation. This is when the -ForceChange switch is not provided
                if ($response -eq "Yes") {
                    Write-Host "Adding ($WindowsCloudLoginApp) to excluded apps for policy $($policy.displayName)"
                    $policy = Invoke-MgGraphRequest -Method GET -Uri "beta/identity/conditionalAccess/policies/$($policy.id)" -OutputType Json | ConvertFrom-Json -depth 99
                    $policy.Conditions.applications.excludeApplications += $applicationId
                    try {
                        $body = @{
                            conditions = $policy.conditions
                        }
                        $body | ConvertTo-Json -Depth 99 | Invoke-MgGraphRequest -Method PATCH -Uri "beta/identity/conditionalAccess/policies/$($policy.id)" -OutputType Json
                    
                    }
                    catch {
                        Write-Error "Failed to update policy $($policy.displayName)"
                    }
                }
            }
        }
        else {
            Write-Output "Applications are assigned but have nothing to do with $ApplicationName in policy $($policy.displayName)"
        }
    }

    # Check if the provided application name is excluded in the policy
    if (($excludedApps -ne "All") -and ($excludedApps -ne "None")) {
        $currentIdsInString = "(" + (($excludedApps | ForEach-Object { "'$_'" }) -join ",") + ")"
        $appInfo = Invoke-MgGraphRequest -Method GET -Uri "beta/servicePrincipals?`$select=id,displayname,Description,CreatedDateTime&`$filter=appId in $($currentIdsInString)" -OutputType Json | ConvertFrom-Json
        if (($appInfo.value.DisplayName -in $ApplicationName) -and ($appInfo.value.DisplayName -notcontains $WindowsCloudLoginApp)) {
            Write-Warning "Application $ApplicationName is assigned but $($WindowsCloudLoginApp ) is not found $($policy.displayName)"
            # If the -UpdatePolicies switch is provided, update the policy, otherwise it only shows the warning
            if ($UpdatePolicies.IsPresent) {
                # If the -MakeBackup switch is provided, create a backup of the policy, default it does.
                if ($MakeBackup.IsPresent) {
                    $policy | ConvertTo-Json | Out-File ".\policyBackup-$($policy.displayName).json"
                }
                Write-Host "Updating policy $($policy.displayName)"
                # In the case of automation, the -ForceChange switch can be used to automatically add the application to the policy
                if (!$ForceChange.IsPresent) {
                    Write-Host "Force change is enabled. Adding ($WindowsCloudLoginApp) to excluded apps for policy $($policy.displayName)"
                    $policy.Conditions.applications.excludeApplications += $applicationId
                    try {
                        $body = @{
                            conditions = $policy.conditions
                        }
                        $body | ConvertTo-Json -Depth 99 | Invoke-MgGraphRequest -Method PATCH -Uri "beta/identity/conditionalAccess/policies/$($policy.id)" -OutputType Json
                    
                    }
                    catch {
                        Write-Error "Failed to update policy $($policy.displayName)"
                    }
                }
                # For manual intervention, the script will ask for confirmation. This is when the -ForceChange switch is not provided
                else {
                    $response = Get-YesNoResponse -Prompt "Do you want to add the ($WindowsCloudLoginApp) into excluded apps? (Yes/No)"
                }
                if ($response -eq "Yes") {
                    Write-Host "Adding ($WindowsCloudLoginApp) to excluded apps for policy $($policy.displayName)"
                    $policy = Invoke-MgGraphRequest -Method GET -Uri "beta/identity/conditionalAccess/policies/$($policy.id)" -OutputType Json | ConvertFrom-Json -depth 99
                    $policy.Conditions.applications.excludeApplications += $applicationId
                    try {
                        $body = @{
                            conditions = $policy.conditions
                        }
                        $body | ConvertTo-Json -Depth 99 | Invoke-MgGraphRequest -Method PATCH -Uri "beta/identity/conditionalAccess/policies/$($policy.id)" -OutputType Json
                    
                    }
                    catch {
                        Write-Error "Failed to update policy $($policy.displayName)"
                    }
                }
            }
        }
        else {
            Write-Output "Applications are assigned but have nothing to do with $ApplicationName in policy $($policy.displayName)"
        }
    }
}
