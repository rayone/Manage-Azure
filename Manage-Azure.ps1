$apsc = "C:\Program Files (x86)\Microsoft SDKs\Windows Azure\PowerShell\Azure\Azure.psd1"
if(!(Test-Path $apsc))
{
	Write-Warning "Please download the Azure Cmd line tools: http://www.windowsazure.com/en-us/downloads/#cmd-line-tools"
	break
}
ipmo $apsc
cls
$cd = [IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)
$global:PublishFile = $null
$global:Subscription = $null
$BackupPath = "vhd-backups"


function list-box([string]$title, $objArr, [bool]$multi = $false)
{
	[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
	[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
	$objForm = New-Object System.Windows.Forms.Form 
	$objForm.Text = $title
	#$objForm.BackColor = "#2086bf"
	#$objForm.Size = New-Object System.Drawing.Size(500,400)
	$objForm.AutoSize = $true
	$objForm.AutoSizeMode = "GrowAndShrink"
	$objForm.StartPosition = "CenterScreen"
	$lbl = New-Object System.Windows.Forms.Label
	$lbl.Location = New-Object System.Drawing.Size(10,20) 
	#$lbl.Size = 480
	$lbl.AutoSize = $true
	$lbl.BackColor = "Transparent"
	$lbl.Text = $title
	$objForm.Controls.Add($lbl)
	$LB = New-Object System.Windows.Forms.ListBox 
	$LB.Location = New-Object System.Drawing.Size(10,40) 
	$LB.Size = New-Object System.Drawing.Size(470,50)	
	$LB.AutoSize = $true
	$LB.Add_DoubleClick({$objForm.Close()})
	if($multi)
	{
		$LB.SelectionMode = "MultiExtended"
	}
	$w = 0
	foreach($obj in $objArr)
	{
		[void] $LB.Items.Add($obj)
		# $ow = $(-join $obj | Measure-Object -character).Character
		# if($ow -gt $w)
		# {
			# $w = $ow
		# }
	}	
	
	[int]$h = $($LB.Items.Count) * 30
	$LB.Height = $h
	#$LB.ColumnWidth = $w * 200
	$objForm.Controls.Add($LB)
	$objForm.Topmost = $True
	$kBtn = New-Object System.Windows.Forms.Button
	$kBtn.Location = New-Object System.Drawing.Size(75,$($h + 40))
	$kBtn.Size = New-Object System.Drawing.Size(75,23)
	$kBtn.Text = "OK"
	$kBtn.Add_Click({$objForm.Close()})
	$objForm.Controls.Add($kBtn)
	$CnBtn = New-Object System.Windows.Forms.Button
	$CnBtn.Location = New-Object System.Drawing.Size(150,$($h + 40))
	$CnBtn.Size = New-Object System.Drawing.Size(75,23)
	$CnBtn.Text = "Cancel"
	$CnBtn.Add_Click({$LB.ClearSelected();$objForm.Close()})
	$objForm.Controls.Add($CnBtn)
	$objForm.Add_Shown({$objForm.Activate()})
	[void] $objForm.ShowDialog()	
	if($multi)
	{
		return $LB.SelectedItems
	}
	else
	{
		return $LB.SelectedIndex
	}
}

function Get-Folder([string]$msg, [string]$InitialDirectory) 
{ 
    $app = New-Object -ComObject Shell.Application 
    $folder = $app.BrowseForFolder(0, $msg, 0, $InitialDirectory) 
    if ($folder)
	{ 
		return $folder.Self.Path 
	} 
	else
	{ 
		return $null	
	} 
}

function Get-Prompt([string]$title, [string]$msg)
{
	$yes = New-Object System.Management.Automation.Host.ChoiceDescription "Y", "Yes."
	$no = New-Object System.Management.Automation.Host.ChoiceDescription "N", "No."
	$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
	return $host.ui.PromptForChoice($title, $msg, $options, 0)
}

function Try-Again
{
	$title = "Try Again or Continue"
	$msg = "There has been a problem, would you like to Continue or Try the last operation again?"
	$yes = New-Object System.Management.Automation.Host.ChoiceDescription "Continue", "Continue to the next step."
	$no = New-Object System.Management.Automation.Host.ChoiceDescription "Try Again", "Try the last step again."
	#$cancel = New-Object System.Management.Automation.Host.ChoiceDescription "Cancel", "Cancel operation."
	$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
	return $host.ui.PromptForChoice($title, $msg, $options, 1)
}

function Check-Errors([string]$log)
{
	$pat = "(failed|errors|NotSupportedException|ConflictError)"
	$LastError = $false
	Get-Item $log | Select-String -Pattern $pat | %{
		Write-Warning $_.Line;
		$LastError = $true	
	}	
	return $LastError
}

function Get-PublishingFile([string]$path=$cd)
{
	Write-Host "Getting Publishing files: " -nonewline
	$pubs = ls $path -filter "*.publishsettings"
	if(($pubs | Measure-Object).Count -eq 1)
	{
		Set-Variable -Name PublishFile -Value $pubs.FullName -Scope Global
	}
	elseif($pubs -eq $null)
	{
		Write-Warning "No Publish Settings File was found with this PS script.`nPlease download it from https://manage.windowsazure.com/publishsettings/Index?client=vs&SchemaVersion=1.0 and select it's location from the file browser."
		Get-PublishingFile $(Get-Folder "Select the directory that contains your Publishing File")
	}
	else
	{
		$selPub = list-box "Select publish settings:" $($pubs | select name)
		$PublishFile = $pubs[$selPub].FullName
	}
	if($PublishFile -ne $null)
	{
		Write-Host $PublishFile
		$PublishFileXML = [xml](Get-Content($PublishFile))	
		Import-AzurePublishSettingsFile $PublishFile
		Get-Subscription
	}
}

function Get-Subscription
{
	Write-Host "Getting Subscriptions: " -nonewline
	$subs = $PublishFileXML.PublishData.PublishProfile.Subscription	
	if(($subs | Measure-Object).Count -eq 1)
	{
		Set-Variable -Name Subscription -Value $subs.Name -Scope Global
	}
	else
	{
		$selSub = list-box "Select subscription:" $($subs | select name)
		if(!($selSub -gt -1))
		{
			Write-Warning "You must select a subscription"
			break
		}
		Set-Variable -Name Subscription -Value $subs[$selSub].Name -Scope Global
	}
	
	Set-AzureSubscription -SubscriptionName $Subscription 
	Select-AzureSubscription -SubscriptionName $Subscription
	Write-Host $Subscription	
}

function Get-StorageAccounts([string]$f=$null)
{
	Write-Host "Getting $f Storage Accounts: " -nonewline
	$StorageAccounts = Get-AzureStorageAccount
	
	if(($StorageAccounts | Measure-Object).Count -eq 1)
	{
		$StorageAccount = $StorageAccounts
	}
	else
	{
		$selSAs = list-box "Select a $f Storage Account:" $($StorageAccounts | select StorageAccountName, AffinityGroup, Location)
		if($selSAs -eq -1)
		{
			Write-Warning "You must select a Storage Account!"
			break
		}
		$StorageAccount = $StorageAccounts[$selSAs]
	}
	Write-Host $StorageAccount.Label
	return $StorageAccount
}

function Get-StorageContainers($SC, [string]$f=$null)
{
	Write-Host "Getting Containers: " -nonewline
	$ctnr = Get-AzureStorageContainer -Context $SC
	if(($ctnr | Measure-Object).Count -eq 1)
	{
		$container = $ctnr.Name
	}
	else
	{
		$selctnr = list-box $f $($ctnr | select name)
		if(!($selctnr -gt -1))
		{
			Write-Warning "You must select a container"
			break
		}
		$container = $ctnr[$selctnr].Name
	}
	Write-Host "$container"
	return $container
}

function Get-Blobs([string]$container, $StorageContext, $blobs, [string]$f=$null)
{
	Write-Host "Getting $container blobs: " -nonewline
	if($blobs -eq $null)
	{
		$blobs = Get-AzureStorageBlob -Container $container -Context $StorageContext
	}
	$selBlobs = list-box $f $($blobs | select Name, Length, LastModified) $true
	if(!($selBlobs.Count -gt -1))
	{
		Write-Warning "You must select at least one blob"
		break
	}
	return $selBlobs
}

function Run-PS([string]$cmd, [string]$PublishFile, [string]$Subscription)
{
	if($cmd.LastIndexOf("-") -gt 1)
	{
		$cmdLog = $cmd.Substring(0, $cmd.LastIndexOf("-"))
	}
	else
	{
		$cmdLog = $cmd
	}
	$log = ("$cd\$cmdLog"+ $(Get-Date -Format yyyy-MM-dd_h-mm-s).ToString() +".txt")
	Start-Process -FilePath "$PSHOME\powershell.exe" -ArgumentList "-WindowStyle hidden -Noninteractive -ExecutionPolicy Bypass Invoke-Command -ScriptBlock {
	Start-Transcript -Path '$log' -Force | out-null; `
	ipmo '$apsc'; `
	Import-AzurePublishSettingsFile '$PublishFile'; `
	Select-AzureSubscription -SubscriptionName '$Subscription'; `
	$cmd; `
	Stop-Transcript}" -Verb Runas
	return $log
}

function Manage-AStorage
{
	$ops = @("Copy Blob", "Delete Blob", "Add Disk", "Remove Disk", "Break Lease", "New Snapshot", "Restore Snapshot") 
	#Todo: Attach disk/blob
	if($op -eq $null)
	{
		$selOp = list-box "Select an operation:" $ops
		if($selOp -gt -1)
		{
			$op = $ops[$selOp]
		}
		else
		{
			Write-Warning "You must select an operation"
			break
		}
	}
	Write-Host "Operation: $op"
	Get-PublishingFile
	
	if($op -ne "Remove Disk")
	{
		$StorageAccount = Get-StorageAccounts "Source"
		$StorageKey = Get-AzureStorageKey -StorageAccountName $StorageAccount.StorageAccountName
		$StorageContext = New-AzureStorageContext -StorageAccountName $StorageAccount.StorageAccountName -StorageAccountKey $StorageKey.Primary
		$container = Get-StorageContainers $StorageContext2 "Select a source container"
		$blobs = Get-AzureStorageBlob -Container $container -Context $StorageContext
	}
	
	if($op -eq "Copy Blob")
	{
		$StorageAccount2 = Get-StorageAccounts "Destination"
		$StorageKey2 = Get-AzureStorageKey -StorageAccountName $StorageAccount2.StorageAccountName
		$StorageContext2 = New-AzureStorageContext -StorageAccountName $StorageAccount2.StorageAccountName -StorageAccountKey $StorageKey2.Primary
		$container2 = Get-StorageContainers $StorageContext2 "Select a Destination container"	
		$selBlobs = Get-Blobs $container $StorageContext $blobs "Select blobs to copy:"
		foreach($b in $selBlobs)
		{	
			$Bname = $b.Name
			$blob = $blobs | ?{$_.Name -eq $Bname}
			#$blob = Get-AzureStorageBlob -Context $StorageContext -Container $container -Blob $b.Name
			if($($blob.ICloudBlob.Uri) -eq $([string]::Format("{0}{1}/{2}",$StorageContext2.BlobEndPoint, $container2, $Bname)))			 
			{
				$Bname = Read-Host "The source and destination are the same, enter a new name for the blob"
			}
			Write-Host "Copying `n - Source: $($blob.ICloudBlob.Uri) `n - Destination: $($StorageContext2.BlobEndPoint)$container2/$Bname"
			Start-AzureStorageBlobCopy -Context $StorageContext -SrcUri $blob.ICloudBlob.Uri -DestContainer $container2 -DestBlob $Bname -DestContext $StorageContext2 -ea stop		
			while($(Get-AzureStorageBlobCopyState -Context $StorageContext2 -Container $container2 -Blob $Bname).Status -eq "Pending")
			{
				Write-Host "." -NoNewline
				Start-Sleep 1
			}
			Write-Warning "Copied $($b.Name)"			
		}
	}
	
	if($op -eq "Delete Blob")
	{
		$selBlobs = Get-Blobs $container $StorageContext $blobs "Select blobs to delete:"
		foreach($b in $selBlobs)
		{
			Remove-AzureStorageBlob  -Context $StorageContext -Container $container -Blob $b.Name
			Write-Warning "Deleted $($b.Name)"
		}
	}
	
	if($op -eq "Add Disk")
	{
		##Todo: Filter blobs that have disk
		$selBlobs = Get-Blobs $container $StorageContext $($blobs | ?{$_.SnapshotTime -eq $null}) "Select blobs to add as an Azure Disk:"
		foreach($b in $selBlobs)
		{
			$blob = $blobs | ?{$_.Name -eq $b.name}
			$diskName = Read-Host "`nEnter a name for the disk"			
			if($(Get-Prompt "OS Disk" "Does the VHD contain an operating system?") -eq 0)
			{
				$OSs = @("Windows","Linux")
				$selOS = list-box "Select an OS:" $OSs
				if(!($selOS -gt -1))
				{
					Write-Warning "You must select an OS"
					break
				}
				$disk = Add-AzureDisk -DiskName $diskName -MediaLocation $blob.ICloudBlob.Uri -OS $OSs[$selOS]
			}
			else
			{
				$disk = Add-AzureDisk -DiskName $diskName -MediaLocation $blob.ICloudBlob.Uri
			}
			Write-Warning "Created $diskName"
		}
	}	
	
	if($op -eq "Remove Disk")
	{
		$disks =  Get-AzureDisk | select DiskName, Location, AttachedTo
		$selDisks = list-box "Select a Azure Disk to remove:" $disks $true
		if(!($selDisks.Count -gt -1))
		{
			Write-Warning "You must select a Disk"
			break
		}
		foreach($disk in $selDisks)
		{
			Remove-AzureDisk -DiskName $disk.DiskName
			Write-Warning "Removed $($disk.DiskName)"
		}
	}
	
	if($op -eq "Break Lease")
	{
		#http://msdn.microsoft.com/en-us/library/microsoft.windowsazure.storage.blob.leasestate.aspx
		$filteredBlobs = $blobs | ?{$_.ICloudBlob.Properties.LeaseState -eq "Leased"}
		if($filteredBlobs -ne $null)
		{
			$selBlobs = Get-Blobs $container $StorageContext $filteredBlobs "Select blobs to break lease:"
			foreach($b in $selBlobs)
			{
				$blob = $blobs | ?{$_.Name -eq $b.name}
				#http://msdn.microsoft.com/en-us/library/microsoft.windowsazure.storage.blob.icloudblob_methods.aspx
				$blob.ICloudBlob.BreakLease(0, $null, $null, $null) | out-null
				# while($(Get-AzureStorageBlob -Container $container -Context $StorageContext -Blob $b.name).ICloudBlob.Properties.LeaseState -eq "Leased")
				# {
					# Write-Host "." -NoNewline
					# Start-Sleep 1
				# }
				Get-AzureStorageBlob -Container $container -Context $StorageContext -Blob $b.name | %{	Write-Host "$($_.ICloudBlob.Uri)`n - Lease State = $($_.ICloudBlob.Properties.LeaseState)"} 
			}			
		}
		else
		{
			$blobs | %{	Write-Host "$($_.ICloudBlob.Uri)`n - Lease State = $($_.ICloudBlob.Properties.LeaseState)"}
			Write-Warning "There are no leased blobs in $container"
		}
	}
	
	if($op -eq "New Snapshot")
	{		
		$selBlobs = Get-Blobs $container $StorageContext $blobs "Select blobs to snapshot:"
		foreach($b in $selBlobs)
		{
			$b.name
			$blob = $blobs | ?{$_.Name -eq $b.name}
			#http://msdn.microsoft.com/en-us/library/microsoft.windowsazure.storageclient.cloudblob_methods.aspx
			try
			{
				$snapshot = $blob.ICloudBlob.CreateSnapshot()
				Write-Warning "Snapshot created $($snapshot.Uri) `nSnapshotTime: $($snapshot.SnapshotTime)"
			}
			catch
			{
				Write-Error "Exception: $($_.Exception.Message)"
			}
		}
	}
	if($op -eq "Restore Snapshot")
	{		
		$selBlobs = Get-Blobs $container $StorageContext $($blobs | ?{$_.SnapshotTime -eq $null}) "Select blobs to restore:"
		
		foreach($b in $selBlobs)
		{
			$b.name
			$blob = $blobs | ?{$_.Name -eq $b.name}
			try
			{
				Write-Host "`nGetting $($b.name) SnapShots"
				$ss = Get-AzureStorageBlob -Container $container -Context $StorageContext | ?{($_.SnapshotTime -ne $null) -and ($_.Name -eq $b.Name)}
				$sst = $ss | select SnapshotTime, Name
				$snap = list-box "Select $($blob.Name) snapshot:" $sst
				if(($snap -eq $null) -or ($snap -lt 0))
				{
					Write-Warning "No snapshot selected."
					break
				}
				else
				{	
					$snapshot = $ss[$snap]
				}
				$ssn = "`n - $($snapshot.Name) `n - $($snapshot.SnapshotTime) `n - $($snapshot.Uri)"
				Write-Host "Restoring SnapShot: $ssn"
				#http://msdn.microsoft.com/en-us/library/microsoft.windowsazure.storage.blob.cloudblockblob.aspx
				$opId = $blob.ICloudBlob.StartCopyFromBlob($snapshot.ICloudBlob.Uri, $null, $null, $null, $null)
				Write-Warning "$($snapshot.Name) restored!"
			}
			catch
			{
				Write-Error "Exception: $($_.Exception.Message)"
			}
		}
	}
}


