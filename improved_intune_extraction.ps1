#***************************************************************
#  AAD intune auth
#   v4 delegated - IMPROVED VERSION WITH PROPER JSON FORMATTING
# check creds with : rundll32.exe keymgr.dll,KRShowKeyMgr
# Enhanced version using beta endpoint for complete data
# Fixed JSON formatting for Pentaho PDI compatibility
#***************************************************************

Import-Module TUN.CredentialManager
Import-Module JWT

#vars
$proxyserver = "appgw.gnb.st.com"
$proxyport = "8080"
$ua = "Windows-AzureAD-Authentication-Provider/1.0"
$url = "https://graph.microsoft.com/v1.0/devices"
$idp_url = "https://sso.st.com/idp/sts.wst"

#azure
$ClientID = (TUN.CredentialManager\Get-StoredCredential -Target "azure_client_id" -AsCredential).Password
$TenantID = (TUN.CredentialManager\Get-StoredCredential -Target "azure_tenant_id" -AsCredential).Password
$certTHUMB = (TUN.CredentialManager\Get-StoredCredential -Target "azure_defender_cert_thumb" -AsCredential).Password

#delegated username/password for API calls
$username = (TUN.CredentialManager\Get-StoredCredential -Target "LegacyGeneric:target=backend_asset_saml" -AsCredential).Username
$password = (TUN.CredentialManager\Get-StoredCredential -Target "LegacyGeneric:target=backend_asset_saml" -AsCredential).Password

#basedir
$basedir = "C:\backend\data-integration4\scripts\intune"

#more proxy crap
$proxycred = Get-StoredCredential -Target "LegacyGeneric:target=backend_asset_ad"
$proxyurl = "http://$($proxyserver):$($proxyport)"

#log
$Logfile = "$basedir\intunev4test.log"

Function LogWrite
{
   Param ([string]$logstring)
   Add-content $Logfile -value "$((Get-Date).ToString()) : $logstring"
   Write-Host "$((Get-Date).ToString()) : $logstring" -ForegroundColor Green
}

# Function to clean and validate JSON data
Function Clean-JsonData {
    Param ([array]$InputData)
    
    $cleanedData = @()
    
    foreach ($item in $InputData) {
        # Only include valid device objects
        if ($item -is [PSCustomObject] -and $item.id -ne $null -and $item.id -ne "") {
            # Create a clean object with consistent property types
            $cleanItem = [PSCustomObject]@{}
            
            # Copy all properties, ensuring proper data types
            foreach ($property in $item.PSObject.Properties) {
                $value = $property.Value
                
                # Handle null values
                if ($value -eq $null) {
                    $cleanItem | Add-Member -MemberType NoteProperty -Name $property.Name -Value $null
                }
                # Handle datetime objects
                elseif ($value -is [DateTime]) {
                    $cleanItem | Add-Member -MemberType NoteProperty -Name $property.Name -Value $value.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                }
                # Handle arrays
                elseif ($value -is [Array]) {
                    $cleanItem | Add-Member -MemberType NoteProperty -Name $property.Name -Value $value
                }
                # Handle other objects
                else {
                    $cleanItem | Add-Member -MemberType NoteProperty -Name $property.Name -Value $value
                }
            }
            
            $cleanedData += $cleanItem
        }
    }
    
    return $cleanedData
}

# Function to export JSON with proper formatting
Function Export-JsonForPentaho {
    Param (
        [array]$Data,
        [string]$FilePath
    )
    
    try {
        # Clean the data first
        $cleanData = Clean-JsonData -InputData $Data
        
        LogWrite "Cleaned data contains [$($cleanData.Count)] valid device records"
        
        # Convert to JSON with specific formatting for Pentaho PDI
        $jsonOutput = $cleanData | ConvertTo-Json -Depth 10 -Compress:$false
        
        # Ensure UTF-8 encoding without BOM for better compatibility
        $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($FilePath, $jsonOutput, $utf8NoBomEncoding)
        
        # Validate the JSON file
        try {
            $testJson = Get-Content -Path $FilePath -Raw | ConvertFrom-Json
            LogWrite "JSON validation successful - file contains [$($testJson.Count)] records"
            return $true
        }
        catch {
            LogWrite "[ERROR] JSON validation failed: $($_.Exception.Message)"
            return $false
        }
    }
    catch {
        LogWrite "[ERROR] Failed to export JSON: $($_.Exception.Message)"
        return $false
    }
}

#starting
LogWrite("Starting Intune data extraction...")

#build credential
#get cert
$cert = (dir cert: -Recurse | Where-Object { $_.Thumbprint  -eq  $certTHUMB })

