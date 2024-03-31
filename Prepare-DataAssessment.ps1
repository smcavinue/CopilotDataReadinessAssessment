<##Author: Sean McAvinue
##Details: PowerShell Script to Configure an Application Registration with the appropriate permissions to run Perform-DataAssessment.ps1
##          Please fully read and test any scripts before running in your production environment!
        .SYNOPSIS
        Creates an app reg with the appropriate permissions to run the tenant data assessment script and uploads a self signed certificate

        .DESCRIPTION
        Connects to Microsoft Graph and and provisions an app reg in Microsoft Entra with the appropriate permissions

        .Notes
        For similar scripts check out the links below
        
            Blog: https://seanmcavinue.net
            GitHub: https://github.com/smcavinue
            Twitter: @Sean_McAvinue
            Linkedin: https://www.linkedin.com/in/sean-mcavinue-4a058874/


    #>

##

function New-AadApplicationCertificate {
    [CmdletBinding(DefaultParameterSetName = 'DefaultSet')]
    Param(
        [Parameter(mandatory = $true, ParameterSetName = 'ClientIdSet')]
        [string]$ClientId,

        [string]$CertificateName,

        [Parameter(mandatory = $false, ParameterSetName = 'ClientIdSet')]
        [switch]$AddToApplication
    )
    ##Function source: https://www.powershellgallery.com/packages/AadSupportPreview/0.3.8/Content/functions%5CNew-AadApplicationCertificate.ps1

    # Create self-signed Cert
    $notAfter = (Get-Date).AddYears(2)

    try {
        $cert = (New-SelfSignedCertificate -DnsName "TenantDataAssessment" -CertStoreLocation "cert:\currentuser\My" -KeyExportPolicy Exportable -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider" -NotAfter $notAfter)
        
    }

    catch {
        Write-Error "ERROR. Probably need to run as Administrator."
        Write-host $_
        return
    }

    if ($AddToApplication) {
        $Key = @{
            Type  = "AsymmetricX509Cert";
            Usage = "Verify";
            key   = $cert.RawData
        }
        Update-MgApplication -ApplicationId $ClientId -KeyCredentials $Key
    }
    Return $cert.Thumbprint
}

write-host "Provisioning Entra App Registration for Tenant Data Assessment Tool" -ForegroundColor Green
##Name of the app
$appName = "Tenant Data Assessment Tool"
##Consent URL
$ConsentURl = "https://login.microsoftonline.com/{tenant-id}/adminconsent?client_id={client-id}"


##Attempt Azure AD connection until successful
$Context = get-mgcontext 
while (!$Context) {
    Try {
        Connect-MgGraph -NoWelcome -Scopes "Application.ReadWrite.All"
        $Context = get-mgcontext
    }
    catch {
        Write-Host "Error connecting to Microsoft Graph: `n$($error[0])`n Try again..." -ForegroundColor Red
        $Context = $null
    }
}

##Create Resource Access Variable

$params = @{
    RequiredResourceAccess = @(
        @{
            ResourceAppId  = "00000003-0000-0000-c000-000000000000"
            ResourceAccess = @(
                @{
                    Id   = "332a536c-c7ef-4017-ab91-336970924f0d"
                    Type = "Role"
                }
            )
        }
    )
}


Try { 
    ##Check for existing app reg with the same name
    $AppReg = Get-MgApplication -Filter "DisplayName eq '$($appName)'"  -ErrorAction SilentlyContinue

    ##If the app reg already exists, do nothing
    if ($appReg) {
        write-host "App already exists - Please delete the existing 'Tenant Assessment Tool' app from Microsoft Entra and rerun the preparation script to recreate, exiting" -ForegroundColor yellow
        Pause
        exit
    }
    else {


        ##Create the new App Reg
        $appReg = New-MgApplication -DisplayName $appName -Web @{ RedirectUris = "http://localhost"; } -RequiredResourceAccess $params.RequiredResourceAccess -ErrorAction Stop
        Write-Host "Waiting for app to provision..."
        start-sleep -Seconds 20
        
    }
}
catch {
    Write-Host "Error creating new app reg: `n$($error[0])`n Exiting..." -ForegroundColor Red
    pause
    exit
}

$Thumbprint = New-AadApplicationCertificate -ClientId $appReg.Id -AddToApplication -certificatename "Tenant Assessment Certificate"

##Update Consent URL
$ConsentURl = $ConsentURl.replace('{tenant-id}', $context.TenantID)
$ConsentURl = $ConsentURl.replace('{client-id}', $appReg.AppId)

write-host "Consent page will appear, don't forget to log in as admin to grant consent!" -ForegroundColor Yellow
Start-Process $ConsentURl

Write-Host "The below details can be used to run the assessment, take note of them and press any button to clear the window.`nTenant ID: $($context.TenantID)`nClient ID: $($appReg.appID)`nCertificate Thumbprint: $thumbprint" -ForegroundColor Green
Pause
clear
