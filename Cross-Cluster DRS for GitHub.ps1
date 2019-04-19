<#

Script Author: Sayan Saha , @sayansaha911

Synopsis:
This script was created for a Private Cloud environment where VM deployment policy is defined to 
deploy VMs only in one Cluster. This created resource crunch on one cluster and hence the script 
calculates Cluster Memory and Datastore trheshold and moves VMs to a different cluster.

Resource data collection has been defined as functions which has been called later to perform the final vMotion.

Thresholds were defined in If-Else conditions according to our requirement. 
Please feel free to change the threshold and the script should work fine.

#>



##########################################################################################################################################
#####################################################Connect to vCenter###################################################################
##########################################################################################################################################

$user = "username"
$password = "password"
Connect-VIServer "vCenter Server Name" -User $user -Password $password

##########################################################################################################################################
#####################################################Defining Variables###################################################################
##########################################################################################################################################


$Cluster = Get-Cluster "Spurce Cluster Name"
$Datastore = Get-DatastoreCluster "Source Datastore Cluster Name"
$NTXCluster = Get-Cluster "Destination Cluster Name"
$NTXDatastore = Get-DatastoreCluster "Destination Datastore Cluster Name"



##########################################################################################################################################
#########################################Function For Cluster Average Memory##############################################################
##########################################################################################################################################

Function Get-ClusterAvgResource {

param ($ClusterName)

$cluster = get-cluster $ClusterName 

$hosts = $cluster |get-vmhost
[double]$cpuAverage = 0
[double]$memAverage = 0
#Write-Host $cluster
   
foreach ($esx in $hosts) 
        {
        #Write-Host $esx
        [double]$esxiCPUavg = [double]($esx | Select-Object @{N = 'cpuAvg'; E = {[double]([math]::Round(($_.CpuUsageMhz) / ($_.CpuTotalMhz) * 100, 2))}} |Select-Object -ExpandProperty cpuAvg)
        $cpuAverage = $cpuAverage + $esxiCPUavg
        [double]$esxiMEMavg = [double]($esx | Select-Object @{N = 'memAvg'; E = {[double]([math]::Round(($_.MemoryUsageMB) / ($_.MemoryTotalMB) * 100, 2))}} |select-object -ExpandProperty memAvg)
        $memAverage = $memAverage + $esxiMEMavg
        }

$cpuAverage = [math]::Round(($cpuAverage / ($hosts.count) ), 1)
$memAverage = [math]::Round(($memAverage / ($hosts.count) ), 1)
$ClusterInfo = "" | Select-Object Name, CPUAvg, MEMAvg
$ClusterInfo.Name = $cluster.Name
$ClusterInfo.CPUAvg = $cpuAverage
$ClusterInfo.MEMAvg = $memAverage

echo $memAverage
}


##########################################################################################################################################
########################################Function to find Nutanix Datastore Details########################################################
##########################################################################################################################################


Function Get-DestinationDatastore {

param ($DestinationDatastoreCluster)


$DestinationDatastore = $null
$DestinationDatastore = Get-Datastore -Location $DestinationDatastoreCluster | Sort-Object FreeSpaceGB -Descending | Select-Object -First 1
$PercentFree = $null
$PercentFree = [Math]::round((($DestinationDatastore.FreeSpaceGB/$DestinationDatastore.CapacityGB) * 100))

$DestDatastoreInfo = "" | Select-Object Name, PercentFree, VMs
$DestDatastoreInfo.Name = $DestinationDatastore.Name
$DestDatastoreInfo.PercentFree = $PercentFree
$DestDatastoreInfo.VMs = $DestinationDatastore | Get-VM


$DestDatastoreInfo
}


##########################################################################################################################################
##########################################Function to find GTCI Datastore Details#########################################################
##########################################################################################################################################


Function Get-SourceDatastore {

param ($SourceDatastoreCluster)



$SourceDatastore = $null
$SourceDatastore = Get-Datastore -Location $SourceDatastoreCluster | Sort-Object FreeSpaceGB -Descending | Select-Object -Last 1
$PercentFree = $null
$PercentFree = [Math]::round(($SourceDatastore.FreeSpaceGB/$SourceDatastore.CapacityGB) * 100)


$DatastoreInfo = "" | Select-Object Name, PercentFree, VMs
$DatastoreInfo.Name = $SourceDatastore.Name
$DatastoreInfo.PercentFree = $PercentFree
$DatastoreInfo.VMs = $SourceDatastore | Get-VM

$DatastoreInfo
}

##########################################################################################################################################
############################################Function to find Latest VMs Commissioned by UCSD##############################################
##########################################################################################################################################


Function Get-LatestVM {

param  ($ClusterName)
$VM = $null
$VMs = Get-VM -Location $ClusterName
$Object = $Null
$Object = @()

foreach ($VM in $VMs)
    {
    $VMName = $null
    $VMName = ($VM.name.split('-')[1]).Trim()
    $VMNumber = $null
    $VMNumber = ($VM.name.split('-')[2]).Trim() 
 
    if ($VMName -eq "UVM")
       {$Object += $VMNumber}
    }

$VMNumber = $Object | Sort-Object -Descending | Select-Object -First 20
$VMNumbering = $VMNumber | Select-Object -Last 10

$LatestVMs = @()
foreach ($Number in $VMNumbering)
    {
    #$Number1 = [string]$Number
    $join = -join ("INBLR-UVM-", $Number)
    $LatestVMs += $join
    }

echo $LatestVMs
}


##########################################################################################################################################
###################################################Function to Send Email#################################################################
##########################################################################################################################################


