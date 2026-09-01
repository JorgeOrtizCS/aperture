using System;
using System.Drawing;
using System.Windows.Forms;
using Aperture_Desktop.Forms;
using Aperture_Desktop_Client.Services;

namespace Aperture_Desktop_Client
{
    public partial class LoginForm : Form
    {
        private readonly AuthenticationService
            _authenticationService;

        public LoginForm(
            AuthenticationService authenticationService)
        {
            InitializeComponent();

            _authenticationService =
                authenticationService;

            ConfigureForm();
        }

        private void ConfigureForm()
        {
            Text = "Aperture - Login";

            StartPosition =
                FormStartPosition.CenterScreen;

            FormBorderStyle =
                FormBorderStyle.FixedDialog;

            MaximizeBox = false;

            MinimizeBox = false;

            AcceptButton = btnLogin;

            CancelButton = btnCancel;

            txtPassword.UseSystemPasswordChar = true;

            lblStatus.Text = string.Empty;

            txtUsername.Focus();
        }

        private async void btnLogin_Click(
            object sender,
            EventArgs e)
        {
            await PerformLogin();
        }

        private async System.Threading.Tasks.Task
            PerformLogin()
        {
            string username =
                txtUsername.Text.Trim();

            string password =
                txtPassword.Text;

            if (string.IsNullOrWhiteSpace(username))
            {
                ShowError(
                    "Please enter your username.");

                txtUsername.Focus();

                return;
            }

            if (string.IsNullOrWhiteSpace(password))
            {
                ShowError(
                    "Please enter your password.");

                txtPassword.Focus();

                return;
            }

            SetLoggingInState(true);

            try
            {
                var response =
                    await _authenticationService.Login(
                        username,
                        password);

                if (response == null)
                {
                    ShowError(
                        "The API returned no response.");

                    return;
                }

                if (!response.Success)
                {
                    ShowError(
                        response.Message ??
                        "Login failed.");

                    txtPassword.SelectAll();

                    txtPassword.Focus();

                    return;
                }

                ShowStatus(
                    "Login successful.",
                    Color.Green);

                OpenMainForm();
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    ex.ToString(),
                    "Login Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);

                ShowError(
                    "Login failed.");
            }
            finally
            {
                SetLoggingInState(false);
            }
        }

        private void OpenMainForm()
        {
            Hide();

            using (var mainForm =
                   new MainForm(
                       _authenticationService))
            {
                mainForm.ShowDialog();
            }

            Close();
        }

        private void SetLoggingInState(
            bool loggingIn)
        {
            txtUsername.Enabled =
                !loggingIn;

            txtPassword.Enabled =
                !loggingIn;

            btnLogin.Enabled =
                !loggingIn;

            btnCancel.Enabled =
                !loggingIn;

            if (loggingIn)
            {
                ShowStatus(
                    "Logging in...",
                    Color.DarkBlue);
            }
        }

        private void ShowStatus(
            string message,
            Color color)
        {
            lblStatus.Text =
                message;

            lblStatus.ForeColor =
                color;
        }

        private void ShowError(
            string message)
        {
            ShowStatus(
                message,
                Color.Firebrick);
        }

        private void btnCancel_Click(
            object sender,
            EventArgs e)
        {
            Close();
        }
    }
}
