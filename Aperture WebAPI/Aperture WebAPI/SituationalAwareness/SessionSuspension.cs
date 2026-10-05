using System.Web;

namespace Aperture_WebAPI.SituationalAwareness
{
    /// <summary>
    /// Suspend/restore for an open viewing session, without touching the database schema.
    ///
    /// A session is "suspended" simply by not being ended: when a periodic check fails for a reason
    /// that can recover (recipient left the allowed area, GPS fix missing, IP or device changed),
    /// the content is withheld for that check but the session stays open. The next passing check
    /// returns the content again, which is the "restore". The session row stays 'Active' in the
    /// database throughout, so no new SessionStatus value is needed; every check is still recorded
    /// in EnvironmentCheck, which gives the audit trail of suspensions.
    ///
    /// The controller passes the denial reason to KeepAlive() before deciding whether to end the
    /// session. Failures that can never recover (expired, revoked) still end it.
    /// </summary>
    public static class SessionSuspension
    {
        private const string TransientFailureKey = "SituationalAwareness.TransientFailure";

        internal static void ClearTransientFailure()
        {
            HttpContext context = HttpContext.Current;
            if (context != null)
            {
                context.Items.Remove(TransientFailureKey);
            }
        }

        internal static void MarkTransientFailure()
        {
            HttpContext context = HttpContext.Current;
            if (context != null)
            {
                context.Items[TransientFailureKey] = true;
            }
        }

        // Denial reasons (as worded by ContentController, IpGeolocationService and LocationCheck) for
        // conditions that can become true again mid-session. Anything not listed ends the session,
        // so an unrecognised or reworded message fails safe. Expiry and revocation are deliberately
        // absent: they can never recover. "IP geolocation failed" (the lookup provider erroring or
        // rate-limiting, e.g. HTTP 429) is also absent on purpose: it is not something the viewer can
        // fix, and keeping the session open would re-call the provider on every poll, and failed
        // lookups are not cached, which would make a rate limit worse.
        private static readonly string[] RecoverableReasonPrefixes =
        {
            "Client IP address changed",
            "Approved device required",
            "Country restriction",
            "State/region restriction",
            "City restriction"
        };

        /// <summary>
        /// True when a denied check should leave the session open (suspended) instead of ending it:
        /// either a situational-awareness check flagged the failure as recoverable on this request,
        /// or the denial reason is one of the recoverable conditions listed above.
        /// </summary>
        public static bool KeepAlive(string denialReason)
        {
            if (FlaggedRecoverable())
            {
                return true;
            }

            if (string.IsNullOrEmpty(denialReason))
            {
                return false;
            }

            foreach (string prefix in RecoverableReasonPrefixes)
            {
                if (denialReason.StartsWith(prefix, System.StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }

            return false;
        }

        private static bool FlaggedRecoverable()
        {
            HttpContext context = HttpContext.Current;
            if (context == null)
            {
                return false;
            }

            object flag = context.Items[TransientFailureKey];
            return flag != null && (bool)flag;
        }
    }
}
