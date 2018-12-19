#Requires -Modules AzureAD, AzureRm.Profile, Azure.Storage, AzureRM.Storage
<#
.SYNOPSIS 
    A Runbook that imports a CSV from Blob storage, compares data with specific attributes in Azure AD and exports the results to Blob Storage.

    NOTE: This Runbook was developed for a client to perform a specific task, but can be retrofitted to accomodate your requirements.

.DESCRIPTION
    General Usage Instructions
    1. Have a process to automatically update CSV to Blob Storage e.g. Logic App or Function
    2. Either configure a Job Schedule to run the runbook or trigger a Job via a Logic App
    3. The runbook will produce 2 results and export the results to Blob storage. Again a Logic App could be trigger to remove the files elsewhere; 
        a. a result file containing all matched data with Azure AD; 
        b. An Issues file with all records that didn't match.

.PARAMETER AzureConnectionName 
    A mandatory string containing the name of the Automation Account Connection Object e.g. AzureRunAsConnection
     
.PARAMETER StorageAccountName 
    A mandatory string containing the name of the Storage Account that contains the Blob storage. 

.PARAMETER BlobName 
    A mandatory string containing the name of the Blob or File Name e.g. Data.csv
 
.PARAMETER ImportContainer 
    A string containing the name of the Container to import the Blob or File Name e.g. import (Default is import)

.PARAMETER ExportContainer 
    A string containing the name of the Container to export the data to a Blob or File Name e.g. export (Default is export)

.PARAMETER PathToPlaceBlob
    A string containing the location to temporarly store the imported and exported data e.g. $env:TEMP (Default is "$($env:TEMP)")
#>

param
(
    [Parameter(Mandatory = $true)]
    [String]$AzureConnectionName,
    
    [parameter(Mandatory=$true)]
    [String] $StorageAccountName,

    [parameter(Mandatory=$true)]
    [String] $BlobName,

    [parameter(Mandatory=$false)]
    [String] $ImportContainer = "import",

    [parameter(Mandatory=$false)]
    [String] $ExportContainer = "export",

    [parameter(Mandatory=$false)]
    [String] $PathToPlaceBlob = "$($env:TEMP)"
)

#region Functions
function Test-FileContent
{
    <#
    .SYNOPSIS 
        Tests CSV for a particular property and keeps removing the first line until found. Handy when there are multiple headers.
        
    .PARAMETER File 
        A string containing the path to the file to test

    .PARAMETER Property
        A string containing the name of the Property in the header to look for.
    #>

    param
    (
        [parameter(Mandatory=$true)]
        [string]$File,

        [parameter(Mandatory=$true)]
        [string]$Property
    )

    # Get the File Contents and check the first line for the Property
    if ( (Get-Content $File | Select-Object -First 1) -notmatch $Property)
    { 
        # No match found. Skip first line and create a temp file and overwrite original file. Nested loop to test new file. 
        Write-Output " WARNING! Property '$Property' is not in the header of the CSV!"
        Get-Content $File | Select-Object -Skip 1 | Set-Content "$File-temp"
        Move-Item "$File-temp" $File -Force
        Test-FileContent -File $File -Property $Property
    } else 
    {
        # Match found
        Write-Output " SUCCESS! Property '$Property' is in the header of the CSV!"
    }        
}

function Test-EmployeeID
{
    <#
    .SYNOPSIS 
        Tests an employeeID from the CSV data if it's length is less than 5. Employee ID's in Azure AD contain pre-fix of 0's to a maximum of 5 characters.
        
        This function corrects the employee ID to successfully match the employee ID in Azure AD
        
    .PARAMETER User 
        An Object contain the a User details from the CSV Data
    #>

    Param
    (
        [parameter(Mandatory=$true)]
        [PSObject]$User
    )   

    # Get the number of characters in the Users Employee ID
    $charCount = ($user.Emp_No | Measure-Object -Character).Characters
    
    # Test the number of characters in theUsers Employee ID
    if ($charCount -lt 5)
    {
        # Employee ID is less than 5 characters. Modifying.
        $tmp = $user.Emp_No
        $diff = 5 - $charCount
        for ($i = 0; $i -lt $diff; $i++)
        {
            $tmp = "0" + $tmp
        }
        $user.Emp_No = $tmp
    }

    # Return modified or unmodified User Object
    return $user
}

