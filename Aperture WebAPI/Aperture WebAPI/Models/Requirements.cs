using System;

namespace Aperture_WebAPI.Models
{
    public class Requirements
    {
        public bool IsLoggedIn { get; set; }
        public DateTime AccessDateTime { get; set; }
    }
}