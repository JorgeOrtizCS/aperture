namespace Aperture_WebAPI.SituationalAwareness
{
    /// <summary>Outcome of a single situational-awareness condition (time window, location, ...).</summary>
    public sealed class ConditionResult
    {
        public bool Passed { get; private set; }
        public string Reason { get; private set; }

        /// <summary>
        /// True when the failure can resolve on its own (the recipient moves back into range, a GPS
        /// fix arrives, ...). A transient failure suspends a viewing session; a non-transient one
        /// (revoked, expired) ends it.
        /// </summary>
        public bool Transient { get; private set; }

        public static ConditionResult Pass()
        {
            return new ConditionResult { Passed = true };
        }

        public static ConditionResult Fail(string reason, bool transient)
        {
            return new ConditionResult { Passed = false, Reason = reason, Transient = transient };
        }
    }
}
