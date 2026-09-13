using System.Web.Http;
using Aperture_WebAPI.Filters;
using Aperture_WebAPI.Infrastructure;

namespace Aperture_WebAPI.Controllers
{
    [RoutePrefix("api/user")]
    public class UserController : ApiController
    {
        [HttpGet]
        [Route("me")]
        [TokenAuthorize]
        public IHttpActionResult Me()
        {
            var user = RequestUser.Get();

            if (user == null)
                return Unauthorized();

            return Ok(new
            {
                success = true,
                user = new
                {
                    id = user.Id,
                    username = user.Username,
                    email = user.Email
                }
            });
        }
    }
}