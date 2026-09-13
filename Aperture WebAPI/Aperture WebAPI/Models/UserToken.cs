using System;

namespace Aperture_WebAPI.Models
{
    public class UserToken
    {
        public long Id { get; set; }

        public int UserId { get; set; }

        public string TokenHash { get; set; }

        public DateTime CreatedAt { get; set; }

        public DateTime ExpiresAt { get; set; }

        public DateTime? RevokedAt { get; set; }
    }
}