function Stop-AVM($oVM, [string]$PublishFile, [string]$Subscription)
{
	#Stop-AzureVM -Name $oVM.Name -ServiceName $oVM.ServiceName -StayProvisioned -Force
	#Start-Job -ScriptBlock $stopVM -ArgumentList $oVM
	$opLog = Run-PS "Stop-AzureVM -ServiceName $($oVM.ServiceName) -Name $($oVM.Name) -Force" $PublishFile $Subscription
	while(!($(Get-AzureVM -ServiceName $($oVM.ServiceName) -Name $($oVM.Name)).InstanceStatus -Match "Stop"))
	{
		$c++
		if($c -gt 160)
		{
			$c = 0
			Write-Warning "Operation RETRY"
			Stop-AVM $oVM $PublishFile $Subscription
			break
		}
		Write-Host "." -NoNewline
		Start-Sleep 1
		if(Check-Errors $opLog)
		{
			Write-Error "There have been errors in the last operation, check the log file"
			ii $opLog
			break
		}
	}
	#Get-Job | Remove-Job
	#This avoids Windows Azure is currently performing an operation with x-ms-requestid that requires exclusive access
	sleep 30
	Write-Host " Stopped"
}

function Start-AVM($oVM, [string]$PublishFile, [string]$Subscription)
{
	#Start-AzureVM -Name $oVM.Name -ServiceName $oVM.ServiceName
	#Start-Job -InputObject $oVM -ScriptBlock{Start-AzureVM -Name $input.Name -ServiceName $input.ServiceName}
	$opLog = Run-PS "Start-AzureVM -ServiceName $($oVM.ServiceName) -Name $($oVM.Name)" $PublishFile $Subscription
	while ($(Get-AzureVM -ServiceName $($oVM.ServiceName) -Name $($oVM.Name)).InstanceStatus -ne "ReadyRole")
	{		
		$c++
		if($c -gt 160)
		{
			$c = 0
			Write-Warning "Operation RETRY"
			Start-AVM $oVM $PublishFile $Subscription
			break
		}
		Write-Host "." -NoNewline
		Start-Sleep 1
		if(Check-Errors $opLog)
		{
			Write-Error "There have been errors in the last operation, check the log file"
			Invoke-Item $opLog
			break
		}
	}			
	#Get-Job | Remove-Job
	#This avoids Windows Azure is currently performing an operation with x-ms-requestid that requires exclusive access
	sleep 30
	Write-Host " Started"
}

