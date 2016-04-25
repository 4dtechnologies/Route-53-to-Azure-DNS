###############################################################################
#
#    Amazon Route 53 to Microsoft Azure DNS Transfer Script
#
#    Copyright (C) 2016 4D Technologies LLC
#	 Author: Jeff E. Denis
#
#	 This program comes with ABSOLUTELY NO WARRANTY
#	 GNU GENERAL PUBLIC LICENSE Version 3
#
###############################################################################

function defineEnvironment {

    # -------------------------------------------
    # User Defined Variables
    # -------------------------------------------

    # -------------------------------------------------------------------------------#
    
    # Enter your environment information here:

    # Azure Subscription ID
    $userDefAzureSubscriptionId = "" #AZURE SUBSRIPTION ID GUID
    $userDefResourceGroup = "" #AZURE RESOURCE GROUP
    
    # AWS IAM KeyId, Secret, Region, and Default Format
    $userDefAWSKeyId = "" #AWS IAM ID
    $userDefAWSSecret = "" # AWS IAM SECRET
    $userDefAWSRegion = "" #AWS REGION (us-east-1)
    $userDefAWSFormat = ""

    # AWS Route53 Hosted Zone to Transfer
    $GLOBAL:route53HostedZone = "/hostedzone/[]" # [Hosted Zone Id]
	
	# Windows Azure Target Domain
	$GLOBAL:userDefAzureDNSZone = "" # Target Azure DNS Zone Name
    $GLOBAL:userDefAzureTargetDomain = "" # Target Azure DNS Domain

    # -------------------------------------------------------------------------------#
    
    # Configure the environment based on provided info
    setupEnvironment (
        $userDefAzureSubscriptionId,
        $userDefResourceGroup,
        $userDefAWSKeyId,
        $userDefAWSSecret,
        $userDefAWSRegion,
        $userDefAWSFormat,
        $route53HostedZone
        )

}

function setupEnvironment {

    # -------------------------------------------
    # Set up the Environment
    # -------------------------------------------

    Write-Host -ForegroundColor White "Setting up azure PowerShell Environment"

    # Init Azure Configurations
    $GLOBAL:azureConfig = @()

    # Retrieve Azure Subscription Id
    Add-Member -InputObject $azureConfig -MemberType NoteProperty -Name subscriptionId -Value ($userDefAzureSubscriptionId)
    
    # Log into Azure
    azureLogin

    # Azure Resource Group, Record Tag (to easily identify imported records), and DNS Domain
    Add-Member -InputObject $azureConfig -MemberType NoteProperty -Name resourceGroup -Value ($userDefResourceGroup)
    Add-Member -InputObject $azureConfig -MemberType NoteProperty -Name azureDNSZone -Value (Get-AzureRmDnsZone -Name ($userDefAzureDNSZone) –ResourceGroupName $azureConfig.resourceGroup)

    Write-Host -ForegroundColor White "Setting up AWS CLI Environment"

    # AWS CLI Configuration
    $GLOBAL:AWSconfig = @()
    
    # AWS IAM KeyId, Secret, Region, and Default Format
    Add-Member -InputObject $AWSconfig -MemberType NoteProperty -Name keyid -Value ($userDefAWSKeyId)
    Add-Member -InputObject $AWSconfig -MemberType NoteProperty -Name secret -Value ($userDefAWSSecret)
    Add-Member -InputObject $AWSconfig -MemberType NoteProperty -Name region -Value ($userDefAWSRegion)
    Add-Member -InputObject $AWSconfig -MemberType NoteProperty -Name format -Value ($userDefAWSFormat)

    [uint32]$GLOBAL:recordsWritten = 0
}

function azureLogin {

    # -------------------------------------------
    # Log into Windows Azure and Select Subscription
    # -------------------------------------------
    
    Write-Host -ForegroundColor White "Prompting for azure Login"

    # Prompt the user to log into their Azure account
    Login-AzureRmAccount

    # Select the user defined subscription ID (TODO: Verify that this completed)
    Select-AzureRmSubscription -Subscriptionid $azureConfig.subscriptionId

}


