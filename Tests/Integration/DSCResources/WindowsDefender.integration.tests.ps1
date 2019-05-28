using module .\helper.psm1

$script:DSCCompositeResourceName = ($MyInvocation.MyCommand.Name -split '\.')[0]
. $PSScriptRoot\.tests.header.ps1
# Header

# Using try/finally to always cleanup even if something awful happens.
try
{
    #region Integration Tests
    $configFile = Join-Path -Path $PSScriptRoot -ChildPath "$($script:DSCCompositeResourceName).config.ps1"
    . $configFile

    $stigList = Get-StigVersionTable -CompositeResourceName $script:DSCCompositeResourceName

    #region Integration Tests

    foreach ($stig in $stigList)
    {
        [xml] $powerstigXml = Get-Content -Path $stig.Path

        $skipRule = Get-Random -InputObject $powerstigXml.DISASTIG.RegistryRule.Rule.id
        $skipRuleType = $null
        $expectedSkipRuleTypeCount = 0

        $skipRuleMultiple = Get-Random -InputObject $powerstigXml.DISASTIG.RegistryRule.Rule.id -Count 2
        $skipRuleTypeMultiple = $null
        $expectedSkipRuleTypeMultipleCount = 0

        $exception = Get-Random -InputObject $powerstigXml.DISASTIG.RegistryRule.Rule.id
        $exceptionMultiple = Get-Random -InputObject $powerstigXml.DISASTIG.RegistryRule.Rule.id -Count 2

        . "$PSScriptRoot\Common.integration.ps1"
    }
    #endregion Tests
}
finally
{
    Restore-TestEnvironment -TestEnvironment $TestEnvironment
}
