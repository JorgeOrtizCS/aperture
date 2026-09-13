using System;

namespace Aperture_WebAPI.Models
{
    public class AuditLog
    {
        public long Id { get; set; }

        public Guid RequestId { get; set; }

        public int? UserId { get; set; }

        public string Username { get; set; }

        public string HttpMethod { get; set; }

        public string Endpoint { get; set; }

        public string QueryString { get; set; }

        public int? StatusCode { get; set; }

        public bool IsSuccess { get; set; }

        public string IpAddress { get; set; }

        public string UserAgent { get; set; }

        public string RequestBody { get; set; }

        public string ResponseBody { get; set; }

        public string ErrorMessage { get; set; }

        public DateTime StartedAt { get; set; }

        public DateTime? CompletedAt { get; set; }

        public int? DurationMs { get; set; }
    }
}