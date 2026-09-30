using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Forms;
using Aperture_Desktop_Client.Models;
using Aperture_Desktop_Client.Services;
namespace Aperture_Desktop.Forms {
 public partial class MainForm : Form {
  readonly AuthenticationService auth;
  readonly Color navy=Color.FromArgb(34,75,113), ink=Color.FromArgb(42,53,69);
  FlowLayoutPanel received,sent;Label status;Button refresh;bool loading;
  public MainForm(AuthenticationService service) {InitializeComponent();auth=service;BuildDashboard();Shown+=async (s,e)=>await LoadContent();}
  Label Label(string value,int size=10,bool bold=false) {return new Label {Text=value,AutoSize=true,Font=new Font("Segoe UI",size,bold?FontStyle.Bold:FontStyle.Regular),ForeColor=ink,Margin=new Padding(3,8,3,8)};}
  Button Button(string value,int width=180) {return new Button {Text=value,BackColor=navy,ForeColor=Color.White,FlatStyle=FlatStyle.Flat,Height=38,Width=width,Margin=new Padding(4,6,4,6)};}
  void BuildDashboard() {
   Controls.Clear();BackColor=Color.FromArgb(248,250,253);Text="Aperture · Secure Content";Size=new Size(920,710);MinimumSize=new Size(740,560);FormBorderStyle=FormBorderStyle.Sizable;MaximizeBox=true;
   var layout=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=1,RowCount=3,Padding=new Padding(26)};layout.RowStyles.Add(new RowStyle(SizeType.Absolute,135));layout.RowStyles.Add(new RowStyle(SizeType.Percent,100));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,38));Controls.Add(layout);
   var top=new FlowLayoutPanel {Dock=DockStyle.Fill,FlowDirection=FlowDirection.TopDown,WrapContents=false};layout.Controls.Add(top,0,0);top.Controls.Add(Label("Aperture",22,true));top.Controls.Add(Label("Welcome back, "+auth.CurrentUser.Username+". Manage your secure content."));
   var actions=new FlowLayoutPanel {Width=820,Height=50};top.Controls.Add(actions);var share=Button("+  Share New Content");share.Click+=async (s,e)=>await Share();actions.Controls.Add(share);
   refresh=Button("Refresh",100);refresh.Click+=async (s,e)=>await LoadContent();actions.Controls.Add(refresh);
   var device=Button("Register device",140);device.Click+=async (s,e)=>await RegisterDevice();actions.Controls.Add(device);
   var logout=Button("Sign out",100);logout.Click+=async (s,e)=>{try{await auth.Logout();Close();}catch(Exception ex){MessageBox.Show(ex.Message,"Sign out failed");}};actions.Controls.Add(logout);
   var columns=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=2};columns.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,50));columns.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,50));layout.Controls.Add(columns,0,1);received=Column(columns,"Shared With Me",0);sent=Column(columns,"My Shared Content",1);
   status=Label("Loading content...");layout.Controls.Add(status,0,2);
  }
  FlowLayoutPanel Column(TableLayoutPanel parent,string title,int index) {var panel=new TableLayoutPanel {Dock=DockStyle.Fill,RowCount=2,Padding=new Padding(5)};panel.RowStyles.Add(new RowStyle(SizeType.Absolute,42));panel.RowStyles.Add(new RowStyle(SizeType.Percent,100));parent.Controls.Add(panel,index,0);panel.Controls.Add(Label(title,14,true),0,0);var list=new FlowLayoutPanel {Dock=DockStyle.Fill,AutoScroll=true,FlowDirection=FlowDirection.TopDown,WrapContents=false};panel.Controls.Add(list,0,1);return list;}
  async Task LoadContent() {if(loading)return;loading=true;refresh.Enabled=false;status.Text="Loading content...";try {var items=await auth.ApiClient.GetAsync<List<SharedContent>>("api/content");received.Controls.Clear();sent.Controls.Clear();foreach(var item in items) {var card=new Button {Text=item.Title+Environment.NewLine+(item.Mine?"To "+item.Recipient:"From "+item.Owner)+"  ·  "+item.Status+" / "+item.PolicyStatus,Width=355,Height=74,TextAlign=ContentAlignment.MiddleLeft,BackColor=Color.White,ForeColor=ink,FlatStyle=FlatStyle.Flat,Margin=new Padding(3,5,3,5)};card.Click+=async (s,e)=>{if(item.Mine)await Manage(item);else await Open(item);};(item.Mine?sent:received).Controls.Add(card);}if(received.Controls.Count==0)received.Controls.Add(Label("Nothing shared with you yet."));if(sent.Controls.Count==0)sent.Controls.Add(Label("Share your first item."));status.Text=items.Count+" item(s) · Updated "+DateTime.Now.ToShortTimeString();}catch(Exception ex){status.Text="Could not load content: "+ex.Message;}finally{loading=false;refresh.Enabled=true;}}
  static Guid DeviceKey() {var directory=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Aperture");Directory.CreateDirectory(directory);var path=Path.Combine(directory,"device-id.txt");Guid key;if(File.Exists(path)&&Guid.TryParse(File.ReadAllText(path),out key)&&key!=Guid.Empty)return key;key=Guid.NewGuid();File.WriteAllText(path,key.ToString("D"));return key;}
  async Task RegisterDevice() {try{var result=await auth.ApiClient.PostAsync<DeviceRegistration,DeviceRegistrationResult>("api/devices",new DeviceRegistration {DeviceKey=DeviceKey(),DeviceName=Environment.MachineName});MessageBox.Show(result.Trusted?"This device is marked trusted.":"Device registered. An administrator must approve it before trusted-device policies allow access.","Device status");}catch(Exception ex){MessageBox.Show(ex.Message,"Device registration failed");}}
  async Task Manage(SharedContent item) {
   using(var form=new Form {Text="Manage shared content",Size=new Size(420,255),StartPosition=FormStartPosition.CenterParent}) {
    var description=Label(item.Title+" · shared with "+item.Recipient+"\nAccess: "+item.Status+" · Policy: "+item.PolicyStatus);description.Location=new Point(20,20);description.AutoSize=false;description.Size=new Size(370,65);form.Controls.Add(description);
    var toggle=Button(item.PolicyStatus=="Active"?"Pause access":"Resume access",165);toggle.Location=new Point(20,100);toggle.Enabled=item.Status=="Active";form.Controls.Add(toggle);
    var revoke=Button("Revoke",130);revoke.Location=new Point(200,100);revoke.Enabled=item.Status=="Active";form.Controls.Add(revoke);
    toggle.Click+=async (sender,args)=>{toggle.Enabled=false;try{await auth.ApiClient.PostAsync<PolicyUpdate,object>("api/content/"+item.Id+"/policy",new PolicyUpdate {Status=item.PolicyStatus=="Active"?"Paused":"Active"});form.DialogResult=DialogResult.OK;form.Close();}catch(Exception ex){MessageBox.Show(ex.Message,"Policy update failed");toggle.Enabled=true;}};
    revoke.Click+=async (sender,args)=>{if(MessageBox.Show("Revoke this recipient's access?","Confirm revocation",MessageBoxButtons.YesNo)!=DialogResult.Yes)return;revoke.Enabled=false;try{await auth.ApiClient.PostAsync("api/content/"+item.Id+"/revoke");form.DialogResult=DialogResult.OK;form.Close();}catch(Exception ex){MessageBox.Show(ex.Message,"Revocation failed");revoke.Enabled=true;}};
    if(form.ShowDialog(this)==DialogResult.OK)await LoadContent();
   }
  }
  async Task Share() {using(var form=new Form {Text="Share New Content",Size=new Size(570,770),StartPosition=FormStartPosition.CenterParent,BackColor=Color.White,AutoScroll=true}) {
   var title=new TextBox {Location=new Point(24,55),Width=500};var recipient=new TextBox {Location=new Point(24,115),Width=500};var body=new TextBox {Location=new Point(24,175),Width=500,Height=240,Multiline=true,ScrollBars=ScrollBars.Vertical};
   string imageData=null;string imageType=null;
   var choose=Button("Select PNG/JPEG",160);choose.Location=new Point(24,420);
   var selection=new Label {Text="Text content selected",Location=new Point(200,428),Width=320};
   choose.Click+=(sender,args)=>{using(var dialog=new OpenFileDialog {Filter="Images|*.png;*.jpg;*.jpeg",Title="Choose an image"}){if(dialog.ShowDialog(form)==DialogResult.OK){var info=new FileInfo(dialog.FileName);if(info.Length>5*1024*1024){MessageBox.Show("Maximum image size is 5 MB.");return;}imageData=Convert.ToBase64String(File.ReadAllBytes(dialog.FileName));imageType=Path.GetExtension(dialog.FileName).Equals(".png",StringComparison.OrdinalIgnoreCase)?"image/png":"image/jpeg";selection.Text=info.Name;}}};
   var expiry=new DateTimePicker {Location=new Point(24,495),Width=240,Format=DateTimePickerFormat.Custom,CustomFormat="yyyy-MM-dd HH:mm",ShowCheckBox=true,Checked=false,Value=DateTime.Now.AddDays(7)};
   var max=new NumericUpDown {Location=new Point(285,495),Width=90,Minimum=0,Maximum=1,Value=0};var trusted=new CheckBox {Text="Require approved device",Location=new Point(24,590),Width=250};var submit=Button("Share securely");submit.Location=new Point(24,635);
   var start=new DateTimePicker {Location=new Point(24,550),Width=240,Format=DateTimePickerFormat.Custom,CustomFormat="yyyy-MM-dd HH:mm",ShowCheckBox=true,Checked=false,Value=DateTime.Now.AddMinutes(5)};
   form.Controls.AddRange(new Control[] {new Label {Text="Title",Location=new Point(24,30),AutoSize=true},title,new Label {Text="Recipient username",Location=new Point(24,90),AutoSize=true},recipient,new Label {Text="Content text",Location=new Point(24,150),AutoSize=true},body,choose,selection,new Label {Text="Expiration (optional)",Location=new Point(24,473),AutoSize=true},expiry,new Label {Text="One view (1 = yes)",Location=new Point(285,473),AutoSize=true},max,new Label {Text="Start time (optional)",Location=new Point(24,527),AutoSize=true},start,trusted,submit});
   submit.Click+=async (s,e)=>{submit.Enabled=false;try{await auth.ApiClient.PostAsync<CreateContentRequest,SharedContent>("api/content",new CreateContentRequest {Title=title.Text,Recipient=recipient.Text,Body=body.Text,FileDataBase64=imageData,FileType=imageType,ExpiresAt=expiry.Checked?(DateTime?)expiry.Value.ToUniversalTime():null,StartTime=start.Checked?(DateTime?)start.Value.ToUniversalTime():null,MaxViews=max.Value==0?(int?)null:(int)max.Value,RequireTrustedDevice=trusted.Checked});form.DialogResult=DialogResult.OK;form.Close();}catch(Exception ex){MessageBox.Show(ex.Message,"Share failed");}finally{if(!submit.IsDisposed)submit.Enabled=true;}};
   if(form.ShowDialog(this)==DialogResult.OK)await LoadContent();
  }}
  async Task Open(SharedContent item) {int sessionId=0;SessionResult opened;
   try {opened=await auth.ApiClient.PostAsync<SessionRequest,SessionResult>("api/content/"+item.Id+"/sessions",new SessionRequest {DeviceKey=DeviceKey()});sessionId=opened.SessionId;}catch(Exception ex){MessageBox.Show(ex.Message,"Access denied or unavailable");return;}
   using(var viewer=new Form {Text="Aperture · "+item.Title,Size=new Size(690,570),StartPosition=FormStartPosition.CenterParent,BackColor=Color.White}) {
    var heading=Label(item.Title,18,true);heading.Dock=DockStyle.Top;heading.Height=60;heading.AutoSize=false;heading.Padding=new Padding(20,12,0,0);
    var badge=Label("Access granted · Recheck every 5 seconds");badge.Dock=DockStyle.Bottom;badge.Height=48;badge.AutoSize=false;badge.Padding=new Padding(20,10,0,0);
    var text=new TextBox {Multiline=true,ReadOnly=true,Dock=DockStyle.Fill,ScrollBars=ScrollBars.Vertical,Font=new Font("Segoe UI",11),BorderStyle=BorderStyle.None,Text=opened.Body};
    var picture=new PictureBox {Dock=DockStyle.Fill,SizeMode=PictureBoxSizeMode.Zoom,Visible=false};
    Action<SessionResult> display=result=>{if(result.FileType=="image/png" || result.FileType=="image/jpeg") {var bytes=Convert.FromBase64String(result.FileDataBase64);using(var stream=new MemoryStream(bytes))using(var original=Image.FromStream(stream)){var previous=picture.Image;picture.Image=new Bitmap(original);if(previous!=null)previous.Dispose();}text.Visible=false;picture.Visible=true;picture.BringToFront();}else{picture.Visible=false;text.Visible=true;text.Text=result.Body;}};
    viewer.Controls.Add(text);viewer.Controls.Add(picture);viewer.Controls.Add(badge);viewer.Controls.Add(heading);display(opened);
    var timer=new Timer {Interval=5000};bool checking=false;timer.Tick+=async (s,e)=>{if(checking||viewer.IsDisposed)return;checking=true;timer.Stop();try{var result=await auth.ApiClient.PostAsync<object,SessionResult>("api/content/sessions/"+sessionId+"/check",new object());if(viewer.IsDisposed)return;if(!result.AccessGranted){text.Clear();picture.Image=null;picture.Visible=false;badge.Text="Access revoked: "+result.Message;badge.ForeColor=Color.Firebrick;viewer.Close();return;}display(result);badge.Text="Access granted · Verified "+DateTime.Now.ToLongTimeString();}catch(Exception){if(!viewer.IsDisposed){text.Clear();picture.Image=null;picture.Visible=false;badge.Text="Access paused: unable to verify with server";badge.ForeColor=Color.Firebrick;viewer.Close();}}finally{checking=false;if(!viewer.IsDisposed)timer.Start();}};
    viewer.FormClosed+=(s,e)=>timer.Dispose();timer.Start();viewer.ShowDialog(this);
   }
   try{await auth.ApiClient.PostAsync("api/content/sessions/"+sessionId+"/end");}catch{ /* Server closes a failed check; abandoned sessions can be expired by maintenance. */ }
  }
 }
}
