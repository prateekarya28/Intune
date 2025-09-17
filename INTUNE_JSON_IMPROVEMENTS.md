# Intune Data Extraction - JSON Formatting Improvements

## Problem Description
The original PowerShell script was generating JSON files that were not properly formatted for Pentaho PDI input steps. Common issues included:
- Inconsistent data types
- Invalid JSON structure
- Encoding issues (UTF-8 BOM)
- Contaminated data arrays
- Missing validation

## Solutions Implemented

### 1. Improved Main Script (`improved_intune_extraction.ps1`)

#### Key Improvements:
- **Clean Data Function**: `Clean-JsonData` ensures only valid device objects are included
- **Proper JSON Export**: `Export-JsonForPentaho` handles formatting specifically for Pentaho PDI
- **UTF-8 Encoding**: Uses UTF-8 without BOM for better compatibility
- **Data Validation**: Validates JSON structure before saving
- **Error Handling**: Comprehensive error handling and logging
- **Backup Creation**: Automatically creates timestamped backups
- **Summary Reports**: Generates export summary for tracking

#### New Features:
```powershell
# Clean data validation
if ($item -is [PSCustomObject] -and $item.id -ne $null -and $item.id -ne "") {
    # Process valid items only
}

# Proper array initialization
$machines = @()  # Simple array instead of ArrayList

# UTF-8 without BOM encoding
$utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($FilePath, $jsonOutput, $utf8NoBomEncoding)
```

### 2. JSON Validation Script (`validate_intune_json.ps1`)

#### Usage:
```powershell
# Basic validation
.\validate_intune_json.ps1 -JsonFilePath "C:\path\to\machines.json"

# Detailed validation with property analysis
.\validate_intune_json.ps1 -JsonFilePath "C:\path\to\machines.json" -Detailed

# Validation with automatic repair
.\validate_intune_json.ps1 -JsonFilePath "C:\path\to\machines.json" -FixIssues
```

#### Features:
- **Structure Validation**: Ensures valid JSON format
- **Property Analysis**: Checks for required Intune device properties
- **Data Consistency**: Validates record integrity
- **Encoding Check**: Detects UTF-8 BOM issues
- **Automatic Repair**: Can fix common JSON issues
- **Pentaho PDI Guidelines**: Provides compatibility recommendations

## Usage Instructions

### Step 1: Run the Improved Extraction Script
```powershell
.\improved_intune_extraction.ps1
```

### Step 2: Validate the Output
```powershell
.\validate_intune_json.ps1 -JsonFilePath "C:\backend\data-integration4\scripts\intune\machines.json" -Detailed
```

### Step 3: Fix Issues if Needed
```powershell
.\validate_intune_json.ps1 -JsonFilePath "C:\backend\data-integration4\scripts\intune\machines.json" -FixIssues
```

## Pentaho PDI Compatibility Requirements

### JSON Structure
- Must be a valid JSON array of objects
- Each object should represent one device record
- Consistent property names across all records

### Encoding
- UTF-8 encoding without BOM
- No special characters that could break parsing

### Data Types
- Dates in ISO 8601 format: `yyyy-MM-ddTHH:mm:ss.fffZ`
- Null values properly handled
- No circular references or complex nested objects

### File Size
- Keep files under 500MB for optimal Pentaho PDI performance
- Consider splitting large datasets if necessary

## Troubleshooting

### Common Issues and Solutions

1. **"Invalid JSON format" Error**
   - Run validation script with `-FixIssues` parameter
   - Check for trailing commas or malformed objects

2. **"Encoding issues" in Pentaho PDI**
   - Ensure file is UTF-8 without BOM
   - Use validation script to check encoding

3. **"Empty or null records" Error**
   - Use the cleaning function in the improved script
   - Validate data consistency with detailed validation

4. **Performance Issues in Pentaho PDI**
   - Check file size (should be < 500MB)
   - Consider pagination for large datasets
   - Use streaming mode in Pentaho PDI

## File Outputs

### Main Files Generated:
- `machines.json` - Main export file for Pentaho PDI
- `machines_backup_YYYYMMDD_HHMMSS.json` - Timestamped backup
- `export_summary.json` - Export metadata and statistics
- `intunev4test.log` - Detailed execution log

### Validation Outputs:
- Console output with validation results
- Repair suggestions and automatic fixes
- Backup files when repairs are made

## Migration from Original Script

### Changes Required:
1. Replace original script with `improved_intune_extraction.ps1`
2. Update any automation that references the old script
3. Add validation step to your workflow
4. Update Pentaho PDI input step if needed (should work with existing configuration)

### Backward Compatibility:
- Output file name remains `machines.json`
- JSON structure is compatible with existing Pentaho PDI transformations
- All original data fields are preserved

## Performance Improvements

### Memory Usage:
- More efficient array handling
- Proper cleanup of temporary objects
- Reduced memory footprint during JSON conversion

### Processing Speed:
- Streamlined data cleaning process
- Optimized JSON serialization
- Better error handling reduces retry overhead

## Monitoring and Maintenance

### Regular Checks:
1. Monitor log files for authentication issues
2. Validate JSON output after each run
3. Check backup file sizes and cleanup old backups
4. Monitor Pentaho PDI import success rates

### Recommended Schedule:
- Daily: Check log files for errors
- Weekly: Run validation script on output files
- Monthly: Review and cleanup backup files
- Quarterly: Review script performance and update if needed