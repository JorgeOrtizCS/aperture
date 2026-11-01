using System;
using MySql.Data.MySqlClient;
using System.Web.Http;
using Aperture_WebAPI.Config;
using Aperture_WebAPI.Controllers;
using Aperture_WebAPI.Filters;
using Aperture_WebAPI.Infrastructure;

namespace Aperture_WebAPI.SituationalAwareness
{
    public class SuspendSessionRequest
    {
        /// <summary>Optional, shown to the recipient (at most 80 characters).</summary>
        public string Reason { get; set; }

        /// <summary>How long checks are denied, 1 to 3600 seconds. Default 30.</summary>
        public int? DurationSeconds { get; set; }
    }

    /// <summary>
    /// Temporary suspension of an open viewing session. The sender of the content or the recipient
    /// viewing it can suspend the session; its periodic checks then withhold the content (the session
    /// stays open) until the hold time has passed, and the next check that passes every condition
    /// lifts the suspension. Suspensions caused by a failed check are reported here too.
    /// </summary>
    [RoutePrefix("api/situational"), TokenAuthorize]
    public class SessionSuspensionController : ApiController
    {
        /// <summary>Suspends an open viewing session (content sender or the recipient). Checks are denied until the hold time has passed; the next passing check after that lifts the suspension.</summary>
        /// <response code="200">Suspended; returns the suspension state.</response>
        /// <response code="400">Reason too long or duration out of range.</response>
        /// <response code="404">No open session, or no access to it.</response>
        [HttpPost, Route("sessions/{sessionId:int}/suspend")]
        public IHttpActionResult Suspend(int sessionId, [FromBody] SuspendSessionRequest request)
        {
            request = request ?? new SuspendSessionRequest();

            string error = SessionSuspension.ValidateHold(request.Reason, request.DurationSeconds);
            if (error != null)
            {
                return BadRequest(error);
            }

            if (!CanAccessOpenSession(sessionId))
            {
                return NotFound();
            }

            return Ok(SessionSuspension.Hold(sessionId, request.Reason, request.DurationSeconds, DateTime.UtcNow));
        }

        /// <summary>Returns whether an open viewing session is suspended, why, and (for a manual suspension) until when checks are denied (content sender or the recipient).</summary>
        /// <response code="200">The suspension state.</response>
        /// <response code="404">No open session, or no access to it.</response>
        [HttpGet, Route("sessions/{sessionId:int}/suspension")]
        public IHttpActionResult GetSuspension(int sessionId)
        {
            if (!CanAccessOpenSession(sessionId))
            {
                return NotFound();
            }

            return Ok(SessionSuspension.GetStatus(sessionId));
        }

        // An open session that the caller is viewing (recipient) or whose content they sent.
        private static bool CanAccessOpenSession(int sessionId)
        {
            using (var db = new MySqlConnection(ConnectionStrings.Database))
            {
                db.Open();
                using (var command = new MySqlCommand(
                    "SELECT 1 FROM ViewingSession s JOIN ContentRecipient r ON r.RecipientID=s.RecipientID JOIN Content c ON c.ContentID=r.ContentID WHERE s.SessionID=@session AND s.Session_Status='Active' AND (r.UserID=@user OR c.SenderID=@user)", db))
                {
                    command.Parameters.AddWithValue("@session", sessionId);
                    command.Parameters.AddWithValue("@user", RequestUser.Get().Id);
                    return command.ExecuteScalar() != null;
                }
            }
        }
    }
}
