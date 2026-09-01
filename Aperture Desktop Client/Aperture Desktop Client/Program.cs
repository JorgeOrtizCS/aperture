using System;
using System.Windows.Forms;
using Aperture_Desktop_Client.Services;

namespace Aperture_Desktop_Client
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            Application.EnableVisualStyles();

            Application.SetCompatibleTextRenderingDefault(
                false);

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
