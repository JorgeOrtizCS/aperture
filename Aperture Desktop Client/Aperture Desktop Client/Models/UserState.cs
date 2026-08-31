using System;

namespace Aperture_Desktop_Client.Models
{
    public class UserState
    {
        public bool IsLoggedIn { get; set; }
        public DateTime AccessDateTime { get; set; }
    }
}
