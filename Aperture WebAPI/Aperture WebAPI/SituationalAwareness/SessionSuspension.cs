using System;
using System.Collections.Concurrent;
using Aperture_WebAPI.Infrastructure;
using Microsoft.AspNetCore.Http;

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
    ///
    /// The suspension state of each open session is tracked here too (in memory, like the session's
    /// IP/device binding), so it can be queried and so a sender or recipient can suspend a session on
    /// purpose (Hold). A held session's checks are denied until the hold time has passed; after that,
    /// the next check that passes every condition lifts the suspension.
    /// </summary>
    public static class SessionSuspension
    {
        public const string SourceManual = "manual";
        public const string SourceCheck = "check";

        public const int DefaultHoldSeconds = 30;
        public const int MaxHoldSeconds = 3600;

        // "Session suspended: " + reason must fit EnvironmentCheck.ViolationType (VARCHAR(100)).
        public const int MaxReasonLength = 80;
        private const string HeldMessagePrefix = "Session suspended";

        private sealed class SuspensionState
        {
            public string Source;
            public string Reason;
            public DateTime SinceUtc;
            public DateTime? HoldUntilUtc;
        }

        private static readonly ConcurrentDictionary<int, SuspensionState> Suspensions =
            new ConcurrentDictionary<int, SuspensionState>();

        /// <summary>
        /// Validates a hold a user asked for. Returns null when valid, otherwise the reason it is not.
        /// </summary>
        public static string ValidateHold(string reason, int? durationSeconds)
        {
            if (reason != null && reason.Trim().Length > MaxReasonLength)
            {
                return "The reason can be at most " + MaxReasonLength + " characters.";
            }

            if (durationSeconds.HasValue && (durationSeconds.Value < 1 || durationSeconds.Value > MaxHoldSeconds))
            {
                return "The duration must be between 1 and " + MaxHoldSeconds + " seconds.";
            }

            return null;
        }

        /// <summary>
        /// Suspends a session on purpose: checks are denied (session kept open) until holdUntilUtc,
        /// then the next fully passing check lifts the suspension.
        /// </summary>
        public static SessionSuspensionStatus Hold(int sessionId, string reason, int? durationSeconds, DateTime nowUtc)
        {
            var state = new SuspensionState
            {
                Source = SourceManual,
                Reason = string.IsNullOrWhiteSpace(reason) ? null : reason.Trim(),
                SinceUtc = nowUtc,
                HoldUntilUtc = nowUtc.AddSeconds(durationSeconds ?? DefaultHoldSeconds)
            };
            Suspensions[sessionId] = state;
            return ToStatus(sessionId, state);
        }

        /// <summary>
        /// True while a manual hold is still running; message is the denial to return for the check.
        /// </summary>
        public static bool IsHeld(int sessionId, DateTime nowUtc, out string message)
        {
            SuspensionState state;
            if (Suspensions.TryGetValue(sessionId, out state) &&
                state.HoldUntilUtc.HasValue && nowUtc < state.HoldUntilUtc.Value)
            {
                message = state.Reason == null ? HeldMessagePrefix + "." : HeldMessagePrefix + ": " + state.Reason;
                return true;
            }

            message = null;
            return false;
        }

        /// <summary>
        /// Updates a session's suspension after a periodic check that did not end it: a passing check
        /// lifts any suspension, a recoverable failure suspends it (keeping an existing hold's details).
        /// </summary>
        public static void RecordCheck(int sessionId, bool accessGranted, string denialReason, DateTime nowUtc)
        {
            if (accessGranted)
            {
                Clear(sessionId);
                return;
            }

            Suspensions.AddOrUpdate(
                sessionId,
                _ => new SuspensionState { Source = SourceCheck, Reason = denialReason, SinceUtc = nowUtc },
                (_, existing) => existing.Source == SourceManual
                    ? existing
                    : new SuspensionState { Source = SourceCheck, Reason = denialReason, SinceUtc = existing.SinceUtc });
        }

        /// <summary>Forgets a session's suspension (the session passed a check or has ended).</summary>
        public static void Clear(int sessionId)
        {
            SuspensionState removed;
            Suspensions.TryRemove(sessionId, out removed);
        }

        public static SessionSuspensionStatus GetStatus(int sessionId)
        {
            SuspensionState state;
            return Suspensions.TryGetValue(sessionId, out state)
                ? ToStatus(sessionId, state)
                : new SessionSuspensionStatus { SessionId = sessionId, Suspended = false };
        }

        private static SessionSuspensionStatus ToStatus(int sessionId, SuspensionState state)
        {
            return new SessionSuspensionStatus
            {
                SessionId = sessionId,
                Suspended = true,
                Source = state.Source,
                Reason = state.Reason,
                SinceUtc = state.SinceUtc,
                HoldUntilUtc = state.HoldUntilUtc
            };
        }
        private const string TransientFailureKey = "SituationalAwareness.TransientFailure";

        internal static void ClearTransientFailure()
        {
            HttpContext context = CurrentHttpContext.Current;
            if (context != null)
            {
                context.Items.Remove(TransientFailureKey);
            }
        }

        internal static void MarkTransientFailure()
        {
            HttpContext context = CurrentHttpContext.Current;
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
            HeldMessagePrefix,
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
            HttpContext context = CurrentHttpContext.Current;
            if (context == null)
            {
                return false;
            }

            object flag = context.Items[TransientFailureKey];
            return flag != null && (bool)flag;
        }
    }

    /// <summary>Suspension state of a viewing session.</summary>
    public sealed class SessionSuspensionStatus
    {
        public int SessionId { get; set; }

        /// <summary>True while content is being withheld from the session.</summary>
        public bool Suspended { get; set; }

        /// <summary>"manual" (suspended through the API) or "check" (a periodic check failed for a recoverable reason).</summary>
        public string Source { get; set; }

        public string Reason { get; set; }

        public DateTime? SinceUtc { get; set; }

        /// <summary>Manual suspensions only: checks are denied until this time; after it, the next passing check lifts the suspension.</summary>
        public DateTime? HoldUntilUtc { get; set; }
    }
}
