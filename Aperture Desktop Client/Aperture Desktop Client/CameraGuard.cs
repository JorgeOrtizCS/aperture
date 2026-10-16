using System;
using System.Drawing;
using System.Windows.Forms;
using Aperture_Desktop_Client.Services;

namespace Aperture_Desktop_Client
{
    /// <summary>
    /// Puts camera detection on any content viewer window (Jorge, Week 6 Task 6.1).
    ///
    /// While the viewer is open it runs the camera detector. When a phone shows up, a cover
    /// goes over the content right away and the status label turns red. The content only
    /// comes back after CLEAR_FRAMES frames in a row with no phone, so one clean frame
    /// can't flash it back. The detector stops when the viewer closes.
    ///
    /// Usage, inside a viewer form:
    ///     var guard = CameraGuard.Attach(viewer, statusLabel, normalTextColor);
    ///     ...
    ///     if (guard.Blocked) guard.KeepOnTop();   // after anything redraws the content
    /// </summary>
    public sealed class CameraGuard
    {
        const int CLEAR_FRAMES = 10;

        readonly Form viewer;
        readonly Label status;
        readonly Color normalColor;
        readonly Label cover;
        readonly CameraDetectionService camera = new CameraDetectionService();
        int clearStreak;

        public bool Blocked { get; private set; }

        CameraGuard(Form viewer, Label status, Color normalColor)
        {
            this.viewer = viewer;
            this.status = status;
            this.normalColor = normalColor;

            cover = new Label
            {
                Dock = DockStyle.Fill,
                Text = "Phone camera detected\nContent hidden until it's gone",
                TextAlign = ContentAlignment.MiddleCenter,
                Font = new Font("Segoe UI", 14, FontStyle.Bold),
                ForeColor = Color.White,
                BackColor = Color.FromArgb(20, 20, 20),
                Visible = false
            };
            viewer.Controls.Add(cover);

            camera.ResultReceived += r => OnUi(() => Handle(r));
            camera.Failed += msg => OnUi(() =>
            {
                status.Text = "Camera detection unavailable: " + msg;
                status.ForeColor = Color.DarkOrange;
            });
            viewer.FormClosed += (s, e) => camera.Dispose();
        }

        public static CameraGuard Attach(Form viewer, Label status, Color normalColor)
        {
            var guard = new CameraGuard(viewer, status, normalColor);
            guard.camera.Start();
            return guard;
        }

        /// <summary>Call after the viewer redraws its content so the cover stays on top.</summary>
        public void KeepOnTop()
        {
            if (Blocked) cover.BringToFront();
        }

        void Handle(CameraDetectionResult r)
        {
            if (r.PhoneDetected)
            {
                clearStreak = 0;
                if (!Blocked)
                {
                    Blocked = true;
                    cover.Visible = true;
                    cover.BringToFront();
                }
                status.Text = "Phone camera detected · content hidden (confidence "
                              + r.PhoneConfidence.ToString("0.00") + ", " + r.LatencyMs.ToString("0") + " ms)";
                status.ForeColor = Color.Firebrick;
            }
            else if (Blocked && ++clearStreak >= CLEAR_FRAMES)
            {
                Blocked = false;
                cover.Visible = false;
                status.Text = "Camera clear · content visible";
                status.ForeColor = normalColor;
            }
        }

        // Detector results arrive on a background thread, WinForms controls have to be
        // touched on the UI thread.
        void OnUi(Action action)
        {
            if (viewer.IsDisposed || !viewer.IsHandleCreated) return;
            try { viewer.BeginInvoke(action); }
            catch (InvalidOperationException) { /* viewer closing */ }
        }
    }

    /// <summary>
    /// Stand-alone test window for the camera guard. Run the client with --camera-test
    /// to open it without logging in or running the Web API.
    /// </summary>
    public sealed class CameraTestForm : Form
    {
        public CameraTestForm()
        {
            Text = "Aperture · Camera detection test";
            Size = new Size(690, 570);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.White;

            var ink = Color.FromArgb(42, 53, 69);
            var heading = new Label
            {
                Text = "Sample protected content", Dock = DockStyle.Top, Height = 60,
                Font = new Font("Segoe UI", 18, FontStyle.Bold), ForeColor = ink, Padding = new Padding(20, 12, 0, 0)
            };
            var status = new Label
            {
                Text = "Starting camera detection...", Dock = DockStyle.Bottom, Height = 48,
                Font = new Font("Segoe UI", 10), ForeColor = ink, Padding = new Padding(20, 10, 0, 0)
            };
            var text = new TextBox
            {
                Multiline = true, ReadOnly = true, Dock = DockStyle.Fill, BorderStyle = BorderStyle.None,
                Font = new Font("Segoe UI", 11),
                Text = "This is sample content used to test Aperture's camera detection." + Environment.NewLine +
                       Environment.NewLine +
                       "Point a phone at your webcam. This text should be covered right away, " +
                       "and come back a moment after the phone is gone."
            };

            Controls.Add(text);
            Controls.Add(status);
            Controls.Add(heading);
            Shown += (s, e) => CameraGuard.Attach(this, status, ink);
        }
    }
}
