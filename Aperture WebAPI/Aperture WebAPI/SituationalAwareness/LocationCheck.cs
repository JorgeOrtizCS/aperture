using System;
using System.Globalization;
using Aperture_WebAPI.Infrastructure;
using Microsoft.AspNetCore.Http;
using Aperture_WebAPI.Services;
using Newtonsoft.Json;

namespace Aperture_WebAPI.SituationalAwareness
{
    /// <summary>
    /// What a sender can require for location. Stored as JSON in AccessPolicy.RequiredLocation.
    /// Either coarse (Country/Region/City, verified by IP lookup) or precise (a center point plus a
    /// radius in meters, verified against the client's own GPS fix). The JSON for coarse policies is
    /// identical to the existing LocationPolicy shape, so older rows keep working unchanged.
    /// </summary>
    public sealed class GeneralLocationPolicy
    {
        public string Country { get; set; }
        public string Region { get; set; }
        public string City { get; set; }
        public double? Latitude { get; set; }
        public double? Longitude { get; set; }
        public double? RadiusMeters { get; set; }
    }

    /// <summary>
    /// General location condition. Picks the right verification method for the policy: a precise
    /// distance check when the sender set a point and radius, otherwise the existing IP-geolocation
    /// check (IpGeolocationService is called as-is and not modified).
    /// </summary>
    public static class LocationCheck
    {
        private const double EarthRadiusMeters = 6371000;

        /// <summary>
        /// Builds the JSON to store in AccessPolicy.RequiredLocation, or null when the sender set no
        /// location restriction. Precise (all three of latitude, longitude, radius) wins over coarse.
        /// </summary>
        public static string BuildPolicyJson(
            string country, string region, string city,
            double? latitude, double? longitude, double? radiusMeters,
            out string error)
        {
            error = null;

            bool anyPrecise = latitude.HasValue || longitude.HasValue || radiusMeters.HasValue;
            bool allPrecise = latitude.HasValue && longitude.HasValue && radiusMeters.HasValue;

            if (anyPrecise && !allPrecise)
            {
                error = "Precise location needs latitude, longitude and radius together.";
                return null;
            }

            if (allPrecise)
            {
                if (!IsValidCoordinate(latitude.Value, longitude.Value) || !IsValidRadius(radiusMeters.Value))
                {
                    error = "The precise location (latitude, longitude, radius) is not valid.";
                    return null;
                }

                return Serialize(new GeneralLocationPolicy
                {
                    Latitude = latitude,
                    Longitude = longitude,
                    RadiusMeters = radiusMeters
                });
            }

            if (Blank(country) && Blank(region) && Blank(city))
            {
                return null;
            }

            return Serialize(new GeneralLocationPolicy
            {
                Country = Trim(country),
                Region = Trim(region),
                City = Trim(city)
            });
        }

        /// <summary>
        /// True when a stored policy asks for a precise (point + radius) check. Any precise field being
        /// present counts, so an incomplete policy is routed here and fails closed rather than being
        /// read as "no restriction" by the coarse path.
        /// </summary>
        public static bool IsPrecisePolicy(string requiredLocationJson)
        {
            try
            {
                var policy = JsonConvert.DeserializeObject<GeneralLocationPolicy>(requiredLocationJson);
                return policy != null &&
                       (policy.Latitude.HasValue || policy.Longitude.HasValue || policy.RadiusMeters.HasValue);
            }
            catch (JsonException)
            {
                return false;
            }
        }

        /// <summary>
        /// Evaluates a stored policy for the current web request: reads the client's GPS fix from the
        /// X-Client-Latitude / X-Client-Longitude headers and flags a recoverable failure so the session
        /// is suspended rather than ended (see SessionSuspension).
        /// </summary>
        public static ConditionResult Evaluate(string requiredLocationJson, string clientIp)
        {
            SessionSuspension.ClearTransientFailure();

            double? latitude = null;
            double? longitude = null;
            HttpContext context = CurrentHttpContext.Current;
            if (context != null)
            {
                latitude = ParseHeader(context.Request.Headers["X-Client-Latitude"]);
                longitude = ParseHeader(context.Request.Headers["X-Client-Longitude"]);
            }

            ConditionResult result = Evaluate(requiredLocationJson, clientIp, latitude, longitude);
            if (!result.Passed && result.Transient)
            {
                SessionSuspension.MarkTransientFailure();
            }

            return result;
        }

        // Missing header -> null (no fix). Present but unparseable -> NaN, which fails validation.
        private static double? ParseHeader(string value)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                return null;
            }

