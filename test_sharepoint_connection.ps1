# SharePoint Connection Tester
# Use this script to diagnose connection issues

param(
[string] $proxyserver = "lps5.sgp.st.com",
[string] $flow_url = "http://flow.st.com/st/UP/Workstation/_vti_bin/Lists.asmx",
[string] $flow_list = "{97c76647-0644-48bf-b7db-fce673a43ea5}",
[string] $flow_view = "{0E3BEEC2-D920-42CB-8FDE-6B1694DE6597}",
[string] $flow_cred = "LegacyGeneric:target=backend_asset"
)

Import-Module credentialManager

Write-Host "=== SharePoint Connection Diagnostics ==="

# Test 1: Credential retrieval
Write-Host "`n1. Testing credential retrieval..."
try {
    $cred = Get-StoredCredential -Target $flow_cred -AsCredential
    if ($null -eq $cred) {
        Write-Host "❌ No credentials found for target: $flow_cred"
        Write-Host "Available credentials:"
        Get-StoredCredential | ForEach-Object { Write-Host "  - $($_.TargetName)" }
    } else {
        Write-Host "✅ Credentials found for user: $($cred.UserName)"
    }
} catch {
    Write-Host "❌ Error retrieving credentials: $($_.Exception.Message)"
}

# Test 2: Basic connectivity
Write-Host "`n2. Testing basic connectivity..."
$baseUrl = $flow_url.Replace("/_vti_bin/Lists.asmx", "")
try {
    $response = Invoke-WebRequest -Uri $baseUrl -Method HEAD -TimeoutSec 10 -UseBasicParsing
    Write-Host "✅ Basic connectivity successful (Status: $($response.StatusCode))"
} catch {
    Write-Host "❌ Basic connectivity failed: $($_.Exception.Message)"
}

# Test 3: SharePoint Lists.asmx endpoint
Write-Host "`n3. Testing SharePoint Lists.asmx endpoint..."
try {
    $response = Invoke-WebRequest -Uri $flow_url -Method GET -TimeoutSec 10 -UseBasicParsing
    Write-Host "✅ Lists.asmx endpoint accessible (Status: $($response.StatusCode))"
    if ($response.Content -like "*GetListItems*") {
        Write-Host "✅ GetListItems method available"
    } else {
        Write-Host "⚠️  GetListItems method not found in WSDL"
    }
} catch {
    Write-Host "❌ Lists.asmx endpoint test failed: $($_.Exception.Message)"
}

# Test 4: SOAP request with authentication
Write-Host "`n4. Testing SOAP request with authentication..."
if ($cred) {
    $soapRequest = @"
<?xml version='1.0' encoding='utf-8'?>
<soap12:Envelope xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance' xmlns:xsd='http://www.w3.org/2001/XMLSchema' xmlns:soap12='http://www.w3.org/2003/05/soap-envelope'>
  <soap12:Body>
    <GetListItems xmlns='http://schemas.microsoft.com/sharepoint/soap/'>
      <listName>$flow_list</listName>
      <viewName>$flow_view</viewName>
      <rowLimit>10</rowLimit>
    </GetListItems>
  </soap12:Body>
</soap12:Envelope>
"@

    try {
        $headers = @{
            'Content-Type' = 'application/soap+xml; charset=utf-8'
            'SOAPAction' = 'http://schemas.microsoft.com/sharepoint/soap/GetListItems'
        }
        
        # Create credential for web request
        $secPassword = ConvertTo-SecureString $cred.Password -AsPlainText -Force
        $webCred = New-Object System.Management.Automation.PSCredential($cred.UserName, $secPassword)
        
        $response = Invoke-WebRequest -Uri $flow_url -Method POST -Body $soapRequest -Headers $headers -Credential $webCred -TimeoutSec 30 -UseBasicParsing
        
        Write-Host "✅ SOAP request successful (Status: $($response.StatusCode))"
        
        # Parse response
        [xml]$xmlResponse = $response.Content
        $items = $xmlResponse.SelectNodes("//z:row")
        Write-Host "✅ Found $($items.Count) items in response"
        
        # Check for errors in response
        $errors = $xmlResponse.SelectNodes("//soap:Fault | //soap12:Fault")
        if ($errors.Count -gt 0) {
            Write-Host "❌ SOAP Fault found:"
            Write-Host $errors[0].OuterXml
        }
        
    } catch {
        Write-Host "❌ SOAP request failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Host "Response body: $($responseBody.Substring(0, [Math]::Min(500, $responseBody.Length)))"
        }
    }
}

# Test 5: Alternative REST API approach
Write-Host "`n5. Testing alternative REST API approach..."
$restUrl = $baseUrl + "/_api/web/lists(guid'$($flow_list.Trim('{}'))')/items"
try {
    $headers = @{
        'Accept' = 'application/json;odata=verbose'
    }
    
    if ($cred) {
        $secPassword = ConvertTo-SecureString $cred.Password -AsPlainText -Force
        $webCred = New-Object System.Management.Automation.PSCredential($cred.UserName, $secPassword)
        $response = Invoke-WebRequest -Uri $restUrl -Headers $headers -Credential $webCred -TimeoutSec 10 -UseBasicParsing
    } else {
        $response = Invoke-WebRequest -Uri $restUrl -Headers $headers -TimeoutSec 10 -UseBasicParsing
    }
    
    Write-Host "✅ REST API accessible (Status: $($response.StatusCode))"
    $jsonResponse = $response.Content | ConvertFrom-Json
    Write-Host "✅ Found $($jsonResponse.d.results.Count) items via REST API"
} catch {
    Write-Host "❌ REST API test failed: $($_.Exception.Message)"
}

Write-Host "`n=== Diagnostics completed ==="
Write-Host "`nRecommendations:"
Write-Host "1. Check if the list GUID and view GUID are correct"
Write-Host "2. Verify the user has permissions to access the list"
Write-Host "3. Consider using REST API instead of SOAP if available"
Write-Host "4. Check SharePoint logs for detailed error information"