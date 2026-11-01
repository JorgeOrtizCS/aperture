using System;
using MySql.Data.MySqlClient;
using System.Web.Http;
using Aperture_WebAPI.Config;
using Aperture_WebAPI.Filters;
using Aperture_WebAPI.Infrastructure;
using Aperture_WebAPI.Models;
namespace Aperture_WebAPI.Controllers {
 [RoutePrefix("api/devices"),TokenAuthorize]
 public class DeviceController : ApiController {
  [HttpPost,Route("")]
  public IHttpActionResult Register(DeviceRegistration request) {
   if(request==null || request.DeviceKey==Guid.Empty || string.IsNullOrWhiteSpace(request.DeviceName) || request.DeviceName.Length>100) return BadRequest("Valid device key and name required.");
   // The existing schema has no DeviceIdentifier column. Keep the client key
   // in DeviceType as Desktop:<guid>, leaving DeviceName for its display name.
   string deviceType="Desktop:"+request.DeviceKey.ToString("D");
   using(var db=new MySqlConnection(ConnectionStrings.Database)) {db.Open();
    using(var tx=db.BeginTransaction(System.Data.IsolationLevel.Serializable)) {
     // Serialize registrations for this user without requiring a new unique index.
     using(var cmd=new MySqlCommand("SELECT UserID FROM Users WHERE UserID=@user FOR UPDATE",db,tx)) {
      cmd.Parameters.AddWithValue("@user",RequestUser.Get().Id);if(cmd.ExecuteScalar()==null)return NotFound();
     }
     object trusted;
     using(var cmd=new MySqlCommand("SELECT IsTrusted FROM TrustedDevices WHERE DeviceType=@key AND UserID=@user ORDER BY DeviceID LIMIT 1 FOR UPDATE",db,tx)) {
      cmd.Parameters.AddWithValue("@key",deviceType);cmd.Parameters.AddWithValue("@user",RequestUser.Get().Id);trusted=cmd.ExecuteScalar();
     }
     if(trusted==null) {
      using(var cmd=new MySqlCommand("INSERT INTO TrustedDevices(UserID,DeviceName,DeviceType,IsTrusted,DateRegistered) VALUES(@user,@name,@key,0,UTC_TIMESTAMP())",db,tx)) {
       cmd.Parameters.AddWithValue("@key",deviceType);cmd.Parameters.AddWithValue("@user",RequestUser.Get().Id);cmd.Parameters.AddWithValue("@name",request.DeviceName.Trim());cmd.ExecuteNonQuery();
      }
     }
     tx.Commit();return Ok(new {trusted=trusted!=null && trusted!=DBNull.Value && Convert.ToBoolean(trusted)});
    }
   }
  }
 }
}
