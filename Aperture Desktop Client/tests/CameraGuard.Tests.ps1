param([string]$Configuration = 'Debug')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$binary = Join-Path $PSScriptRoot "..\Aperture Desktop Client\bin\$Configuration\Aperture Desktop Client.exe"
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $binary))
$type = $assembly.GetType('Aperture_Desktop_Client.CameraGuard')
$resultType = $assembly.GetType('Aperture_Desktop_Client.Services.CameraDetectionResult')
$private = [Reflection.BindingFlags]'Instance,NonPublic'
$form = New-Object Windows.Forms.Form
$status = New-Object Windows.Forms.Label
$guard = $type.GetConstructors($private)[0].Invoke([object[]]@($form.PSObject.BaseObject, $status.PSObject.BaseObject, [Drawing.Color]::Black))
$handle = $type.GetMethod('Handle', $private)
function Assert-Blocked([bool]$expected, [string]$scenario) {
    if ($guard.Blocked -ne $expected) { throw "Failed: $scenario" }
}
function Send-Frame([bool]$phone = $false, [int]$people = 1) {
    $frame = [Activator]::CreateInstance($resultType)
    $frame.PhoneDetected = $phone
    $frame.PersonCount = $people
    $handle.Invoke($guard, @($frame.PSObject.BaseObject)) | Out-Null
}
try {
    Assert-Blocked $true 'startup stays hidden'
    1..9 | ForEach-Object { Send-Frame }
    Assert-Blocked $true 'nine clear frames stay hidden'
    Send-Frame
    Assert-Blocked $false 'ten clear frames reveal content'
    Send-Frame $true
    Assert-Blocked $true 'phone immediately hides content'
    $guard.SetPolicyStatus($false, 'Access has expired.')
    1..10 | ForEach-Object { Send-Frame }
    Assert-Blocked $true 'camera recovery preserves server denial'
    if ($status.Text -notlike '*expired*') { throw 'Server denial reason lost' }
    $guard.SetPolicyStatus($true, $null)
    Assert-Blocked $false 'both checks clear'
    Send-Frame $false 2
    Assert-Blocked $true 'multiple people hide content'
    $guard.SetPolicyStatus($true, $null)
    Assert-Blocked $true 'server success preserves camera block'
    1..9 | ForEach-Object { Send-Frame }
    Send-Frame $true
    1..9 | ForEach-Object { Send-Frame }
    Assert-Blocked $true 'unsafe frame resets clear streak'
    Send-Frame
    Assert-Blocked $false 'recovery after consecutive clear frames'
    $type.GetField('lastFrame', $private).SetValue($guard, [DateTime]::UtcNow.AddSeconds(-10))
    $watchdog = $type.GetField('watchdog', $private).GetValue($guard)
    $watchdog.GetType().GetMethod('OnTick', $private).Invoke($watchdog, @([EventArgs]::Empty)) | Out-Null
    Assert-Blocked $true 'stale camera hides content'
    $options = $type.GetField('restrictions', $private).GetValue($guard)
    $options.BlockPhones = $false
    1..10 | ForEach-Object { Send-Frame $true }
    Assert-Blocked $false 'phone rule can be disabled independently'
    $options.BlockMultiplePeople = $false
    1..10 | ForEach-Object { Send-Frame $false 2 }
    Assert-Blocked $false 'multiple-person rule can be disabled independently'
    Send-Frame $false 0
    Assert-Blocked $false 'viewer presence is optional by default'
    $options.RequireViewer = $true
    Send-Frame $false 0
    Assert-Blocked $true 'missing viewer hides content when required'
    1..10 | ForEach-Object { Send-Frame }
    Assert-Blocked $false 'viewer return releases presence block'
    $repeatPolicy = [Activator]::CreateInstance($options.GetType())
    $repeatPolicy.Enabled = $options.Enabled
    $repeatPolicy.BlockPhones = $options.BlockPhones
    $repeatPolicy.BlockMultiplePeople = $options.BlockMultiplePeople
    $repeatPolicy.RequireViewer = $options.RequireViewer
    $guard.ApplyRestrictions($repeatPolicy)
    Assert-Blocked $false 'repeated server policy does not restart clear-frame recovery'
    $disabledOptions = [Activator]::CreateInstance($options.GetType())
    $disabledOptions.Enabled = $false
    $disabledForm = New-Object Windows.Forms.Form
    $disabledStatus = New-Object Windows.Forms.Label
    $disabledGuard = $type.GetMethod('Attach').Invoke($null, [object[]]@(
        $disabledForm.PSObject.BaseObject, $disabledStatus.PSObject.BaseObject,
        [Drawing.Color]::Black, $disabledOptions.PSObject.BaseObject))
    try {
        if ($disabledGuard.Blocked) { throw 'Disabled camera must not block content' }
        if ($type.GetField('camera', $private).GetValue($disabledGuard).IsRunning) { throw 'Disabled camera launched detector' }
        $disabledGuard.SetPolicyStatus($false, 'Access has expired.')
        $handle.Invoke($disabledGuard, @([Activator]::CreateInstance($resultType))) | Out-Null
        if (!$disabledGuard.Blocked) { throw 'Disabled camera bypassed server denial' }
        $disabledGuard.SetPolicyStatus($true, $null)
        if ($disabledGuard.Blocked) { throw 'Disabled camera prevented server recovery' }
    } finally {
        $type.GetField('watchdog', $private).GetValue($disabledGuard).Dispose()
        $type.GetField('camera', $private).GetValue($disabledGuard).Dispose()
        $disabledForm.Dispose()
    }
    'All camera/policy guard regression checks passed.'
} finally {
    $type.GetField('watchdog', $private).GetValue($guard).Dispose()
    $type.GetField('camera', $private).GetValue($guard).Dispose()
    $form.Dispose()
}



