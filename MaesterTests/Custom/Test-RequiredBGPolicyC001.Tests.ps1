Describe "Check.BreakGlass1" {
    It "CUS.0003: Break Glass test CA001: Require strong multifactor authentication for admins" {

        $userId = '602b7044-910a-4155-b3fd-bd36ae7d1e1a' # Break Glass account 1
        $applicationId = '797f4846-ba00-4fd7-ba43-dac1f8f63013' # Windows Azure Management API 

        $policiesEnforced = Test-MtConditionalAccessWhatIf -UserId $userId `
        -IncludeApplications $applicationId
        $policiesEnforced.displayName | Should -Contain "CA001: Require strong multifactor authentication for admins"
    }
}