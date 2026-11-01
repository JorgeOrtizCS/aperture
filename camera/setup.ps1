param([string]$PythonExecutable = 'python', [string]$IndexUrl = 'https://pypi.org/simple')
$ErrorActionPreference = 'Stop'
$environmentRoot = Join-Path $PSScriptRoot 'venv'
$environmentPython = Join-Path $environmentRoot 'Scripts\python.exe'
if (!(Test-Path -LiteralPath $environmentPython)) {
    & $PythonExecutable -m venv $environmentRoot
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the camera Python environment.' }
}
& $environmentPython -m pip install --index-url $IndexUrl -r (Join-Path $PSScriptRoot 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'Camera dependency installation failed.' }
& $environmentPython -m pip check
if ($LASTEXITCODE -ne 0) { throw 'Camera dependencies are inconsistent.' }
# Validate the actual model and inference without turning on the webcam.
Push-Location (Join-Path $PSScriptRoot 'src')
try {
    & $environmentPython -c "import sys, cv2, mediapipe, numpy as np; from detector_service import CameraDetector; print('Python:', sys.executable); print('OpenCV:', cv2.__version__); print('MediaPipe:', mediapipe.__version__); print('Inference:', CameraDetector().check(np.zeros((480, 640, 3), dtype=np.uint8)))"
    if ($LASTEXITCODE -ne 0) { throw 'Camera imports or model inference failed.' }
} finally { Pop-Location }
Write-Output 'Camera environment ready. Rebuild/restart the desktop client; it selects camera/venv automatically.'
Write-Output "Optional webcam check: & '$environmentPython' '$(Join-Path $PSScriptRoot 'src\detector_service.py')' --check"
