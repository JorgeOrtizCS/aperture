using Microsoft.Extensions.Configuration;

namespace Aperture_WebAPI.Config
{
    /// <summary>
    /// Replaces Web.config's ConfigurationManager. Program.cs sets these once at startup;
    /// values come from appsettings.json, appsettings.{Environment}.json and environment variables.
    /// </summary>
    public static class AppSettings
    {
        public static IConfiguration Configuration { get; set; }

        /// <summary>Project folder at run time; App_Data lives under it (was Server.MapPath("~")).</summary>
        public static string ContentRootPath { get; set; }

        public static string Get(string key)
        {
            return Configuration?[key];
        }
    }
}
