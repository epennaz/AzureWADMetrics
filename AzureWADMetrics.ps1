# ***********************************************************************  
# * DISCLAIMER:  
# *  
# * All sample code is provided by OSIsoft for illustrative purposes only.  
# * These examples have not been thoroughly tested under all conditions.  
# * OSIsoft provides no guarantee nor implies any reliability,  
# * serviceability, or function of these programs.  
# * ALL PROGRAMS CONTAINED HEREIN ARE PROVIDED TO YOU "AS IS"  
# * WITHOUT ANY WARRANTIES OF ANY KIND. ALL WARRANTIES INCLUDING  
# * THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY  
# * AND FITNESS FOR A PARTICULAR PURPOSE ARE EXPRESSLY DISCLAIMED.  
# ************************************************************************  
  
#SCRIPT TESTED VERSIONS:  
#$PSVersionTable  
#Name                           Value                                               
#----                           -----                                               
#PSVersion                      4.0                                                 
#WSManStackVersion              3.0                                                 
#SerializationVersion           1.1.0.1                                             
#CLRVersion                     4.0.30319.34209                                     
#BuildVersion                   6.3.9600.17090                                      
#PSCompatibleVersions           {1.0, 2.0, 3.0, 4.0}                                
#PSRemotingProtocolVersion      2.2   
  
#Import-Module Azure  
#Get-Module Azure  
#ModuleType Version    Name                                       
#---------- -------    ----                                    
#Manifest   0.8.10.1   Azure   
  
#PI AF Developer tools 2.6.0.5843  
  
#Credit to inspiration for Get-AzureWADMetrics goes to Michael Repperger 8-Aug-2014  
#Additional Information here - including adding a proxy server:  

