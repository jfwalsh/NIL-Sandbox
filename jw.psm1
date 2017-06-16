### jw functions   jw.psm1
###

#  Need to add some documentation here
#
#  Functions to simplify PowerCLI scripts when working on VMs in the NIL sandbox.
#

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

## Define a function to ask user to select a VM folder
## Requires a connection to vCenter
#function Select-VmFolder ([String] $Title){
#    $folders = @()
#    $folders += Get-Folder -Type VM | Sort-Object | ogv -Passthru -Title $Title 
#    $folders	# return this
#}

function Select-VMfromFolderName ([String] $FolderName, [String] $Title) {
    $vms = @()
	$vms += Get-Folder -Name $FolderName -Type VM | Get-VM | Sort-Object | ogv -Passthru -Title $Title 
    $vms     # return this
}

## Use as follows:  Select-VMfromFolder -Folder $somefolderobject -Title "Text for ogv window"
function Select-VmFromFolder ($Folder, [String] $Title) {
    $vms = @()
	$vms += Get-VM -Location $Folder | Sort-Object | ogv -Passthru -Title $Title 
    $vms     # return this
}

## Use as follows:  Select-TemplateFromFolder -Folder $somefolderobject -Title "Text for ogv window"
function Select-TemplateFromFolder ($Folder, [String] $Title) {
    $vms = @()
	$vms += Get-Template -Location $Folder | Sort-Object | ogv -Passthru -Title $Title 
    $vms     # return this
}

function Select-FolderAndVM ([String]$FolderTitle, [String]$VmTitle ) {
	$folder = Select-VmFolder -Title $FolderTitle 
	Select-VmFromFolder -Folder $folder -Title $VmTitle
}

function Select-FolderAndTemplate ([String]$FolderTitle, [String]$TemplateTitle ) {
	$folder = Select-VmFolder -Title $FolderTitle 
	Select-TemplateFromFolder -Folder $folder -Title $TemplateTitle
}

## untested below here
function GetCurrentSnapshot ($VM) {
	Get-Snapshot -VM $VM | where {$_.IsCurrent -eq $true}
}

function ListVMandCurrentSnapshot ($VM) {
	$vmName = $VM.Name
	$snap = GetCurrentSnapshot -VM $VM
	$snapName = $snap.Name
	$snapDesc = $snap.ExtensionData.Description
	Write-Host -NoNewLine -ForegroundColor Blue "$vmName  " 
	Write-Host -NoNewLine -ForegroundColor Yellow "$snapName  " 
	Write-Host -ForegroundColor White "$snapDesc"
}


# Use as RevertVMtoCurrentSnapshot -VM <vm-object>

function RevertVmToCurrentSnapshot ($VM) {
	$snap = Get-Snapshot -VM $VM | where {$_.IsCurrent -eq $true}
	if ($snap -ne $null) {
		Set-VM -VM $VM -Snapshot $snap -Confirm:$false 
	}
} 

# Disconnect all network adapters on VM
# Does not change connected at power on status
function DisconnectAllVMNetworks ($VM) {
	$VM | Get-NetworkAdapter | Set-NetworkAdapter -Connected:$false -Confirm:$false
}