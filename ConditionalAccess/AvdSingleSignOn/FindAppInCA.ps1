[CmdletBinding(DefaultParameterSetName = 'Id')]
param (
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
    [string]$AccessToken,

    [parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,
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


if ($AccessToken) {
    Connect-MgGraph -AccessToken $AccessToken -Scopes "https://graph.microsoft.com/.default"
    Connect-Avd -AccessToken $AccessToken -SubscriptionId $SubscriptionId
}
else {
    Connect-MgGraph -Scopes "https://graph.microsoft.com/.default"
    Connect-AzAccount
    Connect-Avd -AccessToken $(Get-AzAccessToken).token -subscriptionId $SubscriptionId
}

# Check if the hostpool has SSO enabled
$ssoEnabled = $false
$hostpools = Get-AvdHostPool
$hostpools.ForEach({
    $hostpool = $_
    if ($hostpool.properties.customrdpproperty.Contains("enablerdsaadauth:i:1")){
        Write-Output "Hostpool $($hostpool.name) has SSO enabled"
        $ssoEnabled = $true
    }
})
# Windows Cloud Login application Id
$applicationId = "270efc09-cd0d-444b-a71f-39af4910ec45"
if ($ssoEnabled){
    $caPolicies = Invoke-MgGraphRequest -Method GET -Uri "beta/identity/conditionalAccess/policies/" -OutputType Json | ConvertFrom-Json
    $caPolicies.value | ForEach-Object {
        $policy = $_
        Write-Information "Checking policy $($policy.displayName)" -InformationAction Continue

        # Finding all applications that are excluded or included in the policy
        $excludedApps = $policy.Conditions.applications.excludeApplications
        $includedApps = $policy.Conditions.applications.includeApplications
        
        # Check if the Windows Cloud Login is missing but has the Microsoft Remote Desktop application
        if (($includedApps.contains("a4a365df-50f1-4397-bc59-1a1564b8bb9c")) -and (!$includedApps.contains($applicationId))) {
            Write-Warning "Application Microsoft Remote Desktop is assigned but $($WindowsCloudLoginApp) is not found $($policy.displayName)"
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
                    # Adding the application to the included applications
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
            Write-Output "Applications are assigned but have nothing to do with  Microsoft Remote Desktopin policy $($policy.displayName)"
        }
        

        # Check if the Windows Cloud Login is missing but has the Microsoft Remote Desktop application
        if (($excludedApps.contains("a4a365df-50f1-4397-bc59-1a1564b8bb9c")) -and (!$excludedApps.contains($applicationId))) {
            Write-Warning "Application  Microsoft Remote Desktop is assigned but $($WindowsCloudLoginApp) is not found $($policy.displayName)"
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
            Write-Output "Applications are assigned but have nothing to do with Windows Remote Desktop in policy $($policy.displayName)"
        }
    }
}