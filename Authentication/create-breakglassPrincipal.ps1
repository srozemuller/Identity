$authHeader = ./graph.authentication.interactive.ps1 -TenantName "rozemuller.onmicrosoft.com" -ClientId "14d82eec-204b-4c2f-b7e8-296a70dab67e" -Scope "https://graph.microsoft.com//.default"

$appUrl = "https://graph.microsoft.com/beta/applications"
$appBody = @{
    "displayName"            = "EmergencyAccess"
    "signInAudience"         = "AzureADMyOrg"
    "requiredResourceAccess" = @(
        @{
            "resourceAppId"  = "00000003-0000-0000-c000-000000000000"
            "resourceAccess" = @(
                @{
                    "id"   = "9e3f62cf-ca93-4989-b6ce-bf83c28f9fe8" # RoleManagement.ReadWrite.Directory
                    "type" = "Role"
                },
                @{
                    "id"   = "df021288-bdef-4463-88db-98f22de89214" # Users.Read.All
                    "type" = "Role"
                }
            )
        }
    )
} | ConvertTo-Json -Depth 5
$appRequest = Invoke-WebRequest -Method POST -Uri $appUrl -Headers $authHeader -Body $appBody
$appOutput = $appRequest.Content | ConvertFrom-Json

$spUrl = "https://graph.microsoft.com/beta/servicePrincipals"
$spRequest = Invoke-WebRequest -Method POST -Uri $spUrl -Headers $authHeader -Body (@{
        "appId" = $appOutput.appId
    } | ConvertTo-Json)
$spOutput = $spRequest.Content | ConvertFrom-Json
$spOutput


$graphSpUrl = "https://graph.microsoft.com/beta/servicePrincipals?`$filter=appId eq '00000003-0000-0000-c000-000000000000'"
$grapSpRequest = Invoke-WebRequest -Method GET -Uri $graphSpUrl -Headers $authHeader
$grapshspOutput = ($grapSpRequest.Content | ConvertFrom-Json).value

$assignUrl = "https://graph.microsoft.com/beta/servicePrincipals/{0}/appRoleAssignments" -f $spOutput.id
$ids = @("df021288-bdef-4463-88db-98f22de89214", "9e3f62cf-ca93-4989-b6ce-bf83c28f9fe8")
foreach ($id in $ids) {
    $body = @{
        "principalId" = $spOutput.id
        "resourceId"  = $grapshspOutput.id
        "appRoleId"   = $id
    } | ConvertTo-Json
    $content = Invoke-WebRequest -Uri $assignUrl -Headers $authHeader -Method POST -Body $body
    $content.Content | ConvertFrom-Json
}


### Create Azure AD Group
$groupName = "CAExcludeGroup"
$groupBody = @{
    displayName        = $groupName
    mailEnabled        = $true
    securityEnabled    = $true
    groupTypes         = @(
        "Unified"
    )
    mailNickname       = $groupName
    isAssignableToRole = $true
    visibility         = "Private"
} | ConvertTo-Json
$group = Invoke-WebRequest -Uri "https://graph.microsoft.com/beta/groups" -Headers $authHeader -Method POST -Body $groupBody
$groupOutput = $group.Content | ConvertFrom-Json


### Add owner to group
$ownerUrl = "https://graph.microsoft.com/beta/groups/{0}/owners/`$ref" -f $groupOutput.id
$ownerBody = @{
    "@odata.id" = "https://graph.microsoft.com/beta/directoryObjects/{0}" -f $spOutput.id
} | ConvertTo-Json
Invoke-WebRequest -Uri $ownerUrl -Headers $authHeader -Method POST -Body $ownerBody


$certificate = Get-Content .\cert.crt -Raw
$certUploadKey = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($certificate))
$appUrl = "https://graph.microsoft.com/v1.0/myorganization/applications/{0}" -f $appOutput.id
$certUploadBody = @{
    keyCredentials = @(
        @{
            displayName = "emergencyaccess_cert"
            keyId       = (New-Guid).Guid
            type        = "AsymmetricX509Cert"
            usage       = "Verify"
            key         = $certUploadKey
        }
    )
} | ConvertTo-Json -Depth 10
Invoke-WebRequest -Uri $appUrl -Method PATCH -Headers $authHeader -Body $certUploadBody

$caPolicyUrl = "https://graph.microsoft.com/beta/identity/conditionalAccess/policies?`$filter=displayName eq 'CA004: Require multifactor authentication for all users'"
$caPolicies = Invoke-WebRequest -Uri $caPolicyUrl -Headers $authHeader -Method GET 
$caPolicy = ($caPolicies.Content | ConvertFrom-Json).value

$updateBody = @{
    conditions = @{
        users = @{
            excludeGroups = @(
                $groupOutput.id
            )
        }
    }
} | ConvertTo-Json -Depth 10
$updateCaUrl = "https://graph.microsoft.com/beta/identity/conditionalAccess/policies/{0}" -f $caPolicy.id
$content = Invoke-WebRequest -Uri $updateCaUrl -Headers $authHeader -Method PATCH -Body $updateBody
$content.Content | ConvertFrom-Json


$token = ./get-jwt-accesstoken.ps1 -TenantName xxx.onmicrosoft.com -CertPath ./cert.pfx -ApplicationId xxx
$certGraphHeader = @{
    'Content-Type' = 'application/json'
    Authorization  = "Bearer {0}" -f $token
}

$userUrl = "https://graph.microsoft.com/beta/users?`$filter=userPrincipalName eq 'user@domain.com'"
$users = Invoke-WebRequest -Uri $userUrl -Method GET -Headers $certGraphHeader
$user = ($users.Content | ConvertFrom-Json).value

$groupUrl = "https://graph.microsoft.com//beta/groups/{0}/members/`$ref" -f $groupOutput.id
$addMemberBody = @{
    "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/{0}" -f $user.id
} | ConvertTo-Json
Invoke-WebRequest -Uri $groupUrl -Method POST -Headers $certGraphHeader -Body $addMemberBody
