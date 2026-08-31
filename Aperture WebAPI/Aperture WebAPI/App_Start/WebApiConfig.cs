using System.Web.Http;
using Aperture_WebAPI.Infrastructure;

namespace Aperture_WebAPI.App_Start
{
    public static class WebApiConfig
    {
        public static void Register(
            HttpConfiguration config)
        {
            config.MapHttpAttributeRoutes();

            //config.MessageHandlers.Add(
            //    new AuditLoggingHandler());

            config.Routes.MapHttpRoute(
                name: "DefaultApi",
                routeTemplate: "api/{controller}/{id}",
                defaults: new
                {
                    id = RouteParameter.Optional
                }
            );

            config.Formatters.JsonFormatter
                .SerializerSettings
                .NullValueHandling =
                    Newtonsoft.Json.NullValueHandling.Ignore;
        }
    }
}