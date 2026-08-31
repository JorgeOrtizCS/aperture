using System;
using System.Security.Cryptography;
using System.Text;

namespace Aperture_WebAPI.Services
{
    public static class TokenService
    {
        public static string GenerateToken()
        {
            byte[] bytes = new byte[64];

            using (var rng = RandomNumberGenerator.Create())
            {
                rng.GetBytes(bytes);
            }

            return Convert.ToBase64String(bytes)
                .Replace("+", "-")
                .Replace("/", "_")
                .Replace("=", "");
        }

        public static string HashToken(string token)
        {
            using (var sha = SHA512.Create())
            {
                byte[] bytes = Encoding.UTF8.GetBytes(token);

                byte[] hash = sha.ComputeHash(bytes);

                return BitConverter
                    .ToString(hash)
                    .Replace("-", "")
                    .ToLowerInvariant();
            }
        }
    }
}