using System.Collections.Generic;
using System.Linq;
using Aperture_WebAPI.Controllers;
using Aperture_WebAPI.Filters;
using Microsoft.OpenApi;
using Swashbuckle.AspNetCore.SwaggerGen;

namespace Aperture_WebAPI.Infrastructure
{
    /// <summary>
    /// Adds what Swagger cannot infer from the controllers: which operations need a bearer token
    /// ([TokenAuthorize] on the action or its controller) and the optional GPS headers read by the
    /// viewing-session endpoints for precise-location policies.
    /// </summary>
    public class SwaggerOperationFilter : IOperationFilter
    {
        public const string BearerScheme = "Bearer";

        public void Apply(OpenApiOperation operation, OperationFilterContext context)
        {
            bool requiresToken =
                context.MethodInfo.GetCustomAttributes(true).OfType<TokenAuthorizeAttribute>().Any() ||
                context.MethodInfo.DeclaringType.GetCustomAttributes(true).OfType<TokenAuthorizeAttribute>().Any();

            // Logout reads the token itself instead of using [TokenAuthorize].
            bool isLogout =
                context.MethodInfo.DeclaringType == typeof(AuthController) &&
                context.MethodInfo.Name == nameof(AuthController.Logout);

            if (requiresToken || isLogout)
            {
                operation.Security ??= new List<OpenApiSecurityRequirement>();
                operation.Security.Add(new OpenApiSecurityRequirement
                {
                    [new OpenApiSecuritySchemeReference(BearerScheme, context.Document)] = new List<string>()
                });

                operation.Responses ??= new OpenApiResponses();
                operation.Responses.TryAdd("401", new OpenApiResponse { Description = "Missing, expired or invalid bearer token." });
            }
            else
            {
                // An empty requirement states explicitly that no token is needed (login, register).
                operation.Security = new List<OpenApiSecurityRequirement> { new OpenApiSecurityRequirement() };
            }

            // LocationCheck reads these on session open and on every periodic check.
            bool readsClientLocation =
                context.MethodInfo.DeclaringType == typeof(ContentController) &&
                (context.MethodInfo.Name == nameof(ContentController.Open) || context.MethodInfo.Name == nameof(ContentController.Check));

            if (readsClientLocation)
            {
                operation.Parameters ??= new List<IOpenApiParameter>();
                operation.Parameters.Add(LocationHeader("X-Client-Latitude", "Recipient's GPS latitude. Required for content with a precise point + radius policy."));
                operation.Parameters.Add(LocationHeader("X-Client-Longitude", "Recipient's GPS longitude. Required for content with a precise point + radius policy."));
            }
        }

        private static OpenApiParameter LocationHeader(string name, string description)
        {
            return new OpenApiParameter
            {
                Name = name,
                In = ParameterLocation.Header,
                Required = false,
                Description = description,
                Schema = new OpenApiSchema { Type = JsonSchemaType.Number, Format = "double" }
            };
        }
    }
}