function Get-MatchedUsers
{
    <#
    .SYNOPSIS 
        Compares User details from CSV Data and Azure AD
        
    .PARAMETER Users 
        An Object contain all Users from the CSV Data

    .PARAMETER ADUsers
        An Array List contain all Users from Azure AD
    #>

    Param
    (
        [parameter(Mandatory=$true)]
        [psobject]$Users,

        [parameter(Mandatory=$true)]
        [System.Collections.ArrayList]$ADUsers
    )

    # Create two Results Arrays
    $Issues = @()
    $Users2 = @()

    # Go through each user from the CSV Data
    foreach ($User in $Users)
    {
        # Remove Variables each loop
        Remove-Variable User, ADUser, employeeID, mail, tmp -ErrorAction SilentlyContinue

        # Create Variables
        $User = Test-EmployeeID -User $User
        $employeeID = $user.Emp_No
        $mail = $user.Email_Address
        $samAccountName = $user."Login ID"

        # Populate a new Issue Object
        $Issue = New-Object PSObject -Property @{
            employeeID = $employeeID
            mail = $mail
            samAccountName = $samAccountName
            message = ""
        }

        # Check if Users employeeid exists in ADUsers.employeeid
        if ($employeeID -notin $ADUsers.employeeid)
        {
            # Write to Issue Object
            $Issue.message = "Chris 21 Emp_No '$($employeeID)' does not match any employeeID in Azure AD"

            # Check if Users samAccountName exists in ADUsers.samAccountName
            if ($samAccountName -notin $ADUsers.samAccountName)
            {
                # Write to Issue Object
                $Issue.message = "Chris 21 'login ID '$($samAccountName)' does not match any mailNickName in Azure AD"
                
                # Check if Users mail exists in ADUsers.mail
                if ($mail -notin $ADUsers.mail)
                {
                    # Write to Issue Object
                    $Issue.message = "Chris 21 Email_Address '$($mail)' does not match any userPrincipalName in Azure AD"
                }
            }
        # Or check if Users samAccountName exists in ADUsers.samAccountName
        } elseif ($samAccountName -notin $ADUsers.samAccountName)
        {
            # Get ADUser Details using matching Employee ID
            [psobject]$ADUser = $ADUsers | Where-Object employeeID -eq $employeeID
            
            # Check if User in Azure AD is enabled
            if ($ADUser.accountEnabled)
            {
                # Write to Issue Object
                $Issue.message = "Chris 21 Login ID '$($samAccountName)' does not match Azure AD mailNickName '$($ADUser.samAccountName)'"
            } else
            {
                # Write to Issue Object
                $Issue.message = "Account Disabled in Azure AD. Skipping"                   
            }
        # Or check if Users mail exists in ADUsers.mail
        } elseif ($mail -notin $ADUsers.mail)
        {
            # Get ADUser Details using matching samAccountName
            [psobject]$ADUser = $ADUsers | Where-Object samAccountName -eq $samAccountName
            
            # Check if User in Azure AD is enabled
            if ($ADUser.accountEnabled)
            {
                # Write to Issue Object
                $Issue.message = "Chris 21 Email_Address '$($mail)' does not match Azure AD userPrincipalName '$($ADUser.mail)'"
            } else
            {
                # Write to Issue Object
                $Issue.message = "Account Disabled in Azure AD. Skipping" 
            }
        }

        # Check if there are any issues
        if ($Issue.message -eq "")
        { 
            # No Issues write to New Users Object
            $Users2 += $User  
        } else
        { 
            # No Issues were found for the User. Adding Issue Object to Issues Object
            $Issues += $Issue
        }            
    }

    # Return Results
    return $Users2, $Issues
}
#endregion

#region Variables and Setup
$date = (Get-Date -Format yyyMMddHHmmss)
$ErrorActionPreference =  "Continue"
$version = "0.01.17102018";
Write-Output " Script Version: $($version)"
#endregion

