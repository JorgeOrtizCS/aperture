using System;
using System.Net.Http.Headers;
using Microsoft.AspNetCore.Http;

namespace Aperture_WebAPI.Infrastructure
{
    public static class BearerToken
    {
        /// <summary>The token from an "Authorization: Bearer ..." header, or null.</summary>
        public static string From(HttpRequest request)
        {
            AuthenticationHeaderValue authorization;

            if (request == null ||
                !AuthenticationHeaderValue.TryParse(request.Headers.Authorization, out authorization))
            {
                return null;
            }

            if (!authorization.Scheme.Equals(
                "Bearer",
                StringComparison.OrdinalIgnoreCase))
            {
                return null;
            }

            return authorization.Parameter;
        }
    }
}
