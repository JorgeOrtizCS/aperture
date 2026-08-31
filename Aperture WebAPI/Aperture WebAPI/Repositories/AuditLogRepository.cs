using System;
using System.Data.SqlClient;
using Aperture_WebAPI.Config;
using Aperture_WebAPI.Models;

namespace Aperture_WebAPI.Repositories
{
    public class AuditLogRepository
    {
        public void Insert(AuditLog log)
        {
            using (SqlConnection connection = new SqlConnection(ConnectionStrings.Database))
            {
                connection.Open();

                const string sql = @"
                    INSERT INTO AuditLogs
                    (
                        RequestId,
                        UserId,
                        Username,
                        HttpMethod,
                        Endpoint,
                        QueryString,
                        StatusCode,
                        IsSuccess,
                        IpAddress,
                        UserAgent,
                        RequestBody,
                        ResponseBody,
                        ErrorMessage,
                        StartedAt,
                        CompletedAt,
                        DurationMs
                    )
                    VALUES
                    (
                        @RequestId,
                        @UserId,
                        @Username,
                        @HttpMethod,
                        @Endpoint,
                        @QueryString,
                        @StatusCode,
                        @IsSuccess,
                        @IpAddress,
                        @UserAgent,
                        @RequestBody,
                        @ResponseBody,
                        @ErrorMessage,
                        @StartedAt,
                        @CompletedAt,
                        @DurationMs
                    )";

                using (SqlCommand command =
                       new SqlCommand(sql, connection))
                {
                    command.Parameters.AddWithValue(
                        "@RequestId",
                        log.RequestId);

                    command.Parameters.AddWithValue(
                        "@UserId",
                        (object)log.UserId ?? DBNull.Value);

                    command.Parameters.AddWithValue(
                        "@Username",
                        (object)log.Username ?? DBNull.Value);

                    command.Parameters.AddWithValue(
                        "@HttpMethod",
                        log.HttpMethod);

                    command.Parameters.AddWithValue(
                        "@Endpoint",
                        log.Endpoint);

                    command.Parameters.AddWithValue(
                        "@QueryString",
                        (object)log.QueryString ?? DBNull.Value);

                    command.Parameters.AddWithValue(
                        "@StatusCode",
                        (object)log.StatusCode ?? DBNull.Value);

                    command.Parameters.AddWithValue(
                        "@IsSuccess",
                        log.IsSuccess);

                    command.Parameters.AddWithValue(
                        "@IpAddress",
                        (object)log.IpAddress ?? DBNull.Value);

                    command.Parameters.AddWithValue(
                        "@UserAgent",
                        (object)log.UserAgent ?? DBNull.Value);

                    command.Parameters.AddWithValue(
                        "@RequestBody",
                        (object)log.RequestBody ?? DBNull.Value);

                    command.Parameters.AddWithValue(
                        "@ResponseBody",
                        (object)log.ResponseBody ?? DBNull.Value);

                    command.Parameters.AddWithValue(
                        "@ErrorMessage",
                        (object)log.ErrorMessage ?? DBNull.Value);

                    command.Parameters.AddWithValue(
                        "@StartedAt",
                        log.StartedAt);

                    command.Parameters.AddWithValue(
                        "@CompletedAt",
                        (object)log.CompletedAt ?? DBNull.Value);

                    command.Parameters.AddWithValue(
                        "@DurationMs",
                        (object)log.DurationMs ?? DBNull.Value);

                    command.ExecuteNonQuery();
                }
            }
        }
    }
}