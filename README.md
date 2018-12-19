# CsvToAzureADRunbook

## Synopsis
A Runbook that imports a CSV from Blob storage, compares data with specific attributes in Azure AD and exports the results to Blob Storage.

    NOTE: This Runbook was developed for a client to perform a specific task, but can be retrofitted to accomodate your requirements.


## Description
General Usage Instructions</br>
1. Have a process to automatically update CSV to Blob Storage e.g. Logic App or Function
2. Either configure a Job Schedule to run the runbook or trigger a Job via a Logic App
3. The runbook will produce 2 results and export the results to Blob storage. Again a Logic App could be triggered to remove the files elsewhere:
    1. A Result file containing all matched data with Azure AD;
    2. An Issues file with all records that didn't match.

## Parameters
- **AzureConnectionName** - A mandatory string containing the name of the Automation Account Connection Object e.g. AzureRunAsConnection 
- **StorageAccountName** - A mandatory string containing the name of the Storage Account that contains the Blob storage.
- **BlobName** - A mandatory string containing the name of the Blob or File Name e.g. Data.csv
- **ImportContainer** - string containing the name of the Container to import the Blob or File Name e.g. import (Default is import)
- **ExportContainer** - A string containing the name of the Container to export the data to a Blob or File Name e.g. export (Default is export)
- **PathToPlaceBlob** - A string containing the location to temporarly store the imported and exported data e.g. $env:TEMP (Default is "$($env:TEMP)")

## Prerequisites
- Azure Tenant 
- Azure Automation Account
- Modules:
   - AzureAD
   - AzureRm.Profile
   - Azure.Storage
   - AzureRM.Storage

## Versioning
[Github](http://github.com/) for version control.

## Authors
* **Paul Towler** - *Initial work* - [CsvToAzureADRunbook](https://github.com/mrptsai/CsvToAzureADRunbook)

See also the list of [contributors](https://github.com/mrptsai/CsvToAzureADRunbook/graphs/contributors) who participated in this project.