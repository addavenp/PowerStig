# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License.
#region Main Function
<#
    .SYNOPSIS
        This function generates a new xml file based on the convert objects from ConvertFrom-StigXccdf.
    .PARAMETER Path
        The full path to the xccdf to convert.
    .PARAMETER Destination
        The full path to save the converted xml to.
    .PARAMETER CreateOrgSettingsFile
        Creates the orginazational settings files associated with the version of the STIG.
    .PARAMETER DoNotExportRawString
        Excludes the check-content elemet content from the converted object.
    .PARAMETER RuleIdFilter
        Filters the list rules that are converted to simplify debugging the conversion process.
    .PARAMETER DoNotExportDescription
        Excludes the Description elemet content from the converted object.
#>
function ConvertTo-PowerStigXml
{
    [CmdletBinding()]
    [OutputType([xml])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Path,

        [Parameter()]
        [string]
        $Destination,

        [Parameter()]
        [switch]
        $CreateOrgSettingsFile,

        [Parameter()]
        [switch]
        $DoNotExportRawString,

        [Parameter()]
        [string[]]
        $RuleIdFilter,

        [Parameter()]
        [switch]
        $DoNotExportDescription
    )

    Begin
    {
        $CurrentVerbosePreference = $global:VerbosePreference

        if ($PSBoundParameters.ContainsKey('Verbose'))
        {
            $global:VerbosePreference = 'Continue'
        }
    }
    Process
    {
        $convertedStigObjects = ConvertFrom-StigXccdf -Path $Path -RuleIdFilter $RuleIdFilter

        # Get the raw xccdf xml to pull additional details from the root node.
        [xml] $xccdfXml = Get-Content -Path $Path -Encoding UTF8
        [version] $stigVersionNumber = Get-StigVersionNumber -StigDetails $xccdfXml

        $ruleTypeList = Get-RuleTypeList -StigSettings $convertedStigObjects

        # Start the XML doc and add the root element
        $xmlDocument = [System.XML.XMLDocument]::New()
        [System.XML.XMLElement] $xmlRoot = $xmlDocument.CreateElement( 'DISASTIG' )

        <#
            Append as child to an existing node. This method will 'leak' an object out of the function
            so DO NOT remove the [void]
        #>
        [void] $xmlDocument.appendChild( $xmlRoot )
        $xmlRoot.SetAttribute( 'version' , $xccdfXml.Benchmark.version )
        $xmlRoot.SetAttribute( 'classification', 'UNCLASSIFIED' )
        $xmlRoot.SetAttribute( 'customname' , '' )
        $xmlRoot.SetAttribute( 'stigid' , $xccdfXml.Benchmark.ID )
        $xmlRoot.SetAttribute( 'description' , $xccdfXml.Benchmark.description )
        $xmlRoot.SetAttribute( 'filename' , (Split-Path -Path $Path -Leaf) )
        $xmlRoot.SetAttribute( 'releaseinfo' , $xccdfXml.Benchmark.'plain-text'.InnerText )
        $xmlRoot.SetAttribute( 'title' , $xccdfXml.Benchmark.title )
        $xmlRoot.SetAttribute( 'notice' , $xccdfXml.Benchmark.notice.Id )
        $xmlRoot.SetAttribute( 'source' , $xccdfXml.Benchmark.reference.source )
        $xmlRoot.SetAttribute( 'fullversion', $stigVersionNumber )
        $xmlRoot.SetAttribute( 'created', $(Get-Date).ToShortDateString() )

        # Add the STIG types as child elements
        foreach ( $ruleType in $ruleTypeList )
        {
            # Create the rule type node
            [System.XML.XMLElement] $xmlRuleType = $xmlDocument.CreateElement( $ruleType )

            # Append as child to an existing node. DO NOT remove the [void]
            [void] $xmlRoot.appendChild( $xmlRuleType )
            $XmlRuleType.SetAttribute( $xmlattribute.ruleDscResourceModule, $dscResourceModule.$ruleType )

            # Get the rules for the current STIG type.
            $rules = $convertedStigObjects | Where-Object { $PSItem.GetType().ToString() -eq $ruleType }

            # Get the list of properties of the current object type to use as child elements
            [System.Collections.ArrayList] $properties = $rules |
                Get-Member |
                Where-Object MemberType -eq Property |
                Select-Object Name -ExpandProperty Name

            <#
                The $properties array is used to set the child elements of the rule. Remove the base
                class properties from the array list that we do not want added as child elements.
            #>
            $propertiesToRemove = @($xmlattribute.ruleId, $xmlattribute.ruleSeverity,
                $xmlattribute.ruleConversionStatus, $xmlattribute.ruleTitle,
                $xmlattribute.ruleDscResource)

            <#
                Because the Remove method on an array is case sensitive and the properties names
                in $propertiesToRemove are in different case from $properties we use the -in comparison
                operator to filter and return the proper case
            #>
            $propertiesToRemove = $properties | Where-Object -FilterScript {$PSItem -in $propertiesToRemove}

            ### [TODO] ###
            <#
                Remove the Description if explicited requested. Once all PowerSTIG
                data files are updated with the description attribute, this and
                the $DoNotExportDescription can be removed from the function. This
                field is used to automatically generate a populated STIG checklist.
            #>
            if ( $DoNotExportDescription )
            {
                $propertiesToRemove += 'Description'
            }
            ### END TODO ###

            # Remove the raw string from the output if it was not requested.
            if ( $DoNotExportRawString )
            {
                $propertiesToRemove += 'RawString'
            }

            # These properties are removed becasue they are attributes of the object, not elements
            foreach ( $propertyToRemove in $propertiesToRemove )
            {
                [void] $properties.Remove( $propertyToRemove )
            }

            # Add the STIG details to the xml document.
            foreach ( $rule in $rules )
            {
                [System.XML.XMLElement] $xmlRuleTypeProperty = $xmlDocument.CreateElement( 'Rule' )
                # Append as child to an existing node. DO NOT remove the [void]
                [void] $xmlRuleType.appendChild( $xmlRuleTypeProperty )
                # Set the base class properties
                $xmlRuleTypeProperty.SetAttribute( $xmlattribute.ruleId, $rule.ID )
                $xmlRuleTypeProperty.SetAttribute( $xmlattribute.ruleSeverity, $rule.severity )
                $xmlRuleTypeProperty.SetAttribute( $xmlattribute.ruleConversionStatus, $rule.conversionstatus )
                $xmlRuleTypeProperty.SetAttribute( $xmlattribute.ruleTitle, $rule.title )
                $xmlRuleTypeProperty.SetAttribute( $xmlattribute.ruleDscResource, $rule.dscresource )

                foreach ( $property in $properties )
                {
                    [System.XML.XMLElement] $xmlRuleTypePropertyUnique = $xmlDocument.CreateElement( $property )
                    # Append as child to an existing node. DO NOT remove the [void]
                    [void] $xmlRuleTypeProperty.appendChild( $xmlRuleTypePropertyUnique )

                    # Skip any blank vaules
                    if ($null -eq $rule.$property)
                    {
                        continue
                    }
                    <#
                        The Permission rule returns an ACE list that needs to be serialized on a second
                        level. This will pick that up and expand the object in the xml.
                    #>
                    if ($property -eq 'AccessControlEntry')
                    {
                        foreach ($ace in $rule.$property)
                        {
                            [System.XML.XMLElement] $aceEntry = $xmlDocument.CreateElement( 'Entry' )
                            [void] $xmlRuleTypePropertyUnique.appendChild( $aceEntry )

                            # Add the ace entry Type
                            [System.XML.XMLElement] $aceEntryType = $xmlDocument.CreateElement( 'Type' )
                            [void] $aceEntry.appendChild( $aceEntryType )
                            $aceEntryType.InnerText = $ace.Type

                            # Add the ace entry Principal
                            [System.XML.XMLElement] $aceEntryPrincipal = $xmlDocument.CreateElement( 'Principal' )
                            [void] $aceEntry.appendChild( $aceEntryPrincipal )
                            $aceEntryPrincipal.InnerText = $ace.Principal

                            # Add the ace entry Principal
                            [System.XML.XMLElement] $aceEntryForcePrincipal = $xmlDocument.CreateElement( 'ForcePrincipal' )
                            [void] $aceEntry.appendChild( $aceEntryForcePrincipal )
                            $aceEntryForcePrincipal.InnerText = $ace.ForcePrincipal

                            # Add the ace entry Inheritance flag
                            [System.XML.XMLElement] $aceEntryInheritance = $xmlDocument.CreateElement( 'Inheritance' )
                            [void] $aceEntry.appendChild( $aceEntryInheritance )
                            $aceEntryInheritance.InnerText = $ace.Inheritance

                            # Add the ace entery FileSystemRights
                            [System.XML.XMLElement] $aceEntryRights = $xmlDocument.CreateElement( 'Rights' )
                            [void] $aceEntry.appendChild( $aceEntryRights )
                            $aceEntryRights.InnerText = $ace.Rights
                        }
                    }
                    elseif ($property -eq 'LogCustomFieldEntry')
                    {
                        foreach ($entry in $rule.$property)
                        {
                            [System.XML.XMLElement] $logCustomFieldEntry = $xmlDocument.CreateElement( 'Entry' )
                            [void] $xmlRuleTypePropertyUnique.appendChild( $logCustomFieldEntry )

                            [System.XML.XMLElement] $entrySourceType = $xmlDocument.CreateElement( 'SourceType' )
                            [void] $logCustomFieldEntry.appendChild( $entrySourceType )
                            $entrySourceType.InnerText = $entry.SourceType

                            [System.XML.XMLElement] $entrySourceName = $xmlDocument.CreateElement( 'SourceName' )
                            [void] $logCustomFieldEntry.appendChild( $entrySourceName )
                            $entrySourceName.InnerText = $entry.SourceName
                        }
                    }
                    else
                    {
                        $xmlRuleTypePropertyUnique.InnerText = $rule.$property
                    }
                }
            }
        }

        $fileList = Get-PowerStigFileList -StigDetails $xccdfXml -Destination $Destination

        try
        {
            $xmlDocument.save( $fileList.Settings.FullName )
            # The save method does not add the required blank line to the file
            Write-Output -InputObject `n | Out-File -FilePath $fileList.Settings.FullName -Append -Encoding utf8 -NoNewline
            Write-Output "Converted Output: $($fileList.Settings.FullName)"
        }
        catch [System.Exception]
        {
            Write-Error -Message $error[0]
        }

        if ($CreateOrgSettingsFile)
        {
            $OrganizationalSettingsXmlFileParameters = @{
                'convertedStigObjects' = $convertedStigObjects
                'StigVersionNumber'    = $stigVersionNumber
                'Destination'          = $fileList.OrgSettings.FullName
            }
            New-OrganizationalSettingsXmlFile @OrganizationalSettingsXmlFileParameters

            Write-Output "Org Settings Output: $($fileList.OrgSettings.FullName)"
        }
    }
    End
    {
        $global:VerbosePreference = $CurrentVerbosePreference
    }
}

<#
    .SYNOPSIS
        Compares the converted xml files from ConvertFrom-StigXccdf.
    .PARAMETER OldStigPath
        The full path to the previous PowerStigXml file to convert.
    .PARAMETER NewStigPath
        The full path to the current PowerStigXml file to convert.
#>
function Compare-PowerStigXml
{
    [CmdletBinding()]
    [OutputType([psobject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $OldStigPath,

        [Parameter(Mandatory = $true)]
        [string]
        $NewStigPath,

        [Parameter()]
        [switch]
        $IgnoreRawString
    )
    Begin
    {
        $CurrentVerbosePreference = $global:VerbosePreference

        if ($PSBoundParameters.ContainsKey('Verbose'))
        {
            $global:VerbosePreference = 'Continue'
        }
    }
    Process
    {

        [xml] $OldStigContent = Get-Content -Path $OldStigPath -Encoding UTF8
        [xml] $NewStigContent = Get-Content -Path $NewStigPath -Encoding UTF8

        $rules = $OldStigContent.DISASTIG.ChildNodes.ToString() -split "\s"

        $returnCompareList = @{}
        $compareObjects = @()
        $propsToIgnore = @()
        if ($ignoreRawString)
        {
            $propsToIgnore += "rawString"
        }
        foreach ( $rule in $rules )
        {
            $OldStigXml = Select-Xml -Xml $OldStigContent -XPath "//$rule/*"
            $NewStigXml = Select-Xml -Xml $NewStigContent -XPath "//$rule/*"

            if ($OldStigXml.Count -lt 2)
            {
                $prop = (Get-Member -MemberType Properties -InputObject $OldStigXml.Node).Name
            }
            else
            {
                $prop = (Get-Member -MemberType Properties -InputObject $OldStigXml.Node[0]).Name
            }
            $OldStigXml = $OldStigXml.Node | Select-Object $prop -ExcludeProperty $propsToIgnore

            if ($NewStigXml.Count -lt 2)
            {
                $prop = (Get-Member -MemberType Properties -InputObject $NewStigXml.Node).Name
            }
            else
            {
                $prop = (Get-Member -MemberType Properties -InputObject $NewStigXml.Node[0]).Name
            }
            $NewStigXml = $NewStigXml.Node | Select-Object $prop -ExcludeProperty $propsToIgnore

            $compareObjects += Compare-Object -ReferenceObject $OldStigXml -DifferenceObject $NewStigXml -Property $prop
        }

        $compareIdList = $compareObjects.Id

        foreach ($stig in $compareObjects)
        {
            $compareIdListFilter = $compareIdList |
                Where-Object {$PSitem -eq $stig.Id}

            if ($compareIdListFilter.Count -gt "1")
            {
                $delta = "changed"
            }
            else
            {
                if ($stig.SideIndicator -eq "=>")
                {
                    $delta = "added"
                }
                elseif ($stig.SideIndicator -eq "<=")
                {
                    $delta = "deleted"
                }
            }

            if ( -not $returnCompareList.ContainsKey($stig.Id))
            {
                [void] $returnCompareList.Add($stig.Id, $delta)
            }
        }
        $returnCompareList.GetEnumerator() | Sort-Object Name
    }
    End
    {
        $global:VerbosePreference = $CurrentVerbosePreference
    }
}
#endregion

#region Private Functions
$organizationalSettingRootComment = @'

    The organizational settings file is used to define the local organizations
    preferred setting within an allowed range of the STIG.

    Each setting in this file is linked by STIG ID and the valid range is in an
    associated comment.

'@

<#
    .SYNOPSIS
        Creates the Organizational settings file that accompanies the converted STIG data.
    .PARAMETER convertedStigObjects
        The Converted Stig Objects to sort through
    .PARAMETER StigVersionNumber
        The version number of the xccdf that is being processed.
    .PARAMETER Destination
        The path to store the output file.
#>
function New-OrganizationalSettingsXmlFile
{
    [CmdletBinding()]
    [OutputType()]
    param
    (
        [Parameter(Mandatory = $true)]
        [psobject]
        $ConvertedStigObjects,

        [Parameter(Mandatory = $true)]
        [version]
        $StigVersionNumber,

        [Parameter(Mandatory = $true)]
        [string]
        $Destination
    )

    $OrgSettings = Get-StigObjectsWithOrgSettings -ConvertedStigObjects $ConvertedStigObjects

    $xmlDocument = [System.XML.XMLDocument]::New()

    ##############################   Root object   ###################################
    [System.XML.XMLElement] $xmlRootElement = $xmlDocument.CreateElement( 'OrganizationalSettings' )

    [void] $xmlDocument.appendChild( $xmlRootElement )
    [void] $xmlRootElement.SetAttribute( 'fullversion', $StigVersionNumber )

    $rootComment = $xmlDocument.CreateComment( $organizationalSettingRootComment )
    [void] $xmlDocument.InsertBefore( $rootComment, $xmlRootElement )

    #########################################   Root object   ##########################################
    #########################################    ID object    ##########################################

    foreach ( $orgSetting in $OrgSettings)
    {
        [System.XML.XMLElement] $xmlSettingChildElement = $xmlDocument.CreateElement( 'OrganizationalSetting' )

        [void] $xmlRootElement.appendChild( $xmlSettingChildElement )

        $xmlSettingChildElement.SetAttribute( $xmlAttribute.ruleId , $orgSetting.id )

        $xmlSettingChildElement.SetAttribute( $xmlAttribute.organizationalSettingValue , "LOCAL_STIG_SETTING_HERE")

        $settingComment = " Ensure $(($orgSetting.OrganizationValueTestString) -f "'$($orgSetting.Id)'")"

        $rangeNameComment = $xmlDocument.CreateComment($settingComment)
        [void] $xmlRootElement.InsertBefore($rangeNameComment, $xmlSettingChildElement)
    }
    #########################################    ID object    ##########################################

    $xmlDocument.Save( $Destination )
}

<#
    .SYNOPSIS
        Creates a version number from the xccdf benchmark element details.
    .PARAMETER stigDetails
        A reference to the in memory xml document.
    .NOTES
        This function should only be called from the public ConvertTo-DscStigXml function.
#>
function Get-StigVersionNumber
{
    [CmdletBinding()]
    [OutputType([version])]
    param
    (
        [Parameter(Mandatory = $true)]
        [xml]
        $StigDetails
    )

    # Extract the revision number from the xccdf
    $revision = ( $StigDetails.Benchmark.'plain-text'.'#text' `
            -split "(Release:)(.*?)(Benchmark)" )[2].trim()

    "$($StigDetails.Benchmark.version).$revision"
}

<#
    .SYNOPSIS
        Creates the file name to create from the xccdf content
    .PARAMETER StigDetails
        A reference to the in memory xml document.
    .NOTES
        This function should only be called from the public ConvertTo-DscStigXml function.
#>
function Get-PowerStigFileList
{
    [CmdletBinding()]
    [OutputType([Hashtable[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [xml]
        $StigDetails,

        [Parameter()]
        [string]
        $Destination
    )

    $id = Split-BenchmarkId -Id $stigDetails.Benchmark.id

    $fileNameBase = "$($id.Technology)-$($id.TechnologyVersion)"

    # If there is a technology role add it to the output name
    if ($id.TechnologyRole)
    {
        $fileNameBase = $fileNameBase + "-$($id.TechnologyRole)"
    }

    $fileNameBase = $fileNameBase + "-$(Get-StigVersionNumber -StigDetails $StigDetails)"

    if ($Destination)
    {
        $Destination = Resolve-Path -Path $Destination
    }
    else
    {
        $Destination = "$(Split-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot)))\StigData\Processed"
    }

    Write-Verbose "[$($MyInvocation.MyCommand.Name)] Destination: $Destination"

    return @{
        Settings    = [System.IO.FileInfo]::new("$Destination\$fileNameBase.xml")
        OrgSettings = [System.IO.FileInfo]::new("$Destination\$fileNameBase.org.default.xml")
    }
}

<#
    .SYNOPSIS
        Splits the Xccdf benchmark ID into an object.
    .PARAMETER Id
        The Id field from the Xccdf benchmark.
#>
function Split-BenchmarkId
{
    [CmdletBinding()]
    [OutputType([Hashtable[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $Id
    )

    # Different STIG's present the Id field in a different format.
    $idVariations = @(
        '(_+)STIG',
        '(_+)Security_Technical_Implementation_Guide_NewBenchmark',
        '(_+)Security_Technical_Implementation_Guide'
    )
    $sqlServerVariations = @(
        'Microsoft_SQL_Server',
        'MS_SQL_Server'
    )
    $sqlServerInstanceVariations = @(
        'Database_Instance'
    )
    $windowsVariations = @(
        'Microsoft_Windows',
        'Windows_Server',
        'Windows'
    )
    $dnsServerVariations = @(
        'Server_Domain_Name_System',
        'Domain_Name_System'
    )
    $activeDirectoryVariations = @(
        'Active_Directory'
    )
    $OfficeVariations = @(
        'Excel',
        'Outlook',
        'PowerPoint',
        'Word'
    )

    $id = $id -replace ($idVariations -join '|'), ''

    switch ($id)
    {
        {$PSItem -match "SQL_Server"}
        {
            $returnId = $id -replace ($sqlServerVariations -join '|'), 'SqlServer'
            $returnId = $returnId -replace ($sqlServerInstanceVariations -join '|'), 'Instance'
            continue
        }
        {$PSItem -match "_Firewall"}
        {
            $returnId = 'WindowsFirewall_All'
            continue
        }
        {$PSItem -match "Windows_Defender_Antivirus"}
        {
            $returnId = 'WindowsDefender_All'
            continue
        }
        {$PSItem -match "IIS_8-5_Server"}
        {
            $returnId = 'IISServer-8.5'
            continue
        }
        {$PSItem -match "IIS_8-5_Site"}
        {
            $returnId = 'IISSite-8.5'
            continue
        }
        {$PSItem -match "Domain_Name_System"}
        {
            # The Windows Server 2012 and 2012 R2 STIGs are combined, so return the 2012R2
            $id = $id -replace '_2012_', '_2012R2_'
            $returnId = $id -replace ($dnsServerVariations -join '|'), 'DNS'
            $returnId = $returnId -replace ($windowsVariations -join '|'), 'WindowsServer'
            continue
        }
        {$PSItem -match "Windows_10"}
        {
            $returnId = $id -Replace "Windows", 'WindowsClient'
            continue
        }
        {$PSItem -match "Windows"}
        {
            # The Windows Server 2012 and 2012 R2 STIGs are combined, so return the 2012R2
            $id = $id -replace '_2012_', '_2012R2_'
            $returnId = $id -replace ($windowsVariations -join '|'), 'WindowsServer'
            continue
        }
        {$PSItem -match "Active_Directory"}
        {
            $role = ($id -split '_')[-1]
            $returnId = "ActiveDirectory_All_$role"
            continue
        }
        {$PSItem -match "IE_"}
        {
            $returnId = "InternetExplorer_11"
            continue
        }
        {$PSItem -match 'FireFox'}
        {
            $returnId = "FireFox_All"
            continue
        }
        {$PSItem -match 'Excel' -or $PSItem -match 'Outlook' -or $PSItem -match 'PowerPoint' -or $PSItem -match 'Word'}
        {
            $officeStig = ($id -split '_')
            $officeStig = $officeStig[1] + $officeStig[2]
            $returnId = 'Office_' + $officeStig
            continue
        }
        {$PSItem -match 'Dot_Net'}
        {
            $returnId = 'DotNetFramework_4'
            continue
        }
        default
        {
            $returnId = $id
        }
    }

    $returnId = $returnId -Split '_'

    return @{
        'Technology'        = $returnId[0]
        'TechnologyVersion' = $returnId[1]
        'TechnologyRole'    = $returnId[2]
    }
}

<#
    .SYNOPSIS
        Filters the list of STIG objects and returns anything that requires an organizational decision.
    .PARAMETER convertedStigObjects
        A reference to the object that contains the converted stig data.
    .NOTES
        This function should only be called from the public ConvertTo-DscStigXml function.
#>
function Get-StigObjectsWithOrgSettings
{
    [CmdletBinding()]
    [OutputType([psobject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [psobject]
        $ConvertedStigObjects
    )

    $ConvertedStigObjects |
        Where-Object { $PSitem.OrganizationValueRequired -eq $true}
}
#endregion
