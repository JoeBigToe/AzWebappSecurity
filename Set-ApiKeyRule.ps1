param(
    [string]$WafPolicyName,
    [string[]]$APIs = @(
        "Calc",
        "DocInteli"
    ),
    [string]$HttpHeaderName = "Ocp-Apim-Subscription-Key",
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName
)


# Initial assert
$context = $null
try { $context = Get-AzContext } catch {}
if ($null -eq $context.Subscription.Id) { throw 'You must call the Login-AzAccount cmdlet before calling any other cmdlets.' }

$secretName = "$httpHeaderName-{0}"
$Script:Priority = 100
$CustomRuleNameTemplate = "Allow{0}WithHeaderKey"

function New-Password {
    param(
        [int]$length = 32
    )

    [char[]]$charset =  "ABCDEFGHIJKLMNOPQRSTUVWXYZ" + `
                        "abcdefghijklmnopqrstuvwxyz" + `
                        "0123456789"

    -join $($charset | Get-Random -Count $length )

} 

function Search-KeyInKeyVault {
    
    param(
        [string[]]$keyVaultNames,
        [string]$apiName
    )

    foreach ($keyVaultName in $keyVaultNames) {
        try {
            $key = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $($secretName -f $apiName)
            if ( $null -eq $key ) {
                continue
            } else {
                $keySecurePointer = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($key.SecretValue)
                try {
                    $secretValueText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($keySecurePointer)
                } finally {
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($keySecurePointer)
                }
                return $secretValueText
            }
        } catch {
            return
        }
    }
}

function Search-KeyInAPIM {
    param(
        [string]$ResourceGroupName,
        [string]$apiName
    )

    $key = $null
    try {
        $context = New-AzApiManagementContext -ResourceGroupName useffsoplfrsg01 -servicename $($ResourceGroupName -replace 'rsg01', 'aam01')
        $key = Get-AzApiManagementSubscriptionKey -Context $context -SubscriptionId "${apiName}SubscriptionKey" | Select-Object -ExpandProperty "PrimaryKey"
    } catch { }

    Write-Output $key
}

function Register-ApiKeyInKeyVault {

    param(
        [string[]]$keyVaultNames,
        [string]$secretName,
        [string]$secretValueText
    )

    $secretvalueEncrypted = ConvertTo-SecureString $secretValueText -AsPlainText -Force

    foreach ($keyVaultName in $keyVaultNames) {
        try {
            Write-Host "Setting secret '$secretName' in vault '$keyVaultName'"
            Set-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -SecretValue $secretvalueEncrypted | Out-Null
        } catch {
            Write-Error "Could not store secret '$secretName' in keyvault '$keyVaultName'"
        }
    }    
}

function Set-ApiKeyRuleInWaf {

    param(
        [string]$ResourceGroupName,
        [string]$WafPolicyName,
        [string]$Api,
        [hashtable]$HttpHeader
    )

    # INFO: trimend('i') is a workaround for an inconsistency in docintel(i) api naming convention in APIM
    $CustomRuleName = $CustomRuleNameTemplate -f $($api.trimend('i').tolower())
    
    # Get rule
    try {
        $wafObject = Get-AzFrontDoorWafPolicy -ResourceGroupName $ResourceGroupName -Name $WafPolicyName
    } catch {
        throw "Could not get WAF Policy '$WafPolicyName' in resource group '$ResourceGroupName' - can't continue execution"
    }
    $wafApiRule = $wafObject.CustomRules | Where-Object { $_.Name -eq $CustomRuleName }

    if ( $null -eq $wafApiRule ) {
        # INFO: Value 6 was chosen to be less likely to colide to an existing priority value
        $Script:Priority += 6
        
        # Add new custom rule
        # INFO: trimend('i') is a workaround for an inconsistency visible in docintel(i) api
        $matchConditionObject1 = New-AzFrontDoorWafMatchConditionObject `
            -MatchVariable "RequestUri" `
            -OperatorProperty "Contains" `
            -MatchValue "/$($api.trimend('i').tolower())"

        $matchConditionObject2 = New-AzFrontDoorWafMatchConditionObject `
            -MatchVariable "RequestHeader" `
            -OperatorProperty "Equal" `
            -MatchValue $HttpHeader.Values[0] `
            -Selector $HttpHeader.Keys[0]
            
        $customRuleObject = New-AzFrontDoorWafCustomRuleObject `
            -Name $CustomRuleName `
            -RuleType "MatchRule" `
            -MatchCondition @($matchConditionObject1, $matchConditionObject2) `
            -Action "Allow" `
            -Priority $Script:Priority

        $wafObject.CustomRules += $customRuleObject

    } else {
        # Update exsiting custom rule
        Write-Host "A custom rule with the name '$customRuleName' already exists - Updating it with the new key value"
        
        $wafApiCondition = $wafApiRule.MatchConditions | Where-Object { $_.Selector -eq $HttpHeader.keys[0] } 
        $wafApiCondition.MatchValue = $httpHeader.values[0]        
    }

    $wafObject | Update-AzFrontDoorWafPolicy

}

function Get-ApiKey {
    param(
        [string]$apiName,
        [string]$ResourceGroupName
    )

    # Check if there is a value in kv
    Write-Host "Checking if key for '$apiName' already exists in one of the key vaults"
    $key = Search-KeyInKeyVault `
        -keyVaultNames $(Get-AzKeyVault -ResourceGroupName $ResourceGroupName | select-Object -expand VaultName) `
        -apiName $apiName
    if ( $null -ne $key ) {
        return $key
    }

    # Check if there is an apim where we can take the key from
    Write-Host "Checking if key for '$apiName' already exists in an existing APIM"
    $key = Search-KeyInAPIM -ResourceGroupName $ResourceGroupName -apiName $apiName
    if ( $null -ne $key ) {
        return $key
    }

    # If key is nowhere, generate a new one
    Write-Host "Key for '$apiName'doesn't exist. Generating a new one"
    return $(New-Password -length 32)

}

foreach ($api in $APIs) {
    
    $key = Get-ApiKey -apiName $api -ResourceGroupName $ResourceGroupName

    Set-ApiKeyRuleInWaf `
        -ResourceGroupName $ResourceGroupName `
        -WafPolicyName $WafPolicyName `
        -HttpHeader @{
            $HttpHeaderName = $key
        } `
        -Api $api

    Register-ApiKeyInKeyVault `
        -keyVaultNames $(Get-AzKeyVault -ResourceGroupName $ResourceGroupName | select-Object -expand VaultName) `
        -SecretName $($secretName -f $api) `
        -SecretValue $key
}