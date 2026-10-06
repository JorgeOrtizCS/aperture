using Microsoft.AspNetCore.Mvc;
using Aperture_WebAPI.Filters;
using Aperture_WebAPI.Infrastructure;

namespace Aperture_WebAPI.Controllers
{
    [Route("api/user")]
    public class UserController : ApiControllerBase
    {
        /// <summary>Returns the logged-in user.</summary>
        /// <response code="200">The user's id and username.</response>
        [HttpGet]
        [Route("me")]
        [TokenAuthorize]
        public IActionResult Me()
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
                    email = (string)null
                }
            });
        }
    }
}