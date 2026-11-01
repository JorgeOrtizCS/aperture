using System.Net;
using System.Net.Http.Headers;
using System.Web.Http;
using Aperture_WebAPI.Models;
using Aperture_WebAPI.Services;

namespace Aperture_WebAPI.Controllers
{
    [RoutePrefix("api/auth")]
    public class AuthController : ApiController
    {
        private readonly AuthenticationService _authenticationService;

        public AuthController()
        {
            _authenticationService =
                new AuthenticationService();
        }

        [HttpPost]
        [Route("login")]
        public IHttpActionResult Login(LoginRequest request)
        {
            LoginResponse response =
                _authenticationService.Login(request);

            if (!response.Success)
            {
                return Content(
                    HttpStatusCode.Unauthorized,
                    response);
            }

            return Ok(response);
        }

        [HttpPost]
        [Route("logout")]
        public IHttpActionResult Logout()
        {
            string token = GetBearerToken();

            if (string.IsNullOrWhiteSpace(token))
            {
                return BadRequest(
                    "Authorization token is required.");
            }

            bool loggedOut =
                _authenticationService.Logout(token);

            if (!loggedOut)
            {
                return Unauthorized();
            }

            return Ok(new
            {
                success = true,
                message = "Logout successful."
            });
        }

        private string GetBearerToken()
        {
            AuthenticationHeaderValue authorization =
                Request.Headers.Authorization;

            if (authorization == null)
                return null;

            if (!authorization.Scheme.Equals(
                    "Bearer",
                    System.StringComparison.OrdinalIgnoreCase))
            {
                return null;
            }

            return authorization.Parameter;
        }
    }
}