using System;
using System.Diagnostics;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Aperture_WebAPI.Models;
using Aperture_WebAPI.Repositories;

namespace Aperture_WebAPI.Infrastructure
{
    public class AuditLoggingHandler : DelegatingHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            Guid requestId = Guid.NewGuid();

            DateTime startedAt = DateTime.UtcNow;

            Stopwatch stopwatch = Stopwatch.StartNew();

            HttpResponseMessage response = null;

            string errorMessage = null;

            try
            {
                response = await base.SendAsync(
                    request,
                    cancellationToken);

                return response;
            }
            catch (Exception ex)
            {
                errorMessage = ex.Message;

                throw;
            }
            finally
            {
                stopwatch.Stop();

                try
                {
                    await WriteAuditLog(
                        request,
                        response,
                        requestId,
                        startedAt,
                        stopwatch.ElapsedMilliseconds,
                        errorMessage);
                }
                catch
                {
                    // IMPORTANT:
                    // Audit logging must not bring down
                    // the API if the audit database fails.
                }
            }
        }

        private async Task WriteAuditLog(
    HttpRequestMessage request,
    HttpResponseMessage response,
    System.Guid requestId,
    System.DateTime startedAt,
    long durationMs,
    string errorMessage)
        {
            var user = RequestUser.Get();

            int? userId = null;
            string username = null;

            if (user != null)
            {
                userId = user.Id;
                username = user.Username;
            }

            int? statusCode = null;

            if (response != null)
            {
                statusCode =
                    (int)response.StatusCode;
            }

            bool success =
                response != null &&
                statusCode >= 200 &&
                statusCode < 400 &&
                string.IsNullOrWhiteSpace(errorMessage);

            var auditLog = new AuditLog
            {
                RequestId = requestId,

                UserId = userId,

                Username = username,

                HttpMethod =
                    request.Method.Method,

                Endpoint =
                    request.RequestUri.AbsolutePath,

                QueryString =
                    request.RequestUri.Query,

                StatusCode =
                    statusCode,

                IsSuccess =
                    success,

                IpAddress =
                    GetIpAddress(request),

                UserAgent =
                    GetUserAgent(request),

                RequestBody =
                    await GetRequestBody(request),

                ResponseBody =
                    await GetResponseBody(response),

                ErrorMessage =
                    errorMessage,

                StartedAt =
                    startedAt,

                CompletedAt =
                    System.DateTime.UtcNow,

                DurationMs =
                    System.Convert.ToInt32(durationMs)
            };

            var repository =
                new AuditLogRepository();

            repository.Insert(auditLog);
        }

        private string GetBearerToken(
            HttpRequestMessage request)
        {
            if (request.Headers.Authorization == null)
                return null;

            if (!request.Headers.Authorization.Scheme
                .Equals(
                    "Bearer",
                    StringComparison.OrdinalIgnoreCase))
            {
                return null;
            }

            return request.Headers.Authorization.Parameter;
        }

        private string GetIpAddress(
            HttpRequestMessage request)
        {
            if (request.Properties.ContainsKey(
                "MS_HttpContext"))
            {
                dynamic context =
                    request.Properties["MS_HttpContext"];

                return context?.Request?.UserHostAddress;
            }

            return null;
        }

        private string GetUserAgent(
            HttpRequestMessage request)
        {
            if (request.Headers.UserAgent == null)
                return null;

            return request.Headers.UserAgent.ToString();
        }

        private async Task<string> GetRequestBody(
            HttpRequestMessage request)
        {
            if (request.Content == null)
                return null;

            try
            {
                string body =
                    await request.Content.ReadAsStringAsync();

                return SanitizeBody(body);
            }
            catch
            {
                return null;
            }
        }

        private async Task<string> GetResponseBody(
            HttpResponseMessage response)
        {
            if (response == null ||
                response.Content == null)
            {
                return null;
            }

            try
            {
                string body =
                    await response.Content.ReadAsStringAsync();

                return SanitizeBody(body);
            }
            catch
            {
                return null;
            }
        }

        private string SanitizeBody(
            string body)
        {
            if (string.IsNullOrWhiteSpace(body))
                return body;

            // Never store passwords or bearer tokens.
            body = System.Text.RegularExpressions
                .Regex.Replace(
                    body,
                    "(\"password\"\\s*:\\s*\")[^\"]*(\")",
                    "$1***REDACTED***$2",
                    System.Text.RegularExpressions
                        .RegexOptions.IgnoreCase);

            body = System.Text.RegularExpressions
                .Regex.Replace(
                    body,
                    "(\"token\"\\s*:\\s*\")[^\"]*(\")",
                    "$1***REDACTED***$2",
                    System.Text.RegularExpressions
                        .RegexOptions.IgnoreCase);

            return body;
        }
    }
}