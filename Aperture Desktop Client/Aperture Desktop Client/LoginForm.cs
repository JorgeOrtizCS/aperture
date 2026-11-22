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

            DesktopTheme.Apply(this);
            ClientSize = new Size(752, 430);
            Padding = new Padding(12);
            var brand = new Panel
            {
                Dock = DockStyle.Left,
                Width = 300,
                BackColor = DesktopTheme.PrimarySoft
            };
            var intro = new Label
            {
                Text = "Share sensitive content securely.",
                Location = new Point(32, 184),
                Size = new Size(234, 64),
                Font = new Font("Segoe UI", 13),
                ForeColor = DesktopTheme.Secondary
            };
            lblTitle.Text = "Aperture";
            lblTitle.Font = new Font("Segoe UI", 30, FontStyle.Bold);
            lblTitle.ForeColor = DesktopTheme.Primary;
            lblTitle.Location = new Point(27, 125);
            brand.Controls.AddRange(new Control[] { lblTitle, intro });

            var card = new Panel { Dock = DockStyle.Fill, BackColor = DesktopTheme.Surface };
            DesktopTheme.RoundCorners(brand);
            DesktopTheme.RoundCorners(card);
            var heading = new Label
            {
                Text = "Sign in",
                Font = new Font("Segoe UI", 20, FontStyle.Bold),
                Location = new Point(32, 27),
                AutoSize = true
            };
            lblUsername.Location = new Point(34, 90);
            txtUsername.Location = new Point(34, 116);
            txtUsername.Width = 382;
            lblPassword.Location = new Point(34, 160);
            txtPassword.Location = new Point(34, 186);
            txtPassword.Width = 382;
            DesktopTheme.StyleInput(txtUsername);
            DesktopTheme.StyleInput(txtPassword);

            btnLogin.Text = "Sign in";
            btnLogin.SetBounds(34, 237, 382, 42);
            DesktopTheme.StyleButton(btnLogin);
            btnCancel.SetBounds(282, 294, 134, 38);
            DesktopTheme.StyleButton(btnCancel, false);
            var register = new Button { Text = "Create account", TabIndex = btnLogin.TabIndex + 1 };
            register.SetBounds(34, 294, 234, 38);
            DesktopTheme.StyleButton(register, false);
            register.Click += async (sender, args) => await Register();
            btnCancel.TabIndex = register.TabIndex + 1;
            lblStatus.SetBounds(34, 348, 382, 58);
            card.Controls.AddRange(new Control[]
            {
                heading, lblUsername, txtUsername, lblPassword, txtPassword, btnLogin, register, btnCancel, lblStatus
            });
            Controls.Add(card);
            Controls.Add(brand);
            ActiveControl = txtUsername;
        }

        private async System.Threading.Tasks.Task Register()
        {
            using (var form = new Form { Text = "Create Aperture account", Size = new Size(430, 440), StartPosition = FormStartPosition.CenterParent })
            {
                DesktopTheme.Apply(form);
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
                foreach (var field in new[] { first, last, username, password }) DesktopTheme.StyleInput(field);
                DesktopTheme.StyleButton(submit);
                form.AcceptButton = submit;
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
                    DesktopTheme.Success);

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
                if (mainForm.ShowDialog() == DialogResult.OK)
                {
                    txtPassword.Clear();
                    lblStatus.Text = string.Empty;
                    SetLoggingInState(false);
                    Show();
                    Activate();
                    txtPassword.Focus();
                    return;
                }
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
                    DesktopTheme.Primary);
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
                DesktopTheme.Danger);
        }

        private void btnCancel_Click(
            object sender,
            EventArgs e)
        {
            Close();
        }
    }
}
