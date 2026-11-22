using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Threading.Tasks;
using System.Windows.Forms;
using Aperture_Desktop_Client;
using Aperture_Desktop_Client.Models;
using Aperture_Desktop_Client.Services;
namespace Aperture_Desktop.Forms {
 public partial class MainForm : Form {
  readonly AuthenticationService auth;
  readonly Color ink=DesktopTheme.Text;
  FlowLayoutPanel received,sent;
  Label status;
  Button refresh;
  bool loading;

  public MainForm(AuthenticationService service)
  {
   InitializeComponent();
   auth=service;
   BuildDashboard();
   Shown+=async (s,e)=>await LoadContent();
  }

  Label Label(string value,int size=10,bool bold=false)
  {
   return new Label {Text=value,AutoSize=true,Font=new Font("Segoe UI",size,bold?FontStyle.Bold:FontStyle.Regular),
    ForeColor=ink,Margin=new Padding(3,8,3,8)};
  }

  Button Button(string value,int width=180,bool primary=true,bool danger=false)
  {
   var button=new Button {Text=value,Height=38,Width=width,Margin=new Padding(4,6,4,6)};
   DesktopTheme.StyleButton(button,primary,danger);
   return button;
  }

  void BuildDashboard()
  {
   DesktopTheme.Apply(this);
   Text="Aperture - Secure Content";
   var workingArea=Screen.FromPoint(Cursor.Position).WorkingArea;
   Size=new Size(Math.Min(1200,workingArea.Width),Math.Min(780,workingArea.Height));
   MinimumSize=new Size(740,510);
   StartPosition=FormStartPosition.CenterScreen;
   var layout=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=1,RowCount=4,Padding=new Padding(24,16,24,8)};
   layout.RowStyles.Add(new RowStyle(SizeType.Absolute,84));
   layout.RowStyles.Add(new RowStyle(SizeType.Absolute,60));
   layout.RowStyles.Add(new RowStyle(SizeType.Percent,100));
   layout.RowStyles.Add(new RowStyle(SizeType.Absolute,36));
   Controls.Add(layout);

   var header=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=2,RowCount=1,BackColor=DesktopTheme.Surface,Padding=new Padding(14,0,12,0)};
   header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
   header.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
   var brand=new FlowLayoutPanel {Dock=DockStyle.Fill,FlowDirection=FlowDirection.TopDown,WrapContents=false};
   var name=Label("Aperture",23,true);
   name.ForeColor=DesktopTheme.Primary;
   name.Margin=new Padding(3,5,3,0);
   var subtitle=Label("Secure Content Dashboard");
   subtitle.ForeColor=DesktopTheme.Secondary;
   subtitle.Margin=new Padding(3,0,3,5);
   brand.Controls.AddRange(new Control[] {name,subtitle});
   DesktopTheme.RoundCorners(header);
   header.Controls.Add(brand,0,0);
   var account=Label(auth.CurrentUser.Username,10,true);
   account.Anchor=AnchorStyles.Right;
   account.AutoEllipsis=true;
   account.MaximumSize=new Size(220,0);
   header.Controls.Add(account,1,0);
   layout.Controls.Add(header,0,0);

   var actions=new FlowLayoutPanel {Dock=DockStyle.Fill,WrapContents=false,Padding=new Padding(0,3,0,0)};
   var share=Button("+  Share New Content");
   share.Click+=async (s,e)=>await Share();
   refresh=Button("Refresh",100,false);
   refresh.Click+=async (s,e)=>await LoadContent();
   var device=Button("Register device",140,false);
   device.Click+=async (s,e)=>await RegisterDevice();
   var logout=Button("Sign out",100,false);
   logout.Click+=async (s,e)=>
   {
    logout.Enabled=false;
    try{await auth.Logout();}
    catch(Exception ex){MessageBox.Show(ex.Message,"Server sign-out unavailable");}
    finally{if(!IsDisposed){DialogResult=DialogResult.OK;Close();}}
   };
   actions.Controls.AddRange(new Control[] {share,refresh,device,logout});
   layout.Controls.Add(actions,0,1);

