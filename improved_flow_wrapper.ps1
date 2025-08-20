#flow vbs wrapper with improved error handling

param(
[string] $proxyserver,
[string] $flow_url,
[string] $flow_list,
[string] $flow_view,
[string] $flow_cred
)

Import-Module credentialManager

Write-Host "=== SharePoint Flow Data Extraction ==="
Write-Host "Proxy Server: $proxyserver"
Write-Host "Flow URL: $flow_url"
Write-Host "List GUID: $flow_list"
Write-Host "View GUID: $flow_view"
Write-Host "Credential Target: $flow_cred"
Write-Host "========================================="

# Test credential retrieval
try {
    $cred = Get-StoredCredential -Target $flow_cred -AsCredential
    if ($null -eq $cred) {
        Write-Error "Failed to retrieve credentials for target: $flow_cred"
        exit 1
    }
    Write-Host "✓ Credentials retrieved successfully for user: $($cred.UserName)"
} catch {
    Write-Error "Error retrieving credentials: $($_.Exception.Message)"
    exit 1
}

# Cleanup previous files
$outputFile = "$($flow_list).xml"
if (Test-Path $outputFile) {
    Remove-Item $outputFile -ErrorAction SilentlyContinue
    Write-Host "✓ Cleaned up previous output file"
}

# Test network connectivity
try {
    $testUrl = $flow_url.Replace("/_vti_bin/Lists.asmx", "")
    Write-Host "Testing connectivity to: $testUrl"
    $response = Invoke-WebRequest -Uri $testUrl -Method HEAD -TimeoutSec 10 -UseBasicParsing -ErrorAction Stop
    Write-Host "✓ Network connectivity test passed"
} catch {
    Write-Warning "Network connectivity test failed: $($_.Exception.Message)"
    Write-Host "Proceeding anyway..."
}

# Call VBS script with enhanced error handling
$vbsScript = "C:\backend\data-integration4\scripts\getX12GetListItemsFlow_improved.vbs"
$vbsArgs = @($flow_url, $flow_list, $flow_view, $proxyserver, $cred.UserName, $cred.Password, $cred.UserName, $cred.Password)

Write-Host "Calling VBS script..."
Write-Host "VBS Script: $vbsScript"

try {
    $process = Start-Process -FilePath "C:\windows\SysWOW64\cscript.exe" -ArgumentList @("/nologo", $vbsScript) + $vbsArgs -Wait -PassThru -RedirectStandardOutput "output.log" -RedirectStandardError "error.log"
    
    # Read and display output
    if (Test-Path "output.log") {
        $output = Get-Content "output.log"
        Write-Host "=== VBS Output ==="
        $output | ForEach-Object { Write-Host $_ }
        Remove-Item "output.log" -ErrorAction SilentlyContinue
    }
    
    # Read and display errors
    if (Test-Path "error.log") {
        $errors = Get-Content "error.log"
        if ($errors) {
            Write-Host "=== VBS Errors ==="
            $errors | ForEach-Object { Write-Error $_ }
        }
        Remove-Item "error.log" -ErrorAction SilentlyContinue
    }
    
    # Check exit code
    if ($process.ExitCode -ne 0) {
        Write-Error "VBS script failed with exit code: $($process.ExitCode)"
        exit $process.ExitCode
    }
    
    # Verify output file was created
    if (Test-Path $outputFile) {
        $fileSize = (Get-Item $outputFile).Length
        Write-Host "✓ Output file created: $outputFile (Size: $fileSize bytes)"
        
        # Quick validation of XML content
        try {
            [xml]$xmlContent = Get-Content $outputFile
            $itemCount = $xmlContent.SelectNodes("//z:row").Count
            Write-Host "✓ XML is valid, contains $itemCount items"
        } catch {
            Write-Warning "XML validation failed: $($_.Exception.Message)"
        }
    } else {
        Write-Error "Output file was not created: $outputFile"
        exit 1
    }
    
} catch {
    Write-Error "Error executing VBS script: $($_.Exception.Message)"
    exit 1
}

Write-Host "=== Extraction completed successfully ==="