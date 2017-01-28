#### Script to deploy templates to folder. 
#### Bulk deploy a list of templates to a specific folder

$VersionText = "Version 0.1 (2017-01-27)"
$Author      = "Redacted"


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

# Array of valid portgroups (networks) that can be selected for new VMs
$WGNames = "WG01","WG02","WG03","WG04","WG05","WG06","WG07","WG08","WG09","WG10","WG11","WG12","WG13","WG14"



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

# First get login credentials from user, using standard Get-Credential call
$myCred = Get-Credential   # example user: jwalsh@nil.si

# Connect to vCenter 
Write-Host "Connecting to vCenter Server $myServerName"
$mySession = Connect-VIServer -Server $myServerName -Credential $myCred

# Ask user to select a single folder where templates are located
# The "-Type VM" is correct - this is to filter out ESX, datastore, network etc. folders. 
$myTemplateFolder = Get-Folder -Type VM | Sort-Object | ogv -OutputMode Single -Title "Select Template Folder"

# Ask user to select a target VM folder - must already exist
$myVmFolder = Get-Folder -Type VM | Sort-Object | ogv -OutputMode Single -Title "Select Target Folder for deployed VMs"
$myVmFolderName = $myVmFolder.Name

# Ask user to select which templates to deploy
$myTemplates = $()
$myTemplates += $myTemplateFolder | Get-Template | ogv -OutputMode Multiple -Title "Select which templates to deploy"

# Ask user to select a datastore
$myDatastore = Get-Datastore | ogv -OutputMode Single -Title "Select Target Datastore"  

if ($myTemplates.Count -eq 0) {
	Write-Host "Error: no templates found in folder $myTemplateFolder ... exiting"
	$discard = $mySession | Disconnect-VIServer -Confirm:$false 
	Exit
} 

# Ask user to select an ESX host
$myVMHost = Get-VMHost | ogv -OutputMode Single -Title "Select an ESX Host"

# Ask user to choose a workgroup from defined list
$myWorkGroup = $WGNames | ogv -OutputMode Single -Title "Select a Work Group for networking"

# Deploy templates to target folder
$myTemplates | % {				# For each template
    $template = $_
    # Deploy Template to VM
	$myTemplateName = $template.Name
	Write-Host "Creating VM `"$myTemplateName`" in folder `"$myVmFolderName`" ..."
    $newVM = New-VM -Template $template -Name $myTemplateName -Location $myVmFolder -VMHost $myVMHost -Datastore $myDatastore -DiskStorageFormat Thin
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