   var columns=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=2,RowCount=1,Margin=new Padding(0)};
   columns.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,50));
   columns.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,50));
   layout.Controls.Add(columns,0,2);
   received=Column(columns,"Shared With Me",0);
   sent=Column(columns,"My Shared Content",1);
   status=Label("Loading content...");
   status.ForeColor=DesktopTheme.Secondary;
   layout.Controls.Add(status,0,3);
  }

  FlowLayoutPanel Column(TableLayoutPanel parent,string title,int index)
  {
   var panel=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=1,RowCount=2,BackColor=DesktopTheme.Surface,
    Padding=new Padding(12,4,12,8),Margin=index==0?new Padding(3,0,8,0):new Padding(8,0,3,0)};
   panel.RowStyles.Add(new RowStyle(SizeType.Absolute,46));
   panel.RowStyles.Add(new RowStyle(SizeType.Percent,100));
   DesktopTheme.RoundCorners(panel);
   parent.Controls.Add(panel,index,0);
   var heading=Label(title,14,true);
   heading.ForeColor=DesktopTheme.Primary;
   panel.Controls.Add(heading,0,0);
   var list=new FlowLayoutPanel {Dock=DockStyle.Fill,AutoScroll=true,FlowDirection=FlowDirection.TopDown,WrapContents=false,
    BackColor=DesktopTheme.Background,Padding=new Padding(6)};
   list.SizeChanged+=(s,e)=>ResizeCards(list);
   panel.Controls.Add(list,0,1);
   return list;
  }

  static void ResizeCards(FlowLayoutPanel list)
  {
   foreach(Control card in list.Controls)
    card.Width=Math.Max(1,list.Width-list.Padding.Horizontal-card.Margin.Horizontal-SystemInformation.VerticalScrollBarWidth);
  }

  async Task LoadContent()
  {
   if(loading)return;
   loading=true;
   refresh.Enabled=false;
   status.ForeColor=DesktopTheme.Secondary;
   status.Text="Loading content...";
   try
   {
    var items=await auth.ApiClient.GetAsync<List<SharedContent>>("api/content");
    if(IsDisposed)return;
    PopulateColumn(received,items,false,"Nothing shared with you yet.");
    PopulateColumn(sent,items,true,"Share your first item.");
    status.Text=items.Count+" item(s) · Updated "+DateTime.Now.ToShortTimeString();
   }
   catch(Exception ex)
   {
    if(IsDisposed)return;
    status.ForeColor=DesktopTheme.Danger;
    status.Text="Could not load content: "+ex.Message;
   }
   finally
   {
    loading=false;
    if(!IsDisposed)refresh.Enabled=true;
   }
  }

  void PopulateColumn(FlowLayoutPanel list,List<SharedContent> items,bool mine,string emptyText)
  {
   list.SuspendLayout();
   try
   {
    while(list.Controls.Count>0)list.Controls[0].Dispose();
    foreach(var item in items)
    {
     if(item.Mine!=mine)continue;
     var card=Button(item.Title+Environment.NewLine+
      (mine?"To "+item.Recipient:"From "+item.Owner)+"  ·  "+item.Status+" / "+item.PolicyStatus,primary:false);
     card.Height=76;
     card.Padding=new Padding(10,0,10,0);
     card.TextAlign=ContentAlignment.MiddleLeft;
     card.ForeColor=ink;
     card.AutoEllipsis=true;
     card.AccessibleName=card.Text;
     card.Click+=async (s,e)=>{if(item.Mine)await Manage(item);else await Open(item);};
     list.Controls.Add(card);
    }
    if(list.Controls.Count==0)
    {
     var empty=Label(emptyText);
     empty.ForeColor=DesktopTheme.Secondary;
     list.Controls.Add(empty);
    }
    ResizeCards(list);
   }
   finally{list.ResumeLayout();}
  }

  static Guid DeviceKey() {var directory=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Aperture");Directory.CreateDirectory(directory);var path=Path.Combine(directory,"device-id.txt");Guid key;if(File.Exists(path)&&Guid.TryParse(File.ReadAllText(path),out key)&&key!=Guid.Empty)return key;key=Guid.NewGuid();File.WriteAllText(path,key.ToString("D"));return key;}
  async Task RegisterDevice() {try{var result=await auth.ApiClient.PostAsync<DeviceRegistration,DeviceRegistrationResult>("api/devices",new DeviceRegistration {DeviceKey=DeviceKey(),DeviceName=Environment.MachineName});MessageBox.Show(result.Trusted?"This device is marked trusted.":"Device registered. An administrator must approve it before trusted-device policies allow access.","Device status");}catch(Exception ex){MessageBox.Show(ex.Message,"Device registration failed");}}
  async Task Manage(SharedContent item) {
   using(var form=new Form {Text="Manage shared content",Size=new Size(500,360),StartPosition=FormStartPosition.CenterParent}) {
    DesktopTheme.Apply(form);
    var description=Label(item.Title+" - shared with "+item.Recipient+"\nAccess: "+item.Status+" - Policy: "+item.PolicyStatus);description.Location=new Point(20,20);description.AutoSize=false;description.Size=new Size(370,65);form.Controls.Add(description);
    var toggle=Button(item.PolicyStatus=="Active"?"Pause access":"Resume access",165);toggle.Location=new Point(20,100);toggle.Enabled=item.Status=="Active";form.Controls.Add(toggle);
    var revoke=Button("Revoke",130,false,true);revoke.Location=new Point(200,100);revoke.Enabled=item.Status=="Active";form.Controls.Add(revoke);
    toggle.Click+=async (sender,args)=>{toggle.Enabled=false;try{await auth.ApiClient.PostAsync<PolicyUpdate,object>("api/content/"+item.Id+"/policy",new PolicyUpdate {Status=item.PolicyStatus=="Active"?"Paused":"Active"});form.DialogResult=DialogResult.OK;form.Close();}catch(Exception ex){MessageBox.Show(ex.Message,"Policy update failed");toggle.Enabled=true;}};
    revoke.Click+=async (sender,args)=>{if(MessageBox.Show("Revoke this recipient's access?","Confirm revocation",MessageBoxButtons.YesNo)!=DialogResult.Yes)return;revoke.Enabled=false;try{await auth.ApiClient.PostAsync("api/content/"+item.Id+"/revoke");form.DialogResult=DialogResult.OK;form.Close();}catch(Exception ex){MessageBox.Show(ex.Message,"Revocation failed");revoke.Enabled=true;}};
    var editTime=Button("Edit time window",195);editTime.Location=new Point(20,155);form.Controls.Add(editTime);
    var editArea=Button("Set allowed area",195);editArea.Location=new Point(230,155);form.Controls.Add(editArea);
    editTime.Click+=async (sender,args)=>{if(await EditConditions(item,false)){form.DialogResult=DialogResult.OK;form.Close();}};
    editArea.Click+=async (sender,args)=>{if(await EditConditions(item,true)){form.DialogResult=DialogResult.OK;form.Close();}};
    if(form.ShowDialog(this)==DialogResult.OK)await LoadContent();
   }
  }
  Task<bool> EditConditions(SharedContent item,bool location) {
   using(var form=new Form {Text=location?"Allowed viewing area":"Viewing time window",Size=new Size(550,340),StartPosition=FormStartPosition.CenterParent}) {
    DesktopTheme.Apply(form);
    var start=new DateTimePicker {Location=new Point(25,60),Width=230,Format=DateTimePickerFormat.Custom,CustomFormat="yyyy-MM-dd HH:mm",ShowCheckBox=true,Checked=item.StartTime.HasValue,Value=item.StartTime.HasValue?item.StartTime.Value.ToLocalTime():DateTime.Now};
    var expiry=new DateTimePicker {Location=new Point(275,60),Width=230,Format=DateTimePickerFormat.Custom,CustomFormat="yyyy-MM-dd HH:mm",ShowCheckBox=true,Checked=item.ExpiresAt.HasValue,Value=item.ExpiresAt.HasValue?item.ExpiresAt.Value.ToLocalTime():DateTime.Now.AddHours(1)};
    var lat=new NumericUpDown {Location=new Point(25,60),Width=145,Minimum=-90,Maximum=90,DecimalPlaces=6,Value=(decimal)(item.Latitude??0)};
    var lon=new NumericUpDown {Location=new Point(185,60),Width=145,Minimum=-180,Maximum=180,DecimalPlaces=6,Value=(decimal)(item.Longitude??0)};
    var radius=new NumericUpDown {Location=new Point(345,60),Width=145,Minimum=1,Maximum=20000000,Value=(decimal)Math.Min(20000000,item.RadiusMeters??500)};
    if(location)form.Controls.AddRange(new Control[] {lat,lon,radius,new Label {Text="Latitude",Location=new Point(25,35)},new Label {Text="Longitude",Location=new Point(185,35)},new Label {Text="Radius (meters)",Location=new Point(345,35)}});
    else form.Controls.AddRange(new Control[] {start,expiry,new Label {Text="Start (optional, local time)",Location=new Point(25,35),AutoSize=true},new Label {Text="Expiry (optional, local time)",Location=new Point(275,35),AutoSize=true}});
    form.Controls.Add(new Label {Text=location?"Replaces the location rule. Recipients must share their device location.":"Changes apply on the next check. Extend expiry within five minutes to restore a suspended viewer.",Location=new Point(25,115),Size=new Size(475,55)});
    var save=Button("Save conditions");save.Location=new Point(25,200);form.Controls.Add(save);
    save.Click+=async (sender,args)=>{save.Enabled=false;try {
     if(location)await auth.ApiClient.PostAsync<PreciseLocationRequest,object>("api/situational/content/"+item.Id+"/location",new PreciseLocationRequest {Latitude=(double)lat.Value,Longitude=(double)lon.Value,RadiusMeters=(double)radius.Value});
     else await auth.ApiClient.PostAsync<TimeWindowRequest,object>("api/situational/content/"+item.Id+"/time",new TimeWindowRequest {StartTime=start.Checked?(DateTime?)start.Value.ToUniversalTime():null,ExpiresAt=expiry.Checked?(DateTime?)expiry.Value.ToUniversalTime():null});
     form.DialogResult=DialogResult.OK;form.Close();
    }catch(Exception ex){MessageBox.Show(ex.Message,"Could not save conditions");save.Enabled=true;}};
    return Task.FromResult(form.ShowDialog(this)==DialogResult.OK);
   }
  }
  Label FieldLabel(string text,int x,int y,bool heading=false)
  {
   var label=Label(text,heading?12:10,heading);
   label.Location=new Point(x,y);
   label.ForeColor=heading?DesktopTheme.Primary:DesktopTheme.Secondary;
   return label;
  }
  async Task Share()
  {
   using(var form=new Form {Text="Share New Content",Size=new Size(1080,740),MinimumSize=new Size(940,520),
    StartPosition=FormStartPosition.CenterParent})
   {
   DesktopTheme.Apply(form);
   var workArea=Screen.FromControl(this).WorkingArea;
   form.Size=new Size(Math.Min(form.Width,workArea.Width),Math.Min(form.Height,workArea.Height));
   var layout=new TableLayoutPanel {Dock=DockStyle.Fill,ColumnCount=2,RowCount=2,Padding=new Padding(16)};
   layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
   layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,500));
   layout.RowStyles.Add(new RowStyle(SizeType.Percent,100));
   layout.RowStyles.Add(new RowStyle(SizeType.Absolute,58));
   form.Controls.Add(layout);

   var composition=new Panel {Dock=DockStyle.Fill,BackColor=DesktopTheme.Surface,AutoScroll=true,Margin=new Padding(0,0,8,0)};
   var restrictions=new Panel {Dock=DockStyle.Fill,BackColor=DesktopTheme.Surface,AutoScroll=true,Margin=new Padding(8,0,0,0)};
   DesktopTheme.RoundCorners(composition);
   DesktopTheme.RoundCorners(restrictions);
   layout.Controls.Add(composition,0,0);
   layout.Controls.Add(restrictions,1,0);
   var contentHeading=Label("Content",16,true);
   contentHeading.ForeColor=DesktopTheme.Primary;
   contentHeading.Location=new Point(20,16);
   var restrictionsHeading=Label("Viewing restrictions",16,true);
   restrictionsHeading.ForeColor=DesktopTheme.Primary;
   restrictionsHeading.Location=new Point(20,16);
   restrictions.Controls.Add(restrictionsHeading);

   var title=new TextBox();
   var recipient=new TextBox();
   var body=new TextBox {Multiline=true,ScrollBars=ScrollBars.Vertical,AcceptsReturn=true};
   var choose=Button("Select PNG/JPEG",160,false);
   var selection=Label("Text content selected");
   selection.AutoSize=false;
   selection.AutoEllipsis=true;
   selection.ForeColor=DesktopTheme.Secondary;
   composition.Controls.AddRange(new Control[] {contentHeading,FieldLabel("Title",20,62),title,
    FieldLabel("Recipient username",20,124),recipient,FieldLabel("Content text",20,186),body,choose,selection});
   Action fitComposition=()=>
   {
    int width=Math.Max(100,composition.ClientSize.Width-40-SystemInformation.VerticalScrollBarWidth);
    int bodyHeight=Math.Max(110,composition.ClientSize.Height-288);
    title.SetBounds(20,86,width,title.PreferredHeight);
    recipient.SetBounds(20,148,width,recipient.PreferredHeight);
    body.SetBounds(20,210,width,bodyHeight);
    choose.Location=new Point(20,220+bodyHeight);
    selection.SetBounds(190,230+bodyHeight,Math.Max(40,width-170),28);
   };
   composition.ClientSizeChanged+=(s,e)=>fitComposition();
   fitComposition();

   string imageData=null;
   string imageType=null;
   choose.Click+=(sender,args)=>
   {
    using(var dialog=new OpenFileDialog {Filter="Images|*.png;*.jpg;*.jpeg",Title="Choose an image"})
    {
     if(dialog.ShowDialog(form)!=DialogResult.OK)return;
     var info=new FileInfo(dialog.FileName);
     if(info.Length>5*1024*1024){MessageBox.Show("Maximum image size is 5 MB.");return;}
     imageData=Convert.ToBase64String(File.ReadAllBytes(dialog.FileName));
     imageType=Path.GetExtension(dialog.FileName).Equals(".png",StringComparison.OrdinalIgnoreCase)?"image/png":"image/jpeg";
     selection.Text=info.Name;
    }
   };

   var start=new DateTimePicker {Location=new Point(20,84),Width=204,Format=DateTimePickerFormat.Custom,
    CustomFormat="yyyy-MM-dd HH:mm",ShowCheckBox=true,Checked=false,Value=DateTime.Now.AddMinutes(5)};
   var expiry=new DateTimePicker {Location=new Point(246,84),Width=204,Format=DateTimePickerFormat.Custom,
    CustomFormat="yyyy-MM-dd HH:mm",ShowCheckBox=true,Checked=false,Value=DateTime.Now.AddDays(7)};
   var max=new NumericUpDown {Location=new Point(20,144),Width=120,Minimum=0,Maximum=1000000};
   var trusted=new CheckBox {Text="Require approved device",Location=new Point(246,143),AutoSize=true};

   var country=new TextBox {Location=new Point(20,233),Width=135};
   var region=new TextBox {Location=new Point(166,233),Width=135};
   var city=new TextBox {Location=new Point(312,233),Width=135};
   var precise=new CheckBox {Text="Require an exact viewing area",Location=new Point(20,275),AutoSize=true};
   var latitude=new NumericUpDown {Location=new Point(20,323),Width=135,Minimum=-90,Maximum=90,DecimalPlaces=6,Enabled=false};
   var longitude=new NumericUpDown {Location=new Point(166,323),Width=135,Minimum=-180,Maximum=180,DecimalPlaces=6,Enabled=false};
   var radius=new NumericUpDown {Location=new Point(312,323),Width=135,Minimum=1,Maximum=20000000,Value=500,Enabled=false};
   precise.CheckedChanged+=(s,e)=>
   {
    latitude.Enabled=longitude.Enabled=radius.Enabled=precise.Checked;
    country.Enabled=region.Enabled=city.Enabled=!precise.Checked;
   };

   var cameraEnabled=new CheckBox {Text="Require camera-based detection for all viewers",Location=new Point(20,406),AutoSize=true};
   var blockPhones=new CheckBox {Text="Hide content when a phone is detected",Location=new Point(38,434),AutoSize=true,Checked=true};
   var blockPeople=new CheckBox {Text="Hide content when multiple people are detected",Location=new Point(38,462),AutoSize=true,Checked=true};
   var requireViewer=new CheckBox {Text="Hide content when no viewer is detected",Location=new Point(38,490),AutoSize=true};
   Action updateCameraOptions=()=>{blockPhones.Enabled=blockPeople.Enabled=requireViewer.Enabled=cameraEnabled.Checked;};
   cameraEnabled.CheckedChanged+=(s,e)=>updateCameraOptions();
   updateCameraOptions();

   restrictions.Controls.AddRange(new Control[]
   {
    FieldLabel("Start time (optional)",20,61),start,FieldLabel("Expiration (optional)",246,61),expiry,
    FieldLabel("Max views (0 = unlimited)",20,121),max,trusted,
    FieldLabel("Allowed location",20,180,true),
    FieldLabel("Country or code",20,210),country,FieldLabel("State or region",166,210),region,FieldLabel("City",312,210),city,
    precise,FieldLabel("Latitude",20,300),latitude,FieldLabel("Longitude",166,300),longitude,
    FieldLabel("Radius (meters)",312,300),radius,
    FieldLabel("Viewers must allow device location sharing.",20,355),
    FieldLabel("Camera protection",20,378,true),cameraEnabled,blockPhones,blockPeople,requireViewer
   });
   foreach(var field in new[] {title,recipient,body,country,region,city})DesktopTheme.StyleInput(field);
   var footer=new FlowLayoutPanel {Dock=DockStyle.Fill,FlowDirection=FlowDirection.RightToLeft,WrapContents=false};
   var submit=Button("Share securely");
   footer.Controls.Add(submit);
   layout.Controls.Add(footer,0,1);
   layout.SetColumnSpan(footer,2);
   submit.Click+=async (s,e)=>{submit.Enabled=false;try{if(cameraEnabled.Checked){var capabilities=await auth.ApiClient.GetAsync<ContentCapabilities>("api/content/capabilities");if(capabilities==null||capabilities.CameraPolicyVersion<1)throw new InvalidOperationException("Update the API before sharing camera-restricted content.");}await auth.ApiClient.PostAsync<CreateContentRequest,SharedContent>("api/content",new CreateContentRequest {CameraRestrictions=new CameraRestrictions {Enabled=cameraEnabled.Checked,BlockPhones=cameraEnabled.Checked&&blockPhones.Checked,BlockMultiplePeople=cameraEnabled.Checked&&blockPeople.Checked,RequireViewer=cameraEnabled.Checked&&requireViewer.Checked},Title=title.Text,Recipient=recipient.Text,Body=body.Text,FileDataBase64=imageData,FileType=imageType,ExpiresAt=expiry.Checked?(DateTime?)expiry.Value.ToUniversalTime():null,StartTime=start.Checked?(DateTime?)start.Value.ToUniversalTime():null,MaxViews=max.Value==0?(int?)null:(int)max.Value,RequireTrustedDevice=trusted.Checked,AllowedCountry=precise.Checked?null:country.Text,AllowedRegion=precise.Checked?null:region.Text,AllowedCity=precise.Checked?null:city.Text,Latitude=precise.Checked?(double?)latitude.Value:null,Longitude=precise.Checked?(double?)longitude.Value:null,RadiusMeters=precise.Checked?(double?)radius.Value:null});form.DialogResult=DialogResult.OK;form.Close();}catch(Exception ex){MessageBox.Show(ex.Message,"Share failed");}finally{if(!submit.IsDisposed)submit.Enabled=true;}};
   if(form.ShowDialog(this)==DialogResult.OK)await LoadContent();
  }}
  async Task Open(SharedContent item) {
   int sessionId=0;
   using(var viewer=new Form {Text="Aperture - "+item.Title,Size=new Size(900,640),MinimumSize=new Size(560,420),StartPosition=FormStartPosition.CenterParent}) {
    DesktopTheme.Apply(viewer);
    viewer.Padding=new Padding(18);
    var heading=Label(item.Title,18,true);heading.ForeColor=DesktopTheme.Primary;heading.AutoEllipsis=true;heading.Dock=DockStyle.Top;heading.Height=60;heading.AutoSize=false;
    var badge=Label("Verifying viewing restrictions...");badge.Dock=DockStyle.Bottom;badge.Height=48;badge.AutoSize=false;
    var text=new TextBox {Multiline=true,ReadOnly=true,Dock=DockStyle.Fill,ScrollBars=ScrollBars.Vertical,Font=new Font("Segoe UI",11),BorderStyle=BorderStyle.None,BackColor=DesktopTheme.Input,ForeColor=ink};
    var picture=new PictureBox {Dock=DockStyle.Fill,SizeMode=PictureBoxSizeMode.Zoom,Visible=false};
    var content=new Panel {Dock=DockStyle.Fill,BackColor=DesktopTheme.Surface,Padding=new Padding(14)};DesktopTheme.RoundCorners(content);content.Controls.Add(text);content.Controls.Add(picture);
    viewer.Controls.Add(content);viewer.Controls.Add(badge);viewer.Controls.Add(heading);
    var guard=CameraGuard.Attach(viewer,badge,ink,new CameraRestrictions {Enabled=false});
    guard.Protect(content);
    guard.SetPolicyStatus(false,"Verifying viewing restrictions...");
    Action clear=()=>{text.Clear();var previous=picture.Image;picture.Image=null;picture.Visible=false;if(previous!=null)previous.Dispose();};
    Action<SessionResult> display=result=>{
     clear();
     if(result.CameraRestrictions==null)throw new InvalidDataException("Server camera policy is missing. Update the API.");
     guard.ApplyRestrictions(result.CameraRestrictions);
     if(result.FileType=="image/png" || result.FileType=="image/jpeg") {
      var bytes=Convert.FromBase64String(result.FileDataBase64);
      using(var stream=new MemoryStream(bytes))using(var original=Image.FromStream(stream))picture.Image=new Bitmap(original);
      text.Visible=false;picture.Visible=true;picture.BringToFront();
     }else{text.Visible=true;text.Text=result.Body;}
     guard.SetPolicyStatus(true,null);
    };
    var location=new ClientLocationService();
    var shareLocation=new CheckBox {Text="Share device location while viewing (Windows location permission required)",Dock=DockStyle.Bottom,Height=28,Checked=item.Latitude.HasValue};
    shareLocation.CheckedChanged+=(s,e)=>{if(shareLocation.Checked)location.Start();else location.Stop();};
    viewer.Controls.Add(shareLocation);if(shareLocation.Checked)location.Start();
    var hide=Button("Hide for 30 seconds",180,false);hide.Dock=DockStyle.Bottom;viewer.Controls.Add(hide);
    var timer=new Timer {Interval=5000};bool checking=false;
    Func<Task> check=async ()=>{
     if(checking||viewer.IsDisposed)return;
     checking=true;timer.Stop();
     try {
      var result=sessionId==0
       ? await auth.ApiClient.PostAsync<SessionRequest,SessionResult>("api/content/"+item.Id+"/sessions",new SessionRequest {DeviceKey=DeviceKey(),CameraPolicyVersion=1},location.Current)
       : await auth.ApiClient.PostAsync<object,SessionResult>("api/content/sessions/"+sessionId+"/check",new object(),location.Current);
      if(result==null)throw new InvalidDataException("Empty verification response.");
      if(result.AccessGranted)sessionId=result.SessionId;
      else if(result.SessionEnded || !result.Suspended)sessionId=0; // Suspended sessions keep their view count and can recover.
      if(viewer.IsDisposed)return;
      if(!result.AccessGranted){guard.SetPolicyStatus(false,result.Message);clear();return;}
      display(result);
     }catch(Exception){if(!viewer.IsDisposed){guard.SetPolicyStatus(false,"Unable to verify with server. Retrying automatically...");clear();}}
     finally{checking=false;if(!viewer.IsDisposed)timer.Start();}
    };
    hide.Click+=async (s,e)=>{if(sessionId==0||checking)return;hide.Enabled=false;checking=true;timer.Stop();try {
     guard.SetPolicyStatus(false,"Session suspended for 30 seconds.");clear();
     await auth.ApiClient.PostAsync<SuspendSessionRequest,object>("api/situational/sessions/"+sessionId+"/suspend",new SuspendSessionRequest {Reason="Viewer requested a pause",DurationSeconds=30});
    }catch(Exception ex){MessageBox.Show(ex.Message,"Could not suspend session");}finally{checking=false;if(!hide.IsDisposed){hide.Enabled=true;timer.Start();}}};
    timer.Tick+=async (s,e)=>await check();
    viewer.Shown+=async (s,e)=>await check();
    viewer.FormClosed+=(s,e)=>{timer.Dispose();location.Dispose();clear();};
    viewer.ShowDialog(this);
    // A pending open request can finish after the viewer closes. Wait for its
    // session ID so that it is ended too, without touching disposed controls.
    while(checking)await Task.Delay(50);
   }
   if(sessionId!=0)try{await auth.ApiClient.PostAsync("api/content/sessions/"+sessionId+"/end");}catch{ }
  }
 }
}
