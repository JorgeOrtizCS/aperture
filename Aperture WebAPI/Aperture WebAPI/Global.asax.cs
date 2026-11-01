using System.Web.Http;

namespace Aperture_WebAPI
{
    public class WebApiApplication : System.Web.HttpApplication
    {
        protected void Application_Start()
        {
            GlobalConfiguration.Configure(
                App_Start.WebApiConfig.Register);
        }
    }
}