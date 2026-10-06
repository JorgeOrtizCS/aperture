using System;
using System.Net;
using System.Security.Principal;
using Aperture_WebAPI.Infrastructure;
using Aperture_WebAPI.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace Aperture_WebAPI.Filters
{
    [AttributeUsage(AttributeTargets.Class | AttributeTargets.Method)]
    public class TokenAuthorizeAttribute
        : Attribute, IAuthorizationFilter
    {
        public void OnAuthorization(
            AuthorizationFilterContext context)
        {
            string token =
                BearerToken.From(context.HttpContext.Request);

            if (string.IsNullOrWhiteSpace(token))
            {
                HandleUnauthorizedRequest(context);
                return;
            }

            var service =
                new AuthenticationService();

            // SQL Server authentication lookup happens HERE.
            var user =
                service.ValidateToken(token);

            if (user == null)
            {
                HandleUnauthorizedRequest(context);
                return;
            }

            // Save the authenticated user
            // for the remainder of this request.
            RequestUser.Set(user);

            var identity =
                new GenericIdentity(
                    user.Username,
                    "Bearer");

            context.HttpContext.User =
                new GenericPrincipal(
                    identity,
                    null);
        }

        private static void HandleUnauthorizedRequest(
            AuthorizationFilterContext context)
        {
            context.Result =
                new ObjectResult(
                    new
                    {
                        success = false,
                        message =
                            "Authentication required."
                    })
                {
                    StatusCode = (int)HttpStatusCode.Unauthorized
                };
        }
    }
}
