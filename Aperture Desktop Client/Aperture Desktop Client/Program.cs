using System;
using System.Windows.Forms;
using Aperture_Desktop_Client.Services;

namespace Aperture_Desktop_Client
{
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            Application.EnableVisualStyles();

            Application.SetCompatibleTextRenderingDefault(
                false);

            // Dev test mode for camera detection, no login or Web API needed:
            //   "Aperture Desktop Client.exe" --camera-test
            if (Array.IndexOf(args, "--camera-test") >= 0)
            {
                Application.Run(new CameraTestForm());
                return;
            }

            var apiClient =
                new ApiClient(
                    "https://localhost:44353/");

            var authenticationService =
                new AuthenticationService(
                    apiClient);

            Application.Run(
                new LoginForm(
                    authenticationService));
        }
    }
}
