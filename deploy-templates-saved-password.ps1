## deploy-templates-saved-password.ps1
##
#### Script to deploy multiple templates from a specific folder to a separate target folder. 
#### Usually the target folder is empty. The VMs will be created with the same name as the template.
#### https://github.com/jfwalsh/NIL-Sandbox/blob/master/deploy-templates-saved-password.ps1

$VersionText = "Version 1.0 (2021-08-24)"
$Author      = "John Walsh | jwalsh@att.com"

## Ver 0.5 - if network is MGMT then map to WGxx-01 to deal with JohnO templates 
##           also increase number of WG networks to 25    
## Ver 0.6 - Move all globals to top
## Ver 0.7 - PowerCLI now in Powershell, so need to check if VMware-PowerCLI module is loaded
## Ver 0.8 - New-VM hangs for bigger VMs, try running it async and monitor with Wait-Task
## Ver 1.0   Refactor code to avoid Wait-Task which seems to hand, replaced it with a loop
##           that pulls tasks with Get-Task every 15 seconds and checks the task status 
##           to see if it has completed.
##           Running New-VM without -RunAsync seems to do an internal Wait-Task so we need to
##           use -TunaAsync and avoid Wait-Task.

#### Might need this in the environment to avoid timeouts ...
# Set-PowerCLIConfiguration -WebOperationTimeoutSeconds 3600 -Scope User

#### Load PowerCLI Module if not yet loaded ####
##     added in 0.7                           ##
if ((Get-Module -Name VMware.PowerCLI) -eq $null) {
	Import-Module VMware.PowerCLI
}

#### GLOBALS ####

#### Make sure to stop script if any errors occur - the default is to continue.
$ErrorActionPreference = "Stop"

# Setting to control whether a post-clone initial snapshot is required.
$DataCenterName = "AlienVault Sandbox"  				# Name of Datacenter in vCenter
$myServerName 	= "awc.nil.com"  		# Put vCenter FQDN or IP here
$numberOfWorkGroups 	= 25 			# How many workgroups? WG-01 to WG-nn
$additionalWorkGroups 	= @("MGMT")   	# Add any additional networks that might be used here 

$createInitialSnapshot 	= $true 		# decide whether to create an initial snapshot 

## WARNING - putting user credentials in this file is a security hazard. Ensure nobody else can read this file
# vCenter credentials
$myUsername = "PUT YOUR VC USERNAME HERE"
$myPassword = "PUT YOUR VC PASSWORD HERE"  
  

  ## Function definitions

## Define a function to ask user to select a VM folder - enhanced to show full path
## Requires a connection to vCenter

function Select-VmFolder ([String] $Title){
    # Get datacenter object
	$dataCenter = Get-DataCenter -Name $DataCenterName 
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
		# Once path has been generated, add it to the $folder object as a NoteProperty
		Add-Member -inputObject $folder -NotePropertyName "FullPath" -NotePropertyValue $path 
	}

	# Extract folder name, path and Id and feed to ogv.  We need the Id to retrieve the folder again
	# as the folder name is ambiguous.
	$selected = $allVMFolders | Select Name,FullPath,Id | ogv -OutputMode Single -Title $Title

	$selectedFolder = Get-Folder -Id $selected.Id

	$selectedFolder  # return this
}

# If you get a lot of warnings about deprecated stuff maybe try the following in your PowerCLI environment:
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

#### Build array of valid workgroup names, "WG01", WG02", etc.
# https://social.technet.microsoft.com/wiki/contents/articles/7855.powershell-using-the-f-format-operator.aspx
$WGNames = @()	# initialise to an empty array
$WGNames += $additionalWorkGroups
for ( $i=1 ;  $i -le $numberOfWorkGroups ; $i++ ) { $WGNames += ("WG{0,2:d2}" -f $i) }


#### Connect to vCenter

# First disconnect any existing connections, to avoid actions being repeated due to duplicate connections
Write-Host "Disconnecting any existing sessions"
Try {
	Disconnect-VIServer -Confirm:$false 
} Catch {
	Write-Host "Looks like there was no existing connection - continuing."
}

# Create VC credential object with username and password
$password = ConvertTo-SecureString $myPassword -AsPlainText -Force   # cannot use password directly - convert to secure string first
$myCred =  New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $myUsername, $password

# Connect to vCenter 
Write-Host "Connecting to vCenter Server $myServerName as $myUsername"
$mySession = Connect-VIServer -Server $myServerName -Credential $myCred

# Ask user to select a folder where Templates are located
Write-Host "Please wait while folder information is retrieved ..."
$myTemplateFolder = Select-VmFolder -Title "Select Template Folder"  

# Ask user to select a target VM folder - this must already exist
Write-Host "Please wait while folder information is retrieved ..."
$myVmFolder = Select-VmFolder -Title "Select Target Folder for deployed VMs"
$myVmFolderName = $myVmFolder.Name

# Ask user to select which templates to deploy
$myTemplates = $()
$myTemplates += $myTemplateFolder | Get-Template -NoRecursion | ogv -OutputMode Multiple -Title "Select which templates to deploy"

if ($myTemplates.Count -eq 0) {	# nothing was selected - exit
	Write-Host "Error: no templates selected ... exiting"
	$discard = $mySession | Disconnect-VIServer -Confirm:$false 
	Exit
}

if ($myTemplates.Count -eq 0) {
	Write-Host "Error: no templates found in folder $myTemplateFolder ... exiting"
	$discard = $mySession | Disconnect-VIServer -Confirm:$false 
	Exit
} 

