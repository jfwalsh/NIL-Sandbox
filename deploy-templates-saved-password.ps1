#### Script to deploy multiple templates from a specific folder to a separate target folder. 
#### Usually the target folder is empty. The VMs will be created with the same name as the template.

$VersionText = "Version 0.3 (2017-06-16)"
$Author      = "John Walsh | jwalsh@alienvault.com"

## TAB size is 4 spaces

## Function definitions

## Define a function to ask user to select a VM folder - enhanced to show full path
## Requires a connection to vCenter

function Select-VmFolder ([String] $Title){
    # Get datacenter object, hard coded for DC "AV" in AWC
	$dataCenter = Get-DataCenter -Name "AV" 
	# Get top level hidden vm folder called "vm" in selected DC
	$vmFolder = Get-Folder -Type VM -Location $dataCenter -Name "vm" -NoRecursion

	# Get all user-visible VM folders, this is recursive by default
	$allVMFolders = Get-Folder -Location $vmFolder | sort

	# Run through all folders, and add new member to each folder object called FullPath which
	# is a string with the path to the folder, built from folder names and '|' separators.
	$allVMFolders | % {
		$folder = $_
		
		$f = $folder		# $f starts at current folder and then loops through parent folders
		$path = $f.Name		# $path is the string showing the full path including any parent folder names

		# While the parent folder is not the root "vm" folder work up and build path string
		while ($f.Parent -ne $vmFolder) {
			# Add parent name to front of $path
			$path = $f.Parent.Name + " | " + $path
			$f = $f.Parent
		}
		# One path has been generated, add it to the $folder object as a NoteProperty
		Add-Member -inputObject $folder -NotePropertyName "FullPath" -NotePropertyValue $path 
	}

	# Extract folder name, path and Id and feed to ogv.  We need the Id to retrieve the folder again
	# as the folder name is ambiguous.
	$selected = $allVMFolders | Select Name,FullPath,Id | ogv -OutputMode Single -Title $Title

	$selectedFolder = Get-Folder -Id $selected.Id

	$selectedFolder  # return this
}


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

# Setting to control whether a post-clone initial snapshot is required.
$createInitialSnapshot = $true


$myServerName = "awc.nil.com"  	# Put vCenter IP or hostname here 
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

# Ask user to select a folder where Templates are located
Write-Host "Please wait while folder information is retrieved ..."
$myTemplateFolder = Select-VmFolder -Title "Select Template Folder"  # from module jw.psm1

# Ask user to select a target VM folder - this must already exist
Write-Host "Please wait while folder information is retrieved ..."
$myVmFolder = Select-VmFolder -Title "Select Target Folder for deployed VMs"
$myVmFolderName = $myVmFolder.Name

# Ask user to select which templates to deploy
$myTemplates = $()
$myTemplates += $myTemplateFolder | Get-Template | ogv -OutputMode Multiple -Title "Select which templates to deploy"

if ($myTemplates.Count -eq 0) {
	Write-Host "Error: no templates found in folder $myTemplateFolder ... exiting"
	$discard = $mySession | Disconnect-VIServer -Confirm:$false 
	Exit
} 

# Ask user to select a datastore
$myDatastore = Get-Datastore | ogv -OutputMode Single -Title "Select Target Datastore"  

# Ask user to select an ESX host
$myVMHost = Get-VMHost | ogv -OutputMode Single -Title "Select an ESX Host"

# Ask user to choose a workgroup from defined list
$myWorkGroup = $WGNames | ogv -OutputMode Single -Title "Select a Work Group for networking"

# Deploy templates to target folder
$myTemplates | % {				# For each template
    $template = $_
	$myTemplateName = $template.Name
    
	# Deploy Template to VM
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
	
	### Create initial state snapshot
	if ($createInitialSnapshot) {
		$discard = New-Snapshot -Name "Initial State" -VM $newVM
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







