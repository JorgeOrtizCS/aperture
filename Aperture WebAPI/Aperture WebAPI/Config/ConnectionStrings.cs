using System.Configuration;
using Aperture_WebAPI.Extensions;

namespace Aperture_WebAPI.Config
{
    public class ConnectionStrings
    {
        private static string _database { get; set; }
        public static string Database
        {
            get
            {
                if (string.IsNullOrEmpty(_database))
                {
                    _database = ConfigurationManager.ConnectionStrings["Database"].ToSafeString();
                }

                return _database;
            }
        }
    }
}