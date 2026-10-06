using System;
using System.Collections.Concurrent;
using Aperture_WebAPI.Config;
using System.Net;
using System.Net.Http;
using Newtonsoft.Json;
namespace Aperture_WebAPI.Services {
 public sealed class LocationPolicy {
  public string Country {get;set;}
  public string Region {get;set;}
  public string City {get;set;}
 }
 public sealed class LocationVerification {
  public bool Success {get;set;}
  public bool Matches {get;set;}
  public string Message {get;set;}
 }
 public static class IpGeolocationService {
  sealed class CachedLocation {public DateTime ExpiresAt;public GeoResponse Value;}
  sealed class GeoResponse {
   [JsonProperty("error")] public bool Error {get;set;}
   [JsonProperty("reason")] public string Reason {get;set;}
   [JsonProperty("country")] public string CountryCode {get;set;}
   [JsonProperty("country_name")] public string CountryName {get;set;}
   [JsonProperty("region")] public string Region {get;set;}
   [JsonProperty("region_code")] public string RegionCode {get;set;}
   [JsonProperty("city")] public string City {get;set;}
  }
  static readonly HttpClient Client=new HttpClient {Timeout=TimeSpan.FromSeconds(6)};
  static readonly ConcurrentDictionary<string,CachedLocation> Cache=new ConcurrentDictionary<string,CachedLocation>();
  public static LocationVerification Verify(string ipAddress,LocationPolicy policy) {
   if(policy==null || (Blank(policy.Country)&&Blank(policy.Region)&&Blank(policy.City)))return Result(true,true,"No geographic restriction.");
   GeoResponse location;string error;
   if(!TryLookup(ipAddress,out location,out error))return Result(false,false,"IP geolocation failed: "+error);
   if(!Matches(policy.Country,location.CountryCode,location.CountryName))return Result(true,false,"Country restriction was not satisfied.");
   if(!Matches(policy.Region,location.Region,location.RegionCode))return Result(true,false,"State/region restriction was not satisfied.");
   if(!Matches(policy.City,location.City))return Result(true,false,"City restriction was not satisfied.");
   return Result(true,true,"Geographic location verified.");
  }
  static bool TryLookup(string ipAddress,out GeoResponse location,out string error) {
   string cacheKey=LookupOwnPublicIp(ipAddress)?"server-public-ip":ipAddress;
   CachedLocation cached;
   if(Cache.TryGetValue(cacheKey,out cached)&&cached.ExpiresAt>DateTime.UtcNow){location=cached.Value;error=null;return true;}
   string template=AppSettings.Get("IpGeolocationUrl");
   if(String.IsNullOrWhiteSpace(template))template="https://ipapi.co/{0}/json/";
   string segment=LookupOwnPublicIp(ipAddress)?String.Empty:Uri.EscapeDataString(ipAddress);
   string url=String.IsNullOrEmpty(segment)?template.Replace("{0}/",String.Empty):String.Format(template,segment);
   try {
    string json=Client.GetStringAsync(url).GetAwaiter().GetResult();
    location=JsonConvert.DeserializeObject<GeoResponse>(json);
    if(location==null||location.Error){error=location==null?"Empty provider response.":(location.Reason??"Provider rejected the lookup.");location=null;return false;}
    Cache[cacheKey]=new CachedLocation {ExpiresAt=DateTime.UtcNow.AddMinutes(15),Value=location};error=null;return true;
   } catch(Exception ex) when(ex is HttpRequestException || ex is System.Threading.Tasks.TaskCanceledException || ex is JsonException) {location=null;error=ex.Message;return false;}
  }
  static bool LookupOwnPublicIp(string value) {
   if(String.Equals(value,"loopback",StringComparison.OrdinalIgnoreCase))return true;
   IPAddress ip;if(!IPAddress.TryParse(value,out ip))return true;
   if(IPAddress.IsLoopback(ip))return true;
   byte[] b=ip.GetAddressBytes();
   if(ip.AddressFamily==System.Net.Sockets.AddressFamily.InterNetwork)return b[0]==10 || b[0]==127 || (b[0]==169&&b[1]==254) || (b[0]==172&&b[1]>=16&&b[1]<=31) || (b[0]==192&&b[1]==168);
   return ip.IsIPv6LinkLocal || ip.IsIPv6SiteLocal || (b.Length==16 && (b[0]&0xfe)==0xfc);
  }
  static bool Matches(string expected,params string[] actual) {if(Blank(expected))return true;foreach(string value in actual)if(String.Equals(expected.Trim(),value==null?null:value.Trim(),StringComparison.OrdinalIgnoreCase))return true;return false;}
  static bool Blank(string value){return String.IsNullOrWhiteSpace(value);}
  static LocationVerification Result(bool success,bool matches,string message){return new LocationVerification {Success=success,Matches=matches,Message=message};}
 }
}
