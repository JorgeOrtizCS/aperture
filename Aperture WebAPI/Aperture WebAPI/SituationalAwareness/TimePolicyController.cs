using System;
using System.Globalization;
using Aperture_WebAPI.Models;
using Newtonsoft.Json;
using MySql.Data.MySqlClient;
using System.Web.Http;
using Aperture_WebAPI.Config;
using Aperture_WebAPI.Controllers;
using Aperture_WebAPI.Filters;
using Aperture_WebAPI.Infrastructure;

namespace Aperture_WebAPI.SituationalAwareness
{
    public class TimeWindowRequest
    {
        /// <summary>UTC. Null removes the start restriction.</summary>
        public DateTime? StartTime { get; set; }

        /// <summary>UTC. Null removes the expiration.</summary>
        public DateTime? ExpiresAt { get; set; }
    }

    /// <summary>
    /// Time-window condition for shared content. A sender can change the window after the content was
    /// created (replacing the StartTime / ExpiresAt set at share time), and the sender or recipient can
    /// check whether the content is inside its window right now. Open viewing sessions pick up a new
    /// window on their next periodic check.
    /// </summary>
    [RoutePrefix("api/situational"), TokenAuthorize]
    public class TimePolicyController : ApiController
    {
        /// <summary>Sets the content's time window (owner only). Times are UTC; null removes that limit. Open sessions pick it up on their next check.</summary>
        /// <response code="200">Window saved.</response>
        /// <response code="400">Expiration must be after the start and in the future.</response>
        /// <response code="404">Not found, or not the owner.</response>
        [HttpPost, Route("content/{id:int}/time")]
        public IHttpActionResult SetTimeWindow(int id, [FromBody] TimeWindowRequest request)
        {
            if (request == null)
            {
                return BadRequest("A start time and/or expiration is required (null removes either one).");
            }

            string error = TimeWindowCheck.ValidatePolicy(request.StartTime, request.ExpiresAt, DateTime.UtcNow);
            if (error != null)
            {
                return BadRequest(error);
            }

            using (var db = new MySqlConnection(ConnectionStrings.Database))
            {
                db.Open();
                using (var command = new MySqlCommand(
                    "UPDATE AccessPolicy p JOIN Content c ON c.ContentID=p.ContentID SET p.Requirements=JSON_SET(p.Requirements,'$.StartTime',@start,'$.ExpiresAt',@expiry) WHERE c.ContentID=@id AND c.SenderID=@owner", db))
                {
                    command.Parameters.AddWithValue("@start", (object)request.StartTime?.ToUniversalTime().ToString("o", CultureInfo.InvariantCulture) ?? DBNull.Value);
                    command.Parameters.AddWithValue("@expiry", (object)request.ExpiresAt?.ToUniversalTime().ToString("o", CultureInfo.InvariantCulture) ?? DBNull.Value);
                    command.Parameters.AddWithValue("@id", id);
                    command.Parameters.AddWithValue("@owner", RequestUser.Get().Id);
                    if (command.ExecuteNonQuery() == 0)
                    {
                        return NotFound();
                    }
                }
            }

            return Ok(new { success = true });
        }

        /// <summary>Checks whether the content is inside its time window right now (sender or recipient).</summary>
        /// <response code="200">passed, the reason when it fails, and the stored window.</response>
        /// <response code="404">Not found, or no access.</response>
        [HttpGet, Route("content/{id:int}/time")]
        public IHttpActionResult CheckTimeWindow(int id)
        {
            DateTime? start;
            DateTime? expiration;

            using (var db = new MySqlConnection(ConnectionStrings.Database))
            {
                db.Open();
                // The sender or a recipient of the content may check its window.
                using (var command = new MySqlCommand(
                    "SELECT p.Requirements FROM AccessPolicy p JOIN Content c ON c.ContentID=p.ContentID WHERE c.ContentID=@id AND (c.SenderID=@user OR EXISTS (SELECT 1 FROM ContentRecipient r WHERE r.ContentID=c.ContentID AND r.UserID=@user))", db))
                {
                    command.Parameters.AddWithValue("@id", id);
                    command.Parameters.AddWithValue("@user", RequestUser.Get().Id);
                    using (var reader = command.ExecuteReader())
                    {
                        if (!reader.Read())
                        {
                            return NotFound();
                        }

                        try {
                            var policy=ViewingRequirements.Parse(reader.IsDBNull(0)?null:reader.GetString(0));
                            start=policy.StartTime;expiration=policy.ExpiresAt;
                        } catch(JsonException) {return BadRequest("The viewing requirements are invalid.");}
                    }
                }
            }

            ConditionResult result = TimeWindowCheck.Evaluate(start, expiration, DateTime.UtcNow);

            return Ok(new
            {
                passed = result.Passed,
                reason = result.Reason,
                startTime = start,
                expiresAt = expiration
            });
        }
    }
}
