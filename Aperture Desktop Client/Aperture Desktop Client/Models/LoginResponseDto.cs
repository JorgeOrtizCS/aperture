using System;

namespace Aperture_Desktop_Client.Models
{
    public class LoginResponseDto
    {
        public bool Success { get; set; }
        public string Message { get; set; }
        public string Token { get; set; }
        public DateTime ExpiresAt { get; set; }
        public UserDto User { get; set; }
    }
}
