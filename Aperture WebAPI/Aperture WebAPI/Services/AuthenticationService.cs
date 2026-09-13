using System;
using System.Data.SqlClient;
using Aperture_WebAPI.Config;
using Aperture_WebAPI.Models;

namespace Aperture_WebAPI.Services
{
    public class AuthenticationService
    {
        private const int TokenExpirationHours = 8;

        public LoginResponse Login(LoginRequest request)
        {
            if (request == null)
            {
                return Failure("Invalid request.");
            }

            if (string.IsNullOrWhiteSpace(request.Username) ||
                string.IsNullOrWhiteSpace(request.Password))
            {
                return Failure("Username and password are required.");
            }

            ApplicationUser user = GetUser(request.Username);

            if (user == null)
            {
                return Failure("Invalid username or password.");
            }

            if (!user.IsActive)
            {
                return Failure("This account is inactive.");
            }

            bool validPassword =
                PasswordService.VerifyPassword(
                    request.Password,
                    user.PasswordHash);

            if (!validPassword)
            {
                return Failure("Invalid username or password.");
            }

            string token = TokenService.GenerateToken();

            string tokenHash = TokenService.HashToken(token);

            DateTime expiresAt =
                DateTime.UtcNow.AddHours(TokenExpirationHours);

            SaveToken(
                user.Id,
                tokenHash,
                expiresAt);

            return new LoginResponse
            {
                Success = true,
                Message = "Login successful.",
                Token = token,
                ExpiresAt = expiresAt,
                User = new UserInfo
                {
                    Id = user.Id,
                    Username = user.Username,
                    Email = user.Email
                }
            };
        }

        public bool Logout(string token)
        {
            if (string.IsNullOrWhiteSpace(token))
                return false;

            string tokenHash =
                TokenService.HashToken(token);

            using (SqlConnection connection = new SqlConnection(ConnectionStrings.Database))
            {
                connection.Open();

                const string sql = @"
                    UPDATE UserTokens
                    SET RevokedAt = GETUTCDATE()
                    WHERE TokenHash = @TokenHash
                      AND RevokedAt IS NULL";

                using (SqlCommand command =
                       new SqlCommand(sql, connection))
                {
                    command.Parameters.AddWithValue(
                        "@TokenHash",
                        tokenHash);

                    return command.ExecuteNonQuery() > 0;
                }
            }
        }

        public ApplicationUser ValidateToken(string token)
        {
            if (string.IsNullOrWhiteSpace(token))
                return null;

            string tokenHash =
                TokenService.HashToken(token);

            using (SqlConnection connection = new SqlConnection(ConnectionStrings.Database))
            {
                connection.Open();

                const string sql = @"
                    SELECT
                        u.Id,
                        u.Username,
                        u.Email,
                        u.PasswordHash,
                        u.IsActive,
                        u.CreatedAt
                    FROM UserTokens t
                    INNER JOIN Users u
                        ON t.UserId = u.Id
                    WHERE t.TokenHash = @TokenHash
                      AND t.RevokedAt IS NULL
                      AND t.ExpiresAt > GETUTCDATE()
                      AND u.IsActive = 1";

                using (SqlCommand command =
                       new SqlCommand(sql, connection))
                {
                    command.Parameters.AddWithValue(
                        "@TokenHash",
                        tokenHash);

                    using (SqlDataReader reader =
                           command.ExecuteReader())
                    {
                        if (!reader.Read())
                            return null;

                        return new ApplicationUser
                        {
                            Id = reader.GetInt32(0),
                            Username = reader.GetString(1),
                            Email = reader.IsDBNull(2)
                                ? null
                                : reader.GetString(2),
                            PasswordHash = reader.GetString(3),
                            IsActive = reader.GetBoolean(4),
                            CreatedAt = reader.GetDateTime(5)
                        };
                    }
                }
            }
        }

        private ApplicationUser GetUser(string username)
        {
            using (SqlConnection connection = new SqlConnection(ConnectionStrings.Database))
            {
                connection.Open();

                const string sql = @"
                    SELECT
                        Id,
                        Username,
                        Email,
                        PasswordHash,
                        IsActive,
                        CreatedAt
                    FROM Users
                    WHERE Username = @Username";

                using (SqlCommand command =
                       new SqlCommand(sql, connection))
                {
                    command.Parameters.AddWithValue(
                        "@Username",
                        username);

                    using (SqlDataReader reader =
                           command.ExecuteReader())
                    {
                        if (!reader.Read())
                            return null;

                        return new ApplicationUser
                        {
                            Id = reader.GetInt32(0),
                            Username = reader.GetString(1),
                            Email = reader.IsDBNull(2)
                                ? null
                                : reader.GetString(2),
                            PasswordHash = reader.GetString(3),
                            IsActive = reader.GetBoolean(4),
                            CreatedAt = reader.GetDateTime(5)
                        };
                    }
                }
            }
        }

        private void SaveToken(
            int userId,
            string tokenHash,
            DateTime expiresAt)
        {
            using (SqlConnection connection = new SqlConnection(ConnectionStrings.Database))
            {
                connection.Open();

                const string sql = @"
                    INSERT INTO UserTokens
                    (
                        UserId,
                        TokenHash,
                        ExpiresAt
                    )
                    VALUES
                    (
                        @UserId,
                        @TokenHash,
                        @ExpiresAt
                    )";

                using (SqlCommand command =
                       new SqlCommand(sql, connection))
                {
                    command.Parameters.AddWithValue(
                        "@UserId",
                        userId);

                    command.Parameters.AddWithValue(
                        "@TokenHash",
                        tokenHash);

                    command.Parameters.AddWithValue(
                        "@ExpiresAt",
                        expiresAt);

                    command.ExecuteNonQuery();
                }
            }
        }

        private LoginResponse Failure(string message)
        {
            return new LoginResponse
            {
                Success = false,
                Message = message
            };
        }
    }
}