#times
$jwtStartTimeUnix = ([DateTimeOffset](Get-Date).ToUniversalTime()).ToUnixTimeSeconds()
$jwtEndTimeUnix = ([DateTimeOffset](Get-Date).AddHours(1).ToUniversalTime()).ToUnixTimeSeconds()

#jwt id
$jwtID = [guid]::NewGuid().Guid

#app endpoint
$appEndPoint = "https://login.microsoftonline.com/$tenantID/oauth2/v2.0/token"

#build JWT token based on cert
$jwt_headers = @{
    alg = "RS256"
    typ = "JWT"
    x5t = ConvertTo-Base64UrlString($cert.GetCertHash())
}  | ConvertTo-Json -Compress

$jwt_payload = @{
    aud = $appEndPoint;
    exp = $jwtEndTimeUnix;
    iss = $clientID;
    jti = $jwtID;
    nbf = $jwtStartTimeUnix;
    sub = $clientID
} | ConvertTo-Json -Compress

$encHeader = ConvertTo-Base64UrlString($jwt_headers)
$encPayLoad = ConvertTo-Base64UrlString($jwt_payload)

$jwtToken = $encHeader + '.' + $encPayLoad
$toSign = [system.text.encoding]::UTF8.GetBytes($jwtToken)

$RSACryptoSP = [System.Security.Cryptography.RSACryptoServiceProvider]::new()
$HashAlgo = [System.Security.Cryptography.SHA256CryptoServiceProvider]::new()
$sha256oid = [System.Security.Cryptography.CryptoConfig]::MapNameToOID("SHA256");

$RSACryptoSP.FromXmlString($cert.PrivateKey.ToXmlString($true))
$hashBytes = $HashAlgo.ComputeHash($toSign)
$signedBytes = $RSACryptoSP.SignHash($hashBytes, $sha256oid)

$sig = ConvertTo-Base64UrlString($signedBytes) 

$jwtTokenSigned = $jwtToken + '.' + $sig

#start auth
LogWrite("Authenticating as [$($username)] ...")

#prep headers
$headers = @{ 
    "SOAPAction" = "http://docs.oasis-open.org/ws-sx/ws-trust/200512/RST/Issue"
        "X-MS-Client-Application" = "Windows-AzureAD-Authentication-Provider/1.0"
    }
#prep req body
$body = "<s:Envelope xmlns:s='http://www.w3.org/2003/05/soap-envelope' xmlns:a='http://www.w3.org/2005/08/addressing' xmlns:u='http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd'> `
<s:Header><a:Action s:mustUnderstand='1'>http://docs.oasis-open.org/ws-sx/ws-trust/200512/RST/Issue</a:Action><a:ReplyTo><a:Address>http://www.w3.org/2005/08/addressing/anonymous</a:Address></a:ReplyTo> `
<a:To s:mustUnderstand='1'>$($idp_url)?TokenProcessorId=UsernameTokenProcessor</a:To><o:Security s:mustUnderstand='1' xmlns:o='http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd'> `
<o:UsernameToken ><o:Username>$($username)</o:Username><o:Password>$($password)</o:Password></o:UsernameToken></o:Security></s:Header> `
<s:Body><trust:RequestSecurityToken xmlns:trust='http://docs.oasis-open.org/ws-sx/ws-trust/200512'><wsp:AppliesTo xmlns:wsp='http://schemas.xmlsoap.org/ws/2004/09/policy'> `
<a:EndpointReference><a:Address>urn:federation:MicrosoftOnline</a:Address></a:EndpointReference></wsp:AppliesTo><trust:KeyType>http://docs.oasis-open.org/ws-sx/ws-trust/200512/Bearer</trust:KeyType> `
<trust:RequestType>http://docs.oasis-open.org/ws-sx/ws-trust/200512/Issue</trust:RequestType></trust:RequestSecurityToken></s:Body></s:Envelope>"

#send req
$response = $null
$response = Invoke-WebRequest -uri "$($idp_url)?TokenProcessorId=UsernameTokenProcessor" -method "Post" -ContentType "application/soap+xml; charset=utf-8" -body $body -UserAgent $ua -headers $headers

