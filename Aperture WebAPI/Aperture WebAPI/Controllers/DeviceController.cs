using System;
using Microsoft.Data.SqlClient;
using Microsoft.AspNetCore.Mvc;
using Aperture_WebAPI.Config;
using Aperture_WebAPI.Filters;
using Aperture_WebAPI.Infrastructure;
using Aperture_WebAPI.Models;
namespace Aperture_WebAPI.Controllers {
 [Route("api/devices"),TokenAuthorize]
 public class DeviceController : ApiControllerBase {
  /// <summary>Registers the current device for the logged-in user. New devices start untrusted until an administrator approves them in SQL.</summary>
  /// <response code="200">Returns trusted: whether the device is approved.</response>
  /// <response code="400">Device key and a name up to 100 characters are required.</response>
  /// <response code="409">This device key is registered to another user.</response>
  [HttpPost,Route("")]
  public IActionResult Register([FromBody] DeviceRegistration request) {
   if(request==null || request.DeviceKey==Guid.Empty || string.IsNullOrWhiteSpace(request.DeviceName) || request.DeviceName.Length>100) return BadRequest("Valid device key and name required.");
   using(var db=new SqlConnection(ConnectionStrings.Database)) {db.Open();
    using(var cmd=new SqlCommand(@"IF NOT EXISTS(SELECT 1 FROM TrustedDevices WHERE DeviceIdentifier=@key) INSERT INTO TrustedDevices(DeviceIdentifier,UserID,DeviceName,DeviceType,IsTrusted) VALUES(@key,@user,@name,N'Desktop',0); SELECT IsTrusted FROM TrustedDevices WHERE DeviceIdentifier=@key AND UserID=@user",db)) {
     cmd.Parameters.AddWithValue("@key",request.DeviceKey.ToString("D"));cmd.Parameters.AddWithValue("@user",RequestUser.Get().Id);cmd.Parameters.AddWithValue("@name",request.DeviceName.Trim());var trusted=cmd.ExecuteScalar();if(trusted==null)return Conflict();return Ok(new {trusted=(bool)trusted});
    }
   }
  }
 }
}
