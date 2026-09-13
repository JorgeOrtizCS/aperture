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

            if (string.IsNullOrWhiteSpace(request.FirstName) || string.IsNullOrWhiteSpace(request.LastName)
                || request.FirstName.Length > 100 || request.LastName.Length > 100 || request.Username.Length > 100)
                return BadRequest("First name, last name, and username are required (maximum 100 characters).");

            string passwordHash =
                PasswordService.HashPassword(
                    request.Password);

            using (SqlConnection connection = new SqlConnection(ConnectionStrings.Database))
            {
                connection.Open();

                const string sql = @"INSERT INTO Users(FirstName, LastName, Username, PasswordHash)
                    VALUES(@FirstName, @LastName, @Username, @PasswordHash)";

                using (SqlCommand command =
                       new SqlCommand(sql, connection))
                {
                    command.Parameters.AddWithValue(
                        "@Username",
                        request.Username);

                    command.Parameters.AddWithValue("@FirstName", request.FirstName.Trim());
                    command.Parameters.AddWithValue("@LastName", request.LastName.Trim());

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