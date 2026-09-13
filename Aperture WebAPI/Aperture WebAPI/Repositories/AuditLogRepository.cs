using System;
using System.Data.SqlClient;
using Aperture_WebAPI.Config;
using Aperture_WebAPI.Models;
namespace Aperture_WebAPI.Repositories {
 public class AuditLogRepository {
  public void Insert(AuditLog log) {
   using(var db=new SqlConnection(ConnectionStrings.Database)) {db.Open();using(var c=new SqlCommand("INSERT INTO AuditLogs(UserID,EventType,Description,EventTime) VALUES(@user,@type,@description,@time)",db)) {
    c.Parameters.AddWithValue("@user",(object)log.UserId??DBNull.Value);
    c.Parameters.AddWithValue("@type",log.HttpMethod+" "+log.StatusCode);
    c.Parameters.AddWithValue("@description",log.Endpoint??"");
    c.Parameters.AddWithValue("@time",log.StartedAt);
    c.ExecuteNonQuery();
   }}
  }
 }
}
