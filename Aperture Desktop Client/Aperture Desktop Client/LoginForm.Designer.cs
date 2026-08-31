namespace Aperture_Desktop_Client
{
    partial class LoginForm
    {
        private System.ComponentModel.IContainer components = null;

        private System.Windows.Forms.Label lblTitle;
        private System.Windows.Forms.Label lblUsername;
        private System.Windows.Forms.TextBox txtUsername;
        private System.Windows.Forms.Label lblPassword;
        private System.Windows.Forms.TextBox txtPassword;
        private System.Windows.Forms.Button btnLogin;
        private System.Windows.Forms.Button btnCancel;
        private System.Windows.Forms.Label lblStatus;

        protected override void Dispose(
            bool disposing)
        {
            if (disposing &&
                (components != null))
            {
                components.Dispose();
            }

            base.Dispose(disposing);
        }

        private void InitializeComponent()
        {
            this.lblTitle =
                new System.Windows.Forms.Label();

            this.lblUsername =
                new System.Windows.Forms.Label();

            this.txtUsername =
                new System.Windows.Forms.TextBox();

            this.lblPassword =
                new System.Windows.Forms.Label();

            this.txtPassword =
                new System.Windows.Forms.TextBox();

            this.btnLogin =
                new System.Windows.Forms.Button();

            this.btnCancel =
                new System.Windows.Forms.Button();

            this.lblStatus =
                new System.Windows.Forms.Label();

            this.SuspendLayout();

            // 
            // lblTitle
            // 
            this.lblTitle.AutoSize = true;

            this.lblTitle.Font =
                new System.Drawing.Font(
                    "Segoe UI",
                    18F,
                    System.Drawing.FontStyle.Bold);

            this.lblTitle.Location =
                new System.Drawing.Point(
                    105,
                    30);

            this.lblTitle.Name =
                "lblTitle";

            this.lblTitle.Size =
                new System.Drawing.Size(
                    170,
                    32);

            this.lblTitle.Text =
                "Aperture Login";

            // 
            // lblUsername
            // 
            this.lblUsername.AutoSize = true;

            this.lblUsername.Location =
                new System.Drawing.Point(
                    40,
                    90);

            this.lblUsername.Name =
                "lblUsername";

            this.lblUsername.Text =
                "Username";

            // 
            // txtUsername
            // 
            this.txtUsername.Location =
                new System.Drawing.Point(
                    40,
                    112);

            this.txtUsername.Name =
                "txtUsername";

            this.txtUsername.Size =
                new System.Drawing.Size(
                    300,
                    23);

            // 
            // lblPassword
            // 
            this.lblPassword.AutoSize = true;

            this.lblPassword.Location =
                new System.Drawing.Point(
                    40,
                    150);

            this.lblPassword.Name =
                "lblPassword";

            this.lblPassword.Text =
                "Password";

            // 
            // txtPassword
            // 
            this.txtPassword.Location =
                new System.Drawing.Point(
                    40,
                    172);

            this.txtPassword.Name =
                "txtPassword";

            this.txtPassword.Size =
                new System.Drawing.Size(
                    300,
                    23);

            this.txtPassword.UseSystemPasswordChar =
                true;

            // 
            // btnLogin
            // 
            this.btnLogin.Location =
                new System.Drawing.Point(
                    40,
                    220);

            this.btnLogin.Name =
                "btnLogin";

            this.btnLogin.Size =
                new System.Drawing.Size(
                    140,
                    35);

            this.btnLogin.Text =
                "Login";

            this.btnLogin.UseVisualStyleBackColor =
                true;

            this.btnLogin.Click +=
                new System.EventHandler(
                    this.btnLogin_Click);

            // 
            // btnCancel
            // 
            this.btnCancel.Location =
                new System.Drawing.Point(
                    200,
                    220);

            this.btnCancel.Name =
                "btnCancel";

            this.btnCancel.Size =
                new System.Drawing.Size(
                    140,
                    35);

            this.btnCancel.Text =
                "Exit";

            this.btnCancel.UseVisualStyleBackColor =
                true;

            this.btnCancel.Click +=
                new System.EventHandler(
                    this.btnCancel_Click);

            // 
            // lblStatus
            // 
            this.lblStatus.AutoSize = false;

            this.lblStatus.Location =
                new System.Drawing.Point(
                    40,
                    275);

            this.lblStatus.Name =
                "lblStatus";

            this.lblStatus.Size =
                new System.Drawing.Size(
                    300,
                    60);

            this.lblStatus.TextAlign =
                System.Drawing.ContentAlignment.TopLeft;

            // 
            // LoginForm
            // 
            this.AcceptButton =
                this.btnLogin;

            this.AutoScaleDimensions =
                new System.Drawing.SizeF(
                    7F,
                    15F);

            this.AutoScaleMode =
                System.Windows.Forms.AutoScaleMode.Font;

            this.CancelButton =
                this.btnCancel;

            this.ClientSize =
                new System.Drawing.Size(
                    380,
                    360);

            this.Controls.Add(
                this.lblTitle);

            this.Controls.Add(
                this.lblUsername);

            this.Controls.Add(
                this.txtUsername);

            this.Controls.Add(
                this.lblPassword);

            this.Controls.Add(
                this.txtPassword);

            this.Controls.Add(
                this.btnLogin);

            this.Controls.Add(
                this.btnCancel);

            this.Controls.Add(
                this.lblStatus);

            this.FormBorderStyle =
                System.Windows.Forms.FormBorderStyle.FixedDialog;

            this.MaximizeBox = false;

            this.MinimizeBox = false;

            this.Name =
                "LoginForm";

            this.StartPosition =
                System.Windows.Forms.FormStartPosition.CenterScreen;

            this.Text =
                "Aperture - Login";

            this.ResumeLayout(false);

            this.PerformLayout();
        }
    }
}

