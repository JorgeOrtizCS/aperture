param([string]$Server = 'localhost', [string]$Database = 'ApertureDB')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Data
$apiPath = Join-Path $PSScriptRoot '..\..\Aperture WebAPI\Aperture WebAPI\bin\Aperture WebAPI.dll'
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $apiPath))
$policyType = $assembly.GetType('Aperture_WebAPI.Models.CameraRestrictions')
$controllerType = $assembly.GetType('Aperture_WebAPI.Controllers.ContentController')
$evaluate = $controllerType.GetMethod('Evaluate', [Reflection.BindingFlags]'Static,NonPublic')
$policy = [Activator]::CreateInstance($policyType)
if (!$policy.SupportsClient(0)) { throw 'Legacy unrestricted content must allow older clients' }
$policy.Enabled = $true
if ($policy.SupportsClient(0)) { throw 'Camera-restricted content must deny older clients' }
if (!$policy.SupportsClient(1)) { throw 'Updated clients must support camera policies' }
$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$builder['Data Source'] = $Server
$builder['Initial Catalog'] = $Database
$builder['Integrated Security'] = $true
$builder['Connect Timeout'] = 3
$db = New-Object System.Data.SqlClient.SqlConnection($builder.ConnectionString)
$db.Open()
$tx = $db.BeginTransaction()
function Command([string]$sql) {
    $command = $db.CreateCommand()
    $command.Transaction = $tx
    $command.CommandText = $sql
    return $command
}
function Execute([string]$sql) {
    $command = Command $sql
    try { $command.ExecuteNonQuery() | Out-Null } finally { $command.Dispose() }
}
function Evaluate([int]$version) {
    return $evaluate.Invoke($null, [object[]]@($db.PSObject.BaseObject, $tx.PSObject.BaseObject,
        [int]$contentId, [int]$recipientId, [Guid]::NewGuid(), 'loopback', $false, $version))
}
function Assert-Denied($result, [string]$message) {
    if ($result.AccessGranted -or $result.Message -notlike $message) { throw "Unexpected policy result: $($result.Message)" }
    if ($result.Body -or $result.FileDataBase64) { throw 'Denied response leaked content' }
}
try {
    $command = Command 'SELECT TOP (1) p.ContentID,r.RecipientID FROM AccessPolicy p JOIN ContentRecipient r ON r.ContentID=p.ContentID ORDER BY p.ContentID'
    $reader = $command.ExecuteReader()
    try {
        if (!$reader.Read()) { throw 'Test needs at least one shared content item; all test changes are rolled back.' }
        $contentId = $reader.GetInt32(0)
        $recipientId = $reader.GetInt32(1)
    } finally { $reader.Dispose(); $command.Dispose() }
    # This transaction temporarily changes a fixture, then rolls back every update.
    Execute "UPDATE AccessPolicy SET PolicyStatus='Active',StartTime=NULL,ExpirationDate=NULL,TrustedDevice=0,MaximumViews=0,RequiredLocation=NULL,ScreenshotRestriction=0,CameraDetectionEnabled=1,BlockPhones=1,BlockMultiplePeople=1,RequireViewer=1 WHERE ContentID=$contentId; UPDATE ContentRecipient SET AccessStatus='Active' WHERE RecipientID=$recipientId;"
    $result = Evaluate 0
    Assert-Denied $result '*requires camera protection*'
    if (!$result.CameraRestrictions.Enabled -or !$result.CameraRestrictions.BlockPhones -or
        !$result.CameraRestrictions.BlockMultiplePeople -or !$result.CameraRestrictions.RequireViewer) { throw 'Stored sender rules were not returned by API evaluation' }
    Execute "UPDATE AccessPolicy SET BlockPhones=0,BlockMultiplePeople=1,RequireViewer=0 WHERE ContentID=$contentId"
    $result = Evaluate 0
    if ($result.CameraRestrictions.BlockPhones -or !$result.CameraRestrictions.BlockMultiplePeople -or $result.CameraRestrictions.RequireViewer) { throw 'Independent policy flags did not round-trip through SQL/API' }
    Execute "UPDATE AccessPolicy SET StartTime=DATEADD(hour,1,GETUTCDATE()) WHERE ContentID=$contentId"
    Assert-Denied (Evaluate 1) '*not begun*'
    Execute "UPDATE AccessPolicy SET StartTime=NULL,ExpirationDate=DATEADD(hour,-1,GETUTCDATE()) WHERE ContentID=$contentId"
    Assert-Denied (Evaluate 1) '*expired*'
    Execute "UPDATE AccessPolicy SET ExpirationDate=NULL,TrustedDevice=1 WHERE ContentID=$contentId"
    Assert-Denied (Evaluate 1) '*Approved device required*'
    Execute "UPDATE AccessPolicy SET TrustedDevice=0,PolicyStatus='Paused' WHERE ContentID=$contentId"
    Assert-Denied (Evaluate 1) '*revoked*'
    'All SQL/API camera policy checks passed; fixture changes rolled back.'
} finally {
    $tx.Rollback()
    $tx.Dispose()
    $db.Dispose()
}
