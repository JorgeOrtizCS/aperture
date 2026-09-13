using System.Data.SqlClient;
using Aperture_WebAPI.Config;
using Aperture_WebAPI.Models;

namespace Aperture_WebAPI.Repositories
{
    public class ContentObjectRepository
    {
        public ContentObject GetByContentObjectId(
            int contentObjectId)
        {
            using (SqlConnection connection = new SqlConnection(ConnectionStrings.Database))
            {
                connection.Open();

                const string sql = @"
                    SELECT
                        ContentObjectId,
                        JSON
                    FROM ContentState
                    WHERE ContentObjectId = @ContentObjectId";

                using (SqlCommand command =
                       new SqlCommand(sql, connection))
                {
                    command.Parameters.AddWithValue(
                        "@ContentObjectId",
                        contentObjectId);

                    using (SqlDataReader reader = command.ExecuteReader())
                    {
                        if (!reader.Read())
                            return null;

                        return new ContentObject
                        {
                            ContentObjectId = reader.GetInt32(0),
                            Json = reader.GetString(1)
                        };
                    }
                }
            }
        }
    }
}