# import the CSV file Windows_365_Cloud_Pc.csv into the $csv variable
$csv = Get-Content -Path ".\Windows_365_Cloud_Pc.csv" | convertfrom-csv -Header username

# for each row in the CSV file, split the value in the using @ as the delimiter
# then write out the first value
$splitlist = @()
foreach ($row in $csv) {
    $PSO = New-Object PSObject -Property @{
        Name = $row.username.Split("@")[0]
    }
    $splitlist += $PSO
}
# export the list to a CSV file
$splitlist | Export-Csv -Path ".\splitlist.csv" -NoTypeInformation


$s = Get-AzStorageAccount | where { $_.Kind -like "StorageV2" }