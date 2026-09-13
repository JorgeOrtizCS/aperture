using System;
using System.Data.SqlClient;
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
   using(var db=new SqlConnection(ConnectionStrings.Database)) {db.Open();
    using(var cmd=new SqlCommand(@"IF NOT EXISTS(SELECT 1 FROM TrustedDevices WHERE DeviceIdentifier=@key) INSERT INTO TrustedDevices(DeviceIdentifier,UserID,DeviceName,DeviceType,IsTrusted) VALUES(@key,@user,@name,N'Desktop',0); SELECT IsTrusted FROM TrustedDevices WHERE DeviceIdentifier=@key AND UserID=@user",db)) {
     cmd.Parameters.AddWithValue("@key",request.DeviceKey.ToString("D"));cmd.Parameters.AddWithValue("@user",RequestUser.Get().Id);cmd.Parameters.AddWithValue("@name",request.DeviceName.Trim());var trusted=cmd.ExecuteScalar();if(trusted==null)return Conflict();return Ok(new {trusted=(bool)trusted});
    }
   }
  }
 }
}
