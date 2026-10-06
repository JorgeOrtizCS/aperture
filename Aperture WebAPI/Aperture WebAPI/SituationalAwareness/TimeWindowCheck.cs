using System;

namespace Aperture_WebAPI.SituationalAwareness
{
    /// <summary>
    /// Time-window condition: content is only viewable between an optional start time and an
    /// optional expiration. Times are UTC, matching how AccessPolicy stores them.
    ///
    /// ContentController.Evaluate() still enforces the same two rules inline with identical messages;
    /// TimePolicyController uses this class to validate and check a content's window. It is ready to
    /// replace those two inline lines if the team wants one owner for it.
    /// </summary>
    public static class TimeWindowCheck
    {
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
                return ConditionResult.Fail("Access has expired.", false);
            }

            return ConditionResult.Pass();
        }
    }
}
