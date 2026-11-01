using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Data;
using MySql.Data.MySqlClient;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Web;
using System.Web.Http;
using Aperture_WebAPI.Config;
using Aperture_WebAPI.Filters;
using Aperture_WebAPI.Infrastructure;
using Aperture_WebAPI.Models;
using Aperture_WebAPI.Services;
using Newtonsoft.Json;

namespace Aperture_WebAPI.Controllers {
 [RoutePrefix("api/content"),TokenAuthorize]
 public class ContentController : ApiController {
  // The approved schema does not contain device/IP columns on ViewingSession.
  // Keep both bindings in the same worker process as the login tokens.
  sealed class SessionBinding {public Guid DeviceKey;public string IpAddress;public int CameraPolicyVersion;}
  static readonly ConcurrentDictionary<int,SessionBinding> SessionBindings=new ConcurrentDictionary<int,SessionBinding>();
  static string StorageRoot {get {var path=HttpContext.Current.Server.MapPath("~/App_Data/ContentFiles");Directory.CreateDirectory(path);return path;}}
  static string StoragePath(int id) {return Path.Combine(StorageRoot,id.ToString()+".bin");}
  static SessionResult ReadContent(int id,string title,string fileType) {
   var bytes=File.ReadAllBytes(StoragePath(id));
   return fileType=="text/plain" ? new SessionResult {AccessGranted=true,Message="Access granted.",Title=title,FileType=fileType,Body=System.Text.Encoding.UTF8.GetString(bytes)} :
    new SessionResult {AccessGranted=true,Message="Access granted.",Title=title,FileType=fileType,FileDataBase64=Convert.ToBase64String(bytes)};
  }
  static MySqlCommand Command(MySqlConnection db,MySqlTransaction tx,string sql) {return new MySqlCommand(sql,db,tx);}
  static void Param(MySqlCommand c,string n,object value) {c.Parameters.AddWithValue(n,value??DBNull.Value);}
  [HttpGet,Route("capabilities")]
  public IHttpActionResult Capabilities() {return Ok(new {CameraPolicyVersion=1});}
  [HttpGet,Route("")]
  public IHttpActionResult List() {
   var items=new List<SharedContent>();
   using(var db=new MySqlConnection(ConnectionStrings.Database)) {db.Open();using(var c=new MySqlCommand(@"SELECT c.ContentID,c.File_Name,u.Username,c.Upload_Date,0,r.Access_Status,NULL AS Recipient,p.PolicyStatus FROM ContentRecipient r JOIN Content c ON c.ContentID=r.ContentID JOIN Users u ON u.UserID=c.SenderID JOIN AccessPolicy p ON p.ContentID=c.ContentID WHERE r.UserID=@user UNION ALL SELECT c.ContentID,c.File_Name,u.Username,c.Upload_Date,1,r.Access_Status,recipient.Username,p.PolicyStatus FROM ContentRecipient r JOIN Content c ON c.ContentID=r.ContentID JOIN Users u ON u.UserID=c.SenderID JOIN Users recipient ON recipient.UserID=r.UserID JOIN AccessPolicy p ON p.ContentID=c.ContentID WHERE c.SenderID=@user ORDER BY Upload_Date DESC",db)) {
    Param(c,"@user",RequestUser.Get().Id);using(var r=c.ExecuteReader())while(r.Read()) {items.Add(new SharedContent {Id=r.GetInt32(0),Title=r.GetString(1),Owner=r.GetString(2),CreatedAt=r.GetDateTime(3),Mine=r.GetBoolean(4),Status=r.GetString(5),Recipient=r.IsDBNull(6)?null:r.GetString(6),PolicyStatus=r.GetString(7)});}
   }}return Ok(items);
  }
  [HttpPost,Route("")]
  public IHttpActionResult Create(CreateContentRequest request) {
   if(request==null || string.IsNullOrWhiteSpace(request.Title) || string.IsNullOrWhiteSpace(request.Recipient) || request.Title.Length>160 ||
      (request.MaxViews.HasValue && request.MaxViews<1) ||
      (request.StartTime.HasValue && request.ExpiresAt.HasValue && request.ExpiresAt<=request.StartTime) ||
      (request.ExpiresAt.HasValue && request.ExpiresAt<=DateTime.UtcNow))
      return BadRequest("Title, recipient and valid policy are required. Maximum views must be positive or unlimited.");
   var camera=request.CameraRestrictions ?? new CameraRestrictions();
   if(!camera.Enabled) {camera.BlockPhones=false;camera.BlockMultiplePeople=false;camera.RequireViewer=false;}
   byte[] bytes;string fileType;
   LocationPolicy location=null;
   if(!String.IsNullOrWhiteSpace(request.AllowedCountry) || !String.IsNullOrWhiteSpace(request.AllowedRegion) || !String.IsNullOrWhiteSpace(request.AllowedCity)) {
    location=new LocationPolicy {Country=TrimOrNull(request.AllowedCountry),Region=TrimOrNull(request.AllowedRegion),City=TrimOrNull(request.AllowedCity)};

   }
   if(!string.IsNullOrWhiteSpace(request.FileDataBase64)) {
    if(request.FileType!="image/png" && request.FileType!="image/jpeg")return BadRequest("Only PNG or JPEG images are supported.");
    if(request.FileDataBase64.Length>7500000)return BadRequest("Image exceeds 5 MB.");
    try{bytes=Convert.FromBase64String(request.FileDataBase64);}catch(FormatException){return BadRequest("Invalid image data.");}
    if(bytes.Length>5*1024*1024 || !ValidImage(bytes,request.FileType))return BadRequest("Invalid PNG/JPEG or image exceeds 5 MB.");
    fileType=request.FileType;
   } else {
    if(string.IsNullOrWhiteSpace(request.Body) || request.Body.Length>10000)return BadRequest("Text is required (up to 10000 characters).");
    bytes=System.Text.Encoding.UTF8.GetBytes(request.Body);fileType="text/plain";
   }
   int newId=0;bool committed=false;
   try{using(var db=new MySqlConnection(ConnectionStrings.Database)) {db.Open();using(var tx=db.BeginTransaction()) {try {
    int recipient;using(var c=Command(db,tx,"SELECT UserID FROM Users WHERE Username=@name AND UserID<>@sender")) {Param(c,"@name",request.Recipient.Trim());Param(c,"@sender",RequestUser.Get().Id);var v=c.ExecuteScalar();if(v==null){tx.Rollback();return BadRequest("Recipient not found.");}recipient=(int)v;}
    using(var c=Command(db,tx,"INSERT INTO Content(SenderID,File_Type,File_Name,Upload_Date) VALUES(@sender,@type,@name,UTC_TIMESTAMP())")) {Param(c,"@sender",RequestUser.Get().Id);Param(c,"@type",fileType);Param(c,"@name",request.Title.Trim());c.ExecuteNonQuery();newId=checked((int)c.LastInsertedId);}
    using(var c=Command(db,tx,"INSERT INTO ContentRecipient(UserID,ContentID,Access_Status,Date_Shared) VALUES(@recipient,@id,'Active',UTC_TIMESTAMP())")) {Param(c,"@recipient",recipient);Param(c,"@id",newId);c.ExecuteNonQuery();}
    var requirements=new ViewingRequirements {StartTime=request.StartTime,ExpiresAt=request.ExpiresAt,MaxViews=request.MaxViews,RequireTrustedDevice=request.RequireTrustedDevice,ScreenshotRestriction=request.ScreenshotRestriction,Location=location,CameraRestrictions=camera};
    using(var c=Command(db,tx,"INSERT INTO AccessPolicy(ContentID,PolicyStatus,Requirements,DateCreated) VALUES(@id,'Active',@requirements,UTC_TIMESTAMP())")) {Param(c,"@id",newId);Param(c,"@requirements",JsonConvert.SerializeObject(requirements));c.ExecuteNonQuery();}
    File.WriteAllBytes(StoragePath(newId),bytes);
    tx.Commit();committed=true;return Ok(new {id=newId});
   }catch{tx.Rollback();throw;}}}}
   finally{if(!committed && newId!=0){var path=StoragePath(newId);if(File.Exists(path))File.Delete(path);}}
  }
  static bool ValidImage(byte[] bytes,string type) {
   if(bytes.Length<8)return false;
   bool signature=type=="image/png" ? bytes[0]==137 && bytes[1]==80 && bytes[2]==78 && bytes[3]==71 && bytes[4]==13 && bytes[5]==10 && bytes[6]==26 && bytes[7]==10 : bytes[0]==255 && bytes[1]==216 && bytes[bytes.Length-2]==255 && bytes[bytes.Length-1]==217;
   if(!signature)return false;
   try {using(var stream=new MemoryStream(bytes))using(var image=System.Drawing.Image.FromStream(stream,true,true)) {return image.Width>0 && image.Height>0 && (long)image.Width*image.Height<=50000000;}}
   catch(ArgumentException){return false;}
   catch(OutOfMemoryException){return false;}
  }
  static string TrimOrNull(string value){return String.IsNullOrWhiteSpace(value)?null:value.Trim();}
  [HttpPost,Route("{id:int}/policy")]
  public IHttpActionResult UpdatePolicy(int id,PolicyUpdate request) {
   if(request==null || (request.Status!="Active" && request.Status!="Paused"))return BadRequest("Status must be Active or Paused.");
   using(var db=new MySqlConnection(ConnectionStrings.Database)) {db.Open();using(var tx=db.BeginTransaction()) {try {
    using(var c=Command(db,tx,"UPDATE AccessPolicy p JOIN Content c ON c.ContentID=p.ContentID SET p.PolicyStatus=@status WHERE c.ContentID=@id AND c.SenderID=@owner")) {Param(c,"@status",request.Status);Param(c,"@id",id);Param(c,"@owner",RequestUser.Get().Id);if(c.ExecuteNonQuery()==0){tx.Rollback();return NotFound();}}
    if(request.Status=="Paused")using(var c=Command(db,tx,"UPDATE ViewingSession s JOIN ContentRecipient r ON r.RecipientID=s.RecipientID SET s.Session_Status='Revoked',s.Session_End=UTC_TIMESTAMP() WHERE r.ContentID=@id AND Session_Status='Active'")){Param(c,"@id",id);c.ExecuteNonQuery();}
    tx.Commit();return Ok(new {status=request.Status});
   }catch{tx.Rollback();throw;}}}
  }
  [HttpPost,Route("{id:int}/revoke")]
  public IHttpActionResult Revoke(int id) {
   using(var db=new MySqlConnection(ConnectionStrings.Database)) {db.Open();using(var tx=db.BeginTransaction()) {try {
    using(var c=Command(db,tx,"UPDATE ContentRecipient r JOIN Content c ON c.ContentID=r.ContentID SET r.Access_Status='Revoked' WHERE c.ContentID=@id AND c.SenderID=@owner")) {Param(c,"@id",id);Param(c,"@owner",RequestUser.Get().Id);if(c.ExecuteNonQuery()==0){tx.Rollback();return NotFound();}}
    using(var c=Command(db,tx,"UPDATE ViewingSession s JOIN ContentRecipient r ON r.RecipientID=s.RecipientID SET s.Session_Status='Revoked',s.Session_End=UTC_TIMESTAMP() WHERE r.ContentID=@id AND Session_Status='Active'")) {Param(c,"@id",id);c.ExecuteNonQuery();}
    tx.Commit();return Ok(new {success=true});
   }catch{tx.Rollback();throw;}}}
  }
  [HttpPost,Route("{id:int}/sessions")]
  public IHttpActionResult Open(int id,SessionRequest request) {
   if(request==null || request.DeviceKey==Guid.Empty)return BadRequest("Device key required.");
   string currentIp=GetRemoteIp(Request);
   if(currentIp==null)return Content(HttpStatusCode.Forbidden,new SessionResult {AccessGranted=false,Message="The API could not verify the client IP address."});
   using(var db=new MySqlConnection(ConnectionStrings.Database)) {db.Open();using(var tx=db.BeginTransaction(IsolationLevel.Serializable)) {try {
    int recipient;using(var c=Command(db,tx,"SELECT RecipientID FROM ContentRecipient WHERE ContentID=@id AND UserID=@user AND Access_Status='Active' FOR UPDATE")) {Param(c,"@id",id);Param(c,"@user",RequestUser.Get().Id);var v=c.ExecuteScalar();if(v==null){tx.Rollback();return NotFound();}recipient=(int)v;}
    var result=Evaluate(db,tx,id,recipient,request.DeviceKey,currentIp,false,request.CameraPolicyVersion);if(!result.AccessGranted){tx.Commit();return Content(HttpStatusCode.Forbidden,result);}
    using(var c=Command(db,tx,"INSERT INTO ViewingSession(RecipientID,Session_Start,Session_Status) VALUES(@recipient,UTC_TIMESTAMP(),'Active')")) {Param(c,"@recipient",recipient);c.ExecuteNonQuery();result.SessionId=checked((int)c.LastInsertedId);}
    RecordCheck(db,tx,result.SessionId,true,true,result.DeviceVerified,null);tx.Commit();
    SessionBindings[result.SessionId]=new SessionBinding {DeviceKey=request.DeviceKey,IpAddress=currentIp,CameraPolicyVersion=request.CameraPolicyVersion};
    return Ok(result);
   }catch{tx.Rollback();throw;}}}
  }
  [HttpPost,Route("sessions/{sessionId:int}/check")]
  public IHttpActionResult Check(int sessionId) {
   SessionBinding binding;if(!SessionBindings.TryGetValue(sessionId,out binding))return Content(HttpStatusCode.Forbidden,new SessionResult {AccessGranted=false,Message="Session expired; open the content again."});
   using(var db=new MySqlConnection(ConnectionStrings.Database)) {db.Open();using(var tx=db.BeginTransaction(IsolationLevel.Serializable)) {try {
    int id,recipient;using(var c=Command(db,tx,@"SELECT r.ContentID,s.RecipientID FROM ViewingSession s JOIN ContentRecipient r ON r.RecipientID=s.RecipientID WHERE s.SessionID=@session AND r.UserID=@user AND s.Session_Status='Active' FOR UPDATE")) {Param(c,"@session",sessionId);Param(c,"@user",RequestUser.Get().Id);using(var r=c.ExecuteReader()){if(!r.Read()){tx.Rollback();return NotFound();}id=r.GetInt32(0);recipient=r.GetInt32(1);}}
    string currentIp=GetRemoteIp(Request);
    bool ipVerified=currentIp!=null && String.Equals(binding.IpAddress,currentIp,StringComparison.OrdinalIgnoreCase);
    var result=ipVerified ? Evaluate(db,tx,id,recipient,binding.DeviceKey,currentIp,true,binding.CameraPolicyVersion) : Deny("Client IP address changed during the viewing session.");
    result.SessionId=sessionId;RecordCheck(db,tx,sessionId,result.AccessGranted,ipVerified&&result.LocationVerified,result.DeviceVerified,result.AccessGranted?null:result.Message);
    if(!result.AccessGranted){EndSession(db,tx,sessionId,"Revoked");SessionBinding old;SessionBindings.TryRemove(sessionId,out old);}
    tx.Commit();return Ok(result);
   }catch{tx.Rollback();throw;}}}
  }
  [HttpPost,Route("sessions/{sessionId:int}/end")]
  public IHttpActionResult End(int sessionId) {
   using(var db=new MySqlConnection(ConnectionStrings.Database)) {db.Open();using(var c=new MySqlCommand(@"UPDATE ViewingSession s JOIN ContentRecipient r ON r.RecipientID=s.RecipientID SET s.Session_Status='Ended',s.Session_End=UTC_TIMESTAMP() WHERE s.SessionID=@session AND r.UserID=@user AND s.Session_Status='Active'",db)) {Param(c,"@session",sessionId);Param(c,"@user",RequestUser.Get().Id);if(c.ExecuteNonQuery()==0)return NotFound();SessionBinding old;SessionBindings.TryRemove(sessionId,out old);return Ok(new {success=true});}}
  }
  static void EndSession(MySqlConnection db,MySqlTransaction tx,int session,string status) {using(var c=Command(db,tx,"UPDATE ViewingSession SET Session_Status=@status,Session_End=UTC_TIMESTAMP() WHERE SessionID=@session AND Session_Status='Active'")) {Param(c,"@status",status);Param(c,"@session",session);c.ExecuteNonQuery();}}
  static void RecordCheck(MySqlConnection db,MySqlTransaction tx,int session,bool allowed,bool ipVerified,bool deviceVerified,string reason) {using(var c=Command(db,tx,"INSERT INTO EnvironmentCheck(Check_Timestamp,SessionID,ViewCount,LocationVerified,DeviceVerified,PolicySatisfied,ViolationType) SELECT UTC_TIMESTAMP(),@session,(SELECT COUNT(*) FROM ViewingSession WHERE RecipientID=s.RecipientID),@ip,@device,@ok,@reason FROM ViewingSession s WHERE s.SessionID=@session")) {Param(c,"@session",session);Param(c,"@ip",ipVerified);Param(c,"@device",deviceVerified);Param(c,"@ok",allowed);Param(c,"@reason",reason);c.ExecuteNonQuery();}}
  static string GetRemoteIp(HttpRequestMessage request) {
   string value=null;
   if(request!=null && request.Properties.ContainsKey("MS_HttpContext")) {
    dynamic context=request.Properties["MS_HttpContext"];
    value=context==null?null:context.Request.UserHostAddress;
   }
   if(String.IsNullOrWhiteSpace(value) && HttpContext.Current!=null)value=HttpContext.Current.Request.UserHostAddress;
   IPAddress address;
   if(IPAddress.TryParse(value,out address)) {
    if(IPAddress.IsLoopback(address))return "loopback";
    if(address.IsIPv4MappedToIPv6)address=address.MapToIPv4();
    return address.ToString();
   }
   return String.IsNullOrWhiteSpace(value)?null:value.Trim();
  }
  static SessionResult Evaluate(MySqlConnection db,MySqlTransaction tx,int id,int recipient,Guid device,string clientIp,bool existing,int cameraPolicyVersion) {
   using(var c=Command(db,tx,@"SELECT c.File_Name,c.File_Type,r.Access_Status,p.PolicyStatus,p.Requirements,CASE WHEN EXISTS(SELECT 1 FROM TrustedDevices d WHERE d.UserID=r.UserID AND d.DeviceType=@device AND d.IsTrusted=1) THEN 1 ELSE 0 END,(SELECT COUNT(*) FROM ViewingSession s WHERE s.RecipientID=r.RecipientID) FROM Content c JOIN ContentRecipient r ON r.ContentID=c.ContentID JOIN AccessPolicy p ON p.ContentID=c.ContentID WHERE c.ContentID=@id AND r.RecipientID=@recipient")) {Param(c,"@id",id);Param(c,"@recipient",recipient);Param(c,"@device","Desktop:"+device.ToString("D"));using(var r=c.ExecuteReader()) {
    if(!r.Read())return Deny("Content or policy not found.");string reason=null;bool locationVerified=true;var now=DateTime.UtcNow;
    ViewingRequirements policy;
    try {policy=ViewingRequirements.Parse(r.IsDBNull(4)?null:r.GetString(4));}
    catch(JsonException) {return Deny("The viewing requirements are invalid.");}
    if(r.GetString(2)!="Active" || r.GetString(3)!="Active")reason="Access has been revoked.";
    else if(policy.StartTime.HasValue && now<policy.StartTime.Value)reason="Access has not begun.";
    else if(policy.ExpiresAt.HasValue && now>=policy.ExpiresAt.Value)reason="Access has expired.";
    else if(!existing && policy.MaxViews.HasValue && r.GetInt64(6)>=policy.MaxViews.Value)reason="Maximum views reached.";
    else if(policy.RequireTrustedDevice && r.GetInt32(5)==0)reason="Approved device required.";
    else if(policy.Location!=null) {
     var verification=IpGeolocationService.Verify(clientIp,policy.Location);locationVerified=verification.Success&&verification.Matches;if(!locationVerified)reason=verification.Message;
    }
    var camera=policy.CameraRestrictions ?? new CameraRestrictions();
    if(reason==null && !camera.SupportsClient(cameraPolicyVersion))reason="This content requires camera protection. Use an updated Aperture desktop client.";
    if(reason==null && policy.ScreenshotRestriction)reason="Screenshot restriction cannot be enforced by this desktop client.";
    if(reason!=null)return new SessionResult {AccessGranted=false,Message=reason,DeviceVerified=r.GetInt32(5)!=0,LocationVerified=locationVerified,CameraRestrictions=camera};
    try{var result=ReadContent(id,r.GetString(0),r.GetString(1));result.DeviceVerified=r.GetInt32(5)!=0;result.LocationVerified=locationVerified;result.CameraRestrictions=camera;return result;}
    catch(IOException){return Deny("Content file is unavailable.");}
   }}
  }
  static SessionResult Deny(string message){return new SessionResult {AccessGranted=false,Message=message};}
 }
}
