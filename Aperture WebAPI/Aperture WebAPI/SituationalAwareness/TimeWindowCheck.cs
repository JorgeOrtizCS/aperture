using System;

namespace Aperture_WebAPI.SituationalAwareness
{
    /// <summary>
    /// Time-window condition: content is only viewable between an optional start time and an
    /// optional expiration. Times are UTC, matching how AccessPolicy stores them.
    ///
    /// ContentController.Evaluate() still enforces the start rule inline with an identical message and
    /// asks ExpiredReason() for the expiry message, which adds the grace period for open sessions.
    /// TimePolicyController uses this class to validate and check a content's window.
    /// </summary>
    public static class TimeWindowCheck
    {
        /// <summary>
        /// How long an open viewing session waits, suspended, after its window expires. If the sender
        /// extends the window in that time the session resumes on its next check; otherwise it ends.
        /// </summary>
        public const int ExpiryGraceSeconds = 300;

        public const string ExpiredMessage = "Access has expired.";
        public const string AwaitingExtensionMessage = "Viewing time expired. Waiting for the sender to extend it.";

        /// <summary>
        /// Denial reason for an expired window. For an open session still inside the grace period
        /// the failure is flagged as recoverable, so the session is suspended instead of ended.
        /// Opening the content after expiry is always refused.
        /// </summary>
        public static string ExpiredReason(DateTime expiration, DateTime nowUtc, bool openSession)
        {
            if (openSession && nowUtc < expiration.AddSeconds(ExpiryGraceSeconds))
            {
                SessionSuspension.MarkTransientFailure();
                return AwaitingExtensionMessage;
            }

            return ExpiredMessage;
        }

        /// <summary>
        /// Validates a window a sender wants to set, with the same rules ContentController.Create()
        /// applies when content is shared. Either end may be null (unrestricted). Returns null when
        /// valid, otherwise the reason it is not.
        /// </summary>
        public static string ValidatePolicy(DateTime? start, DateTime? expiration, DateTime nowUtc)
        {
            if (start.HasValue && expiration.HasValue && expiration.Value <= start.Value)
            {
                return "The expiration must be after the start time.";
            }

            if (expiration.HasValue && expiration.Value <= nowUtc)
            {
                return "The expiration must be in the future.";
            }

            return null;
        }

        public static ConditionResult Evaluate(DateTime? start, DateTime? expiration, DateTime nowUtc)
        {
            if (start.HasValue && nowUtc < start.Value)
            {
                return ConditionResult.Fail("Access has not begun.", false);
            }

            if (expiration.HasValue && nowUtc >= expiration.Value)
            {
                return ConditionResult.Fail(ExpiredMessage, false);
            }

            return ConditionResult.Pass();
        }
    }
}