#http://blogs.technet.com/b/omx/archive/2014/08/08/read-the-azure-storage-analytics-metrics-table-with-powershell.aspx 
function Get-AzureWADMetrics
{
<#
.SYNOPSIS
	tbd.
.DESCRIPTION
	tbd.
#>
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [string]
		$primaryStoreKey,
	    [parameter(Mandatory=$true)]
		[string]
		$storageName,
	    [parameter(Mandatory=$true)]
		[string]
		$minutesAgo
	)

    BEGIN 
    {
    }

    PROCESS
    {
        $strTable = 'WADPerformanceCountersTable()'
        $tableEP = 'https://'+$storageName+'.'+'Table'+'.core.windows.net/'

        $ts = [System.DateTime]::UTCNow.AddMinutes(-$minutesAgo)

        # Get the current date/time and format it properly the culture "" is the invariant culture
        $myDateObj = Get-Date
        $myInvariantCulture = New-Object System.Globalization.CultureInfo("")
        $strDate = $myDateObj.ToUniversalTime().ToString("R", $myInvariantCulture)

        # This will get only the metrics from when your partition key requests it (past 30 mins) in this case.
        $strTableUri = $tableEP + $strTable + '?$filter=PartitionKey%20ge%20''' + '0' + $ts.Ticks + ''''

        # Preare the HttpWebRequest
        $tableWebRequest = [System.Net.HttpWebRequest]::Create($strTableUri)
        $tableWebRequest.Timeout = 15000
        $tableWebRequest.ContentType = "application/xml"
        $tableWebRequest.Method = "GET"
        $tableWebRequest.Headers.Add("x-ms-date", $strDate)
      
         # Create a hasher and seed it with the storage key
        $sharedKey = [System.Convert]::FromBase64String( $primaryStoreKey)
        $myHasher = New-Object System.Security.Cryptography.HMACSHA256
        $myHasher.Key = $sharedKey

        # Create the Authorization header
        $strToSign = $tableWebRequest.Method + "`n" `
                    + $tableWebRequest.Headers.Get("Content-MD5") + "`n" `
                    + $tableWebRequest.Headers.Get("Content-Type") + "`n" `
                    + $tableWebRequest.Headers.Get("x-ms-date") + "`n" `
                    + '/' + $storageName + '/' + $strTable
        $bytesToSign = [System.Text.Encoding]::UTF8.GetBytes($strToSign)
        $strSignedStr = [System.Convert]::ToBase64String($myHasher.ComputeHash($bytesToSign))
        $strAuthHeader = "SharedKey " + $storageName + ":" + $strSignedStr
        $tableWebRequest.Headers.Add("Authorization", $strAuthHeader)

        # Read the results        
        $tableResponse = $tableWebRequest.GetResponse()
        $tableResponseReader = New-Object System.IO.StreamReader($tableResponse.GetResponseStream())
        [xml]$xmlMetricsData = $tableResponseReader.ReadToEnd()
        $tableResponseReader.Close()

        Write-Output $xmlMetricsData
       }

    END
    {
    }
}

function Set-AzureWADMetrics
{
<#
.SYNOPSIS
	tbd.
.DESCRIPTION
	tbd.
#> 
[CmdletBinding()]
    param (
            [Parameter(Mandatory = $true, ValueFromPipeline=$true)]
            $xmlMetricsData,
            [Parameter(Mandatory = $true)]
            [String]
            $subscriptionName,
            [Parameter(Mandatory = $true)]
            [String]
            $subscriptionID,
            [Parameter(Mandatory = $true)]
            [String[]]
            $azureVMs
            )

    BEGIN
    { 
    }
    
    PROCESS
    {
    $entries = $xmlMetricsData.feed.entry

    # Load AFSDK
    [System.Reflection.Assembly]::LoadWithPartialName("OSIsoft.AFSDKCommon") | Out-Null
    [System.Reflection.Assembly]::LoadWithPartialName("OSIsoft.AFSDK") | Out-Null

    # Create AF Object
    $PISystems=New-object 'OSIsoft.AF.PISystems'
    $PISystem=$PISystems.DefaultPISystem
    $myAFDB=$PISystem.Databases.DefaultDatabase

    # Create PI Object
    $PIDataArchives=New-object 'OSIsoft.AF.PI.PIServers'
    $PIDataArchive=$PIDataArchives.DefaultPIServer

    # Create AF UpdateOption
    $AFUpdateOption = New-Object 'OSISoft.AF.Data.AFUpdateOption'
    #Set AF Update Option to Replace
    $AFUpdateOption.value__ = "0"

    # Create AF BufferOption
    $AFBufferOption = New-Object 'OSISoft.AF.Data.AFBufferOption'
    #Set AF Buffer Option to Buffer if Possible
    $AFBufferOption.value__ = "1"

    #Create AF Recorded Value
    $AFRecordedValue = New-Object 'OSIsoft.AF.Data.AFBoundaryType'
    #Set AF recorded Value option to Inside
    $AFRecordedValue.value__ = "0"

    # Add required entries pulled from Azure Table in Get-AzureVMMetrics
    #Create the top level subscription element
    if($myAFDB.Elements.Contains($subscriptionID) -eq $false)
    {
        $mysubscriptionElement=$myAFDB.Elements.Add($subscriptionID) 
        $mysubscriptionElement.Description = $subscriptionName
    }
    else
    {
        #find just that element already created
        $mysubscriptionElement= $myAFDB.Elements | Where-Object {$_.Name -eq $subscriptionID}  
    }

    #Create the subelements corresponding to each VM monitored
    if($mysubscriptionElement.Elements.Contains($storageName) -eq $false)
    {
        $myElement=$mysubscriptionElement.Elements.Add($storageName) 
    }
    else
    {
        #find just that element already created
        $myElement = $mysubscriptionElement.Elements | Where-Object {$_.Name -eq $storageName} 
    }

                
    #Create the Attributes for Metrics
    #Order: 'Disk Read Bytes/sec,Disk Write Bytes/sec,Network Out,Percentage CPU,Network In'
     # Add required entries pulled from Azure Table in Get-AzureVMMetrics
    for($i=0; $i -lt $entries.Count; $i++)
    {
        $metricName = $entries.content.properties.CounterName[$i].Replace("\","_") 
        $metricValuesTimeStamps =  $entries.content.properties[$i].timestamp.'#text'
        [double]$metricValues = $entries.content.properties.CounterValue[$i].InnerText 
        $roleinstance =  $entries.content.properties[$i].roleinstance       

        $myAttrName = $roleinstance + $metricName  

        if($myElement.Attributes.Contains($myAttrName) -eq $false) 
        { $myAttr=$myElement.Attributes.Add($myAttrName)}
        else
        {$myAttr=$myElement.Attributes | Where-Object {$_.Name -eq $myAttrName}}
            
        # Assign Tag Name to the PI Point
        $tagName = $subscriptionID +'_' + $roleinstance + '_'+ $metricName #$tagname = "Testing"
                  
        #Create the PI Point associated with that attribute
		$piPoint = $null
        if([OSIsoft.AF.PI.PIPoint]::TryFindPIPoint($PIDataArchive,$tagName,[ref]$piPoint) -eq $false)
		{ 
            $piPoint = $piDataArchive.CreatePIPoint($tagName) 
        }			

        #Manipulate TimeStamp String to output something friendly for AF to input
		#example $timestamp = "2015-05-05T18:17:43.943Z"
		$timestampu = @(); foreach($tsz in $metricValuesTimeStamps) { $timestampu += ([Datetime]::Parse(($tsz -replace "Z",""))) }
			
        $recordedValues = New-Object 'Collections.Generic.List[OSIsoft.AF.Asset.AFValue]'
            
		for($j=0; $j -lt $timestampu.Count; $j++)
		{
			# Instantiate a new 'AFValue' object to persist...				
			$newValue = New-Object 'OSIsoft.AF.Asset.AFValue'

			# Fill in the properties.
			$newValue.Timestamp = New-object 'OSIsoft.AF.Time.AFTime'($timestampu[$j])   
            $newValue.pipoint = $pipoint
			$newValue.Value = $metricValues[$j]

			# Add to collection.
			$recordedValues.Add($newValue)	
		}
    
        #Update the PI Point Values
        try
        {
            $piPoint.UpdateValues($recordedValues,$AFUpdateOption)
        }
        catch
        {
            $message = ($_.ErrorDetails.Message)
            {continue}  
            #throw "{0}: {1}" -f $message.Error.Code, $message.Error.Message 
        }
        #Associate the PI point with that Attribute
        $myAttr.DataReferencePlugIn = $PISystem.DataReferencePlugIns["PI Point"]
        $myAttr.ConfigString = "\\%server%\$tagName;ReadOnly=false"
        
        #Check in the AF Elements
        $mysubscriptionElement.CheckIn()
        $myElement.CheckIn()
        
    }


    #Disconnect from the AF Server
    #$PISystem.Disconnect()

    # Disconnect from the PI Data Archive
    #$PIDataArchive.Disconnect()
    }
    END
    {
    }
   
}

#Calling the Scripts. Note that Set-AzureWADMetrics takes pipeline input from Get-AzureWADMetrics:
#Set the Azure Subscription to the current one  
$subscriptionName = 'XXXXXX' #Enter the name of your Subscription  
$selectAzureSubscription = Select-AzureSubscription -SubscriptionName $subscriptionName  

#Assume it's the first storagename hardcoded here, but may change.
$storageNames = (Get-AzureStorageAccount).Label 
$storageName = $storageNames[0]
 
$subscriptionID = $selectAzureSubscription.Id.ToString()  
  
#Retrieve all of the VMs and loop through them for individual output  
[String[]]$azureVMs = (Get-AzureVM).ServiceName  
  
#Save the storage account key (replace with your storage name hardcoded if you know it)  
$primaryStoreKey  = (Get-AzureStorageKey -StorageAccountName $storageName).Primary  

#How many minutes ago do you want to pull perfmon counters from:  
$minutesAgo = "30"    
  
#Get and Set the Azure Metrics. In this example, we pull the past 30 minutes from the WADPerformanceCounter NoSQL table.  
Get-AzureWADMetrics -primaryStoreKey $primaryStoreKey -storageName $storageName -minutesAgo $minutesAgo | Set-AzureWADMetrics -subscriptionName $subscriptionName -subscriptionID $subscriptionID -azureVMs $azureVMs 

