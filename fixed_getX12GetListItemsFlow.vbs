Option Explicit

''''''''''''''''''''''''''''''
' Generic Flow list extractor - FIXED VERSION
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
Dim viewFields, request, xmlDoc, responseText

Set xmlDoc = CreateObject("MSXML2.DOMDocument.6.0")
xmlDoc.async = False

url = WScript.Arguments.Item(0)
list = WScript.Arguments.Item(1)
view = WScript.Arguments.Item(2)
phost = WScript.Arguments.Item(3)
puser = WScript.Arguments.Item(4)
ppass = WScript.Arguments.Item(5)
flowu = WScript.Arguments.Item(6)
flowp = WScript.Arguments.Item(7)

'echo so we know what we're doing
wscript.echo "Generic Flow list extractor"
wscript.echo "consumer url : " & url
wscript.echo "list         : " & list
wscript.echo "view         : " & view
wscript.echo "proxy host   : " & phost
wscript.echo "Flow user    : " & flowu

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

const SXH_OPTION_SELECT_CLIENT_SSL_CERT = 3

On Error Resume Next

with CreateObject("MSXML2.ServerXMLHTTP.6.0")
  .setOption SXH_OPTION_SELECT_CLIENT_SSL_CERT,""
  .setProxy "2", phost, "<local>"
  .open "POST", url, False, flowu, flowp
  .setProxyCredentials puser, ppass
  .setRequestHeader "Authorization", "Basic " & Base64Encode(flowu & ":" & flowp)
  .setRequestHeader "Content-Type", "application/soap+xml; charset=utf-8"
  .setRequestHeader "SOAPAction","http://schemas.microsoft.com/sharepoint/soap/GetListItems"
  wscript.echo "Sending SOAP request..."
  .send request
  wscript.echo "Request sent, HTTP Status: " & .status & " " & .statusText
  
  ' *** ENHANCED XML PROCESSING ***
  responseText = .responseText
  
  ' Debug information
  WScript.Echo "Response size: " & Len(responseText) & " characters"
  
  ' Save raw response for debugging
  Dim fso, debugFile
  Set fso = CreateObject("Scripting.FileSystemObject")
  Set debugFile = fso.CreateTextFile(list & "_raw_response.txt", True)
  debugFile.Write responseText
  debugFile.Close
  WScript.Echo "Raw response saved to: " & list & "_raw_response.txt"
  
  ' Check for empty response
  If Len(responseText) = 0 Then
      WScript.Echo "ERROR: Empty response received"
      WScript.Quit 1
  End If
  
  ' Check for SOAP faults
  If InStr(responseText, "soap:Fault") > 0 Or InStr(responseText, "soap12:Fault") > 0 Then
      WScript.Echo "ERROR: SOAP Fault in response"
      WScript.Echo responseText
      WScript.Quit 1
  End If
  
  ' Clean response of invalid XML characters
  responseText = CleanXMLString(responseText)
  
  ' Attempt to load XML
  xmlDoc.loadXML(responseText)
  
  If Err.Number <> 0 Then
      WScript.Echo "ERROR loading XML: " & Err.Description
      WScript.Echo "Error Number: " & Err.Number
      Set debugFile = fso.CreateTextFile(list & "_cleaned_response.txt", True)
      debugFile.Write responseText
      debugFile.Close
      WScript.Echo "Cleaned response saved for analysis"
      WScript.Quit 1
  End If
  
  ' Check XML parse errors
  If xmlDoc.parseError.errorCode <> 0 Then
      WScript.Echo "XML Parse Error Details:"
      WScript.Echo "  Error Code: " & xmlDoc.parseError.errorCode
      WScript.Echo "  Reason: " & xmlDoc.parseError.reason
      WScript.Echo "  Line: " & xmlDoc.parseError.line
      WScript.Echo "  Position: " & xmlDoc.parseError.linepos
      WScript.Echo "  Source: " & xmlDoc.parseError.srcText
      
      ' Extract problematic section
      Dim lines, problemLine
      lines = Split(responseText, vbCrLf)
      If xmlDoc.parseError.line <= UBound(lines) Then
          problemLine = lines(xmlDoc.parseError.line - 1)
          WScript.Echo "  Problem line: " & problemLine
      End If
      
      WScript.Quit 1
  End If
  
  WScript.Echo "✓ XML loaded successfully"
  
  ' Count items
  Dim itemNodes
  Set itemNodes = xmlDoc.selectNodes("//z:row")
  WScript.Echo "Items found: " & itemNodes.length
  
  ' Try to save XML file
  On Error Resume Next
  xmlDoc.save(list & ".xml")
  
  If Err.Number <> 0 Then
      WScript.Echo "ERROR saving XML file: " & Err.Description
      
      ' Try alternative save method
      Err.Clear
      Set debugFile = fso.CreateTextFile(list & ".xml", True)
      debugFile.Write xmlDoc.xml
      debugFile.Close
      
      If Err.Number <> 0 Then
          WScript.Echo "Alternative save method also failed: " & Err.Description
          WScript.Quit 1
      Else
          WScript.Echo "✓ XML saved using alternative method"
      End If
  Else
      WScript.Echo "✓ XML saved successfully"
  End If
  
end with

On Error GoTo 0

WScript.Echo "saved to     : " & list & ".xml"

' Function to clean invalid XML characters
Function CleanXMLString(inputString)
    Dim i, char, result, charCode
    result = ""
    
    For i = 1 To Len(inputString)
        char = Mid(inputString, i, 1)
        charCode = Asc(char)
        
        ' Keep valid XML 1.0 characters:
        ' #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]
        If (charCode = 9) Or (charCode = 10) Or (charCode = 13) Or _
           (charCode >= 32 And charCode <= 55295) Or _
           (charCode >= 57344 And charCode <= 65533) Then
            result = result & char
        Else
            ' Replace invalid characters with space
            result = result & " "
        End If
    Next
    
    CleanXMLString = result
End Function

Function Base64Encode(inData)
  Const Base64 = _
"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
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