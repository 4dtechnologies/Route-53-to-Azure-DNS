# Amazon Route 53 to Microsoft Azure DNS Transfer Script
## 4D Technologies LLC
### Author: Jeff E. Denis

## The Task at Hand
Recently I was tasked with migrating our Amazon Route 53 DNS records to Microsoft Azure DNS. It's not uncommon to have several hundred DNS records for a given zone and entering them by hand would be nothing less than tedious. Rather than trudge through just under five hundred records and hope that mistakes weren't introduced, I figured a script would be better suited for the task.

## Prerequisites
This script assumes the following:
 
 - You've installed and configured the AWS Command Line Tool. For more information on how this is accomplished, please read: http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-set-up.html
 
 - The Azure Windows PowerShell cmdlets are installed. For more on this, check out: https://azure.microsoft.com/en-us/documentation/articles/powershell-install-configure/

 - You've created a target DNS Zone in Microsoft Azure. A reference on how to manage Azure DNS zones can be found at: https://azure.microsoft.com/en-us/documentation/articles/dns-operations-dnszones/
 
## Let's Get Started
In the User Defined Variables section of this script, set your Microsoft Azure and Amazon Web Services credentials. If you're unsure on what your AWS Hosted Zone Id is, try issuing this command in the AWS CLI: "aws route53 list-hosted-zones". This will produce a list of all the DNS zones accessible with your AWS IAM account.

Execute the script. Shortly after execution, it will request Azure login credentials. Be sure to use an account with appropriate permissions for the target subscription Id and resource group.

Once logged in, the script will begin the migration. The basic steps involved are:

 1. Log into Azure and select the target subscription and resource group
 2. Export the Route 53 DNS records as json
 3. Parse the export and prepare the records for import into Azure DNS
 4. Import the records into Azure based on a number of variables such as record type while avoiding import of SOA and NS records. These are automatically created with the Azure DNS zone.
 
## Precautions
As always, test your work when possible in a staged environment. Inspect the results and only once you're satisfied, run it against a production DNS zone. This script is intended to be run once for migration purposes.

## Trademarks
Any trademarks contained in the source code, and/or in the documentation, are the sole property of their respective owners.