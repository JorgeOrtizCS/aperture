using System.Data.SqlClient;
using System.Web.Http;
using Aperture_WebAPI.Config;
using Aperture_WebAPI.Filters;
using Aperture_WebAPI.Infrastructure;

namespace Aperture_WebAPI.SituationalAwareness
{
    public class PreciseLocationRequest
    {
        public double? Latitude { get; set; }
        public double? Longitude { get; set; }
        public double? RadiusMeters { get; set; }
    }

    /// <summary>
    /// Lets a sender restrict their content to a precise point + radius, instead of the coarse
    /// country/region/city restriction set when the content is created. Replaces any existing
    /// location restriction on that content.
    /// </summary>
    [RoutePrefix("api/situational"), TokenAuthorize]
    public class LocationPolicyController : ApiController
    {
        [HttpPost, Route("content/{id:int}/location")]
        public IHttpActionResult SetPreciseLocation(int id, PreciseLocationRequest request)
        {
            if (request == null || !request.Latitude.HasValue || !request.Longitude.HasValue || !request.RadiusMeters.HasValue)
            {
                return BadRequest("Latitude, longitude and radius are all required.");
            }

            string error;
            string policyJson = LocationCheck.BuildPolicyJson(
                null, null, null, request.Latitude, request.Longitude, request.RadiusMeters, out error);
            if (error != null)
            {
                return BadRequest(error);
            }

            using (var db = new SqlConnection(ConnectionStrings.Database))
            {
                db.Open();
                using (var command = new SqlCommand(
                    "UPDATE p SET RequiredLocation=@location FROM AccessPolicy p JOIN Content c ON c.ContentID=p.ContentID WHERE c.ContentID=@id AND c.SenderID=@owner", db))
                {
                    command.Parameters.AddWithValue("@location", policyJson);
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
    }
}