function parseRoute53 {

    # -------------------------------------------
    # Parse Output from AWS Command Line Tool
    # -------------------------------------------

    Write-Host -ForegroundColor White "Collecting and Parsing Records from Route 53 DNS"

    # Read in the Route53 hosted zone from the AWS CLI export.
    $GLOBAL:rawAWSjson = cmd.exe /c "aws route53 list-resource-record-sets --hosted-zone-id $route53HostedZone"
    
    # Parse as json string
    $GLOBAL:jsonString = $rawAWSjson | Out-String | ConvertFrom-Json
    
    # Create a global variable to house the DNS records export    
    [System.Collections.ArrayList]$GLOBAL:route53Records=@()
     
	# Parse the output and prepare it for import into Azure DNS
    foreach ($ResourceRecords in $jsonString.ResourceRecordSets) {
    
        foreach ($existingRecord in $ResourceRecords.ResourceRecords) {
    
			# Add DNS Record Properties
            Add-Member -InputObject $existingRecord -MemberType NoteProperty -Name Name -Value ($ResourceRecords.Name.TrimEnd('.'))
            Add-Member -InputObject $existingRecord -MemberType NoteProperty -Name Type -Value ($ResourceRecords.Type)
            Add-Member -InputObject $existingRecord -MemberType NoteProperty -Name TTL -Value ($ResourceRecords.TTL)
            Add-Member -InputObject $existingRecord -MemberType NoteProperty -Name Preference -Value ('')
            Add-Member -InputObject $existingRecord -MemberType NoteProperty -Name Priority -Value ('')
            Add-Member -InputObject $existingRecord -MemberType NoteProperty -Name Weight -Value ('')
            Add-Member -InputObject $existingRecord -MemberType NoteProperty -Name Port -Value ('')

            # Check for MX record and set required properties
            if ($ResourceRecords.Type -eq 'MX') {                

                $existingRecord.Preference = [uint16]$existingRecord.Value.Split(' ')[0]
				$existingRecord.Value = $existingRecord.Value.Split(' ')[1]

            # Check for SRV record and set required properties
            } elseif ($ResourceRecords.Type -eq 'SRV') {                

                $existingRecord.Priority = $existingRecord.Value.Split(' ')[0]
                $existingRecord.Weight = $existingRecord.Value.Split(' ')[1]
                $existingRecord.Port = [uint16]$existingRecord.Value.Split(' ')[2]
                $existingRecord.Value = $existingRecord.Value.Split(' ')[3]

            # Check for SPF record and set required properties
            } elseif ($ResourceRecords.Type -eq 'SPF') {
                            
                $existingRecord.Type = "TXT"

            }
           
            # Handle wildcards
            if ($existingRecord.Name.Split('.')[0] -eq '\052') {

				$existingRecord.Name = $existingRecord.Name.Replace('\052', '*')

            }

            # Clean the root domain out of the name property

            if ($existingRecord.Name -eq $userDefAzureTargetDomain) {

                $existingRecord.Name = '@'

            } else {

                $existingRecord.Name = $existingRecord.Name.Replace($userDefAzureTargetDomain,'').TrimEnd('.')

            }

            $route53Records.Add($existingRecord)

        }

    }
   
}

