function Get-RandomString {
    param (
        [Parameter(Mandatory)]
        [int] $length
    )
    #$charSet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789{]+-[*=@:)}$^%;(_!&amp;#?>/|.'.ToCharArray()
    $charSet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.ToCharArray()
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $bytes = New-Object byte[]($length)
 
    $rng.GetBytes($bytes)
 
    $result = New-Object char[]($length)
 
    for ($i = 0 ; $i -lt $length ; $i++) {
        $result[$i] = $charSet[$bytes[$i] % $charSet.Length]
    }
 
    return (-join $result)
}

$azureUrl = "https://management.azure.com"
$graphUrl = "https://graph.microsoft.com"
$subscriptionId = "subscription-id"
$resourceGroup = "resource-group"
$laWorkspaceName = "log-analytics-workspace"
$microsoftDomain = "xx.onmicrosoft.com"

# Get the access token for the Azure and Graph API
$graphHeader = @{
    'Content-Type' = 'application/json'
    Authorization  = "Bearer {0}" -f (Get-AzAccessToken -ResourceUrl $graphUrl).Token
}

$azureHeader = @{
    'Content-Type' = 'application/json'
    Authorization  = "Bearer {0}" -f (Get-AzAccessToken -ResourceUrl $azureUrl).Token
}

$workspaceId = "/subscriptions/{0}/resourcegroups/{1}/providers/microsoft.operationalinsights/workspaces/{2}" -f $subscriptionId, $resourceGroup, $laWorkspaceName

$username = Get-RandomString 8
$password = Get-RandomString 24
$userInfo = @{
    "accountEnabled"    = $true
    "displayName"       = "Break Glass"
    "mailNickname"      = $username
    "userPrincipalName" = "{0}{1}@{2}" -f "bkr", $username, $microsoftDomain
    "passwordProfile"   = @{
        "forceChangePasswordNextSignIn" = $false
        "password"                      = $password
    }
} | ConvertTo-Json -Depth 5
$userUrl = "{0}/beta/users" -f $graphUrl
$value = Invoke-RestMethod -Uri $userUrl -Method POST -Headers $graphHeader -Body $userInfo -ContentType "application/json"
$value

$pimUrl = "{0}/beta/roleManagement/directory/roleAssignmentScheduleRequests" -f $graphUrl 
$pimBody = @{
    action           = "adminAssign"
    justification    = "Assign permanent break glass global admin permissions"
    reason           = "Permanent global admin permissions needed in case of emergency"
    roleDefinitionId = "62e90394-69f5-4237-9190-012177145e10"
    directoryScopeId = "/"
    principalId      = $value.id
    scheduleInfo     = @{
        startDateTime = Get-Date
        expiration    = @{
            type = "noExpiration"
        }
    }
} | ConvertTo-Json -Depth 5
$pimValue = Invoke-RestMethod -Uri $pimUrl -Method POST -Headers $graphHeader -Body $pimBody -ContentType "application/json"
$pimValue


$logsUrl = "{0}/providers/microsoft.aadiam/diagnosticSettings/{1}?api-version=2017-04-01" -f $azureUrl, "signInLogs"
$logsBody = @{
    properties = @{
        logs        = @(
            @{    
                "category"        = "SignInLogs"
                "categoryGroup"   = $null
                "enabled"         = $true
                "retentionPolicy" = @{
                    "days"    = 90
                    "enabled" = $true
                }
            }
        )
        workspaceID = $workspaceId
    }
} | ConvertTo-Json -Depth 5
$logsValue = Invoke-RestMethod -Uri $logsUrl -Method PUT -Headers $azureHeader -Body $logsBody -ContentType "application/json"
$logsValue


$actionGroupUrl = "{0}/subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Insights/actionGroups/{3}?api-version=2021-09-01" -f $azureUrl, $subscriptionId, $resourceGroup, "ToAdmin"
$actionGroupBody = @{
    location   = "Global"
    properties = @{
        groupShortName = "mail"
        emailReceivers = @(
            @{
                name                 = "IT admin email"
                emailAddress         = "it@admin.com"
                useCommonAlertSchema = $true
            }
        )
        smsReceivers = @(
            @{
                name         = "SMS"
                countryCode  = "31"
                phoneNumber  = "0655108372"
                status = "Enabled"
            }
        )
    }
} | ConvertTo-Json -Depth 5
$actionGroupValue = Invoke-RestMethod -Uri $actionGroupUrl -Method PUT -Headers $azureHeader -Body $actionGroupBody -ContentType "application/json"
$actionGroupValue

$queryUrl = "{0}/subscriptions/{1}/resourceGroups/{2}/providers/Microsoft.Insights/scheduledQueryRules/{3}?api-version=2021-08-01" -f $azureUrl, $subscriptionId, $resourceGroup, "BreakGlassUsed"
$queryBody = @{
    location = "westeurope"
    properties = @{
      description = "Break glass account used!"
      severity = 0
      evaluationFrequency = "PT5M"
      "scopes" = @(
        $workspaceId
      )
      windowSize = "PT5M"
      criteria = @{
        allOf = @(
          @{
            query = "SigninLogs
            | where UserPrincipalName == tolower('$($value.userPrincipalName)')"
            timeAggregation = "count"
            dimensions = @(
              @{
                name = "ServicePrincipalName"
                operator = "Include"
                values = @(
                  "*"
                )
              }
            )
            operator = "GreaterThan"
            threshold = 0
          }
        )
      }
      actions = @{
        actionGroups = @(
          $actionGroupValue.id
        )
      }
      autoMitigate = $false
    }
} | ConvertTo-Json -Depth 10
$queryValue = Invoke-RestMethod -Uri $queryUrl -Method PUT -Headers $azureHeader -Body $queryBody -ContentType "application/json"
$queryValue

# Get conditional access policies
$caUrl = "{0}/beta/identity/conditionalAccess/policies" -f $graphUrl 
$caPolicies = Invoke-RestMethod -Uri $caUrl -Method GET -Headers $graphHeader
$caBody = @{
    conditions = @{
        users = @{
            excludeUsers = @(
                $value.id
            )
        }
    }
} | ConvertTo-Json -Depth 5
# Update conditional access policies with MFA requirement
$caPolicies.value | Where-Object {$_.grantControls.builtInControls -match "mfa"} | ForEach-Object {
    $caUrl = "{0}/beta/identity/conditionalAccess/policies/{1}" -f $graphUrl, $_.id
    $caValue = Invoke-RestMethod -Uri $caUrl -Method PATCH -Headers $graphHeader -Body $caBody -ContentType "application/json"
    $caValue
}

