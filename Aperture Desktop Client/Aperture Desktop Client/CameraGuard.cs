using System;
using System.Drawing;
using System.Windows.Forms;
using Aperture_Desktop_Client.Services;

namespace Aperture_Desktop_Client
{
    public sealed class CameraGuard
    {
        const int ClearFrames = 10;
        readonly Form viewer;
        readonly Label status;
        readonly Color normalColor;
        readonly Label cover;
        readonly CameraDetectionService camera = new CameraDetectionService();
        readonly Timer watchdog = new Timer { Interval = 500 };
        DateTime lastFrame = DateTime.UtcNow;
        int clearStreak;
        string cameraReason = "Starting camera detection...";
        string policyReason;
        Control protectedContent;
        CameraRestrictions restrictions = new CameraRestrictions();
        public bool Blocked => cameraReason != null || policyReason != null;

        CameraGuard(Form viewer, Label status, Color normalColor)
        {
            this.viewer = viewer;
            this.status = status;
            this.normalColor = normalColor;
            cover = new Label {
                Dock = DockStyle.Fill, TextAlign = ContentAlignment.MiddleCenter,
                Font = new Font("Segoe UI", 14, FontStyle.Bold), ForeColor = Color.White,
                BackColor = Color.FromArgb(20, 20, 20)
            };
            viewer.Controls.Add(cover);
            camera.ResultReceived += result => OnUi(() => Handle(result));
            camera.Failed += message => OnUi(() => {
                if (!restrictions.Enabled) return;
                clearStreak = 0;
                cameraReason = "Camera detection unavailable: " + message;
                Render();
            });
            watchdog.Tick += (s, e) => {
                if (restrictions.Enabled && (DateTime.UtcNow - lastFrame).TotalSeconds > 5) {
                    clearStreak = 0;
                    cameraReason = "Camera detection unavailable: no recent frames";
                    Render();
                }
            };
            viewer.FormClosed += (s, e) => { watchdog.Dispose(); camera.Dispose(); };
            Render();
        }

        public static CameraGuard Attach(Form viewer, Label status, Color normalColor, CameraRestrictions restrictions = null)
        {
            var guard = new CameraGuard(viewer, status, normalColor);
            guard.restrictions = restrictions ?? new CameraRestrictions();
            if (guard.restrictions.Enabled) {
                guard.watchdog.Start();
                guard.camera.Start();
            } else {
                guard.cameraReason = null;
            }
            guard.Render();
            return guard;
        }

        public void SetPolicyStatus(bool granted, string message)
        {
            policyReason = granted ? null : (string.IsNullOrWhiteSpace(message) ? "Viewing restrictions are not satisfied." : message);
            Render();
        }

        // Only call with the authoritative policy from a session response.
        public void ApplyRestrictions(CameraRestrictions policy)
        {
            if (policy == null) throw new ArgumentNullException(nameof(policy));
            if (restrictions.SameAs(policy)) return;
            policyReason = "Verifying viewing restrictions...";
            camera.Stop();
            watchdog.Stop();
            restrictions = policy;
            clearStreak = 0;
            lastFrame = DateTime.UtcNow;
            cameraReason = policy.Enabled ? "Starting camera detection..." : null;
            Render();
            if (policy.Enabled) {
                watchdog.Start();
                camera.Start();
            }
        }

        public void KeepOnTop() { Render(); }

        public void Protect(Control content)
        {
            protectedContent = content;
            Render();
        }

        void Render()
        {
            if (protectedContent != null) {
                protectedContent.Visible = !Blocked;
                protectedContent.Enabled = !Blocked;
            }
            cover.Visible = Blocked;
            if (Blocked) {
                cover.Text = "Content hidden" + Environment.NewLine + (policyReason ?? cameraReason);
                cover.BringToFront();
            }
            status.Text = Blocked ? "Content hidden: " + (policyReason ?? cameraReason) :
                (restrictions.Enabled ? "Access granted - camera clear" : "Access granted - camera detection off");
            status.ForeColor = Blocked ? Color.Firebrick : normalColor;
        }

        void Handle(CameraDetectionResult result)
        {
            if (!restrictions.Enabled) return;
            lastFrame = DateTime.UtcNow;
            string reason = null;
            if (restrictions.BlockPhones && result.PhoneDetected)
                reason = "Phone detected. Remove it to resume viewing.";
            else if (restrictions.BlockMultiplePeople && result.PersonCount > 1)
                reason = "Multiple people detected. View this content alone.";
            else if (restrictions.RequireViewer && result.PersonCount == 0)
                reason = "No viewer detected. Return to the camera to resume viewing.";
            if (reason != null) {
                clearStreak = 0;
                cameraReason = reason;
            }
            else if (++clearStreak >= ClearFrames) {
                clearStreak = ClearFrames;
                cameraReason = null;
            }
            Render();
        }

        void OnUi(Action action)
        {
            if (viewer.IsDisposed || !viewer.IsHandleCreated) return;
            try { viewer.BeginInvoke(new Action(() => { if (!viewer.IsDisposed) action(); })); }
            catch (InvalidOperationException) { }
        }
    }

    public sealed class CameraTestForm : Form
    {
        public CameraTestForm()
        {
            Text = "Aperture - Camera detection test";
            Size = new Size(690, 570);
            StartPosition = FormStartPosition.CenterScreen;
            var status = new Label { Dock = DockStyle.Bottom, Height = 48 };
            Controls.Add(new TextBox {
                Multiline = true, ReadOnly = true, Dock = DockStyle.Fill,
                Text = "Sample protected content. A phone or multiple people should hide this text. It returns after ten clear frames."
            });
            Controls.Add(status);
            Shown += (s, e) => CameraGuard.Attach(this, status, Color.FromArgb(42, 53, 69));
        }
    }
}