function azureImportRecords {

    # -------------------------------------------
    # Import Route 53 Records into Azure DNS
    # -------------------------------------------
    
    Write-Host -ForegroundColor White "Importing Route 53 Records into Azure DNS"
     
    foreach ($ResourceRecords in $route53Records) { 

        # Clear the recordPrecheck value
        $recordPrecheck = ''

        # Check if a record set by this name already exists
        $recordPrecheck = Get-AzureRmDnsRecordSet -Name $ResourceRecords.Name -ResourceGroupName $azureConfig.resourceGroup -ZoneName $azureConfig.azureDNSZone.Name -RecordType $ResourceRecords.Type -ErrorAction SilentlyContinue

        if ($recordPrecheck.Name -ne $ResourceRecords.Name -and $recordPrecheck.RecordType -ne $ResourceRecords.Type -and $recordPrecheck.Value -ne $ResourceRecords.Value ) {
           
            # Configure the new record set and adjust the type as necessary before commiting the record
            if ($ResourceRecords.Type -eq 'A') {

                newRecord
                Add-AzureRmDnsRecordConfig -RecordSet $azureDNSRecordSet -Ipv4Address $ResourceRecords.Value
                commitRecord

            } elseif ($ResourceRecords.Type -eq 'AAAA') {
                
                newRecord
                Add-AzureRmDnsRecordConfig -RecordSet $azureDNSRecordSet -Ipv6Address $ResourceRecords.Value
                commitRecord

            } elseif ($ResourceRecords.Type -eq 'CNAME') {

                newRecord
                Add-AzureRmDnsRecordConfig -RecordSet $azureDNSRecordSet -Cname $ResourceRecords.Value
                commitRecord

            } elseif ($ResourceRecords.Type -eq 'MX') {

                newRecord
                Add-AzureRmDnsRecordConfig -RecordSet $azureDNSRecordSet -Exchange $ResourceRecords.Value -Preference $ResourceRecords.Preference
                commitRecord

            } elseif ($ResourceRecords.Type -eq 'NS' -or $ResourceRecords.Type -eq 'SOA') {

                Write-Host -ForegroundColor Gray "INFO: Encountered"($ResourceRecords.Type)"record. Skipping"
            
            } elseif ($ResourceRecords.Type -eq 'SRV') {

                # Change the record type to be SRV to comply with Azure DNS
                $ResourceRecords.Type = "SRV"
                newRecord
                Add-AzureRmDnsRecordConfig -RecordSet $azureDNSRecordSet -Priority $ResourceRecords.Priority -Port $ResourceRecords.Port -Weight $ResourceRecords.Weight  -Target $ResourceRecords.Value
                commitRecord

            } elseif ($ResourceRecords.Type -eq 'TXT' -or $ResourceRecords.Type -eq 'SPF') {

                newRecord
                Add-AzureRmDnsRecordConfig -RecordSet $azureDNSRecordSet -Value $ResourceRecords.Value
                commitRecord
       
            } else {

                # If the record was not one that we were expecting, map it as TXT to avoid loss and inform the user.
                Write-Host -ForegroundColor Red "ERROR: Could not map the record type for"($ResourceRecords.Name)"!"
                        
            }


        } else {
			
			# Warn the user if an existing record is discovered
            Write-Host -ForegroundColor Yellow "WARNING: The"($ResourceRecords.Type)"set for"($ResourceRecords.Name)"already exists!"

        }
        
    }
    
	# Inform the user that the records have been written
    Write-Host -ForegroundColor Green "Import of"($route53HostedZone)"finished."($recordsWritten)"new records written."

}

function newRecord {

    # -------------------------------------------
    # Define and create the new azure DNS record set
    # -------------------------------------------
    
    # Check that we're not about to exceed the limit for Azure DNS records
    if ($recordsWritten > 4998) {
     
        Write-Host -ForegroundColor Red "FATAL: Azure DNS does not support more than 5,000 records in a single DNS Zone"
        cleanup
    
    } else {
    
	# Inform the user of the record currently being created
    Write-Host -ForegroundColor White "Creating new record set:"($ResourceRecords.Name)
    
	# Create a new record
	$GLOBAL:azureDNSRecordSet = New-AzureRmDnsRecordSet -Name $ResourceRecords.Name -RecordType $ResourceRecords.Type -Ttl $ResourceRecords.TTL –Zone $azureConfig.azureDNSZone
    
	# Increment the records written counter
	$GLOBAL:recordsWritten++

    }

}

function commitRecord {

    # -------------------------------------------
    # Commit the record set
    # -------------------------------------------
    
    Write-Host -ForegroundColor White "Commiting the record set.."
    
	# Commit the new record
	Set-AzureRmDnsRecordSet -RecordSet $azureDNSRecordSet

}


function cleanup(){
    
    # -------------------------------------------
    # Remove variables
    # -------------------------------------------

    Write-Host -ForegroundColor White "Cleanup: Removing Variables"
    Remove-Variable -Scope Global -Name route53Records, azureConfig, AWSconfig, userDefAzureDNSZone, userDefAzureTargetDomain

    # If we wrote any records, clean up the record set variable
    if ($recordsWritten -ne 0) {

        Remove-Variable -Scope Global -Name azureDNSRecordSet

    }

    exit
    
}

function main() {

    defineEnvironment
    parseRoute53
    azureImportRecords
    cleanup

}

# Let's roll
main