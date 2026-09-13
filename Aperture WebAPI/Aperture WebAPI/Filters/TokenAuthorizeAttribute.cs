using System.Net;
using System.Net.Http;
using System.Security.Principal;
using System.Threading;
using System.Web.Http;
using System.Web.Http.Controllers;
using Aperture_WebAPI.Infrastructure;
using Aperture_WebAPI.Services;

namespace Aperture_WebAPI.Filters
{
    public class TokenAuthorizeAttribute
        : AuthorizeAttribute
    {
        protected override bool IsAuthorized(
            HttpActionContext actionContext)
        {
            var authorization =
                actionContext.Request
                    .Headers.Authorization;

            if (authorization == null)
                return false;

            if (!authorization.Scheme.Equals(
                "Bearer",
                System.StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            string token =
                authorization.Parameter;

            if (string.IsNullOrWhiteSpace(token))
                return false;

            var service =
                new AuthenticationService();

            // SQL Server authentication lookup happens HERE.
            var user =
                service.ValidateToken(token);

            if (user == null)
                return false;

            // Save the authenticated user
            // for the remainder of this request.
            RequestUser.Set(user);

            var identity =
                new GenericIdentity(
                    user.Username,
                    "Bearer");

            var principal =
                new GenericPrincipal(
                    identity,
                    null);

            Thread.CurrentPrincipal =
                principal;

            actionContext.RequestContext.Principal =
                principal;

            return true;
        }

        protected override void HandleUnauthorizedRequest(
            HttpActionContext actionContext)
        {
            actionContext.Response =
                actionContext.Request.CreateResponse(
                    HttpStatusCode.Unauthorized,
                    new
                    {
                        success = false,
                        message =
                            "Authentication required."
                    });
        }
    }
}