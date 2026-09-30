using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
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
  sealed class SessionBinding {public Guid DeviceKey;public string IpAddress;}
  static readonly ConcurrentDictionary<int,SessionBinding> SessionBindings=new ConcurrentDictionary<int,SessionBinding>();
  static string StorageRoot {get {var path=HttpContext.Current.Server.MapPath("~/App_Data/ContentFiles");Directory.CreateDirectory(path);return path;}}
  static string StoragePath(int id) {return Path.Combine(StorageRoot,id.ToString()+".bin");}
  static SessionResult ReadContent(int id,string title,string fileType) {
   var bytes=File.ReadAllBytes(StoragePath(id));
   return fileType=="text/plain" ? new SessionResult {AccessGranted=true,Message="Access granted.",Title=title,FileType=fileType,Body=System.Text.Encoding.UTF8.GetString(bytes)} :
    new SessionResult {AccessGranted=true,Message="Access granted.",Title=title,FileType=fileType,FileDataBase64=Convert.ToBase64String(bytes)};
  }
  static SqlCommand Command(SqlConnection db,SqlTransaction tx,string sql) {return new SqlCommand(sql,db,tx);}
  static void Param(SqlCommand c,string n,object value) {c.Parameters.AddWithValue(n,value??DBNull.Value);}
  [HttpGet,Route("")]
  public IHttpActionResult List() {
   var items=new List<SharedContent>();
   using(var db=new SqlConnection(ConnectionStrings.Database)) {db.Open();using(var c=new SqlCommand(@"SELECT c.ContentID,c.FileName,u.Username,c.UploadDate,CAST(0 AS bit),r.AccessStatus,CAST(NULL AS varchar(100)) AS Recipient,p.PolicyStatus FROM ContentRecipient r JOIN Content c ON c.ContentID=r.ContentID JOIN Users u ON u.UserID=c.SenderID JOIN AccessPolicy p ON p.ContentID=c.ContentID WHERE r.UserID=@user UNION ALL SELECT c.ContentID,c.FileName,u.Username,c.UploadDate,CAST(1 AS bit),r.AccessStatus,recipient.Username,p.PolicyStatus FROM ContentRecipient r JOIN Content c ON c.ContentID=r.ContentID JOIN Users u ON u.UserID=c.SenderID JOIN Users recipient ON recipient.UserID=r.UserID JOIN AccessPolicy p ON p.ContentID=c.ContentID WHERE c.SenderID=@user ORDER BY UploadDate DESC",db)) {
    Param(c,"@user",RequestUser.Get().Id);using(var r=c.ExecuteReader())while(r.Read()) {items.Add(new SharedContent {Id=r.GetInt32(0),Title=r.GetString(1),Owner=r.GetString(2),CreatedAt=r.GetDateTime(3),Mine=r.GetBoolean(4),Status=r.GetString(5),Recipient=r.IsDBNull(6)?null:r.GetString(6),PolicyStatus=r.GetString(7)});}
   }}return Ok(items);
  }
  [HttpPost,Route("")]
  public IHttpActionResult Create(CreateContentRequest request) {
   if(request==null || string.IsNullOrWhiteSpace(request.Title) || string.IsNullOrWhiteSpace(request.Recipient) || request.Title.Length>160 ||
      (request.MaxViews.HasValue && request.MaxViews!=1) ||
      (request.StartTime.HasValue && request.ExpiresAt.HasValue && request.ExpiresAt<=request.StartTime) ||
      (request.ExpiresAt.HasValue && request.ExpiresAt<=DateTime.UtcNow))
      return BadRequest("Title, recipient and valid policy are required. Maximum views is unlimited or one.");
   byte[] bytes;string fileType;
   string requiredLocation=null;
   if(!String.IsNullOrWhiteSpace(request.AllowedCountry) || !String.IsNullOrWhiteSpace(request.AllowedRegion) || !String.IsNullOrWhiteSpace(request.AllowedCity)) {
    requiredLocation=JsonConvert.SerializeObject(new LocationPolicy {Country=TrimOrNull(request.AllowedCountry),Region=TrimOrNull(request.AllowedRegion),City=TrimOrNull(request.AllowedCity)});
    if(requiredLocation.Length>255)return BadRequest("The geographic restriction is too long.");
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
   try{using(var db=new SqlConnection(ConnectionStrings.Database)) {db.Open();using(var tx=db.BeginTransaction()) {try {
    int recipient;using(var c=Command(db,tx,"SELECT UserID FROM Users WHERE Username=@name AND UserID<>@sender")) {Param(c,"@name",request.Recipient.Trim());Param(c,"@sender",RequestUser.Get().Id);var v=c.ExecuteScalar();if(v==null){tx.Rollback();return BadRequest("Recipient not found.");}recipient=(int)v;}
    using(var c=Command(db,tx,"INSERT INTO Content(SenderID,FileType,FileName) OUTPUT INSERTED.ContentID VALUES(@sender,@type,@name)")) {Param(c,"@sender",RequestUser.Get().Id);Param(c,"@type",fileType);Param(c,"@name",request.Title.Trim());newId=(int)c.ExecuteScalar();}
    using(var c=Command(db,tx,"INSERT INTO ContentRecipient(UserID,ContentID,AccessStatus) VALUES(@recipient,@id,'Active')")) {Param(c,"@recipient",recipient);Param(c,"@id",newId);c.ExecuteNonQuery();}
    using(var c=Command(db,tx,"INSERT INTO AccessPolicy(ContentID,StartTime,ExpirationDate,RequiredLocation,TrustedDevice,MaximumViews,ScreenshotRestriction) VALUES(@id,@start,@expiry,@location,@trusted,@views,@screen)")) {Param(c,"@id",newId);Param(c,"@start",request.StartTime);Param(c,"@expiry",request.ExpiresAt);Param(c,"@location",requiredLocation);Param(c,"@trusted",request.RequireTrustedDevice);Param(c,"@views",request.MaxViews==1);Param(c,"@screen",request.ScreenshotRestriction);c.ExecuteNonQuery();}
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
   using(var db=new SqlConnection(ConnectionStrings.Database)) {db.Open();using(var tx=db.BeginTransaction()) {try {
    using(var c=Command(db,tx,"UPDATE p SET PolicyStatus=@status FROM AccessPolicy p JOIN Content c ON c.ContentID=p.ContentID WHERE c.ContentID=@id AND c.SenderID=@owner")) {Param(c,"@status",request.Status);Param(c,"@id",id);Param(c,"@owner",RequestUser.Get().Id);if(c.ExecuteNonQuery()==0){tx.Rollback();return NotFound();}}
    if(request.Status=="Paused")using(var c=Command(db,tx,"UPDATE ViewingSession SET SessionStatus='Revoked',SessionEnd=GETUTCDATE() WHERE ContentID=@id AND SessionStatus='Active'")){Param(c,"@id",id);c.ExecuteNonQuery();}
    tx.Commit();return Ok(new {status=request.Status});
   }catch{tx.Rollback();throw;}}}
  }
  [HttpPost,Route("{id:int}/revoke")]
  public IHttpActionResult Revoke(int id) {
   using(var db=new SqlConnection(ConnectionStrings.Database)) {db.Open();using(var tx=db.BeginTransaction()) {try {
    using(var c=Command(db,tx,"UPDATE r SET AccessStatus='Revoked' FROM ContentRecipient r JOIN Content c ON c.ContentID=r.ContentID WHERE c.ContentID=@id AND c.SenderID=@owner")) {Param(c,"@id",id);Param(c,"@owner",RequestUser.Get().Id);if(c.ExecuteNonQuery()==0){tx.Rollback();return NotFound();}}
    using(var c=Command(db,tx,"UPDATE ViewingSession SET SessionStatus='Revoked',SessionEnd=GETUTCDATE() WHERE ContentID=@id AND SessionStatus='Active'")) {Param(c,"@id",id);c.ExecuteNonQuery();}
    tx.Commit();return Ok(new {success=true});
   }catch{tx.Rollback();throw;}}}
  }
  [HttpPost,Route("{id:int}/sessions")]
  public IHttpActionResult Open(int id,SessionRequest request) {
   if(request==null || request.DeviceKey==Guid.Empty)return BadRequest("Device key required.");
   string currentIp=GetRemoteIp(Request);
   if(currentIp==null)return Content(HttpStatusCode.Forbidden,new SessionResult {AccessGranted=false,Message="The API could not verify the client IP address."});
   using(var db=new SqlConnection(ConnectionStrings.Database)) {db.Open();using(var tx=db.BeginTransaction(IsolationLevel.Serializable)) {try {
    int recipient;using(var c=Command(db,tx,"SELECT RecipientID FROM ContentRecipient WITH (UPDLOCK,HOLDLOCK) WHERE ContentID=@id AND UserID=@user AND AccessStatus='Active'")) {Param(c,"@id",id);Param(c,"@user",RequestUser.Get().Id);var v=c.ExecuteScalar();if(v==null){tx.Rollback();return NotFound();}recipient=(int)v;}
    var result=Evaluate(db,tx,id,recipient,request.DeviceKey,currentIp,false);if(!result.AccessGranted){tx.Commit();return Content(HttpStatusCode.Forbidden,result);}
    using(var c=Command(db,tx,"INSERT INTO ViewingSession(RecipientID,ContentID) OUTPUT INSERTED.SessionID VALUES(@recipient,@id)")) {Param(c,"@recipient",recipient);Param(c,"@id",id);result.SessionId=(int)c.ExecuteScalar();}
    RecordCheck(db,tx,result.SessionId,true,true,result.DeviceVerified,null);tx.Commit();
    SessionBindings[result.SessionId]=new SessionBinding {DeviceKey=request.DeviceKey,IpAddress=currentIp};
    return Ok(result);
   }catch{tx.Rollback();throw;}}}
  }
  [HttpPost,Route("sessions/{sessionId:int}/check")]
  public IHttpActionResult Check(int sessionId) {
   SessionBinding binding;if(!SessionBindings.TryGetValue(sessionId,out binding))return Content(HttpStatusCode.Forbidden,new SessionResult {AccessGranted=false,Message="Session expired; open the content again."});
   using(var db=new SqlConnection(ConnectionStrings.Database)) {db.Open();using(var tx=db.BeginTransaction(IsolationLevel.Serializable)) {try {
    int id,recipient;using(var c=Command(db,tx,@"SELECT s.ContentID,s.RecipientID FROM ViewingSession s WITH (UPDLOCK,HOLDLOCK) JOIN ContentRecipient r ON r.RecipientID=s.RecipientID WHERE s.SessionID=@session AND r.UserID=@user AND s.SessionStatus='Active'")) {Param(c,"@session",sessionId);Param(c,"@user",RequestUser.Get().Id);using(var r=c.ExecuteReader()){if(!r.Read()){tx.Rollback();return NotFound();}id=r.GetInt32(0);recipient=r.GetInt32(1);}}
    string currentIp=GetRemoteIp(Request);
    bool ipVerified=currentIp!=null && String.Equals(binding.IpAddress,currentIp,StringComparison.OrdinalIgnoreCase);
    var result=ipVerified ? Evaluate(db,tx,id,recipient,binding.DeviceKey,currentIp,true) : Deny("Client IP address changed during the viewing session.");
    result.SessionId=sessionId;RecordCheck(db,tx,sessionId,result.AccessGranted,ipVerified&&result.LocationVerified,result.DeviceVerified,result.AccessGranted?null:result.Message);
    if(!result.AccessGranted){EndSession(db,tx,sessionId,"Revoked");SessionBinding old;SessionBindings.TryRemove(sessionId,out old);}
    tx.Commit();return Ok(result);
   }catch{tx.Rollback();throw;}}}
  }
  [HttpPost,Route("sessions/{sessionId:int}/end")]
  public IHttpActionResult End(int sessionId) {
   using(var db=new SqlConnection(ConnectionStrings.Database)) {db.Open();using(var c=new SqlCommand(@"UPDATE s SET SessionStatus='Ended',SessionEnd=GETUTCDATE() FROM ViewingSession s JOIN ContentRecipient r ON r.RecipientID=s.RecipientID WHERE s.SessionID=@session AND r.UserID=@user AND s.SessionStatus='Active'",db)) {Param(c,"@session",sessionId);Param(c,"@user",RequestUser.Get().Id);if(c.ExecuteNonQuery()==0)return NotFound();SessionBinding old;SessionBindings.TryRemove(sessionId,out old);return Ok(new {success=true});}}
  }
  static void EndSession(SqlConnection db,SqlTransaction tx,int session,string status) {using(var c=Command(db,tx,"UPDATE ViewingSession SET SessionStatus=@status,SessionEnd=GETUTCDATE() WHERE SessionID=@session AND SessionStatus='Active'")) {Param(c,"@status",status);Param(c,"@session",session);c.ExecuteNonQuery();}}
  static void RecordCheck(SqlConnection db,SqlTransaction tx,int session,bool allowed,bool ipVerified,bool deviceVerified,string reason) {using(var c=Command(db,tx,"INSERT INTO EnvironmentCheck(SessionID,ViewCount,LocationVerified,DeviceVerified,PolicySatisfied,ViolationType) SELECT @session,(SELECT COUNT(*) FROM ViewingSession WHERE RecipientID=s.RecipientID),@ip,@device,@ok,@reason FROM ViewingSession s WHERE s.SessionID=@session")) {Param(c,"@session",session);Param(c,"@ip",ipVerified);Param(c,"@device",deviceVerified);Param(c,"@ok",allowed);Param(c,"@reason",reason);c.ExecuteNonQuery();}}
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
  static SessionResult Evaluate(SqlConnection db,SqlTransaction tx,int id,int recipient,Guid device,string clientIp,bool existing) {
   using(var c=Command(db,tx,@"SELECT c.FileName,c.FileType,r.AccessStatus,p.PolicyStatus,p.StartTime,p.ExpirationDate,p.MaximumViews,p.TrustedDevice,p.RequiredLocation,p.ScreenshotRestriction,CASE WHEN EXISTS(SELECT 1 FROM TrustedDevices d WHERE d.UserID=r.UserID AND d.DeviceIdentifier=@device AND d.IsTrusted=1) THEN 1 ELSE 0 END,(SELECT COUNT(*) FROM ViewingSession s WHERE s.RecipientID=r.RecipientID) FROM Content c JOIN ContentRecipient r ON r.ContentID=c.ContentID JOIN AccessPolicy p ON p.ContentID=c.ContentID WHERE c.ContentID=@id AND r.RecipientID=@recipient")) {Param(c,"@id",id);Param(c,"@recipient",recipient);Param(c,"@device",device.ToString("D"));using(var r=c.ExecuteReader()) {
    if(!r.Read())return Deny("Content or policy not found.");string reason=null;bool locationVerified=true;var now=DateTime.UtcNow;
    if(r.GetString(2)!="Active" || r.GetString(3)!="Active")reason="Access has been revoked.";
    else if(!r.IsDBNull(4) && now<r.GetDateTime(4))reason="Access has not begun.";
    else if(!r.IsDBNull(5) && now>=r.GetDateTime(5))reason="Access has expired.";
    else if(!existing && r.GetBoolean(6) && r.GetInt32(11)>=1)reason="Maximum views reached.";
    else if(r.GetBoolean(7) && r.GetInt32(10)==0)reason="Approved device required.";
    else if(!r.IsDBNull(8)) {
     LocationPolicy policy;
     try {policy=JsonConvert.DeserializeObject<LocationPolicy>(r.GetString(8));}
     catch(JsonException) {policy=null;reason="The geographic access policy is invalid.";}
     if(reason==null) {var verification=IpGeolocationService.Verify(clientIp,policy);locationVerified=verification.Success&&verification.Matches;if(!locationVerified)reason=verification.Message;}
    }
    if(reason==null && r.GetBoolean(9))reason="Screenshot restriction cannot be enforced by this desktop client.";
    if(reason!=null)return new SessionResult {AccessGranted=false,Message=reason,DeviceVerified=r.GetInt32(10)!=0,LocationVerified=locationVerified};
    try{var result=ReadContent(id,r.GetString(0),r.GetString(1));result.DeviceVerified=r.GetInt32(10)!=0;result.LocationVerified=locationVerified;return result;}
    catch(IOException){return Deny("Content file is unavailable.");}
   }}
  }
  static SessionResult Deny(string message){return new SessionResult {AccessGranted=false,Message=message};}
 }
}
