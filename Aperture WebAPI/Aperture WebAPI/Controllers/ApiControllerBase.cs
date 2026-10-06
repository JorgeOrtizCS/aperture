using System.Net;
using Microsoft.AspNetCore.Mvc;

namespace Aperture_WebAPI.Controllers
{
    /// <summary>
    /// Keeps the Web API 2 helper signatures and response bodies so existing clients
    /// see exactly what they saw before the move to ASP.NET Core.
    /// </summary>
    public abstract class ApiControllerBase : ControllerBase
    {
        // Web API 2's BadRequest(string) answered {"Message":"..."}, not a bare string.
        protected BadRequestObjectResult BadRequest(string message)
        {
            return base.BadRequest(new { Message = message });
        }

        protected ObjectResult Content(HttpStatusCode statusCode, object value)
        {
            return StatusCode((int)statusCode, value);
        }
    }
}
