# PATCH FOR EXISTING INTUNE SCRIPT TO FIX DEVICEACTIONRESULTS ISSUE
# This patch addresses the empty deviceActionResults field issue
# 
# PROBLEM: deviceActionResults field appears empty even when data exists in Intune portal
# ROOT CAUSE: Standard API calls may not populate this field completely
# 
# SOLUTION: Use enhanced API calls and fallback mechanisms

# Replace the existing managed devices query section with this enhanced version:

Function Get-EnhancedDeviceActionResults {
    param(
        [hashtable]$headers,
        [string]$proxyurl,
        [System.Management.Automation.PSCredential]$proxycred,
        [string]$ua
    )
    
    LogWrite "Querying ManagedDevices with enhanced deviceActionResults extraction..."
    
    try {
        # METHOD 1: Use beta endpoint with select parameter
        $url = 'https://graph.microsoft.com/beta/deviceManagement/managedDevices?$select=*'
        $result = Invoke-RestMethod -uri $url -ErrorAction Stop -UserAgent $ua -headers $headers -Proxy $proxyurl -ProxyCredential $proxycred
        $machines = @()
        $machines += $result.value
        
        # Handle pagination
        while ($result.'@odata.nextLink') {
            try {
                Start-Sleep -Seconds 2
                $result = (Invoke-RestMethod -Uri $result.'@odata.nextLink' -Headers $headers -Proxy $proxyurl -ProxyCredential $proxycred -UserAgent $ua -Method Get -ContentType "application/json")
                $machines += $result.value
                LogWrite("Retrieved $($machines.count) devices so far...")
            } catch {
                $ex = $_.Exception
                LogWrite("[ERROR] Pagination error: $($ex.Message)")
                break
            }
        }
        
        LogWrite "Total devices retrieved: $($machines.count)"
        
        # METHOD 2: For devices still showing empty deviceActionResults, try individual queries
        $emptyActionDevices = $machines | Where-Object { 
            $_.deviceActionResults -eq $null -or $_.deviceActionResults.Count -eq 0 
        }
        
        if ($emptyActionDevices.Count -gt 0) {
            LogWrite "Found $($emptyActionDevices.Count) devices with potentially missing action results"
            LogWrite "Attempting individual device queries for enhanced data retrieval..."
            
            # Limit individual queries to avoid rate limiting (adjust as needed)
            $maxIndividualQueries = [Math]::Min(100, $emptyActionDevices.Count)
            $sampleDevices = $emptyActionDevices | Select-Object -First $maxIndividualQueries
            
            foreach ($device in $sampleDevices) {
                try {
                    # Try individual device query with v1.0 endpoint
                    $deviceUrl = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/$($device.id)"
                    $individualDevice = Invoke-RestMethod -Uri $deviceUrl -Headers $headers -Proxy $proxyurl -ProxyCredential $proxycred -UserAgent $ua -Method Get -ContentType "application/json" -ErrorAction SilentlyContinue
                    
                    if ($individualDevice.deviceActionResults -and $individualDevice.deviceActionResults.Count -gt 0) {
                        # Update the device in our collection
                        $deviceIndex = $machines.IndexOf($device)
                        if ($deviceIndex -ge 0) {
                            $machines[$deviceIndex].deviceActionResults = $individualDevice.deviceActionResults
                            LogWrite("Updated device '$($device.deviceName)' with $($individualDevice.deviceActionResults.Count) action results")
                        }
                    }
                    
                    Start-Sleep -Milliseconds 200  # Rate limiting
                } catch {
                    LogWrite("Individual query failed for device $($device.id): $($_.Exception.Message)")
                }
            }
        }
        
        return $machines
        
    } catch {
        $ex = $_.Exception
        LogWrite("[ERROR] Enhanced device query failed: $($ex.Message)")
        
        # FALLBACK: Try original method
        LogWrite("Falling back to original query method...")
        try {
            $url = 'https://graph.microsoft.com/v1.0/deviceManagement/managedDevices'
            $result = Invoke-RestMethod -uri $url -ErrorAction Stop -UserAgent $ua -headers $headers -Proxy $proxyurl -ProxyCredential $proxycred
            $machines = @()
            $machines += $result.value
            
            while ($result.'@odata.nextLink') {
                try {
                    Start-Sleep -Seconds 2
                    $result = (Invoke-RestMethod -Uri $result.'@odata.nextLink' -Headers $headers -Proxy $proxyurl -ProxyCredential $proxycred -UserAgent $ua -Method Get -ContentType "application/json")
                    $machines += $result.value
                } catch {
                    LogWrite("[ERROR] Fallback pagination error: $($_.Exception.Message)")
                    break
                }
            }
            
            return $machines
        } catch {
            LogWrite("[ERROR] Fallback method also failed: $($_.Exception.Message)")
            return $null
        }
    }
}

# INSTRUCTIONS FOR APPLYING THIS PATCH:
# 1. Replace the section in your original script that starts with:
#    "LogWrite 'Querying ManagedDevices...'"
#    and ends with the machines collection building
# 
# 2. Replace that entire section with a call to:
#    $machines = Get-EnhancedDeviceActionResults -headers $headers -proxyurl $proxyurl -proxycred $proxycred -ua $ua
#
# 3. Add this function definition near the top of your script after the LogWrite function

# ADDITIONAL IMPROVEMENTS TO CONSIDER:
# 1. Add device action results summary logging
# 2. Export separate action results file
# 3. Add retry logic for failed API calls

# Example of enhanced export section:
Function Export-EnhancedResults {
    param($machines, $basedir)
    
    if ($machines -and $machines.Count -gt 0) {
        LogWrite "Exporting [$($machines.Count)] devices to machines.json..."
        
        # Count devices with action results
        $devicesWithActions = $machines | Where-Object { 
            $_.deviceActionResults -and $_.deviceActionResults.Count -gt 0 
        }
        
        LogWrite "Summary:"
        LogWrite "  Total devices: $($machines.Count)"
        LogWrite "  Devices with action results: $($devicesWithActions.Count)"
        LogWrite "  Devices without action results: $(($machines.Count - $devicesWithActions.Count))"
        
        # Export main file
        $machines | ConvertTo-Json -Depth 100 | Out-File -Path "$basedir\machines.json" -Encoding UTF8
        LogWrite("Export to machines.json successful!")
        
        # Export action results summary if any exist
        if ($devicesWithActions.Count -gt 0) {
            $actionsSummary = @()
            foreach ($device in $devicesWithActions) {
                foreach ($action in $device.deviceActionResults) {
                    $actionsSummary += [PSCustomObject]@{
                        DeviceName = $device.deviceName
                        DeviceId = $device.id
                        UserPrincipalName = $device.userPrincipalName
                        ActionName = $action.actionName
                        ActionState = $action.actionState
                        StartDateTime = $action.startDateTime
                        LastUpdatedDateTime = $action.lastUpdatedDateTime
                    }
                }
            }
            
            $actionsSummary | ConvertTo-Json -Depth 10 | Out-File -Path "$basedir\device_actions_summary.json" -Encoding UTF8
            LogWrite("Created device actions summary with $($actionsSummary.Count) total action records")
        }
    }
}

Write-Host "PATCH READY - Copy the functions above into your script and modify the device query section as instructed" -ForegroundColor Green