#extract SAML assertion
if ($response.StatusCode -eq 200) {

    $xmlContent = $response.Content
    $xmlObject = [xml]$xmlContent
    $assertionxml = $xmlObject.Envelope.Body.RequestSecurityTokenResponseCollection.RequestSecurityTokenResponse.RequestedSecurityToken.Assertion
    
    #convert to Base64
    $assertion = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($assertionxml.OuterXml))

    #get token
    LogWrite("getting token ...")
    $TokenRequestParams = @{
                Method = 'POST'
                Uri    = "https://login.microsoftonline.com/$tenantID/oauth2/v2.0/token"
                Body   = @{
                    grant_type="urn:ietf:params:oauth:grant-type:saml1_1-bearer"
                    client_id  = "$ClientId"
                    scope = "openid https://graph.microsoft.com/.default"
                    assertion = "$assertion"
                    client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
                    client_assertion = "$jwtTokenSigned"
                }
            }
    
    $tokens = Invoke-RestMethod @TokenRequestParams -ErrorAction Stop -UserAgent $ua -Proxy $proxyurl -ProxyCredential $proxycred
    
    if ($tokens.token_type -eq "Bearer") {
        $access_token = $tokens.access_token
        $headers = @{ 
            "Authorization" = "bearer $access_token"
        }
        
        LogWrite "Querying ManagedDevices overview..."
        try{
            $url = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDeviceOverview'
            $result = Invoke-RestMethod -uri $url -ErrorAction Stop -UserAgent $ua -headers $headers -Proxy $proxyurl -ProxyCredential $proxycred
            $expected_count = $result.enrolledDeviceCount
        } catch {
            $ex = $_.Exception
            LogWrite("[ERROR][$($ex.Message)]")
            break
        }
        
        LogWrite "enrolledDeviceCount : $expected_count"
        LogWrite "Querying ManagedDevices..."
        
        try{
            # Use beta endpoint for complete data including managementState
            $url = 'https://graph.microsoft.com/beta/deviceManagement/managedDevices'
            $result = Invoke-RestMethod -uri $url -ErrorAction Stop -UserAgent $ua -headers $headers -Proxy $proxyurl -ProxyCredential $proxycred
            
            # Initialize array properly for JSON export
            $machines = @()
            
            # Add devices with proper validation
            foreach ($device in $result.value) {
                if ($device -ne $null -and $device.id -ne $null) {
                    $machines += $device
                }
            }
            
        } catch {
            $ex = $_.Exception
            LogWrite("[ERROR][$($ex.Message)]")
            break
        }
        
        # Handle pagination
        if ($result.'@odata.nextLink') {
            do {
                try{
                    Start-Sleep -Seconds 2
                    $result = (Invoke-RestMethod -Uri $result.'@odata.nextLink' -Headers $headers -Proxy $proxyurl -ProxyCredential $proxycred -UserAgent $ua -Method Get -ContentType "application/json")
                    LogWrite("Retrieved [$($machines.Count)] devices so far...")
                    
                    # Add devices with proper validation
                    foreach ($device in $result.value) {
                        if ($device -ne $null -and $device.id -ne $null) {
                            $machines += $device
                        }
                    }
                    
                } catch {
                    $ex = $_.Exception
                    LogWrite("[ERROR][$($ex.Message)]")
                    break
                }
            } until (
                !$result.'@odata.nextLink'
            )
        }
                
        LogWrite "Total devices retrieved: [$($machines.Count)]"
        
        if ($($machines.Count) -ge $expected_count) {
            LogWrite "Exporting [$($machines.Count)] devices to machines.json..."
            
            # Export with improved JSON formatting
            $exportSuccess = Export-JsonForPentaho -Data $machines -FilePath "$basedir\machines.json"
            
            if ($exportSuccess) {
                LogWrite("JSON export successful! File is ready for Pentaho PDI.")
                
                # Create a backup with timestamp
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $backupPath = "$basedir\machines_backup_$timestamp.json"
                Copy-Item "$basedir\machines.json" $backupPath
                LogWrite("Backup created: $backupPath")
                
                # Generate summary report
                $summary = @{
                    ExportTimestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                    TotalDevices = $machines.Count
                    ExpectedDevices = $expected_count
                    FilePath = "$basedir\machines.json"
                    BackupPath = $backupPath
                    Status = "Success"
                }
                
                $summary | ConvertTo-Json -Depth 2 | Out-File -Path "$basedir\export_summary.json" -Encoding UTF8
                LogWrite("Export summary saved to: $basedir\export_summary.json")
                
            } else {
                LogWrite("[ERROR] JSON export failed!")
            }
            
        } else {
             LogWrite "[WARNING] Incomplete results! Expected [$expected_count] - got [$($machines.Count)]"
             LogWrite "Proceeding with export of available data..."
             
             # Export available data anyway
             $exportSuccess = Export-JsonForPentaho -Data $machines -FilePath "$basedir\machines_partial.json"
             if ($exportSuccess) {
                 LogWrite("Partial JSON export successful! File: machines_partial.json")
             }
        }
        
    } else {
        LogWrite("Failed to acquire token!")
    }
} else {
    LogWrite("Failed to authenticate!")
}

LogWrite("Intune data extraction completed!")