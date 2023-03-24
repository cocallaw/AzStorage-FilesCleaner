#region variables
$_csvfilepath = ""
#endregion
#region functions
function Get-Option {
    Write-Host "What would you like to do?"
    Write-Host "1 - Select Azure Subscription"
    Write-Host "2 - Identify Files to Remove"    
    Write-Host "3 - Remove Files From Azure Files Share"
    Write-Host "8 - Exit"
    $o = Read-Host -Prompt 'Please type the number of the option you would like to perform '
    return ($o.ToString()).Trim()
}
function Helper-AzSubscription {
    param (
        [parameter (Mandatory = $false)]
        [switch]$whoami,
        [parameter (Mandatory = $false)]
        [switch]$select
    )
    if ($whoami) {
        Write-Host "You are currently logged in as:" -BackgroundColor Black -ForegroundColor Green
        Get-AzContext | ft Account, Name -AutoSize
    }
    if ($select) {
        Write-Host "Please select the Azure subscription you would like to use:" -BackgroundColor Black -ForegroundColor Yellow
        $sub = Get-AzSubscription | ogv -Title "Select Your Azure Subscription" -PassThru
        Write-Host "Changing Azure Subscription to" $sub.Name "with the ID of" $sub.Id -BackgroundColor Black -ForegroundColor Yellow
        Select-AzSubscription -SubscriptionId $sub.Id
    }
}
function Get-CSVlistpath {
    Add-Type -AssemblyName System.Windows.Forms
    $FB = New-Object System.Windows.Forms.OpenFileDialog -Property @{ 
        InitialDirectory = [Environment]::GetFolderPath('Desktop')
        Filter           = 'CSV File (*.csv)|*.csv'
        Multiselect      = $false
    }
    $null = $FB.ShowDialog()
    return $FB.FileName
}
function Get-CSVlist {
    param (
        [parameter (Mandatory = $true)]
        [string]$csvfilepath
    )
    $csv = Get-Content -Path $csvfilepath | Select-Object -Skip 1 | ConvertFrom-Csv -Header matchvalue, directory, sharename, storageacct, resourcegroup
    Write-Host $csv.count"Items were imported from the CSV file provided"  -BackgroundColor Black -ForegroundColor Green
    return $csv 
}
function Get-AzStgAcctWithShare {
    $stgacctfltr = @()
    Write-Host "Getting list of available storage accounts" -BackgroundColor Black -ForegroundColor Green
    $stgaccts = Get-AzStorageAccount | where { $_.Kind -like "StorageV2" }
    Write-Host $stgaccts.count"Storage Accounts were found"  -BackgroundColor Black -ForegroundColor Green
    foreach ($stg in $stgaccts) {
        $sh = $stg | Get-AzRMStorageShare
        if ($sh.count -gt 0) {
            $PSO = New-Object PSObject -Property @{
                StorageAccountName = $stg.StorageAccountName
                ResrouceGroupName  = $stg.ResourceGroupName
                ShareName          = $sh.Name
                Context            = $stg.Context
            }
            $stgacctfltr += $PSO
        }
    }
    return $stgacctfltr
}
function Get-ShareMatches {
    [CmdletBinding()]
    param (
        [parameter (Mandatory = $true)]
        [psobject]$names,
        [parameter (Mandatory = $true)]
        [string]$share,
        [parameter (Mandatory = $true)]
        [Microsoft.Azure.Commands.Common.Authentication.Abstractions.IStorageContext]$stgcontext
    )
    $sfiles = Get-AzStorageFile -Context $stgcontext -ShareName $share
    $ArrayList = New-Object -TypeName System.Collections.ArrayList
    foreach ($n in $names) {
        if ($n.directory -ne $null) {
            $a = $n.matchvalue
            $b = $sfiles | where { $_.Name -like "*$a*" }
            if ($b -ne $null) {
                if ($b.count -gt 1) {
                    Write-Host "$a has been matched to" $b.count "files" -ForegroundColor Yellow
                }
                else {
                    Write-Host "$a has been matched to" $b.Name
                    $match = @{id = $a; dir = $b.Name } 
                    $ArrayList += $match
                }
            }
        }
    }
    return $ArrayList
}
function Get-MatchedCSVList {
    param (
        [parameter (Mandatory = $true)]
        [psobject]$csv,
        [parameter (Mandatory = $true)]
        [psobject]$uss
    )
    foreach ($u in $uss) {
        $matched = Get-ShareMatches -names $csv -share $u.ShareName -stgcontext $u.Context
        foreach ($m in $matched) {
            foreach ($c in $csv) {
                if ($c.matchvalue -eq $m.id) {
                    $c.directory = $m.dir
                    $c.sharename = $u.ShareName
                    $c.storageacct = $u.StorageAccountName
                    $c.resourcegroup = $u.ResrouceGroupName
                }
            }
        }
    }
    return $csv
}
function Get-StorageContextList {
    param (
        [parameter (Mandatory = $true)]
        [psobject]$csv
    )
    $stgcontextlist = @()
    foreach ($c in $csv) {
        if ($c.storageacct -eq $null -or $c.resourcegroup -eq $null) {
            $csv = $csv | where { $_.matchvalue -ne $c.matchvalue }
        }
    }
    $fcsv = $csv | select storageacct, resourcegroup | sort storageacct | group storageacct
    foreach ($f in $fcsv) {
        $stgcontext = (Get-AzStorageAccount -ResourceGroupName $f.group[0].resourcegroup -AccountName $f.name).Context
        $PSO = New-Object PSObject -Property @{
            StorageAccountName = $f.name
            Context            = $stgcontext
        }
        $stgcontextlist += $PSO
    }
    return $stgcontextlist
}
function Start-AzFileRemoval {
    param (
        [parameter (Mandatory = $true)]
        [psobject]$csv,
        [parameter (Mandatory = $true)]
        [psobject]$stgcntxt
    )
    $rnd = Get-Random -Minimum 100 -Maximum 999 
    $r = Read-Host "Please type in $rnd to confirm and start deletion or type stop to cancel"
    if ($r.trim() -eq $rnd) {
        write-host "Deletion confirmed starting in 5 seconds" -ForegroundColor Green
        Start-Sleep -Seconds 5
        Write-Host "Starting Deletion" -ForegroundColor Yellow
        foreach ($c in $csv) {
            if ($c.directory -eq $null -or $c.sharename -eq $null -or $c.storageacct -eq $null -or $c.resourcegroup -eq $null) {
                Write-Host "Skipping" $c.matchvalue "as it has not been properly matched" -ForegroundColor Yellow
            }
            else {
                $stgcontext = $stgcntxt | where { $_.StorageAccountName -eq $c.storageacct }
                $stgcontext = $stgcontext.Context
                Write-Host "Removing files from Directory" $c.directory "in" $c.storageacct
                $t = Get-AzStorageFile -Context $stgcontext -ShareName $c.sharename -Path $c.directory | Get-AzStorageFile 
                if ($t.count -gt 0) {
                    Get-AzStorageFile -Context $stgcontext -ShareName $c.sharename -Path $c.directory | Get-AzStorageFile | Remove-AzStorageFile 
                }
                Write-Host "Removing the directory" $c.directory "from" $c.sharename "in" $c.storageacct
                Remove-AzStorageDirectory -Context $stgcontext -ShareName $c.sharename -Path $c.directory
            }
        }
    }
    elseif ($r.trim().ToLower() -eq "stop") {
        Write-Host "Machine reset aborted" -ForegroundColor Red
        exit
    }
    else {
        Write-Host "Unknown input please try again" -ForegroundColor Red
        Invoke-Option -userSelection (Get-Option)
    }
}
function Invoke-Option {
    param (
        [parameter (Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateLength(1, 1)]
        [string]$userSelection
    )
    if ($userSelection -eq "1") {
        #1 - Select Azure Subscription
        Helper-AzSubscription -whoami
        Helper-AzSubscription -select
        Invoke-Option -userSelection (Get-Option)
    }
    elseif ($userSelection -eq "2") {
        #2 - Identify Files to Remove
        Write-Host "Starting the process to identify the files to remove from the Azure Files Share"
        Write-Host "Please select the CSV file that contains the list of names to perform matching against"
        $csvfilepath = Get-CSVlistpath
        $Global:_csvfilepath = $csvfilepath
        $csv = Get-CSVlist -csvfilepath $csvfilepath
        $stgacctwshare = Get-AzStgAcctWithShare
        Write-Host "Please select the Azure Files Share you would like to perform the matching against"
        $uss = $stgacctwshare | ogv -Title "Select Azure File Share" -PassThru
        $mcsv = Get-MatchedCSVList -uss $uss -csv $csv
        $mcsv | Export-Csv -Path $Global:_csvfilepath -NoTypeInformation
        Invoke-Option -userSelection (Get-Option)
    }
    elseif ($userSelection -eq "3") {
        #3 - Remove Files from Azure Files Share"
        Write-Host "Starting the process to identify the files to remove from the Azure Files Share" -ForegroundColor Green
        Write-Host "Please select the CSV file that contains the list of names to perform removal against" -ForegroundColor Yellow
        $csvfilepath = Get-CSVlistpath
        $Global:_csvfilepath = $csvfilepath
        $csv = Get-CSVlist -csvfilepath $csvfilepath
        $stgcntxt = Get-StorageContextList -csv $csv
        Start-AzFileRemoval -csv $csv -stgcntxt $stgcntxt
        Invoke-Option -userSelection (Get-Option)
    }
    elseif ($userSelection -eq "8") {
        #8 - Exit
        break
    }
    else {
        Write-Host "You have selected an invalid option please select again." -ForegroundColor Red
        Invoke-Option -userSelection (Get-Option)
    }
}
#endregion
#region main
Write-Host "Welcome to the Azure Files Cleaner Script"
try {
    Invoke-Option -userSelection (Get-Option)
}
catch {
    Write-Host "Something went wrong" -ForegroundColor Yellow
    Invoke-Option -userSelection (Get-Option)
}
#endregion