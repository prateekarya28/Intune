# Alternative SharePoint extraction using REST API

param(
[string] $siteUrl = "http://flow.st.com/st/UP/Workstation",
[string] $listGuid = "97c76647-0644-48bf-b7db-fce673a43ea5",
[string] $flow_cred = "LegacyGeneric:target=backend_asset"
)

Import-Module credentialManager

try {
    # Get credentials
    $cred = Get-StoredCredential -Target $flow_cred -AsCredential
    if ($null -eq $cred) {
        throw "No credentials found for target: $flow_cred"
    }

    # Build REST API URL
    $listGuidClean = $listGuid.Trim('{}')
    $restUrl = "$siteUrl/_api/web/lists(guid'$listGuidClean')/items"
    
    Write-Host "Extracting data from: $restUrl"
    
    # Create headers
    $headers = @{
        'Accept' = 'application/json;odata=verbose'
        'Content-Type' = 'application/json;odata=verbose'
    }
    
    # Create credential object
    $secPassword = ConvertTo-SecureString $cred.Password -AsPlainText -Force
    $webCred = New-Object System.Management.Automation.PSCredential($cred.UserName, $secPassword)
    
    # Make REST API call
    $response = Invoke-RestMethod -Uri $restUrl -Headers $headers -Credential $webCred -Method GET
    
    Write-Host "✅ Successfully retrieved $($response.d.results.Count) items"
    
    # Convert to XML format (similar to SOAP response)
    $xmlDoc = New-Object System.Xml.XmlDocument
    $root = $xmlDoc.CreateElement("data")
    $xmlDoc.AppendChild($root)
    
    foreach ($item in $response.d.results) {
        $itemElement = $xmlDoc.CreateElement("row")
        foreach ($property in $item.PSObject.Properties) {
            if ($property.Value -ne $null) {
                $itemElement.SetAttribute($property.Name, $property.Value.ToString())
            }
        }
        $root.AppendChild($itemElement)
    }
    
    # Save to file
    $outputFile = "$listGuid.xml"
    $xmlDoc.Save($outputFile)
    Write-Host "✅ Data saved to: $outputFile"
    
} catch {
    Write-Host "❌ REST API extraction failed: $($_.Exception.Message)"
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Host "Response: $($responseBody.Substring(0, [Math]::Min(500, $responseBody.Length)))"
    }
}