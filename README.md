# AzStorage-FilesCleaner

## Prerequisites

* Current Version of [Azure Powershell](https://docs.microsoft.com/en-us/powershell/azure/install-az-p)
* User running script must be logged into Azure Powershell with the appropriate RBAC permissions to work with Azure Storage Accounts and File Shares

## How to run

To run this PowerShell Script from Powershell on yout local machine run the command below -

`Invoke-Expression $(Invoke-WebRequest -uri aka.ms/azfilescleanerps -UseBasicParsing).Content`
 
or the shorthand version 

`iwr -useb aka.ms/azfilescleanerps | iex`

To download a local copy of the latest version of the script run the command below -

 `Invoke-WebRequest -Uri aka.ms/azfilescleanerps -OutFile Run-AzFilesCleaner.ps1`