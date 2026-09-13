using System;

namespace Aperture_WebAPI.Models
{
    public class UserState
    {
        public bool IsLoggedIn { get; set; }
        public DateTime AccessDateTime { get; set; }
    }
}