# Ask user to select a datastore
$myDatastore = Get-Datastore | ogv -OutputMode Single -Title "Select Target Datastore"  
if ($myDataStore -eq $null) {	# nothing was selected - exit
	Write-Host "Error: no Datastore selected ... exiting"
	$discard = $mySession | Disconnect-VIServer -Confirm:$false 
	Exit
}

# Ask user to select an ESX host
$myVMHost = Get-VMHost | ogv -OutputMode Single -Title "Select an ESX Host"
if ($myVMHost -eq $null) {	# nothing was selected - exit
	Write-Host "Error: no ESX Server selected ... exiting"
	$discard = $mySession | Disconnect-VIServer -Confirm:$false 
	Exit
}

# Ask user to choose a workgroup from defined list
$myWorkGroup = $WGNames | ogv -OutputMode Single -Title "Select a Work Group for networking"
if ($myWorkGroup -eq $null) {	# nothing was selected - exit
	Write-Host "Error: no network selected ... exiting"
	$discard = $mySession | Disconnect-VIServer -Confirm:$false 
	Exit
}

# Deploy templates to target folder
$myTemplates | % {				# For each template
    $template = $_
	$myTemplateName = $template.Name
    
	# Deploy Template to VM
	Write-Host "Creating VM `"$myTemplateName`" in folder `"$myVmFolderName`" ..."
	## Debug
	Write-Host "executing: New-VM -Template $template -Name $myTemplateName -Location $myVmFolder -VMHost $myVMHost -Datastore $myDatastore -DiskStorageFormat Thin"
	##
	try {
		$myTask = New-VM -Template $template -Name $myTemplateName -Location $myVmFolder -VMHost $myVMHost -Datastore $myDatastore -DiskStorageFormat Thin -RunAsync
		$myTaskId = $myTask.Id
		
		##Wait-Task -Task $myTask  # Avoid weird timeout issues with New-VM  - but this can hang also.  Looks like a problem in comms to VC?
		##
		## Maybe use Get-Task in a loop and wait until there are no more tasks running? Rather than waiting for this task to comlete?
		##
		
		# Monitor the running tasks every 15 seconds. If there are no tasks running, assume the New-VM task is complete.
		# If tasks are found, look to see if any have the same task ID as the New-VM task. If yes, check state for success, if not keep waiting.
		# If no tasks are found assume success (might be iffy?)
		$taskRunning = $true
		while ($taskRunning) {
			write-host "Getting tasks..." 	#DEBUG
			$allTasks = Get-Task
			$allTasks  						#DEBUG
			write-host "" 					#DEBUG
			$taskCount = $allTasks.Count 
 			if ($taskCount -eq 0) {
				write-host "No tasks found"  #DEBUG
				$taskRunning = $false		 #Is this safe ??
			} else {
				write-host "Found $taskCount tasks"
				write-host "Looking for a task with ID $myTaskId" #DEBUG
			    $tasklist = @()
				$tasklist += $allTasks | ? { $_.Id -eq $myTaskId }
				
				if ($tasklist.Count -eq 0) {
					Write-Host "No match found for $myTaskId, assuming task has completed ... Continuing script"
					$taskRunning = $false 
				} else {
					# We found our task, now check its state
					# Assume that there is one task, which we can reference as index 0
					$task = $tasklist[0]
					$state = $task.State
					
					if ($state -eq "Success") {
						# If the state is Success we can continue, by marking $taskRunning as $false
						Write-Host "State = Success ... Continuing script."  #DEBUG
						$taskRunning = $false
					} elseif ($state -eq "error") {
						Write-Host "Error encountered copying template, exiting ..."
						Exit
					} else {  # Keep waiting
						$taskRunning = $true
						write-host "Task State: $state"
						$percentComplete = $task.percentComplete
						write-host "Percent Complete: $percentComplete"
					}
				}
			}
			if ($taskRunning) {
				Start-Sleep -s 15
			}
		}
		
		# Okay, find the VM by name, now that the New-VM task is complete
		$findVM = @()
		$findVM += Get-VM -Location $myVmFolder -Name $myTemplateName
		$newVM = $findVM[0]
		
				
		Write-Host "Created new VM: $newVM"
	} catch {
		Write-Error $_
	}
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
			# Ver 0.5: If old network is MGMT (and new network is not) then replace with WGxx-01
			if ($myWorkGroup -ne $myOldNetworkName) {
				if ($myOldNetworkName -match 'MGMT') {  # FIXME: what if other names possible?
					$myOldNetworkName = 'WG01-01'  # fake the name
				}
				# Okay, so old and new network names are different - is the new network MGMT?
				if ($myWorkGroup -eq "MGMT") { 			# more FIXME, ditto
					$myNewNetworkName = $myWorkGroup
					Write-Host "Changing $myAdapterName on $myVMName from $myOldNetworkName to $myNewNetworkName"
					$discard = $myNetworkAdapter | Set-NetworkAdapter -NetworkName $myNewNetworkName -Confirm:$false
				} elseif ($myOldNetworkName -match 'WG\d\d-\d\d') {
					$myNewNetworkName = $myOldNetworkName -replace 'WG\d\d',$myWorkGroup
					Write-Host "Changing  $myAdapterName on $myVMName from $myOldNetworkName to $myNewNetworkName"
					$discard = $myNetworkAdapter | Set-NetworkAdapter -NetworkName $myNewNetworkName -Confirm:$false
				}
			}
		}
	}
	
	### Create initial state snapshot
	if ($createInitialSnapshot) {
		Write-Host "Creating initial snapshot for $myVMName"
#		$discard = New-Snapshot -Name "Initial State" -VM $newVM
        try {
			$snap = New-Snapshot -Name "Initial State" -VM $newVM
			Write-Host "Created snapshot: $snap"
		} catch {
			Write-Error $_
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
