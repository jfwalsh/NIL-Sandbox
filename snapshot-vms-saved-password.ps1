#### Script to snapshot multiple VMs with embedded username and password

$VersionText = "Version 0.1 (2017-02-06)"
$Author      = "John Walsh | jwalsh@alienvault.com"


#### http://www.pragmaticio.com/2015/01/vmware-powercli-suppress-vcenter-certificate-warnings/
# PowerCLI> Set-PowerCLIConfiguration -InvalidCertificateAction ignore -DisplayDeprecationWarnings:$false -confirm:$false
#
# Scope    ProxyPolicy     DefaultVIServerMode InvalidCertificateAction  DisplayDeprecationWarnings WebOperationTimeout
#                                                                                                   Seconds
# -----    -----------     ------------------- ------------------------  -------------------------- -------------------
# Session  UseSystemProxy  Multiple            Ignore                    False                      300
# User
# AllUsers                                     Ignore                    False
#

#### GLOBALS ####

$myServerName = "awc"  	# Put vCenter IP or hostname here 
						# awc defined in local hosts file to be 192.168.252.141



#### Make sure to stop script if any errors occur - the default is to continue.
$ErrorActionPreference = "Stop"

#### Connect to vCenter

# First disconnect any existing connections, to avoid actions being repeated due to duplicate connections
Write-Host "Disconnecting any existing sessions"
Try {
	Disconnect-VIServer -Confirm:$false 
} Catch {
	Write-Host "Looks like there was no existing connection - continuing."
}

## First get login credentials from user, using standard Get-Credential call
## $myCred = Get-Credential   

## WARNING - putting user credentials in this file is a security hazard. Ensure nobody else can read this file

# vCenter credentials
$myUsername = "put username here"
$myPassword = "put password here"  

$password = ConvertTo-SecureString $myPassword -AsPlainText -Force   # cannot use password directly - convert to secure string first

$myCred =  New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $myUsername, $password

# Connect to vCenter 
Write-Host "Connecting to vCenter Server $myServerName"
$mySession = Connect-VIServer -Server $myServerName -Credential $myCred

# Ask user to select a single folder where VMs are located
$VmFolder = Get-Folder -Type VM | Sort-Object | ogv -OutputMode Single -Title "Select Folder"

# Ask user to select which VMs to revert
$myVMs = $()
$myVMs += Get-VM -Location $VmFolder | ogv -OutputMode Multiple -Title "Select which VMs to snapshot"


if ($myVMs.Count -eq 0) {
	Write-Host "Error: no VMs selected ... exiting"
	$discard = $mySession | Disconnect-VIServer -Confirm:$false 
	Exit
} 

# Display current snapshot for all selected VMs
Write-Host ""
Write-Host "Current Snapshot for selected VMs"
Write-Host "----------------------------------"

$myVMs | % {
	$vm = $_
	$vmName = $vm.Name
	$snap = Get-Snapshot -VM $vm | where {$_.IsCurrent -eq $true}
	if ($snap -eq $null) {
		Write-Host "VM $vmName has no snapshots"
	} else {
		$snapName = $snap.Name
		Write-Host "VM $vmName : Current snapshot is `"$snapName`""
	}
}
Write-Host ""

# Ask for Snapshot Name
$snapShotName = Read-Host -Prompt "Please provide a snapshot name"

# Ask for Snapshot Description
$snapShotDescription = Read-Host -Prompt "Please provide a snapshot description"

# Ask if we should continue?
$userChoice = Read-Host -Prompt "Do you wish to create new snapshots? [Yes or No] (default is NO)"
if ($userChoice -notlike "y*") {
	Write-Host "OK, exiting ..."
	Write-Host "Disconnecting from vCenter..."
	$discard = $mySession | Disconnect-VIServer -Confirm:$false
	Exit
}

# Create new snapshots
$myVMs | % {				# For each VM
	$vm = $_
	$vmName = $vm.Name
	$snap = New-Snapshot -VM $vm -Name $snapShotName -Description $snapShotDescription -Confirm:$false
}

# Display current snapshot for all selected VMs again
Write-Host "`n"
Write-Host "Confirm that snapshots have been done.`n"
Write-Host "Current Snapshot for selected VMs"
Write-Host "----------------------------------"

$myVMs | % {
	$vm = $_
	$vmName = $vm.Name
	$snap = Get-Snapshot -VM $vm | where {$_.IsCurrent -eq $true}
	if ($snap -eq $null) {
		Write-Host "VM $vmName has no snapshots"
	} else {
		$snapName = $snap.Name
		Write-Host "VM $vmName : Current snapshot is `"$snapName`""
	}
}
Write-Host ""


##########################################################################
#### 
####  Make sure we are disconnected
####
##########################################################################

Write-Host "Disconnecting from vCenter..."
$discard = $mySession | Disconnect-VIServer -Confirm:$false
Write-Host "Script finished ... "

##########################################################################
#### 
#### That's all, folks!
####
##########################################################################







