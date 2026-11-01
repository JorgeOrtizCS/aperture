using System;
using Newtonsoft.Json;
using Aperture_WebAPI.Services;
namespace Aperture_WebAPI.Models {
 // Versioned storage contract, independent of the existing client request shape.
 public class ViewingRequirements {
  [JsonProperty(Required=Required.Always)]
  public int Version {get;set;} = 1;
  public DateTime? StartTime {get;set;}
  public DateTime? ExpiresAt {get;set;}
  public int? MaxViews {get;set;}
  public bool RequireTrustedDevice {get;set;}
  public bool ScreenshotRestriction {get;set;}
  public LocationPolicy Location {get;set;}
  public CameraRestrictions CameraRestrictions {get;set;}
  public static ViewingRequirements Parse(string json) {
   if(String.IsNullOrWhiteSpace(json))throw new JsonSerializationException("Missing requirements.");
   var policy=JsonConvert.DeserializeObject<ViewingRequirements>(json,new JsonSerializerSettings {MissingMemberHandling=MissingMemberHandling.Error,DateTimeZoneHandling=DateTimeZoneHandling.Utc});
   if(policy==null || policy.Version!=1 || (policy.MaxViews.HasValue && policy.MaxViews<1) ||
      (policy.StartTime.HasValue && policy.ExpiresAt.HasValue && policy.ExpiresAt<=policy.StartTime))
    throw new JsonSerializationException("Invalid requirements.");
   return policy;
  }
 }
 public class SharedContent {public int Id {get;set;} public string Title {get;set;} public string Body {get;set;} public string Owner {get;set;} public bool Mine {get;set;} public DateTime CreatedAt {get;set;} public string Status {get;set;} public string PolicyStatus {get;set;} public string Recipient {get;set;} public int? MaxViews {get;set;} public DateTime? ExpiresAt {get;set;} public DateTime? StartTime {get;set;} public bool RequireTrustedDevice {get;set;} public bool ScreenshotRestriction {get;set;} public string RequiredLocation {get;set;} public string AllowedCountry {get;set;} public string AllowedRegion {get;set;} public string AllowedCity {get;set;} }
 public class CreateContentRequest {public CameraRestrictions CameraRestrictions {get;set;} public string Title {get;set;} public string Body {get;set;} public string FileDataBase64 {get;set;} public string FileType {get;set;} public string Recipient {get;set;} public int? MaxViews {get;set;} public DateTime? ExpiresAt {get;set;} public DateTime? StartTime {get;set;} public bool RequireTrustedDevice {get;set;} public bool ScreenshotRestriction {get;set;} public string RequiredLocation {get;set;} public string AllowedCountry {get;set;} public string AllowedRegion {get;set;} public string AllowedCity {get;set;} }
 public class CameraRestrictions {
  public bool Enabled {get;set;}
  public bool BlockPhones {get;set;}
  public bool BlockMultiplePeople {get;set;}
  public bool RequireViewer {get;set;}
  public bool SupportsClient(int version) {return !Enabled || version>=1;}
 }
 public class PolicyUpdate {public string Status {get;set;} }
 public class SessionRequest {public int CameraPolicyVersion {get;set;} public Guid DeviceKey {get;set;} }
 public class SessionResult {public CameraRestrictions CameraRestrictions {get;set;} public int SessionId {get;set;} public bool AccessGranted {get;set;} public bool DeviceVerified {get;set;} public bool LocationVerified {get;set;} public string Message {get;set;} public string Title {get;set;} public string Body {get;set;} public string FileDataBase64 {get;set;} public string FileType {get;set;} }
 public class DeviceRegistration {public Guid DeviceKey {get;set;} public string DeviceName {get;set;} }
}