            double parsed;
            return double.TryParse(value.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out parsed)
                ? parsed
                : double.NaN;
        }

        public static ConditionResult Evaluate(
            string requiredLocationJson, string clientIp,
            double? recipientLatitude, double? recipientLongitude)
        {
            GeneralLocationPolicy policy;
            try
            {
                policy = JsonConvert.DeserializeObject<GeneralLocationPolicy>(requiredLocationJson);
            }
            catch (JsonException)
            {
                return ConditionResult.Fail("The geographic access policy is invalid.", false);
            }

            if (policy == null)
            {
                return ConditionResult.Pass();
            }

            bool anyPrecise = policy.Latitude.HasValue || policy.Longitude.HasValue || policy.RadiusMeters.HasValue;
            bool allPrecise = policy.Latitude.HasValue && policy.Longitude.HasValue && policy.RadiusMeters.HasValue;

            if (anyPrecise && !allPrecise)
            {
                return ConditionResult.Fail("The precise location policy is incomplete.", false);
            }

            return allPrecise
                ? VerifyPrecise(policy, recipientLatitude, recipientLongitude)
                : VerifyByIp(policy, clientIp);
        }

        private static ConditionResult VerifyByIp(GeneralLocationPolicy policy, string clientIp)
        {
            var coarse = new LocationPolicy
            {
                Country = policy.Country,
                Region = policy.Region,
                City = policy.City
            };

            LocationVerification verification = IpGeolocationService.Verify(clientIp, coarse);

            return verification.Success && verification.Matches
                ? ConditionResult.Pass()
                : ConditionResult.Fail(verification.Message, true);
        }

        private static ConditionResult VerifyPrecise(
            GeneralLocationPolicy policy, double? recipientLatitude, double? recipientLongitude)
        {
            if (!IsValidCoordinate(policy.Latitude.Value, policy.Longitude.Value) || !IsValidRadius(policy.RadiusMeters.Value))
            {
                return ConditionResult.Fail("The precise location policy is invalid.", false);
            }

            if (!recipientLatitude.HasValue || !recipientLongitude.HasValue)
            {
                return ConditionResult.Fail(
                    "This content requires precise location, but the client did not provide GPS coordinates.", true);
            }

            // A failed or spoofed GPS reading (NaN, out of range) must never pass the radius check:
            // any comparison against NaN is false, which would otherwise read as "inside the radius".
            if (!IsValidCoordinate(recipientLatitude.Value, recipientLongitude.Value))
            {
                return ConditionResult.Fail("The client's GPS coordinates were invalid.", true);
            }

            double distance = HaversineDistanceMeters(
                policy.Latitude.Value, policy.Longitude.Value,
                recipientLatitude.Value, recipientLongitude.Value);

            return distance <= policy.RadiusMeters.Value
                ? ConditionResult.Pass()
                : ConditionResult.Fail("Recipient is outside the required location radius.", true);
        }

        /// <summary>Great-circle distance between two lat/long points, in meters.</summary>
        private static double HaversineDistanceMeters(double lat1, double lon1, double lat2, double lon2)
        {
            double rLat1 = ToRadians(lat1);
            double rLon1 = ToRadians(lon1);
            double rLat2 = ToRadians(lat2);
            double rLon2 = ToRadians(lon2);

            double dLat = rLat2 - rLat1;
            double dLon = rLon2 - rLon1;

            double h = Math.Pow(Math.Sin(dLat / 2), 2) +
                       Math.Cos(rLat1) * Math.Cos(rLat2) * Math.Pow(Math.Sin(dLon / 2), 2);

            return 2 * EarthRadiusMeters * Math.Asin(Math.Sqrt(h));
        }

        private static double ToRadians(double degrees)
        {
            return degrees * Math.PI / 180.0;
        }

        private static bool IsValidCoordinate(double latitude, double longitude)
        {
            return !double.IsNaN(latitude) && !double.IsInfinity(latitude) &&
                   !double.IsNaN(longitude) && !double.IsInfinity(longitude) &&
                   latitude >= -90 && latitude <= 90 &&
                   longitude >= -180 && longitude <= 180;
        }

        private static bool IsValidRadius(double radiusMeters)
        {
            return !double.IsNaN(radiusMeters) && !double.IsInfinity(radiusMeters) && radiusMeters > 0;
        }

        private static string Serialize(GeneralLocationPolicy policy)
        {
            return JsonConvert.SerializeObject(
                policy, new JsonSerializerSettings { NullValueHandling = NullValueHandling.Ignore });
        }

        private static bool Blank(string value)
        {
            return string.IsNullOrWhiteSpace(value);
        }

        private static string Trim(string value)
        {
            return Blank(value) ? null : value.Trim();
        }
    }
}
