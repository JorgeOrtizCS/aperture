using System;

namespace Aperture_WebAPI.Models
{
    public class LoginResponse
    {
        public bool Success { get; set; }

        public string Message { get; set; }

        public string Token { get; set; }

        public DateTime ExpiresAt { get; set; }

        public UserInfo User { get; set; }
    }
}