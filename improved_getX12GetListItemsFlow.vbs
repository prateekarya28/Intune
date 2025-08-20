Option Explicit

''''''''''''''''''''''''''''''
' Generic Flow list extractor - IMPROVED VERSION
' params: 
' 0 : list consumer url
' 1 : list name 
' 2 : view name 
' 3 : proxy host
' 4 : proxy user
' 5 : proxy passwd
' 6 : XNet user
' 7 : XNet passwd
'''''''''''''''''''''''''''''

Dim url, list, phost, puser, ppass, flowu, flowp, view
Dim request, xmlDoc, http

' Enable error handling
On Error Resume Next

Set xmlDoc = CreateObject("MSXML2.DOMDocument.6.0")
xmlDoc.async = False

' Validate arguments
If WScript.Arguments.Count < 8 Then
    WScript.Echo "Error: Insufficient arguments provided"
    WScript.Echo "Expected 8 arguments, got " & WScript.Arguments.Count
    WScript.Quit 1
End If

' Get arguments
url = WScript.Arguments.Item(0)
list = WScript.Arguments.Item(1)
view = WScript.Arguments.Item(2)
phost = WScript.Arguments.Item(3)
puser = WScript.Arguments.Item(4)
ppass = WScript.Arguments.Item(5)
flowu = WScript.Arguments.Item(6)
flowp = WScript.Arguments.Item(7)

' Validate required parameters
If url = "" Or list = "" Or view = "" Then
    WScript.Echo "Error: URL, list, or view cannot be empty"
    WScript.Quit 1
End If

' Display configuration
WScript.Echo "=== SharePoint Flow Data Extraction ==="
WScript.Echo "Consumer URL : " & url
WScript.Echo "List GUID    : " & list
WScript.Echo "View GUID    : " & view
WScript.Echo "Proxy Host   : " & phost
WScript.Echo "Flow User    : " & flowu
WScript.Echo "========================================="

' Build SOAP request with proper escaping
request = "<?xml version='1.0' encoding='utf-8'?>" & _
"<soap12:Envelope xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance' xmlns:xsd='http://www.w3.org/2001/XMLSchema' xmlns:soap12='http://www.w3.org/2003/05/soap-envelope'>" & _
"  <soap12:Body>" & _
"    <GetListItems xmlns='http://schemas.microsoft.com/sharepoint/soap/'>" & _
"      <listName>" & list & "</listName>" & _
"      <viewName>" & view & "</viewName>" & _
"      <rowLimit>10000</rowLimit>" & _
"    </GetListItems>" & _
"  </soap12:Body>" & _
"</soap12:Envelope>"

WScript.Echo "SOAP Request prepared, length: " & Len(request)

' Create HTTP object with error handling
Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
If Err.Number <> 0 Then
    WScript.Echo "Error creating HTTP object: " & Err.Description
    WScript.Quit 1
End If

' Configure SSL options
Const SXH_OPTION_SELECT_CLIENT_SSL_CERT = 3
Const SXH_SERVER_CERT_IGNORE_ALL_SERVER_ERRORS = 13056

' Try different HTTP configurations
Dim httpSuccess
httpSuccess = False

' Attempt 1: With SSL cert ignore
WScript.Echo "Attempting connection (SSL ignore)..."
On Error Resume Next
http.setOption SXH_SERVER_CERT_IGNORE_ALL_SERVER_ERRORS, SXH_SERVER_CERT_IGNORE_ALL_SERVER_ERRORS
If Err.Number = 0 Then
    WScript.Echo "✓ SSL certificate ignore option set"
Else
    WScript.Echo "⚠ Could not set SSL ignore option: " & Err.Description
    Err.Clear
End If

' Set proxy
If phost <> "" Then
    http.setProxy 2, phost, "<local>"
    If Err.Number = 0 Then
        WScript.Echo "✓ Proxy set to: " & phost
    Else
        WScript.Echo "⚠ Error setting proxy: " & Err.Description
        Err.Clear
    End If
End If

' Open connection
http.open "POST", url, False, flowu, flowp
If Err.Number <> 0 Then
    WScript.Echo "Error opening connection: " & Err.Description
    WScript.Quit 1
End If
WScript.Echo "✓ Connection opened"

' Set proxy credentials if provided
If puser <> "" And ppass <> "" Then
    http.setProxyCredentials puser, ppass
    If Err.Number = 0 Then
        WScript.Echo "✓ Proxy credentials set"
    Else
        WScript.Echo "⚠ Error setting proxy credentials: " & Err.Description
        Err.Clear
    End If
End If

' Set headers
http.setRequestHeader "Content-Type", "application/soap+xml; charset=utf-8"
http.setRequestHeader "SOAPAction", "http://schemas.microsoft.com/sharepoint/soap/GetListItems"

' Add authorization header if credentials provided
If flowu <> "" And flowp <> "" Then
    Dim authHeader
    authHeader = "Basic " & Base64Encode(flowu & ":" & flowp)
    http.setRequestHeader "Authorization", authHeader
    WScript.Echo "✓ Authorization header set"
End If

' Additional headers for better compatibility
http.setRequestHeader "User-Agent", "SharePoint-Data-Extractor/1.0"
http.setRequestHeader "Accept", "text/xml, application/xml"

WScript.Echo "Sending SOAP request..."

' Send request with error handling
http.send request
If Err.Number <> 0 Then
    WScript.Echo "Error sending request: " & Err.Description
    WScript.Quit 1
End If

WScript.Echo "Request sent successfully"
WScript.Echo "HTTP Status: " & http.status & " " & http.statusText

' Check HTTP status
If http.status <> 200 Then
    WScript.Echo "Error: HTTP " & http.status & " - " & http.statusText
    WScript.Echo "Response Headers:"
    WScript.Echo http.getAllResponseHeaders
    WScript.Echo "Response Body:"
    WScript.Echo http.responseText
    WScript.Quit 1
End If

' Process response
Dim responseText
responseText = http.responseText

If responseText = "" Then
    WScript.Echo "Error: Empty response received"
    WScript.Quit 1
End If

WScript.Echo "✓ Response received, length: " & Len(responseText)

' Load and validate XML
xmlDoc.loadXML(responseText)
If Err.Number <> 0 Then
    WScript.Echo "Error loading XML: " & Err.Description
    WScript.Echo "Response text: " & Left(responseText, 500) & "..."
    WScript.Quit 1
End If

If xmlDoc.parseError.errorCode <> 0 Then
    WScript.Echo "XML Parse Error: " & xmlDoc.parseError.reason
    WScript.Echo "Line: " & xmlDoc.parseError.line
    WScript.Echo "Position: " & xmlDoc.parseError.linepos
    WScript.Echo "Response text: " & Left(responseText, 500) & "..."
    WScript.Quit 1
End If

' Check for SOAP faults
Dim faultNode
Set faultNode = xmlDoc.selectSingleNode("//soap:Fault | //soap12:Fault")
If Not faultNode Is Nothing Then
    WScript.Echo "SOAP Fault detected:"
    WScript.Echo faultNode.xml
    WScript.Quit 1
End If

' Count items
Dim itemNodes
Set itemNodes = xmlDoc.selectNodes("//z:row")
WScript.Echo "✓ Found " & itemNodes.length & " items in response"

' Save XML
Dim outputFile
outputFile = list & ".xml"
xmlDoc.save(outputFile)
If Err.Number <> 0 Then
    WScript.Echo "Error saving file: " & Err.Description
    WScript.Quit 1
End If

WScript.Echo "✓ Data saved to: " & outputFile
WScript.Echo "=== Extraction completed successfully ==="

On Error GoTo 0

' Cleanup
Set http = Nothing
Set xmlDoc = Nothing

WScript.Quit 0

' Base64 encoding function (improved)
Function Base64Encode(inData)
    Const Base64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    Dim sOut, I
    
    ' Handle empty input
    If Len(inData) = 0 Then
        Base64Encode = ""
        Exit Function
    End If
    
    ' For each group of 3 bytes
    For I = 1 To Len(inData) Step 3
        Dim nGroup, pOut
        
        ' Create one long from this 3 bytes
        nGroup = &H10000 * Asc(Mid(inData, I, 1)) + _
          &H100 * MyASC(Mid(inData, I + 1, 1)) + _
          MyASC(Mid(inData, I + 2, 1))
        
        ' Convert to octal
        nGroup = Oct(nGroup)
        
        ' Add leading zeros
        nGroup = String(8 - Len(nGroup), "0") & nGroup
        
        ' Convert to base64
        pOut = Mid(Base64, CLng("&o" & Mid(nGroup, 1, 2)) + 1, 1) + _
          Mid(Base64, CLng("&o" & Mid(nGroup, 3, 2)) + 1, 1) + _
          Mid(Base64, CLng("&o" & Mid(nGroup, 5, 2)) + 1, 1) + _
          Mid(Base64, CLng("&o" & Mid(nGroup, 7, 2)) + 1, 1)
        
        ' Add to output string
        sOut = sOut + pOut
    Next
    
    ' Handle padding
    Select Case Len(inData) Mod 3
        Case 1: ' 8 bit final
            sOut = Left(sOut, Len(sOut) - 2) + "=="
        Case 2: ' 16 bit final
            sOut = Left(sOut, Len(sOut) - 1) + "="
    End Select
    
    Base64Encode = sOut
End Function

Function MyASC(OneChar)
    If OneChar = "" Then 
        MyASC = 0 
    Else 
        MyASC = Asc(OneChar)
    End If
End Function