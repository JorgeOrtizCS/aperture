param([string]$Configuration = 'Debug')
$ErrorActionPreference = 'Stop'
$binary = Join-Path $PSScriptRoot "..\Aperture Desktop Client\bin\$Configuration\Aperture Desktop Client.exe"
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path $binary))
$type = $assembly.GetType('Aperture_Desktop_Client.Services.CameraDetectionService')
$resolve = $type.GetMethod('FindPythonExecutable', [Reflection.BindingFlags]'Static,NonPublic')
$originalPython = $env:APERTURE_PYTHON
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('aperture-camera-test-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path (Join-Path $fixture 'camera with spaces\src') -Force | Out-Null
    $script = Join-Path $fixture 'camera with spaces\src\detector_service.py'
    $env:APERTURE_PYTHON = $null
    if ($resolve.Invoke($null, [object[]]@([string]$script)) -ne 'python') { throw 'PATH fallback failed.' }
    $localPython = Join-Path $fixture 'camera with spaces\venv\Scripts\python.exe'
    New-Item -ItemType Directory -Path (Split-Path $localPython) -Force | Out-Null
    New-Item -ItemType File -Path $localPython | Out-Null
    if ($resolve.Invoke($null, [object[]]@([string]$script)) -ne $localPython) { throw 'Camera environment was not selected.' }
    $env:APERTURE_PYTHON = 'C:\custom python\python.exe'
    if ($resolve.Invoke($null, [object[]]@([string]$script)) -ne $env:APERTURE_PYTHON) { throw 'Explicit Python override was ignored.' }
    Write-Output 'Camera interpreter selection checks passed.'
} finally {
    $env:APERTURE_PYTHON = $originalPython
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedFixture.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path $resolvedFixture -Leaf) -like 'aperture-camera-test-*') {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}
