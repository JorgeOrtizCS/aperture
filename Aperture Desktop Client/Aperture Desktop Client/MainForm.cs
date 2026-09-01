using System;
using System.Drawing;
using System.Windows.Forms;
using Aperture_Desktop_Client.Services;

namespace Aperture_Desktop.Forms
{
    public partial class MainForm : Form
    {
        private readonly AuthenticationService _authenticationService;
        private readonly StateService _stateService;

        public MainForm(
            AuthenticationService authenticationService)
        {
            InitializeComponent();

            _authenticationService =
                authenticationService;

            _stateService =
                new StateService(
                    _authenticationService.ApiClient);

            ConfigureForm();
        }

        private void ConfigureForm()
        {
            Text = "Aperture";

            StartPosition =
                FormStartPosition.CenterScreen;

            lblUsername.Text =
                "Welcome, " +
                _authenticationService.CurrentUser.Username;

            lblResult.Text =
                "Ready.";

            lblResult.ForeColor =
                Color.Black;

            txtContentObjectId.Focus();
        }

        private async void btnCheckAccess_Click(
            object sender,
            EventArgs e)
        {
            if (!int.TryParse(
                txtContentObjectId.Text.Trim(),
                out int contentObjectId))
            {
                lblResult.Text =
                    "Please enter a valid Content Object ID.";

                lblResult.ForeColor =
                    Color.Firebrick;

                return;
            }

            btnCheckAccess.Enabled = false;

            lblResult.Text =
                "Checking access...";

            lblResult.ForeColor =
                Color.DarkBlue;

            try
            {
                var response =
                    await _stateService.CheckState(
                        contentObjectId);

                if (response == null)
                {
                    lblResult.Text =
                        "No response received from the API.";

                    lblResult.ForeColor =
                        Color.Firebrick;

                    return;
                }

                if (response.AccessGranted)
                {
                    lblResult.Text =
                        "ACCESS GRANTED";

                    lblResult.ForeColor =
                        Color.Green;
                }
                else
                {
                    lblResult.Text =
                        "ACCESS DENIED";

                    lblResult.ForeColor =
                        Color.Firebrick;
                }
            }
            catch (Exception ex)
            {
                lblResult.Text =
                    "API Error";

                lblResult.ForeColor =
                    Color.Firebrick;

                MessageBox.Show(
                    ex.Message,
                    "API Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);
            }
            finally
            {
                btnCheckAccess.Enabled = true;
            }
        }

        private async void btnLogout_Click(
            object sender,
            EventArgs e)
        {
            btnLogout.Enabled = false;

            try
            {
                await _authenticationService.Logout();

                Close();
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    ex.Message,
                    "Logout Error",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error);

                btnLogout.Enabled = true;
            }
        }

        protected override void OnFormClosing(
            FormClosingEventArgs e)
        {
            base.OnFormClosing(e);
        }
    }
}