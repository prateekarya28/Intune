@echo off
cd /d C:\backend\data-integration4\scripts\flow\

echo === SharePoint Flow Data Extraction ===
echo Starting extraction process...

rem Test connection first
echo Testing connection...
"c:\Program Files\PowerShell\7\pwsh.exe" "C:\backend\data-integration4\scripts\flow\test_sharepoint_connection.ps1" -proxyserver "lps5.sgp.st.com" -flow_url "http://flow.st.com/st/UP/Workstation/_vti_bin/Lists.asmx" -flow_list "{97c76647-0644-48bf-b7db-fce673a43ea5}" -flow_view "{0E3BEEC2-D920-42CB-8FDE-6B1694DE6597}" -flow_cred "LegacyGeneric:target=backend_asset"

if %ERRORLEVEL% neq 0 (
    echo Connection test failed. Check the output above for details.
    pause
    exit /b 1
)

echo.
echo Connection test passed. Proceeding with data extraction...

rem backend_asset extraction with improved script
"c:\Program Files\PowerShell\7\pwsh.exe" "C:\backend\data-integration4\scripts\flow\improved_flow_wrapper.ps1" -proxyserver "lps5.sgp.st.com" -flow_url "http://flow.st.com/st/UP/Workstation/_vti_bin/Lists.asmx" -flow_list "{97c76647-0644-48bf-b7db-fce673a43ea5}" -flow_view "{0E3BEEC2-D920-42CB-8FDE-6B1694DE6597}" -flow_cred "LegacyGeneric:target=backend_asset"

if %ERRORLEVEL% neq 0 (
    echo Data extraction failed. Check the output above for details.
    pause
    exit /b 1
)

echo.
echo === Extraction completed successfully ===

cd /d C:\backend\data-integration4\scripts\

pause