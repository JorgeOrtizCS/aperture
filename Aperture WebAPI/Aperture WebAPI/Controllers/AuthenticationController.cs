using System.Net;
using Microsoft.AspNetCore.Mvc;
using Aperture_WebAPI.Infrastructure;
using Aperture_WebAPI.Models;
using Aperture_WebAPI.Services;

namespace Aperture_WebAPI.Controllers
{
    [Route("api/auth")]
    public class AuthController : ApiControllerBase
    {
        private readonly AuthenticationService _authenticationService;

        public AuthController()
        {
            _authenticationService =
                new AuthenticationService();
        }

        /// <summary>Logs in and returns a bearer token valid for 8 hours. Tokens live in the API's memory and stop working when it restarts.</summary>
        /// <response code="200">Logged in; use Token as the bearer token.</response>
        /// <response code="401">Invalid username or password.</response>
        [ProducesResponseType(typeof(LoginResponse), 200)]
        [ProducesResponseType(typeof(LoginResponse), 401)]
        [HttpPost]
        [Route("login")]
        public IActionResult Login([FromBody] LoginRequest request)
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

        /// <summary>Invalidates the bearer token sent with this request.</summary>
        /// <response code="200">Logged out.</response>
        /// <response code="400">No bearer token was sent.</response>
        [HttpPost]
        [Route("logout")]
        public IActionResult Logout()
        {
            string token = BearerToken.From(Request);

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
    }
}