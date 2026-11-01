$ErrorActionPreference = 'Stop'
$bin = Join-Path $PSScriptRoot '..\Aperture WebAPI\bin'
Add-Type -AssemblyName System.Web
Add-Type -Path (Join-Path $bin 'Newtonsoft.Json.dll')
Add-Type -Path (Join-Path $bin 'Aperture WebAPI.dll')
function Assert([bool]$Value, [string]$Scenario) { if (!$Value) { throw "Failed: $Scenario" } }
function New-Request {
 [System.Web.HttpContext]::Current = New-Object System.Web.HttpContext(
  (New-Object System.Web.HttpRequest('', 'http://localhost/', '')),
  (New-Object System.Web.HttpResponse((New-Object IO.StringWriter))))
}
$oldContext=[System.Web.HttpContext]::Current
try {
 $now=[DateTime]::UtcNow
 $errorMessage=$null
 $json=[Aperture_WebAPI.SituationalAwareness.LocationCheck]::BuildPolicyJson($null,$null,$null,26.37,-80.1,500,[ref]$errorMessage)
 Assert ($null -eq $errorMessage) 'valid precise policy'
 $inside=[Aperture_WebAPI.SituationalAwareness.LocationCheck]::Evaluate($json,'loopback',26.37,-80.1)
 Assert $inside.Passed 'inside radius'
 $outside=[Aperture_WebAPI.SituationalAwareness.LocationCheck]::Evaluate($json,'loopback',26.4,-80.1)
 Assert (!$outside.Passed -and $outside.Transient) 'outside radius suspends'
 $missing=[Aperture_WebAPI.SituationalAwareness.LocationCheck]::Evaluate($json,'loopback',$null,$null)
 Assert (!$missing.Passed -and $missing.Transient) 'missing GPS fails closed and can recover'
 $badFix=[Aperture_WebAPI.SituationalAwareness.LocationCheck]::Evaluate($json,'loopback',[double]::NaN,0)
 Assert (!$badFix.Passed) 'NaN GPS is rejected'
 [Aperture_WebAPI.SituationalAwareness.LocationCheck]::BuildPolicyJson($null,$null,$null,26.37,$null,500,[ref]$errorMessage) | Out-Null
 Assert ($null -ne $errorMessage) 'partial GPS policy is rejected'
 $invalid=[Aperture_WebAPI.SituationalAwareness.LocationCheck]::Evaluate('{"Latitude":91,"Longitude":0,"RadiusMeters":500}','loopback',0,0)
 Assert (!$invalid.Passed -and !$invalid.Transient) 'invalid stored coordinates terminate'
 $policy=[Aperture_WebAPI.Models.ViewingRequirements]::Parse('{"Version":1,"MaxViews":3,"Location":{"Latitude":26.37,"Longitude":-80.1,"RadiusMeters":500},"CameraRestrictions":{"Enabled":true,"BlockPhones":true}}')
 $roundTrip=[Aperture_WebAPI.Models.ViewingRequirements]::Parse([Newtonsoft.Json.JsonConvert]::SerializeObject($policy))
 Assert ($roundTrip.Location.RadiusMeters -eq 500 -and $roundTrip.CameraRestrictions.BlockPhones -and $roundTrip.MaxViews -eq 3) 'GPS and camera JSON round trip'
 $rejected=$false
 try {[Aperture_WebAPI.Models.ViewingRequirements]::Parse('{"Version":2}') | Out-Null} catch {$rejected=$true}
 Assert $rejected 'unknown requirements version fails closed'
 Assert ($null -ne [Aperture_WebAPI.SituationalAwareness.TimeWindowCheck]::ValidatePolicy($now,$now.AddSeconds(-1),$now)) 'invalid time window'
 New-Request
 $reason=[Aperture_WebAPI.SituationalAwareness.TimeWindowCheck]::ExpiredReason($now.AddSeconds(-20),$now,$true)
 Assert ([Aperture_WebAPI.SituationalAwareness.SessionSuspension]::KeepAlive($reason)) 'expiry grace keeps existing session'
 New-Request
 $reason=[Aperture_WebAPI.SituationalAwareness.TimeWindowCheck]::ExpiredReason($now.AddSeconds(-301),$now,$true)
 Assert (![Aperture_WebAPI.SituationalAwareness.SessionSuspension]::KeepAlive($reason)) 'grace ends after five minutes'
 Assert (![Aperture_WebAPI.SituationalAwareness.SessionSuspension]::KeepAlive('Access has been revoked.')) 'revocation is terminal'
 Assert (![Aperture_WebAPI.SituationalAwareness.SessionSuspension]::KeepAlive('IP geolocation failed: unavailable')) 'provider failure is terminal'
 $session=2147483646
 [Aperture_WebAPI.SituationalAwareness.SessionSuspension]::Hold($session,'Brief pause',30,$now) | Out-Null
 $message=$null
 Assert ([Aperture_WebAPI.SituationalAwareness.SessionSuspension]::IsHeld($session,$now.AddSeconds(29),[ref]$message)) 'manual hold remains active'
 Assert (![Aperture_WebAPI.SituationalAwareness.SessionSuspension]::IsHeld($session,$now.AddSeconds(31),[ref]$message)) 'manual hold expires'
 [Aperture_WebAPI.SituationalAwareness.SessionSuspension]::RecordCheck($session,$false,'Outside area',$now.AddSeconds(31))
 Assert (([Aperture_WebAPI.SituationalAwareness.SessionSuspension]::GetStatus($session)).Source -eq 'check') 'expired hold reports new failing condition'
 [Aperture_WebAPI.SituationalAwareness.SessionSuspension]::RecordCheck($session,$true,$null,$now.AddSeconds(32))
 Assert (!([Aperture_WebAPI.SituationalAwareness.SessionSuspension]::GetStatus($session)).Suspended) 'passing check restores session'
 Assert ($null -ne [Aperture_WebAPI.SituationalAwareness.SessionSuspension]::ValidateHold('reason',3601)) 'hold duration capped'
 Write-Output 'Situational-awareness location, time, suspension and camera JSON checks passed.'
} finally {
 [Aperture_WebAPI.SituationalAwareness.SessionSuspension]::Clear(2147483646)
 [System.Web.HttpContext]::Current=$oldContext
}