#region Main Code
try
{  
    Write-Output '', " Getting the connection 'AzureRunAsConnection'..."
    $servicePrincipalConnection = Get-AutomationConnection -Name $AzureConnectionName
    $environment = Get-AzureRmEnvironment -Name AzureCloud

    Write-Output '', " Logging in to Azure..."
    $Context = Login-AzureRmAccount `
    -ServicePrincipal `
    -TenantId $servicePrincipalConnection.TenantId `
    -ApplicationId $servicePrincipalConnection.ApplicationId `
    -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint `
    -Environment $environment

    Write-Output '', " Logging in to Azure AD..."
    $ContextAD = Connect-AzureAD `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint   

    Write-Output '', " Downloading $($BlobName) from Azure Blob Storage to $($PathToPlaceBlob)"  

    Write-Output '', " Getting the Storage Account Context..."
    $StorageAccount = Get-AzureRmStorageAccount | Where StorageAccountName -eq $StorageAccountName
    $AccessKey = (Get-AzureRmStorageAccountKey -Name $StorageAccount.StorageAccountName -ResourceGroupName $StorageAccount.ResourceGroupName).Value[0]
    $StorageContext = New-AzureStorageContext -StorageAccountName $StorageAccount.StorageAccountName -StorageAccountKey $AccessKey
    Write-Output " SUCCESS! Got Storage Account Context!"
        
    Write-Output '', " Getting the Storage Account Blob Content..."
    $Blob = Get-AzureStorageBlobContent `
        -Blob $BlobName `
        -Container $ImportContainer `
        -Destination $PathToPlaceBlob `
        -Context $StorageContext `
        -Force
    Write-Output " SUCCESS! Got the Storage Account Blob Content!"

    Write-Output '', " Checking '$($PathToPlaceBlob)\$($BlobName)'..."
    $Item = Get-Item -Path "$($PathToPlaceBlob)\$($BlobName)" -ErrorAction Stop
    Write-Output " SUCCESS! '$($PathToPlaceBlob)\$($BlobName)' exists!"

    Write-Output '', " Checking Header of CSV....."
    Test-FileContent -File "$($PathToPlaceBlob)\$($BlobName)" -Property "Emp_No"
    
    Write-output "`r`n Importing Users from CSV....."
    $Users = Import-Csv "$($PathToPlaceBlob)\$($BlobName)"
        
    $ADUsers = @()
    Write-output "`r`n Getting Users from Azure AD....."
    $Items = Get-AzureADGroup -SearchString ChisholmStaff | Get-AzureADGroupMember -All $true
    $Items = $Items | ConvertTo-Json | ConvertFrom-Json 
    foreach ($item in $Items)
    {
        $tmp = New-Object PSObject -Property @{
            employeeId = $item.ExtensionProperty.employeeId
            mail = $item.UserPrincipalName
            samAccountName = $item.mailNickName
            accountEnabled = $item.accountEnabled
        }

        $ADUsers += $tmp
    }

    Write-Output "`r`n Matching and Comparing records....."
    [psobject]$Users, [psobject]$Issues = Get-MatchedUsers -Users $Users -ADUsers $ADUsers

    if ($Users)
    {
        $Users | Export-Csv -Path "$($PathToPlaceBlob)\$($BlobName)" -NoTypeInformation
            
        Write-Output '', " Writing '$($BlobName)' to Azure Blob Storage..."
        $Blob = Set-AzureStorageBlobContent `
            -Blob $BlobName `
            -Container $ExportContainer `
            -File "$($PathToPlaceBlob)\$($BlobName)" `
            -Context $StorageContext `
            -Force
        Write-Output " SUCCESS! Wrote '$($BlobName)' to Azure Blob Storage!"
    } else 
    {
        Write-Output " WARNING! Nothing to Export!"
    }

    if ($Issues)
    {
        $Issues | Export-Csv -Path "$($PathToPlaceBlob)\Issues_$($date).csv" -NoTypeInformation
            
        Write-Output '', " Writing 'Issues_$($date).csv' to Azure Blob Storage..."
        $Blob = Set-AzureStorageBlobContent `
            -Blob "Issues_$($date).csv" `
            -Container $ExportContainer `
            -File "$($PathToPlaceBlob)\Issues_$($date).csv" `
            -Context $StorageContext `
            -Force
        Write-Output " SUCCESS! Wrote 'Issues_$($date).csv' to Azure Blob Storage!"
    } else 
    {
        Write-Output " SUCCESS! No Issues were found!" 
    }
} catch
{
    if($_.Exception.Message)
    { Write-Error -Message "$($_.Exception.Message)" -ErrorAction Continue } else
    { Write-Error -Message "$($_.Exception)" -ErrorAction Continue }
        
	throw "$($_.Exception)"
} finally
{ Write-Output '', " Runbook ended at time: $(get-Date -format r)" }
#endregion