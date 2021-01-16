param (
    [switch] $all,
    [string[]] $WebAppNames,
    [Parameter(Mandatory)]
    $ResourceGroupName,    
    [Switch] $BehindFrontDoor
)

$context = $null
try { $context = Get-AzContext } catch {}
if ($null -eq $context.Subscription.Id) { throw 'You must call the Login-AzAccount cmdlet before calling any other cmdlets.' }

if ($all) {
    $WebAppNames = (Get-AzWebApp -ResourceGroup $ResourceGroupName).Name
}

try {
    $frontDoorBackendIpAddresses = Get-AzNetworkServiceTag -Location eastus | `
        Select-Object -ExpandProperty Values | `
        Where-Object { $_.Name -eq "AzureFrontDoor.Backend" } | `
        Select-Object -ExpandProperty Properties | `
        Select-Object -ExpandProperty AddressPrefixes
} catch {
    throw "Could not get IP addresses of FrontDoor service"
}

$frontDoorBackendIp4Addresses = $frontDoorBackendIpAddresses -match "\d+\.\d+\.\d+\.\d+"

if ( $frontDoorBackendIp4Addresses.count -eq 0 ) {
    throw "Could not get IP addresses of FrontDoor service"
}
    

$WebAppNames | ForEach-Object -ThrottleLimit 4 -Parallel {
    $WebApp = $_
    $ips = $using:frontDoorBackendIp4Addresses

    try {
        $web_app = Get-AzWebApp -Name $WebApp -ResourceGroupName $using:ResourceGroupName
        $lock_cfg = Get-AzWebAppAccessRestrictionConfig -ResourceGroupName $web_app.ResourceGroup -Name $web_app.Name
    }
    catch {
        throw "WebApp '$WebApp' could not be fetched, failed with following error: $_"
    }
    
    for ($i = 0; $i -lt $ips.Count; $i++) {
        if ( $ips[$i] -notin $lock_cfg.MainSiteAccessRestrictions.IpAddress ) {
            Write-Host "Adding rule number $i for IP Address: $($ips[$i]) for webapp '$WebApp'"
            Add-AzWebAppAccessRestrictionRule `
                -ResourceGroupName $web_app.ResourceGroup `
                -WebAppName $web_app.Name`
                -Name "AzureFrontDoor-Allow-Rule$i"`
                -Priority $(200+$i) `
                -Action Allow `
                -IpAddress $ips[$i]
        }
    }
}