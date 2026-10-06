using Aperture_WebAPI.Extensions;
using Microsoft.Extensions.Configuration;

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
                    _database = AppSettings.Configuration?.GetConnectionString("Database").ToSafeString();
                }

                return _database;
            }
        }
    }
}
