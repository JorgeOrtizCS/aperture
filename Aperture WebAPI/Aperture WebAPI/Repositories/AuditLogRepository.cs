using System;
using MySql.Data.MySqlClient;
using Aperture_WebAPI.Config;
using Aperture_WebAPI.Models;
namespace Aperture_WebAPI.Repositories {
 public class AuditLogRepository {
  public void Insert(AuditLog log) {
   using(var db=new MySqlConnection(ConnectionStrings.Database)) {db.Open();using(var c=new MySqlCommand("INSERT INTO AuditLogs(UserID,EventType,Description,EventTime) VALUES(@user,@type,@description,@time)",db)) {
    c.Parameters.AddWithValue("@user",(object)log.UserId??DBNull.Value);
    c.Parameters.AddWithValue("@type",log.HttpMethod+" "+log.StatusCode);
    c.Parameters.AddWithValue("@description",log.Endpoint??"");
    c.Parameters.AddWithValue("@time",log.StartedAt);
    c.ExecuteNonQuery();
   }}
  }
 }
}
