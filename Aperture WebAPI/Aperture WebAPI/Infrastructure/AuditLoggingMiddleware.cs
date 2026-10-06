using System;
using System.Diagnostics;
using System.Threading.Tasks;
using Aperture_WebAPI.Models;
using Aperture_WebAPI.Repositories;
using Microsoft.AspNetCore.Http;

namespace Aperture_WebAPI.Infrastructure
{
    public class AuditLoggingMiddleware
    {
        private readonly RequestDelegate _next;

        public AuditLoggingMiddleware(RequestDelegate next)
        {
            _next = next;
        }

        public async Task InvokeAsync(HttpContext context)
        {
            Guid requestId = Guid.NewGuid();

            DateTime startedAt = DateTime.UtcNow;

            Stopwatch stopwatch = Stopwatch.StartNew();

            bool completed = false;

            string errorMessage = null;

            try
            {
                await _next(context);

                completed = true;
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
                    WriteAuditLog(
                        context,
                        completed,
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

        private void WriteAuditLog(
    HttpContext context,
    bool completed,
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

            // No status when the request threw: the response was never produced.
            int? statusCode = null;

            if (completed)
            {
                statusCode =
                    context.Response.StatusCode;
            }

            bool success =
                completed &&
                statusCode >= 200 &&
                statusCode < 400 &&
                string.IsNullOrWhiteSpace(errorMessage);

            var auditLog = new AuditLog
            {
                RequestId = requestId,

                UserId = userId,

                Username = username,

                HttpMethod =
                    context.Request.Method,

                Endpoint =
                    context.Request.Path.Value,

                QueryString =
                    context.Request.QueryString.Value,

                StatusCode =
                    statusCode,

                IsSuccess =
                    success,

                IpAddress =
                    context.Connection.RemoteIpAddress?.ToString(),

                UserAgent =
                    GetUserAgent(context.Request),

                RequestBody =
                    null, // Never persist request bodies.

                ResponseBody =
                    null, // Never persist response bodies.

                ErrorMessage =
                    errorMessage,

                StartedAt =
                    startedAt,

                CompletedAt =
                    System.DateTime.UtcNow,

                DurationMs =
                    (int)System.Math.Min(durationMs, int.MaxValue)
            };

            var repository =
                new AuditLogRepository();

            repository.Insert(auditLog);
        }

        private string GetUserAgent(
            HttpRequest request)
        {
            string userAgent =
                request.Headers.UserAgent.ToString();

            return string.IsNullOrEmpty(userAgent)
                ? null
                : userAgent;
        }
    }
}
