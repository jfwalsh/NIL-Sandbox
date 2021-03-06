#### Script to change WG of a set of VMs from a specific folder.

$VersionText = "Version 0.1 (2017-02-09)"
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

# Array of valid portgroups (networks) that can be selected for new VMs - change this as needed
$numberOfWorkGroups = 20
#### Build array of valid workgroup names, "WG01", WG02", etc.
# https://social.technet.microsoft.com/wiki/contents/articles/7855.powershell-using-the-f-format-operator.aspx
$WGNames = @()	# initialise to an empty array
for ( $i=1 ;  $i -le $numberOfWorkGroups ; $i++ ) { $WGNames += ("WG{0,2:d2}" -f $i) }

#### Redundant - direct definition of the array of workgroups
#$WGNames = "WG01","WG02","WG03","WG04","WG05","WG06","WG07","WG08","WG09","WG10","WG11","WG12","WG13","WG14","WG15","WG16","WG17","WG18","WG19","WG20"

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

## WARNING - putting user credentials in this file is a security hazard. Ensure nobody else can read this file

# vCenter credentials
$myUsername = "Put Username Here"
$myPassword = "Put Password Here"  

$password = ConvertTo-SecureString $myPassword -AsPlainText -Force   # cannot use password directly - convert to secure string first

$myCred =  New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $myUsername, $password

# Connect to vCenter 
Write-Host "Connecting to vCenter Server $myServerName"
$mySession = Connect-VIServer -Server $myServerName -Credential $myCred

# Ask user to select a single folder where templates are located
# The "-Type VM" is correct - this is to filter out ESX, datastore, network etc. folders. 
$mySourceVMFolder = Get-Folder -Type VM | Sort-Object | ogv -OutputMode Single -Title "Select VM Folder"


# Ask user to select which VMs to change WG
$mySourceVMs = $()
$mySourceVMs += $mySourceVMFolder | Get-VM | ogv -OutputMode Multiple -Title "Select which VMs will be moved to a new network"

if ($mySourceVMs.Count -eq 0) {
	Write-Host "Error: no VMs selected from folder " + $mySourceVMFolder + " ... exiting"
	$discard = $mySession | Disconnect-VIServer -Confirm:$false 
	Exit
} 

# Ask user to choose a workgroup from defined list
$myWorkGroup = $WGNames | ogv -OutputMode Single -Title "Select a new Work Group for networking"

# CHange WG for selected VMs
$mySourceVMs | % {				# For each VM

	$newVM = $_
	$myVMName = $newVM.Name
	
	# Adjust networks on new VM 
	# Get array of network adapters from newly created VM
	$myVMNetworkAdapters = @()
	$myVMNetworkAdapters += $newVM | Get-NetworkAdapter
	# Check that there is at least one defined
	if ($myVMNetworkAdapters.Count -ge 1) {
		$myVMNetworkAdapters | % {
			$myNetworkAdapter = $_
			$myAdapterName = $myNetworkAdapter.Name
			$myOldNetworkName = $myNetworkAdapter.NetworkName
			# Check if current name matches WGnn-nn format
			# If so, replace WGnn with target workgroup, leaving -nn part the same.
			# Example: WG01-03 could become WG12-03.
			if ($myOldNetworkName -match 'WG\d\d-\d\d') {
				$myNewNetworkName = $myOldNetworkName -replace 'WG\d\d',$myWorkGroup
				Write-Host "Changing  $myAdapterName on $myVMName from $myOldNetworkName to $myNewNetworkName"
				$discard = $myNetworkAdapter | Set-NetworkAdapter -NetworkName $myNewNetworkName -Confirm:$false
			}
		}
	}
}

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







