using Aperture_WebAPI.Models;

namespace Aperture_WebAPI.Infrastructure
{
    public static class RequestUser
    {
        private const string UserKey = "AuthenticatedUser";

        public static void Set(
            ApplicationUser user)
        {
            var context =
                System.Web.HttpContext.Current;

            if (context != null)
            {
                context.Items[UserKey] = user;
            }
        }

        public static ApplicationUser Get()
        {
            var context =
                System.Web.HttpContext.Current;

            if (context == null)
                return null;

            return context.Items[UserKey]
                as ApplicationUser;
        }
    }
}