using System;
namespace Aperture_Desktop_Client.Models {
 public class SharedContent {public int Id {get;set;} public string Title {get;set;} public string Body {get;set;} public string Owner {get;set;} public bool Mine {get;set;} public DateTime CreatedAt {get;set;} public string Status {get;set;} public string PolicyStatus {get;set;} public string Recipient {get;set;} }
 public class CreateContentRequest {public string Title {get;set;} public string Body {get;set;} public string FileDataBase64 {get;set;} public string FileType {get;set;} public string Recipient {get;set;} public int? MaxViews {get;set;} public DateTime? ExpiresAt {get;set;} public DateTime? StartTime {get;set;} public bool RequireTrustedDevice {get;set;} public bool ScreenshotRestriction {get;set;} public string RequiredLocation {get;set;} }
 public class PolicyUpdate {public string Status {get;set;} }
 public class SessionRequest {public Guid DeviceKey {get;set;} }
 public class SessionResult {public int SessionId {get;set;} public bool AccessGranted {get;set;} public string Message {get;set;} public string Title {get;set;} public string Body {get;set;} public string FileDataBase64 {get;set;} public string FileType {get;set;} }
 public class DeviceRegistration {public Guid DeviceKey {get;set;} public string DeviceName {get;set;} }
 public class DeviceRegistrationResult {public bool Trusted {get;set;} }
}
