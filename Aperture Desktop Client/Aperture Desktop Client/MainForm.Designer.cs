namespace Aperture_Desktop.Forms
{
    partial class MainForm
    {
        private System.ComponentModel.IContainer components = null;

        private System.Windows.Forms.Label lblTitle;
        private System.Windows.Forms.Label lblUsername;
        private System.Windows.Forms.Label lblContentObjectId;
        private System.Windows.Forms.TextBox txtContentObjectId;
        private System.Windows.Forms.Button btnCheckAccess;
        private System.Windows.Forms.Label lblResult;
        private System.Windows.Forms.Button btnLogout;

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

            this.lblContentObjectId =
                new System.Windows.Forms.Label();

            this.txtContentObjectId =
                new System.Windows.Forms.TextBox();

            this.btnCheckAccess =
                new System.Windows.Forms.Button();

            this.lblResult =
                new System.Windows.Forms.Label();

            this.btnLogout =
                new System.Windows.Forms.Button();

            this.SuspendLayout();

            // 
            // lblTitle
            // 
            this.lblTitle.AutoSize = true;

            this.lblTitle.Font =
                new System.Drawing.Font(
                    "Segoe UI",
                    18F,
                    System.Drawing.FontStyle.Bold,
                    System.Drawing.GraphicsUnit.Point,
                    ((byte)(0)));

            this.lblTitle.Location =
                new System.Drawing.Point(
                    30,
                    25);

            this.lblTitle.Name =
                "lblTitle";

            this.lblTitle.Size =
                new System.Drawing.Size(
                    91,
                    32);

            this.lblTitle.TabIndex =
                0;

            this.lblTitle.Text =
                "Aperture";

            // 
            // lblUsername
            // 
            this.lblUsername.AutoSize = true;

            this.lblUsername.Font =
                new System.Drawing.Font(
                    "Segoe UI",
                    10F,
                    System.Drawing.FontStyle.Regular,
                    System.Drawing.GraphicsUnit.Point,
                    ((byte)(0)));

            this.lblUsername.Location =
                new System.Drawing.Point(
                    32,
                    70);

            this.lblUsername.Name =
                "lblUsername";

            this.lblUsername.Size =
                new System.Drawing.Size(
                    100,
                    19);

            this.lblUsername.TabIndex =
                1;

            this.lblUsername.Text =
                "Welcome";

            // 
            // lblContentObjectId
            // 
            this.lblContentObjectId.AutoSize = true;

            this.lblContentObjectId.Location =
                new System.Drawing.Point(
                    32,
                    115);

            this.lblContentObjectId.Name =
                "lblContentObjectId";

            this.lblContentObjectId.Size =
                new System.Drawing.Size(
                    113,
                    15);

            this.lblContentObjectId.TabIndex =
                2;

            this.lblContentObjectId.Text =
                "Content Object ID";

            // 
            // txtContentObjectId
            // 
            this.txtContentObjectId.Location =
                new System.Drawing.Point(
                    32,
                    138);

            this.txtContentObjectId.Name =
                "txtContentObjectId";

            this.txtContentObjectId.Size =
                new System.Drawing.Size(
                    320,
                    23);

            this.txtContentObjectId.TabIndex =
                3;

            // 
            // btnCheckAccess
            // 
            this.btnCheckAccess.Location =
                new System.Drawing.Point(
                    32,
                    180);

            this.btnCheckAccess.Name =
                "btnCheckAccess";

            this.btnCheckAccess.Size =
                new System.Drawing.Size(
                    320,
                    40);

            this.btnCheckAccess.TabIndex =
                4;

            this.btnCheckAccess.Text =
                "Check Access";

            this.btnCheckAccess.UseVisualStyleBackColor =
                true;

            this.btnCheckAccess.Click +=
                new System.EventHandler(
                    this.btnCheckAccess_Click);

            // 
            // lblResult
            // 
            this.lblResult.BorderStyle =
                System.Windows.Forms.BorderStyle.FixedSingle;

            this.lblResult.Font =
                new System.Drawing.Font(
                    "Segoe UI",
                    11F,
                    System.Drawing.FontStyle.Bold,
                    System.Drawing.GraphicsUnit.Point,
                    ((byte)(0)));

            this.lblResult.Location =
                new System.Drawing.Point(
                    32,
                    240);

            this.lblResult.Name =
                "lblResult";

            this.lblResult.Size =
                new System.Drawing.Size(
                    320,
                    50);

            this.lblResult.TabIndex =
                5;

            this.lblResult.Text =
                "Ready.";

            this.lblResult.TextAlign =
                System.Drawing.ContentAlignment.MiddleCenter;

            // 
            // btnLogout
            // 
            this.btnLogout.Location =
                new System.Drawing.Point(
                    32,
                    320);

            this.btnLogout.Name =
                "btnLogout";

            this.btnLogout.Size =
                new System.Drawing.Size(
                    320,
                    35);

            this.btnLogout.TabIndex =
                6;

            this.btnLogout.Text =
                "Logout";

            this.btnLogout.UseVisualStyleBackColor =
                true;

            this.btnLogout.Click +=
                new System.EventHandler(
                    this.btnLogout_Click);

            // 
            // MainForm
            // 
            this.AcceptButton =
                this.btnCheckAccess;

            this.AutoScaleDimensions =
                new System.Drawing.SizeF(
                    7F,
                    15F);

            this.AutoScaleMode =
                System.Windows.Forms.AutoScaleMode.Font;

            this.ClientSize =
                new System.Drawing.Size(
                    390,
                    390);

            this.Controls.Add(
                this.btnLogout);

            this.Controls.Add(
                this.lblResult);

            this.Controls.Add(
                this.btnCheckAccess);

            this.Controls.Add(
                this.txtContentObjectId);

            this.Controls.Add(
                this.lblContentObjectId);

            this.Controls.Add(
                this.lblUsername);

            this.Controls.Add(
                this.lblTitle);

            this.FormBorderStyle =
                System.Windows.Forms.FormBorderStyle.FixedDialog;

            this.MaximizeBox = false;

            this.MinimizeBox = false;

            this.Name =
                "MainForm";

            this.StartPosition =
                System.Windows.Forms.FormStartPosition.CenterScreen;

            this.Text =
                "Aperture";

            this.ResumeLayout(false);

            this.PerformLayout();
        }
    }
}