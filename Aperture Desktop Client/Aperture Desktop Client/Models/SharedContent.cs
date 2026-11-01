using System;
namespace Aperture_Desktop_Client.Models {
 public class ContentCapabilities {public int CameraPolicyVersion {get;set;} }
 public class SharedContent {public DateTime? StartTime {get;set;} public DateTime? ExpiresAt {get;set;} public double? Latitude {get;set;} public double? Longitude {get;set;} public double? RadiusMeters {get;set;} public int Id {get;set;} public string Title {get;set;} public string Body {get;set;} public string Owner {get;set;} public bool Mine {get;set;} public DateTime CreatedAt {get;set;} public string Status {get;set;} public string PolicyStatus {get;set;} public string Recipient {get;set;} }
 public class CreateContentRequest {public double? Latitude {get;set;} public double? Longitude {get;set;} public double? RadiusMeters {get;set;} public CameraRestrictions CameraRestrictions {get;set;} public string Title {get;set;} public string Body {get;set;} public string FileDataBase64 {get;set;} public string FileType {get;set;} public string Recipient {get;set;} public int? MaxViews {get;set;} public DateTime? ExpiresAt {get;set;} public DateTime? StartTime {get;set;} public bool RequireTrustedDevice {get;set;} public bool ScreenshotRestriction {get;set;} public string RequiredLocation {get;set;} public string AllowedCountry {get;set;} public string AllowedRegion {get;set;} public string AllowedCity {get;set;} }
 public class ClientLocation {public double Latitude {get;set;} public double Longitude {get;set;} }
 public class TimeWindowRequest {public DateTime? StartTime {get;set;} public DateTime? ExpiresAt {get;set;} }
 public class PreciseLocationRequest {public double Latitude {get;set;} public double Longitude {get;set;} public double RadiusMeters {get;set;} }
 public class SuspendSessionRequest {public string Reason {get;set;} public int DurationSeconds {get;set;} }
 public class PolicyUpdate {public string Status {get;set;} }
 public class SessionRequest {public int CameraPolicyVersion {get;set;} public Guid DeviceKey {get;set;} }
 public class SessionResult {public bool Suspended {get;set;} public bool SessionEnded {get;set;} public CameraRestrictions CameraRestrictions {get;set;} public int SessionId {get;set;} public bool AccessGranted {get;set;} public string Message {get;set;} public string Title {get;set;} public string Body {get;set;} public string FileDataBase64 {get;set;} public string FileType {get;set;} }
 public class DeviceRegistration {public Guid DeviceKey {get;set;} public string DeviceName {get;set;} }
 public class DeviceRegistrationResult {public bool Trusted {get;set;} }
}