Function Send-Mail($DatastoreName)
{

Process{
$From = "Enter your corporate email address"
$To = "Storage Team Email"
$Cc = "Team who needs to be informed"
$Date = ( get-date ).ToString('yyyy/MM/dd')
$Subject = "Low Space Alert on $DatastoreName - $Date"
$SMTPServer = "Enter SMTP server details"
$SMTPPort = "587"
$Body = "Hi Team, `n

Datastores are full in $DatastoreName and each datastore in the cluster has less than 15% free space. Please do the needful.


Thanks and Regards,

Sayan Saha
Microsoft® Certified IT Professional | ITIL V3 Foundation | System Analyst | TIS-InTC 
Unisys Global Services - India | Purva Premier No.135/1, Residency Road | Bangalore 560025 | Direct Phone: +91 080 41595943 | Net Phone: 7595943 | Mobile phone: +91 9663884091 | Email: sayan.saha@in.unisys.com
 

THIS COMMUNICATION MAY CONTAIN CONFIDENTIAL AND/OR OTHERWISE PROPRIETARY MATERIAL and is for use only by the intended recipient. If you received this in error, please contact the sender and delete the e-mail and its attachments from all devices.

"

Send-MailMessage -From $From -To $To -Cc $Cc -Subject $Subject -Body $Body -SmtpServer NA-MAILRELAY-T3.na.uis.unisys.com
        }
}



##########################################################################################################################################
############################################Migrating VMs based on Cluster Memory Threshold###############################################
##########################################################################################################################################


$VMs =  Get-LatestVM -ClusterName $Cluster


Foreach ($VM in $VMs)

    {
    $ClusterMemory = $null
    $ClusterMemory = Get-ClusterAvgResource -ClusterName $Cluster

        If ($ClusterMemory -gt 70)
            {
            $DatastoreTo = $null
            $DatastoreTo = Get-DestinationDatastore -DestinationDatastoreCluster $NTXDatastore
        
                If ($DatastoreTo.PercentFree -gt 10)
                    {
                    
                    #$VM |  Move-VM -Destination (Get-VMHost -Location $NTXCluster | Sort-Object "MemoryUsageGB" | select -First 1) -Datastore $DatastoreTo -confirm:$false -RunAsync:$true
                    echo $VM "moving to" ((Get-VMHost -Location $NTXCluster | Sort-Object "MemoryUsageGB" | select -First 1).Name)  $DatastoreTo.Name
                    
                    }
            
                Else 
                    {
                    #Send-Mail -DatastoreName  $NTXDatastore
                    break
                    }
            }
     }

     
##########################################################################################################################################
############################################Migrating VMs based on Cluster Datastore Threshold############################################
##########################################################################################################################################


$DatastoreFrom = Get-SourceDatastore -SourceDatastoreCluster $Datastore


$Objects = @()
Foreach ($VM in $DatastoreFrom.VMs)
    {
    If ($VM.PowerState -eq "PoweredOff")
        {$Objects += $VM}

    }
#$Objects
$VM = $Null
$VMs = $Null

If ($Objects)
    {
    Foreach ($VM in $Objects)
        {
        $DatastoreFrom = (Get-SourceDatastore -SourceDatastoreCluster $Datastore).PercentFree
    

            If ($DatastoreFrom -le 5)
                {
                $DatastoreTo = $null
                $DatastoreTo = Get-DestinationDatastore -DestinationDatastoreCluster $NTXDatastore
        
                    If ($DatastoreTo.PercentFree -gt 10)
                        {
                        echo $VM.Name "moving to" ((Get-VMHost -Location $NTXCluster | Sort-Object "MemoryUsageGB" | select -First 1).Name) $DatastoreTo.Name
                        #$VM |  Move-VM -Destination (Get-VMHost -Location $NTXCluster | Sort-Object "MemoryUsageGB" | select -First 1) -Datastore $DatastoreTo -confirm:$false -RunAsync:$true
                        }
            
                    Else 
                        {
                        #Send-mail -DatastoreName $NTXDatastore
                        break
                        }
                }
         }
     }

Else
    {
    $VMs = Get-Datastore -Location $Datastore | Get-VM | Where-Object -Property PowerState -EQ "PoweredOff" | Select-Object -First 5
        
        Foreach ($VM in $VMs)
            {
            $DatastoreFrom = Get-SourceDatastore -SourceDatastoreCluster $Datastore
                If ($DatastoreFrom.PercentFree -le 5)
                {
                $DatastoreTo = $null
                $DatastoreTo = Get-DestinationDatastore -DestinationDatastoreCluster $NTXDatastore
        
                    If ($DatastoreTo.PercentFree -gt 15)
                        {
                        #$VM |  Move-VM -Destination ((Get-VMHost -Location $NTXCluster | Sort-Object "MemoryUsageGB" | select -First 1).Name) -Datastore $DatastoreTo.Name -confirm:$false -RunAsync:$true
                        echo $VM.Name "moving to" ((Get-VMHost -Location $NTXCluster | Sort-Object "MemoryUsageGB" | select -First 1).Name)  $DatastoreTo.Name
                        $server = Get-Datastore $DatastoreFrom.Name | Get-VM | Select-Object -First 1
                        #$server | Move-VM -Datastore ((Get-Datastore -Location $Datastore | Sort-Object FreeSpaceGB -Descending | Select-Object -First 1).Name)
                        echo $server "moving to" ((Get-Datastore -Location $Datastore | Sort-Object FreeSpaceGB -Descending | Select-Object -First 1).Name)
                        }
            
                    Else 
                        {
                        #Send-mail -DatastoreName $NTXDatastore
                        break
                        }
                }
            }
    
    }


##########################################################################################################################################
##########################################################Disconnect vCenter##############################################################
##########################################################################################################################################

Disconnect-VIServer "server name"


##########################################################################################################################################
#############################################################Script End###################################################################
##########################################################################################################################################