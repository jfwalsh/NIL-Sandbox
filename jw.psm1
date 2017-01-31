### jw functions   jw.psm1


## Define a function to ask user to select a VM folder
## Requires a connection to vCenter
function Select-VmFolder ([String] $Title){
    $folders = @()
    $folders += Get-Folder -Type VM | Sort-Object | ogv -Passthru -Title $Title 
    $folders	# return this
}

function Select-VMfromFolderName ([String] $FolderName, [String] $Title) {
    $vms = @()
	$vms += Get-Folder -Name $FolderName -Type VM | Get-VM | Sort-Object | ogv -Passthru -Title $Title 
    $vms     # return this
}

## Use as follows:  Select-VMfromFolder -Folder $somefolderobject -Title "Text for ogv window"
function Select-VMfromFolder ($Folder, [String] $Title) {
    $vms = @()
	$vms += Get-VM -Location $Folder | Sort-Object | ogv -Passthru -Title $Title 
    $vms     # return this
}

function Select-FolderandVM ([String]$FolderTitle, [String]$VmTitle ) {
	$folder = Select-VmFolder -Title $FolderTitle 
	Select-VMfromFolder -Folder $folder -Title $VmTitle
}

## untested below here


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