function Get-StorageContext($Disk)
{
	Write-Host " - Getting Disk '$($Disk.DiskName)' Storage Account: " -nonewline
	$StorageAccount = Get-AzureStorageAccount | ? {$_.Endpoints -match("http://" + $Disk.MediaLink.Host + "/")}
	Write-Host $StorageAccount.StorageAccountName -nonewline
	$StorageKey = Get-AzureStorageKey -StorageAccountName $StorageAccount.StorageAccountName
	$StorageContext = New-AzureStorageContext -StorageAccountName $StorageAccount.StorageAccountName -StorageAccountKey $StorageKey.Primary
	Write-Host "... Done"
	return $StorageContext
}

function Manage-AVM
{
	$ops = @("Start", "Stop", "Backup", "Restore", "Export VM XML", "New VM XML")
	$selOp = list-box "Select an operation:" $ops
	if($selOp -gt -1)
	{
		$op = $ops[$selOp]
	}
	else
	{
		Write-Warning "You must select an operation"
		break
	}
	Write-Host "Operation: $op"
	Get-PublishingFile
	

	if($op -eq "New VM XML")
	{
		Write-Host "Getting XML files: " -nonewline
		$vmxs = ls $cd -filter "*.xml"
		if(($vmxs | Measure-Object).Count -eq 1)
		{
			$vmx = $vmxs.FullName
		}
		elseif($vmxs -eq $null)
		{
			Write-Warning "No VM XML Settings File was found with this PS script.`nPlease create and try again."
			break
		}
		else
		{
			$selVMX = list-box "Select XML settings file for your new VM:" $($vmxs | select name)
			$vmx = $vmxs[$selVMX].FullName
		}
		
		Write-Host $vmx
		
		if($(Get-Prompt "Getting Cloud Services:" "Would you like to use an Existing Cloud Service? N to create a new one.") -eq 1)
		{
			$cs = Read-Host "Enter name of new Cloud Service"
			
			if($(Get-Prompt "Cloud Service Location or Affinity Group" "Would you like to use a Datacenter location or Affinity Group? N to use Affinity Group.") -eq 1)
			{
				Write-Host "Getting Affinity Groups: " -nonewline
				$ags = Get-AzureAffinityGroup		
				$selAg = list-box "Select a Affinity Group for your Cloud Service:" $($ags | select name)
				$Ag = $ags[$selAg].Name
				if($Ag -ne $null)
				{
					$opLog = Run-PS "New-AzureService -ServiceName $cs -AffinityGroup $Ag" $PublishFile $Subscription
				}
			}
			else
			{
				Write-Host "Getting locations: " -nonewline
				$locs = Get-AzureLocation		
				$selLoc = list-box "Select a location for your Cloud Service:" $($locs | select name)
				$loc = $locs[$selLoc].Name
				if($loc -ne $null)
				{
					$opLog = Run-PS "New-AzureService -ServiceName $cs -Location '$loc'" $PublishFile $Subscription
				}
			}
			Start-Sleep 3
			if(Check-Errors $opLog)
			{
				Write-Error "There have been errors in the last operation, check the log file"
				ii $opLog
				break
			}
		}
		else
		{
			Write-Host "Getting Cloud Services: " -nonewline
			$css = Get-AzureService
			if(($css | Measure-Object).Count -eq 1)
			{
				$cs = $css.ServiceName
			}
			elseif($css -eq $null)
			{
				Write-Warning "No cloud services found."
				break
			}
			else
			{
				$selCSS = list-box "Select a Cloud Service for your new VM:" $($css | select servicename, location, AffinityGroup)
				$cs = $css[$selCSS].ServiceName
			}
		}
		Write-Host $cs
		if($cs -ne $null)
		{		
			$nvmXML = [xml](Get-Content($vmx))	
			$nvmosd = Get-AzureDisk -DiskName $nvmXML.PersistentVM.OSVirtualHardDisk.DiskName
			$nvmname = $nvmXML.PersistentVM.RoleName 
			$StorageContext = Get-StorageContext $nvmosd
			Set-AzureSubscription -SubscriptionName $Subscription -CurrentStorageAccount $StorageContext.StorageAccountName 
			try
			{
				Write-Host " - Creating $nvmname in $cs" -nonewline
				$nVM = Import-AzureVM -Path $vmx | New-AzureVM -ServiceName $cs -ea stop
				Write-Host "... $($nVM.OperationStatus)"
				$oVM = Get-AzureVM $nvmname# -ea stop | out-null
				#for some reason $oVM is sometimes null
				if($oVM -eq $null)
				{
					$oVM = Get-AzureVM | ?{$_.Name -eq $nvmname}
				}
				if($oVM)
				{
					Write-Host " - Starting $nvmname " -nonewline
					Start-AVM $oVM $PublishFile $Subscription
				}
				else
				{
					Write-Error "Unable to get $nvmname, something's gone terribly wrong... did MS update the damn Azure SDK?"
					break
				}
			}
			catch
			{
				Write-Error $_
				break
			}
			
			Write-Host "All done!"
		}
		break
	}
	
	
	Write-Host "Getting VMs: "
	$VMs = Get-AzureVM | sort name

	if($op -eq "Stop"){$VMs = $VMs | ?{!($_.Status -Match "Stop")}}
	if($op -eq "Start"){$VMs = $VMs | ?{$_.Status -ne "ReadyRole"}}
	$selVMs = list-box "Select VM's to $op :" $($VMs | select name,ServiceName,status) $true
	if($selVMs -eq "")
	{
		Write-Warning "You must select a VM!"
		break
	}
	
	foreach($vm in $selVMs)
	{
		$oVM = $VMs | ?{$_.Name -eq $vm.name}

		if($op -eq "Export VM XML")
		{
			Export-AzureVM -Name $vm.Name -ServiceName $vm.ServiceName -Path "$cd\$($vm.Name)-$(Get-Date -Format yyyy-MM-dd_h-mm-s).xml"
			Manage-AVM
		}
		
		if($op -eq "Stop")
		{
			if(!($oVM.Status -Match "Stop"))
			{
				Write-Host " - Stopping $($oVM.Name) " -NoNewline
				Stop-AVM $oVM $PublishFile $Subscription
			}
			else
			{
				Write-Warning "$vm is already @ $op, duh!"
			}
		}
		if($op -eq "Start")
		{
			if($oVM.Status -ne "ReadyRole")
			{
				Write-Host " - Starting $($oVM.Name) " -NoNewline
				Start-AVM $oVM $PublishFile $Subscription
			}
			else
			{
				Write-Warning "$vm is already @ $op, duh!"
			}
		}
		if($op -eq "Backup")
		{
			Write-Host " - Backing up $($oVM.Name) "
			Export-AzureVM -Name $vm.Name -ServiceName $vm.ServiceName -Path "$cd\$($oVM.Name)-$(Get-Date -Format yyyy-MM-dd_h-mm-s).xml" | Out-Null
			$bRestart = $false
			if(!($oVM.Status -Match "Stop"))
			{
				Write-Host " - Stopping $($oVM.Name) " -nonewline
				#Stop-AzureVM -Name $oVM.Name -ServiceName $oVM.ServiceName -Force
				Stop-AVM $oVM $PublishFile $Subscription
				$bRestart = $true
			}
			
			Write-Host " - Getting $($oVM.Name) attached disks" -nonewline
			$Disks = Get-AzureDisk | ?{($_.AttachedTo.RoleName -eq $($oVM.Name)) -and  ($_.AttachedTo.HostedServiceName -eq $($oVM.ServiceName))}
			Write-Host "...Done"
			$Disks | %{
				$Disk = $_
				if($StorageContext -eq $null)
				{
					$StorageContext = Get-StorageContext $Disk
					
					Write-Host " - Getting Backup container: $BackupPath"
					$BackupContainer = $StorageContext | Get-AzureStorageContainer | ?{$_.Name -eq $BackupPath}
					if($BackupContainer -eq $null)
					{
						Write-Host -ForegroundColor Yellow " - Backup container doesn't exist, creating: $BackupPath"
						New-AzureStorageContainer -Name $BackupPath -Context $StorageContext -Permission Off | out-null
						$StorageContext | Get-AzureStorageContainer | ?{$_.Name -eq $BackupPath}
					}
				}
				#$backupBlob = $($StorageContext.StorageAccount.CreateCloudBlobClient()).GetBlobReferenceFromServer($Disk.MediaLink)
				$backupDiskName = "$($Disk.DiskName)-$(Get-Date -Format yyyy-MM-dd_h-mm-s).vhd"
				Write-Host " - Creating Backup: $backupDiskName ... " -nonewline
				Start-AzureStorageBlobCopy -SrcUri $Disk.MediaLink -DestContainer $BackupPath -DestBlob $backupDiskName -DestContext $StorageContext | out-null
				$BackupState = Get-AzureStorageBlobCopyState -Container $BackupPath -Blob $backupDiskName -Context $StorageContext
				Write-Host $BackupState.Status
			}
			
			if($bRestart)
			{
				Write-Host " - Restarting $($oVM.Name) " -nonewline
				#Start-AzureVM -Name $oVM.Name -ServiceName $oVM.ServiceName
				Start-AVM $oVM $PublishFile $Subscription
			}
		}
		if($op -eq "Restore")
		{
			$sVMConfig = "$cd\$($vm.Name)-$(Get-Date -Format yyyy-MM-dd_h-mm-s).xml"
			Write-Host " - Saving $($oVM.Name) configuration: $sVMConfig"
			Export-AzureVM -Name $oVM.Name -ServiceName $oVM.ServiceName -Path $sVMConfig | out-null
			Write-Host " - Restoring $($oVM.Name) started"
			$Deployment = Get-AzureDeployment $oVM.ServiceName | Out-Null
			$VNetName = $Deployment.VNetName		
			$bRestart = $false
			if(!($oVM.Status -Match "Stop"))
			{
				Write-Host " - Stopping $($oVM.Name) " -nonewline
				Stop-AVM $oVM $PublishFile $Subscription
				$bRestart = $true
			}
			Write-Host " - Removing $($oVM.Name) " -nonewline
			Remove-AzureVM -Name $oVM.Name -ServiceName $oVM.ServiceName | out-null
			Write-Host "... Done"
			
			Write-Host " - Getting $($oVM.Name) attached disks" -nonewline
			$Disks = Get-AzureDisk | ?{($_.AttachedTo.RoleName -eq $($oVM.Name)) -and  ($_.AttachedTo.HostedServiceName -eq $($oVM.ServiceName))}
			Write-Host "...Done"
			$Disks | %{
				$Disk = $_				
				Write-Host " - Disk: $($Disk.DiskName)"			
				if($StorageContext -eq $null)
				{
					$StorageContext = Get-StorageContext $Disk
				}
				
				Write-Host " - Getting Backups from: $BackupPath"
				$backups = $StorageContext | Get-AzureStorageContainer -Container $BackupPath | Get-AzureStorageBlob
				
				$selBackup = list-box "Select a Restore for $($Disk.DiskName):" $($backups | select name)
				if(!($selBackup -gt -1))
				{
					Write-Warning "You must select a Restore for $($Disk.DiskName)"
					break
				}
				
				#http://msdn.microsoft.com/en-us/library/microsoft.windowsazure.storageclient.cloudblobclient_members.aspx
				$currentBlob = $($StorageContext.StorageAccount.CreateCloudBlobClient()).GetBlobReferenceFromServer($Disk.MediaLink)
				$backupBlob = $backups[$selBackup]
				
				if($currentBlob -eq $null)
				{
					Write-Error "Can't get attached disks blob reference... ABORTING"
					Write-Host "ReNew VM from backed up configuration file using operation: New VM XML"
					break
				}
				
				Write-Host " - Removing disk and VHD: $($Disk.DiskName)" -nonewline
				while($(Get-AzureDisk | ?{($_.AttachedTo.RoleName -eq $($oVM.Name)) -and ($_.DiskName -eq $($Disk.DiskName))}) -ne $null)
				{
					Write-Host "." -NoNewline
					Start-Sleep 1
				}
				Remove-AzureDisk -DiskName $Disk.DiskName -DeleteVHD -ea stop | out-null			
				Write-Host "... Done"				
				Write-Host " - Coping backup blob to $($currentBlob.Container.Name)" -nonewline
				Start-AzureStorageBlobCopy -SrcUri $backupBlob.ICloudBlob.Uri -DestContainer $currentBlob.Container.Name -DestBlob $currentBlob.Name -DestContext $StorageContext -ea stop | out-null
				Write-Host "... Done"
				
				Write-Host " - Creating New '$($Disk.DiskName)' Disk" -nonewline
				if($Disk.OS -ne $null)
				{
					Add-AzureDisk -DiskName $Disk.DiskName -MediaLocation $currentBlob.Uri -OS $Disk.OS -ea stop | out-null
				}
				else
				{
					Add-AzureDisk -DiskName $Disk.DiskName -MediaLocation $currentBlob.Uri -ea stop | out-null
				}
				Write-Host "... Done"
			}
			sleep 30
			#Seems to lose StorageContext
			Set-AzureSubscription -SubscriptionName $Subscription -CurrentStorageAccount $StorageContext.StorageAccount
			Write-Host " - Recreating $($oVM.Name)" -nonewline
			Import-AzureVM -Path $sVMConfig | New-AzureVM -ServiceName $oVM.ServiceName -VNetName $VNetName -ea stop | out-null
			Write-Host "... Done"
			if($bRestart)
			{
				Write-Host " - Restarting $($oVM.Name) " -nonewline
				#Start-AzureVM -Name $oVM.Name -ServiceName $oVM.ServiceName
				Start-AVM $oVM $PublishFile $Subscription
			}
			Write-Host "All Done!"
		}
	}
}
