using System;

namespace Aperture_WebAPI.SituationalAwareness
{
    /// <summary>
    /// Time-window condition: content is only viewable between an optional start time and an
    /// optional expiration. Times are UTC, matching how AccessPolicy stores them.
    ///
    /// Not called by the controller by default: ContentController.Evaluate() already enforces the
    /// same two rules inline with identical messages. It is here as this section's own
    /// implementation, ready to replace those two inline lines if the team wants one owner for it.
    /// </summary>
    public static class TimeWindowCheck
    {
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
