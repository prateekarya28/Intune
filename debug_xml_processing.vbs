Option Explicit

' Debug version to identify XML processing issues
' Add this code to your existing VBS script for troubleshooting

Dim url, list, phost, puser, ppass, flowu, flowp, view
Dim request, xmlDoc, http, responseText

Set xmlDoc = CreateObject("MSXML2.DOMDocument.6.0")
xmlDoc.async = False

' Get your existing arguments (same as before)
url = WScript.Arguments.Item(0)
list = WScript.Arguments.Item(1)
view = WScript.Arguments.Item(2)
phost = WScript.Arguments.Item(3)
puser = WScript.Arguments.Item(4)
ppass = WScript.Arguments.Item(5)
flowu = WScript.Arguments.Item(6)
flowp = WScript.Arguments.Item(7)

' Your existing SOAP request
request = "<?xml version='1.0' encoding='utf-8'?>" + _
"<soap12:Envelope xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance' xmlns:xsd='http://www.w3.org/2001/XMLSchema' xmlns:soap12='http://www.w3.org/2003/05/soap-envelope'>" + _
"  <soap12:Body>" + _
"    <GetListItems xmlns='http://schemas.microsoft.com/sharepoint/soap/'>" + _
"      <listName>" & list & "</listName>" + _
"      <viewName>" & view & "</viewName>" + _
"      <rowLimit>100000</rowLimit>" + _
"    </GetListItems>" + _
"  </soap12:Body>" + _
"</soap12:Envelope>"

On Error Resume Next

Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
With http
    .setOption 3, ""
    .setProxy "2", phost, "<local>"
    .open "POST", url, False, flowu, flowp
    .setProxyCredentials puser, ppass
    .setRequestHeader "Authorization", "Basic " & Base64Encode(flowu & ":" & flowp)
    .setRequestHeader "Content-Type", "application/soap+xml; charset=utf-8"
    .setRequestHeader "SOAPAction","http://schemas.microsoft.com/sharepoint/soap/GetListItems"
    
    WScript.Echo "Sending SOAP request..."
    .send request
    WScript.Echo "Request sent, HTTP Status: " & .status & " " & .statusText
    
    ' *** ENHANCED DEBUGGING STARTS HERE ***
    
    ' Get response text
    responseText = .responseText
    
    ' Debug: Check response size
    WScript.Echo "Response size: " & Len(responseText) & " characters"
    
    ' Debug: Save raw response for analysis
    Dim fso, rawFile
    Set fso = CreateObject("Scripting.FileSystemObject")
    Set rawFile = fso.CreateTextFile(list & "_raw_response.txt", True)
    rawFile.Write responseText
    rawFile.Close
    WScript.Echo "Raw response saved to: " & list & "_raw_response.txt"
    
    ' Debug: Check for common XML issues
    If InStr(responseText, "<?xml") = 0 Then
        WScript.Echo "ERROR: Response doesn't appear to be XML"
        WScript.Echo "First 200 characters: " & Left(responseText, 200)
        WScript.Quit 1
    End If
    
    ' Debug: Check for SOAP faults
    If InStr(responseText, "soap:Fault") > 0 Or InStr(responseText, "soap12:Fault") > 0 Then
        WScript.Echo "ERROR: SOAP Fault detected in response"
        WScript.Echo "Response: " & responseText
        WScript.Quit 1
    End If
    
    ' Debug: Check for invalid characters
    Dim i, char, invalidChars
    invalidChars = ""
    For i = 1 To Len(responseText)
        char = Mid(responseText, i, 1)
        If Asc(char) < 32 And Asc(char) <> 9 And Asc(char) <> 10 And Asc(char) <> 13 Then
            invalidChars = invalidChars & "Pos " & i & ": ASCII " & Asc(char) & "; "
            If Len(invalidChars) > 200 Then Exit For ' Limit output
        End If
    Next
    
    If invalidChars <> "" Then
        WScript.Echo "WARNING: Invalid XML characters found: " & invalidChars
        ' Clean the response
        responseText = CleanXMLString(responseText)
        WScript.Echo "Response cleaned of invalid characters"
    End If
    
End With

' Try to load XML with better error handling
WScript.Echo "Attempting to parse XML..."
xmlDoc.loadXML(responseText)

