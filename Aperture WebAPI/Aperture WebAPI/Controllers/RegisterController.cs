using System;
using System.Data.SqlClient;
using System.Net;
using System.Web.Http;
using Aperture_WebAPI.Config;
using Aperture_WebAPI.Models;
using Aperture_WebAPI.Services;

namespace Aperture_WebAPI.Controllers
{
    [RoutePrefix("api/register")]
    public class RegisterController : ApiController
    {
        [HttpPost]
        [Route("")]
        public IHttpActionResult Register(RegisterRequest request)
        {
            if (request == null)
                return BadRequest("Invalid request.");

            if (string.IsNullOrWhiteSpace(request.Username))
                return BadRequest("Username is required.");

            if (string.IsNullOrWhiteSpace(request.Password))
                return BadRequest("Password is required.");

            if (request.Password.Length < 8)
                return BadRequest(
                    "Password must be at least 8 characters.");

            string passwordHash =
                PasswordService.HashPassword(
                    request.Password);

            using (SqlConnection connection = new SqlConnection(ConnectionStrings.Database))
            {
                connection.Open();

                const string sql = @"
                    INSERT INTO Users
                    (
                        Username,
                        Email,
                        PasswordHash,
                        IsActive
                    )
                    VALUES
                    (
                        @Username,
                        @Email,
                        @PasswordHash,
                        1
                    )";

                using (SqlCommand command =
                       new SqlCommand(sql, connection))
                {
                    command.Parameters.AddWithValue(
                        "@Username",
                        request.Username);

                    command.Parameters.AddWithValue(
                        "@Email",
                        (object)request.Email ?? DBNull.Value);

                    command.Parameters.AddWithValue(
                        "@PasswordHash",
                        passwordHash);

                    try
                    {
                        command.ExecuteNonQuery();
                    }
                    catch (SqlException ex)
                    {
                        if (ex.Number == 2601 ||
                            ex.Number == 2627)
                        {
                            return Content(
                                HttpStatusCode.Conflict,
                                new
                                {
                                    success = false,
                                    message =
                                        "Username already exists."
                                });
                        }

                        throw;
                    }
                }
            }

            return Ok(new
            {
                success = true,
                message = "User created successfully."
            });
        }
    }
}