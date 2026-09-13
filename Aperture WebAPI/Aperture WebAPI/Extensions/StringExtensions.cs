namespace Aperture_WebAPI.Extensions
{
    public static class StringExtensions
    {
        public static string ToSafeString(this object value)
        {
            return value == null ? string.Empty : value.ToString();
        }
    }
}