##Input parameters for ClientID Certiciate Thumbprint and TenantID
param(
    [Parameter(Mandatory = $true)]
    [string]$ClientID,

    [Parameter(Mandatory = $true)]
    [string]$Thumbprint,

    [Parameter(Mandatory = $true)]
    [string]$TenantID,

    [Parameter(Mandatory = $false)]
    [string]$CSVPath
)
# Connect to Microsoft Graph
Connect-MgGraph -NoWelcome -ClientId $ClientID -CertificateThumbprint $Thumbprint -TenantId $TenantID
$OutputFileName = "C:\DataAssessment\DataAssessment-$(get-date -Format HHmm-ddMMyy).csv"
if (!$csvPath) {
    $SiteList = (Get-MgSite -All | ? { $_.weburl -notlike "*-my.sharepoint.com*" } |  select id, WebURL)
}
else {
    Try {
        write-host "Validating CSV file..."
        $SiteList = Import-Csv $csvPath
        $SiteList | add-member -MemberType NoteProperty -Name "ID" -Value $_.SiteURL
        foreach ($site in $SiteList) {

            $Split = $site.WebURL.Split("/")
            if (!$Split[4]) {
                $JoinedSiteID = "$($Split[2])"
                $Site.Id = (Get-MgSite -SiteId $JoinedSiteID -ErrorAction stop).id
            }
            else {
                $JoinedSiteID = "$($split[2]):/sites/$($split[4])"
                $Site.Id = (Get-MgSite -SiteId $JoinedSiteID -ErrorAction stop).id
            }

        }
    }
    catch {
        Write-Host "Error finding sites in site list: $($_.Exception.Message)" -ForegroundColor Red
        Pause
        Exit
    }
}

##Get a list of items in a document libraries in each site and check permissions on each item using Graph PowerShell
$i = 0
foreach ($site in $SiteList) {
    $i++
    $SiteName = (get-mgsite -SiteId $site.id).DisplayName
    Write-Progress -Activity "Checking Permissions" -Status "Checking Site $i of $($SiteList.Count)" -PercentComplete (($i / $SiteList.Count) * 100)
    [array]$Libraries = Get-MgSiteDrive -SiteId $site.id -Filter "DriveType eq 'documentLibrary'" | ? { $_.name -ne "Preservation Hold Library" }

    foreach ($library in $Libraries) {
        $List = Get-MgSiteList -SiteId $site.id | ? { $_.WebUrl -eq $library.weburl }
        [array]$Items = Get-MgSiteListItem -SiteId $site.id -ListId $List.id 
        $x = 0
        foreach ($item in $Items) {
            $x++
            Write-Progress -Activity "Checking Permissions" -Status "Checking Site $i of $($SiteList.Count) - Item $x of $($items.count)" -PercentComplete (($i / $SiteList.Count) * 100)
            $DriveItem = Get-MgSiteListItemDriveItem -ListId $list.id -SiteId $site.Id -ListItemId $item.id
            $Permissions = Get-MgDriveItemPermission -DriveId $library.id -DriveItemId $Driveitem.id

            $ItemID = $DriveItem.Id
            $Name = $DriveItem.Name
            $URL = $Item.WebUrl
            $SiteGroups = ($permissions.GrantedToV2.SiteGroup.DisplayName | ? { $_ -ne $null }) -join ';'
            $SiteGroupsCount = ($permissions.GrantedToV2.SiteGroup.DisplayName | ? { $_ -ne $null }).count
            $Users = ($permissions.GrantedToV2.User.DisplayName | ? { $_ -ne $null }) -join ';'
            $UsersCount = ($permissions.GrantedToV2.User.DisplayName | ? { $_ -ne $null }).count
            $Links = ($permissions.link.scope | ? { $_ -ne $null }) -join ';'
            $LinksCount = ($permissions.link.scope | ? { $_ -ne $null }).count

            $PermissionObject = New-Object PSObject -Property @{
                Name = $Name
                URL = $URL
                SiteGroups = $SiteGroups
                SiteGroupsCount = $SiteGroupsCount
                Users = $Users
                UsersCount = $UsersCount
                Links = $Links
                LinksCount = $LinksCount
                SiteName = $SiteName
                SiteURL = $site.WebURL
            }
            If ($PSVersionTable.PSVersion.Major -ge 7) {
                $PermissionObject | Export-Csv -Path $OutputFileName -Append
            }
            Else {
                $PermissionObject | Export-Csv -Path $OutputFileName -Append -NoTypeInformation
            }
        }	
    }
}
