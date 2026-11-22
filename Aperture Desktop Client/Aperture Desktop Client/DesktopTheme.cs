using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace Aperture_Desktop_Client
{
    internal static class DesktopTheme
    {
        internal static readonly Color Background = Color.FromArgb(173, 191, 208);
        internal static readonly Color Surface = Color.FromArgb(206, 218, 229);
        internal static readonly Color Input = Color.FromArgb(223, 232, 239);
        internal static readonly Color Primary = Color.FromArgb(31, 78, 121);
        internal static readonly Color PrimarySoft = Color.FromArgb(156, 180, 201);
        internal static readonly Color Text = Color.FromArgb(24, 37, 52);
        internal static readonly Color Secondary = Color.FromArgb(54, 71, 89);
        internal static readonly Color Success = Color.FromArgb(0, 96, 70);
        internal static readonly Color Danger = Color.FromArgb(130, 18, 27);

        internal static void Apply(Form form)
        {
            form.Font = new Font("Segoe UI", 10);
            form.ForeColor = Text;
            form.BackColor = Background;
        }

        internal static void StyleButton(Button button, bool primary = true, bool danger = false)
        {
            button.UseVisualStyleBackColor = false;
            button.FlatStyle = FlatStyle.Flat;
            button.BackColor = primary ? Primary : Surface;
            button.ForeColor = primary ? Input : danger ? Danger : Primary;
            button.FlatAppearance.BorderSize = 0;
            button.FlatAppearance.MouseOverBackColor = primary ? Color.FromArgb(25, 64, 100) : Input;
            button.FlatAppearance.MouseDownBackColor = primary ? Color.FromArgb(20, 52, 83) : PrimarySoft;
            button.Cursor = Cursors.Hand;
            RoundCorners(button, 9);
        }

        internal static void StyleInput(TextBox input)
        {
            input.BorderStyle = BorderStyle.FixedSingle;
            input.BackColor = Input;
            input.ForeColor = Text;
            RoundCorners(input, 4);
        }

        internal static void RoundCorners(Control control, int radius = 14)
        {
            void UpdateRegion(object sender, EventArgs args)
            {
                int width = control.Width;
                int height = control.Height;
                int diameter = Math.Min(Math.Min(width, height), radius * 2 * control.DeviceDpi / 96);
                if (diameter < 2)
                {
                    control.Region = null;
                    return;
                }

                using (var outline = new GraphicsPath())
                {
                    outline.AddArc(0, 0, diameter, diameter, 180, 90);
                    outline.AddArc(width - diameter, 0, diameter, diameter, 270, 90);
                    outline.AddArc(width - diameter, height - diameter, diameter, diameter, 0, 90);
                    outline.AddArc(0, height - diameter, diameter, diameter, 90, 90);
                    outline.CloseFigure();
                    control.Region = new Region(outline);
                }
            }

            control.SizeChanged += UpdateRegion;
            control.DpiChangedAfterParent += UpdateRegion;
            UpdateRegion(control, EventArgs.Empty);
        }
    }
}

