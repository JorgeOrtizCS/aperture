using System;
using System.Diagnostics;
using System.IO;
using Newtonsoft.Json;

namespace Aperture_Desktop_Client.Services
{
    /// <summary>
    /// One line of output from camera/src/detector_service.py. These five fields are
    /// the detection contract every app reads.
    /// </summary>
    public class CameraDetectionResult
    {
        [JsonProperty("phone_detected")] public bool PhoneDetected { get; set; }
        [JsonProperty("phone_confidence")] public double PhoneConfidence { get; set; }
        [JsonProperty("person_count")] public int PersonCount { get; set; }
        [JsonProperty("latency_ms")] public double LatencyMs { get; set; }
        [JsonProperty("timestamp")] public string Timestamp { get; set; }
    }

    /// <summary>
    /// Starts the Python camera detector in the background and raises an event for every
    /// frame result. The detector prints one JSON line per frame, this class just reads them.
    ///
    /// Events fire on a background thread, so UI code has to marshal back with
    /// BeginInvoke before touching controls.
    ///
    /// Where it looks for things:
    ///   APERTURE_PYTHON   python executable (default "python", must have mediapipe + opencv installed)
    ///   APERTURE_DETECTOR full path to detector_service.py (default: searches up from the exe
    ///                     for camera\src\detector_service.py, which finds it inside the repo)
    /// </summary>
    public sealed class CameraDetectionService : IDisposable
    {
        Process process;
        bool stopping;

        public event Action<CameraDetectionResult> ResultReceived;
        public event Action<string> Failed;

        public bool IsRunning => process != null && !process.HasExited;

        public void Start()
        {
            if (IsRunning) return;
            stopping = false;

            var script = FindDetectorScript();
            if (script == null)
            {
                Failed?.Invoke("detector_service.py not found (set APERTURE_DETECTOR)");
                return;
            }

            var python = Environment.GetEnvironmentVariable("APERTURE_PYTHON");
            if (string.IsNullOrWhiteSpace(python)) python = "python";

            var info = new ProcessStartInfo
            {
                FileName = python,
                // -u = unbuffered, so results arrive every frame instead of in chunks
                Arguments = "-u \"" + script + "\"",
                WorkingDirectory = Path.GetDirectoryName(script),
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };

            try
            {
                process = new Process { StartInfo = info, EnableRaisingEvents = true };
                process.OutputDataReceived += (s, e) => HandleLine(e.Data);
                process.ErrorDataReceived += (s, e) => { if (!string.IsNullOrEmpty(e.Data)) Debug.WriteLine("[detector] " + e.Data); };
                process.Exited += (s, e) => { if (!stopping) Failed?.Invoke("Camera detector stopped"); };
                process.Start();
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
            }
            catch (Exception ex)
            {
                process = null;
                Failed?.Invoke("Could not start camera detector: " + ex.Message);
            }
        }

        void HandleLine(string line)
        {
            if (string.IsNullOrWhiteSpace(line) || !line.TrimStart().StartsWith("{")) return;
            try
            {
                var result = JsonConvert.DeserializeObject<CameraDetectionResult>(line);
                if (result != null) ResultReceived?.Invoke(result);
            }
            catch (JsonException)
            {
                // A malformed line just gets skipped, the next frame is a few ms away.
            }
        }

        static string FindDetectorScript()
        {
            var fromEnv = Environment.GetEnvironmentVariable("APERTURE_DETECTOR");
            if (!string.IsNullOrWhiteSpace(fromEnv) && File.Exists(fromEnv)) return fromEnv;

            // bin\Debug\ is a few folders below the repo root, so walk up until we hit it.
            var dir = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
            while (dir != null)
            {
                var candidate = Path.Combine(dir.FullName, "camera", "src", "detector_service.py");
                if (File.Exists(candidate)) return candidate;
                dir = dir.Parent;
            }
            return null;
        }

        public void Stop()
        {
            stopping = true;
            try
            {
                if (IsRunning) process.Kill();
            }
            catch (InvalidOperationException) { /* already exited */ }
            finally
            {
                process?.Dispose();
                process = null;
            }
        }

        public void Dispose() => Stop();
    }
}
