using System.Web.Http;
using Aperture_WebAPI.App_Start;

namespace Aperture_WebAPI
{
    public class WebApiApplication
        : System.Web.HttpApplication
    {
        protected void Application_Start()
        {
            GlobalConfiguration.Configure(WebApiConfig.Register);
        }
    }
}