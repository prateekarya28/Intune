# Intune DeviceActionResults Troubleshooting Guide

## Problem Description
The `deviceActionResults` field in your Intune data extraction script is returning empty arrays `[]` even though device actions are visible in the Intune portal.

## Root Cause Analysis

### Primary Issues Identified:

1. **API Endpoint Limitations**: The standard `v1.0/deviceManagement/managedDevices` endpoint may not always populate the `deviceActionResults` field completely.

2. **Missing Device Actions**: The `deviceActionResults` field only contains data when administrative actions have been performed on devices (remote wipe, locate, restart, sync, etc.).

3. **Permissions and Scope**: Some device action data might require specific Graph API permissions or scopes.

4. **API Version Differences**: The beta endpoint sometimes provides more complete data than the v1.0 endpoint.

## Solutions Implemented

### Solution 1: Enhanced API Query Strategy
- Use the beta endpoint: `https://graph.microsoft.com/beta/deviceManagement/managedDevices`
- Add `?$select=*` parameter to ensure all fields are returned
- Implement individual device queries for devices with empty results

### Solution 2: Fallback Mechanisms
- If beta endpoint fails, fallback to v1.0 endpoint
- Implement retry logic for failed API calls
- Add individual device queries for enhanced data retrieval

### Solution 3: Data Validation and Logging
- Log the number of devices with and without action results
- Create separate summary files for device actions
- Enhanced error handling and logging

## Implementation Options

### Option A: Complete Script Replacement
Use the provided `intune_enhanced_extraction.ps1` script which includes all enhancements.

### Option B: Patch Existing Script
Apply the functions from `deviceActionResults_patch.ps1` to your existing script.

## Testing and Validation

### Step 1: Verify Permissions
Ensure your application has the following permissions:
- `DeviceManagementManagedDevices.Read.All`
- `DeviceManagementManagedDevices.ReadWrite.All`

### Step 2: Test with Known Devices
1. Identify devices in your Intune portal that have recent actions
2. Note the device IDs
3. Test the enhanced script with these specific devices

### Step 3: Monitor API Responses
Check the logs for:
- Total device count
- Devices with action results count
- Any API errors or rate limiting issues

### Step 4: Validate Output
1. Check `machines.json` for populated `deviceActionResults` fields
2. Review `device_actions_summary.json` for action details
3. Compare results with Intune portal data

## Common Issues and Solutions

### Issue: Still Getting Empty Results
**Possible Causes:**
- No recent device actions in your tenant
- Insufficient permissions
- API rate limiting

**Solutions:**
- Perform a test action (like device sync) in Intune portal
- Verify application permissions in Azure AD
- Add delays between API calls

### Issue: Rate Limiting Errors
**Symptoms:**
- HTTP 429 responses
- Throttling error messages

**Solutions:**
- Increase delays between API calls
- Reduce the number of individual device queries
- Implement exponential backoff

### Issue: Authentication Failures
**Symptoms:**
- 401 Unauthorized responses
- Token acquisition failures

**Solutions:**
- Verify certificate thumbprint
- Check credential manager entries
- Validate tenant ID and client ID

## Performance Considerations

### API Call Optimization
- The enhanced script makes additional API calls for better data completeness
- Individual device queries are limited to avoid rate limiting
- Implement caching for repeated queries

### Rate Limiting Guidelines
- Microsoft Graph allows up to 100 requests per tenant per minute
- Add 200-500ms delays between individual device queries
- Monitor for throttling responses and implement backoff

## Expected Results

### With Device Actions Present:
```json
{
  "deviceActionResults": [
    {
      "@odata.type": "microsoft.graph.deviceActionResult",
      "actionName": "sync",
      "actionState": "done",
      "startDateTime": "2024-01-15T10:30:00Z",
      "lastUpdatedDateTime": "2024-01-15T10:31:00Z"
    }
  ]
}
```

### Summary Statistics:
- Total devices: [count]
- Devices with action results: [count]
- Devices without action results: [count]

## Additional Resources

### Microsoft Graph API Documentation:
- [managedDevice resource type](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-manageddevice)
- [deviceActionResult resource type](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-deviceactionresult)

### Intune Device Actions:
- Sync
- Restart
- Remote wipe
- Locate device
- Reset passcode
- Remote lock

## Support and Troubleshooting

If issues persist after implementing these solutions:

1. Enable verbose logging in the script
2. Capture specific error messages
3. Test with a small subset of devices first
4. Verify device actions exist in Intune portal
5. Check Azure AD application permissions

The enhanced script provides comprehensive logging to help identify and resolve any remaining issues.