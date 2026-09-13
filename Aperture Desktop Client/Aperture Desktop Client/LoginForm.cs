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

            BackColor = Color.FromArgb(248, 250, 253);
            ClientSize = new Size(420, 465);
            lblTitle.Text = "Aperture";
            lblTitle.ForeColor = Color.FromArgb(42, 53, 69);
            lblTitle.Location = new Point(40, 60);
            lblUsername.Location = new Point(40, 155);
            txtUsername.Location = new Point(40, 180);
            txtUsername.Width = 340;
            lblPassword.Location = new Point(40, 225);
            txtPassword.Location = new Point(40, 250);
            txtPassword.Width = 340;
            btnLogin.Text = "Sign In";
            btnLogin.Location = new Point(40, 310);
            btnLogin.Width = 340;
            btnLogin.BackColor = Color.FromArgb(34, 75, 113);
            btnLogin.ForeColor = Color.White;
            btnLogin.FlatStyle = FlatStyle.Flat;
            btnCancel.Location = new Point(40, 365);
            btnCancel.Width = 340;
            lblStatus.Location = new Point(40, 405);
            lblStatus.Width = 340;
            var register = new Button {
                Text = "Create account", Location = new Point(40, 392), Width = 340,
                Height = 32, FlatStyle = FlatStyle.Flat, BackColor = Color.White
            };
            register.Click += async (sender, args) => await Register();
            Controls.Add(register);
            lblStatus.Location = new Point(40, 430);
            ClientSize = new Size(420, 500);
            txtUsername.Focus();
        }

        private async System.Threading.Tasks.Task Register()
        {
            using (var form = new Form { Text = "Create Aperture account", Size = new Size(430, 440), StartPosition = FormStartPosition.CenterParent })
            {
                var first = new TextBox { Location = new Point(30, 55), Width = 350 };
                var last = new TextBox { Location = new Point(30, 115), Width = 350 };
                var username = new TextBox { Location = new Point(30, 175), Width = 350 };
                var password = new TextBox { Location = new Point(30, 235), Width = 350, UseSystemPasswordChar = true };
                var submit = new Button { Text = "Create account", Location = new Point(30, 295), Width = 350, Height = 40 };
                form.Controls.AddRange(new Control[] {
                    new Label { Text = "First name", Location = new Point(30, 32), AutoSize = true }, first,
                    new Label { Text = "Last name", Location = new Point(30, 92), AutoSize = true }, last,
                    new Label { Text = "Username", Location = new Point(30, 152), AutoSize = true }, username,
                    new Label { Text = "Password (at least 8 characters)", Location = new Point(30, 212), AutoSize = true }, password, submit
                });
                submit.Click += async (sender, args) => {
                    submit.Enabled = false;
                    try {
                        await _authenticationService.ApiClient.PostAsync<
                            Aperture_Desktop_Client.Models.RegisterRequestDto, object>("api/register",
                            new Aperture_Desktop_Client.Models.RegisterRequestDto {
                                FirstName = first.Text, LastName = last.Text,
                                Username = username.Text, Password = password.Text
                            });
                        txtUsername.Text = username.Text;
                        form.DialogResult = DialogResult.OK;
                        form.Close();
                    } catch (Exception ex) { MessageBox.Show(ex.Message, "Registration failed"); }
                    finally { submit.Enabled = true; }
                };
                form.ShowDialog(this);
            }
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