If Err.Number <> 0 Then
    WScript.Echo "ERROR during loadXML: " & Err.Description
    WScript.Echo "Error Number: " & Err.Number
    Err.Clear
    WScript.Quit 1
End If

If xmlDoc.parseError.errorCode <> 0 Then
    WScript.Echo "XML Parse Error Details:"
    WScript.Echo "  Error Code: " & xmlDoc.parseError.errorCode
    WScript.Echo "  Reason: " & xmlDoc.parseError.reason
    WScript.Echo "  Line: " & xmlDoc.parseError.line
    WScript.Echo "  Line Position: " & xmlDoc.parseError.linepos
    WScript.Echo "  Source Text: " & xmlDoc.parseError.srcText
    
    ' Save problematic section for analysis
    Dim errorStart, errorEnd, problemSection
    errorStart = xmlDoc.parseError.linepos - 100
    If errorStart < 1 Then errorStart = 1
    errorEnd = xmlDoc.parseError.linepos + 100
    If errorEnd > Len(responseText) Then errorEnd = Len(responseText)
    problemSection = Mid(responseText, errorStart, errorEnd - errorStart)
    
    Set rawFile = fso.CreateTextFile(list & "_error_section.txt", True)
    rawFile.Write problemSection
    rawFile.Close
    WScript.Echo "Problem section saved to: " & list & "_error_section.txt"
    
    WScript.Quit 1
End If

WScript.Echo "✓ XML parsed successfully"

' Try to save with error handling
Dim outputFile
outputFile = list & ".xml"

On Error Resume Next
xmlDoc.save(outputFile)

If Err.Number <> 0 Then
    WScript.Echo "ERROR saving XML file: " & Err.Description
    WScript.Echo "Error Number: " & Err.Number
    
    ' Try alternative save method
    Err.Clear
    Set rawFile = fso.CreateTextFile(outputFile, True)
    rawFile.Write xmlDoc.xml
    rawFile.Close
    
    If Err.Number <> 0 Then
        WScript.Echo "ERROR with alternative save method: " & Err.Description
        WScript.Quit 1
    Else
        WScript.Echo "✓ XML saved using alternative method"
    End If
Else
    WScript.Echo "✓ XML saved successfully to: " & outputFile
End If

On Error GoTo 0

' Count items for verification
Dim itemNodes
Set itemNodes = xmlDoc.selectNodes("//z:row")
WScript.Echo "Total items extracted: " & itemNodes.length

WScript.Echo "=== Extraction completed ==="

' Function to clean invalid XML characters
Function CleanXMLString(inputString)
    Dim i, char, result
    result = ""
    
    For i = 1 To Len(inputString)
        char = Mid(inputString, i, 1)
        ' Keep valid XML characters only
        If (Asc(char) >= 32) Or (Asc(char) = 9) Or (Asc(char) = 10) Or (Asc(char) = 13) Then
            result = result & char
        End If
    Next
    
    CleanXMLString = result
End Function

' Your existing Base64Encode function
Function Base64Encode(inData)
    Const Base64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    Dim sOut, I
    
    For I = 1 To Len(inData) Step 3
        Dim nGroup, pOut
        nGroup = &H10000 * Asc(Mid(inData, I, 1)) + _
          &H100 * MyASC(Mid(inData, I + 1, 1)) + _
          MyASC(Mid(inData, I + 2, 1))
        nGroup = Oct(nGroup)
        nGroup = String(8 - Len(nGroup), "0") & nGroup
        pOut = Mid(Base64, CLng("&o" & Mid(nGroup, 1, 2)) + 1, 1) + _
          Mid(Base64, CLng("&o" & Mid(nGroup, 3, 2)) + 1, 1) + _
          Mid(Base64, CLng("&o" & Mid(nGroup, 5, 2)) + 1, 1) + _
          Mid(Base64, CLng("&o" & Mid(nGroup, 7, 2)) + 1, 1)
        sOut = sOut + pOut
    Next
    
    Select Case Len(inData) Mod 3
        Case 1: sOut = Left(sOut, Len(sOut) - 2) + "=="
        Case 2: sOut = Left(sOut, Len(sOut) - 1) + "="
    End Select
    Base64Encode = sOut
End Function

Function MyASC(OneChar)
    If OneChar = "" Then MyASC = 0 Else MyASC = Asc(OneChar)
End Function