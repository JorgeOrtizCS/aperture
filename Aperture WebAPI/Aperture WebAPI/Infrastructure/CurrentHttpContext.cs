using Microsoft.AspNetCore.Http;

namespace Aperture_WebAPI.Infrastructure
{
    /// <summary>
    /// Stand-in for System.Web's HttpContext.Current, which ASP.NET Core does not have.
    /// Lets the static helpers (RequestUser, SessionSuspension, LocationCheck) keep their shape.
    /// </summary>
    public static class CurrentHttpContext
    {
        private static IHttpContextAccessor _accessor;

        public static void Configure(IHttpContextAccessor accessor)
        {
            _accessor = accessor;
        }

        public static HttpContext Current
        {
            get { return _accessor?.HttpContext; }
        }
    }
}
