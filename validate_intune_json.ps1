#***************************************************************
#  JSON Validation Script for Intune Data
#  Use this script to validate JSON output before importing to Pentaho PDI
#***************************************************************

param(
    [Parameter(Mandatory=$true)]
    [string]$JsonFilePath,
    
    [Parameter(Mandatory=$false)]
    [switch]$Detailed,
    
    [Parameter(Mandatory=$false)]
    [switch]$FixIssues
)

Function Write-ValidationLog {
    Param ([string]$message, [string]$type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($type) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$type] $message" -ForegroundColor $color
}

Function Test-JsonStructure {
    Param ([string]$FilePath)
    
    Write-ValidationLog "Starting JSON validation for: $FilePath"
    
    # Check if file exists
    if (-not (Test-Path $FilePath)) {
        Write-ValidationLog "File not found: $FilePath" "ERROR"
        return $false
    }
    
    # Check file size
    $fileInfo = Get-Item $FilePath
    Write-ValidationLog "File size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB"
    
    try {
        # Test JSON parsing
        Write-ValidationLog "Testing JSON parsing..."
        $jsonContent = Get-Content -Path $FilePath -Raw -Encoding UTF8
        $jsonData = $jsonContent | ConvertFrom-Json
        
        Write-ValidationLog "JSON parsing successful!" "SUCCESS"
        Write-ValidationLog "Total records found: $($jsonData.Count)"
        
        # Validate structure
        if ($jsonData.Count -eq 0) {
            Write-ValidationLog "No records found in JSON file" "WARNING"
            return $false
        }
        
        # Check first record structure
        $firstRecord = $jsonData[0]
        $properties = $firstRecord | Get-Member -MemberType NoteProperty
        Write-ValidationLog "Properties found in first record: $($properties.Count)"
        
        if ($Detailed) {
            Write-ValidationLog "Property details:"
            foreach ($prop in $properties | Sort-Object Name) {
                $value = $firstRecord.($prop.Name)
                $valueType = if ($value -eq $null) { "null" } else { $value.GetType().Name }
                Write-ValidationLog "  - $($prop.Name): $valueType"
            }
        }
        
        # Check for required Intune device properties
        $requiredProperties = @("id", "deviceName", "operatingSystem", "complianceState", "managementState")
        $missingProperties = @()
        
        foreach ($reqProp in $requiredProperties) {
            if (-not ($properties.Name -contains $reqProp)) {
                $missingProperties += $reqProp
            }
        }
        
        if ($missingProperties.Count -gt 0) {
            Write-ValidationLog "Missing recommended properties: $($missingProperties -join ', ')" "WARNING"
        } else {
            Write-ValidationLog "All recommended properties found!" "SUCCESS"
        }
        
        # Check for data consistency
        Write-ValidationLog "Checking data consistency across records..."
        $recordsToCheck = [Math]::Min(100, $jsonData.Count)
        $inconsistentRecords = 0
        
        for ($i = 0; $i -lt $recordsToCheck; $i++) {
            $record = $jsonData[$i]
            if ($record.id -eq $null -or $record.id -eq "") {
                $inconsistentRecords++
            }
        }
        
        if ($inconsistentRecords -gt 0) {
            Write-ValidationLog "Found $inconsistentRecords records with missing or empty ID (out of $recordsToCheck checked)" "WARNING"
        } else {
            Write-ValidationLog "Data consistency check passed!" "SUCCESS"
        }
        
        # Check encoding
        $encoding = [System.Text.Encoding]::UTF8
        $bytes = [System.IO.File]::ReadAllBytes($FilePath)
        $hasBOM = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        
        if ($hasBOM) {
            Write-ValidationLog "File has UTF-8 BOM (may cause issues with some systems)" "WARNING"
        } else {
            Write-ValidationLog "File encoding is clean UTF-8 without BOM" "SUCCESS"
        }
        
        return $true
        
    } catch {
        Write-ValidationLog "JSON validation failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

Function Repair-JsonFile {
    Param ([string]$FilePath)
    
    Write-ValidationLog "Attempting to repair JSON file..."
    
    try {
        # Read and parse JSON
        $jsonContent = Get-Content -Path $FilePath -Raw -Encoding UTF8
        $jsonData = $jsonContent | ConvertFrom-Json
        
        # Clean the data
        $cleanedData = @()
        foreach ($item in $jsonData) {
            if ($item -ne $null -and $item.id -ne $null -and $item.id -ne "") {
                $cleanedData += $item
            }
        }
        
        Write-ValidationLog "Cleaned data: $($cleanedData.Count) valid records"
        
        # Create backup
        $backupPath = $FilePath -replace "\.json$", "_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        Copy-Item $FilePath $backupPath
        Write-ValidationLog "Backup created: $backupPath"
        
        # Export cleaned data
        $cleanedJson = $cleanedData | ConvertTo-Json -Depth 10 -Compress:$false
        $utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($FilePath, $cleanedJson, $utf8NoBomEncoding)
        
        Write-ValidationLog "File repaired successfully!" "SUCCESS"
        return $true
        
    } catch {
        Write-ValidationLog "Failed to repair file: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

Function Show-PentahoCompatibilityInfo {
    Write-ValidationLog "=== Pentaho PDI Compatibility Guidelines ==="
    Write-ValidationLog "1. File should be valid JSON (array of objects)"
    Write-ValidationLog "2. Use UTF-8 encoding without BOM"
    Write-ValidationLog "3. Each object should have consistent property names"
    Write-ValidationLog "4. Avoid nested objects if possible (flatten for easier processing)"
    Write-ValidationLog "5. Date fields should be in ISO 8601 format (yyyy-MM-ddTHH:mm:ss.fffZ)"
    Write-ValidationLog "6. File size should be reasonable for memory processing"
    Write-ValidationLog "================================================"
}

# Main execution
Write-ValidationLog "JSON Validation Tool for Pentaho PDI Compatibility" "SUCCESS"
Show-PentahoCompatibilityInfo

$validationPassed = Test-JsonStructure -FilePath $JsonFilePath

if (-not $validationPassed -and $FixIssues) {
    Write-ValidationLog "Attempting to fix issues..."
    $repairSuccess = Repair-JsonFile -FilePath $JsonFilePath
    
    if ($repairSuccess) {
        Write-ValidationLog "Re-validating repaired file..."
        $validationPassed = Test-JsonStructure -FilePath $JsonFilePath
    }
}

if ($validationPassed) {
    Write-ValidationLog "JSON file is ready for Pentaho PDI import!" "SUCCESS"
    exit 0
} else {
    Write-ValidationLog "JSON file has issues that need to be resolved before Pentaho PDI import" "ERROR"
    exit 1
}