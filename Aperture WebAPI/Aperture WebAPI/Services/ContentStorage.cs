using System;
using System.Configuration;
using System.Globalization;
using System.IO;
using System.Web;
using System.Web.Configuration;
using System.Web.Security;

namespace Aperture_WebAPI.Services
{
    internal static class ContentStorage
    {
        private const string Purpose = "Aperture.Content.v1";

        internal static void Write(int id, byte[] bytes)
        {
            var path = GetPath(id, ".protected");
            var temporaryPath = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            var encrypted = MachineKey.Protect(bytes, Purpose, GetContentPurpose(id));

            Directory.CreateDirectory(Path.GetDirectoryName(path));
            try
            {
                File.WriteAllBytes(temporaryPath, encrypted);
                File.Move(temporaryPath, path);
            }
            finally
            {
                File.Delete(temporaryPath);
            }
        }

        internal static byte[] Read(int id)
        {
            var legacyPath = GetPath(id, ".bin");
            byte[] encrypted;
            try
            {
                encrypted = File.ReadAllBytes(GetPath(id, ".protected"));
            }
            catch (FileNotFoundException)
            {
                // The viewing transaction holds the recipient lock during migration.
                var bytes = File.ReadAllBytes(legacyPath);
                Write(id, bytes);
                File.Delete(legacyPath);
                return bytes;
            }

            var plaintext = MachineKey.Unprotect(encrypted, Purpose, GetContentPurpose(id));
            // Retry cleanup if migration published the encrypted copy before being interrupted.
            File.Delete(legacyPath);
            return plaintext;
        }

        internal static void Delete(int id)
        {
            var path = GetPath(id, ".protected");
            if (Directory.Exists(Path.GetDirectoryName(path)))
                File.Delete(path);
        }

        private static string GetPath(int id, string extension)
        {
            var directory = HttpContext.Current.Server.MapPath("~/App_Data/ContentFiles");
            return Path.Combine(directory, id.ToString(CultureInfo.InvariantCulture) + extension);
        }

        private static string GetContentPurpose(int id)
        {
            var keys = (MachineKeySection)WebConfigurationManager.GetSection("system.web/machineKey");
            if (keys.ValidationKey.StartsWith("AutoGenerate", StringComparison.OrdinalIgnoreCase) ||
                keys.DecryptionKey.StartsWith("AutoGenerate", StringComparison.OrdinalIgnoreCase))
                throw new ConfigurationErrorsException("Content storage requires explicit machineKey keys.");

            return id.ToString(CultureInfo.InvariantCulture);
        }
    }
}
