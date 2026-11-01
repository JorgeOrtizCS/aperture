using System;
using System.Device.Location;
using Aperture_Desktop_Client.Models;
namespace Aperture_Desktop_Client.Services {
 public sealed class ClientLocationService : IDisposable {
  readonly GeoCoordinateWatcher watcher=new GeoCoordinateWatcher(GeoPositionAccuracy.High);
  bool running;
  public void Start() {running=true;watcher.Start(false);}
  public void Stop() {running=false;watcher.Stop();}
  public ClientLocation Current {
   get {
    var position=watcher.Position;
    if(!running || watcher.Status!=GeoPositionStatus.Ready || position.Location.IsUnknown ||
       DateTimeOffset.UtcNow-position.Timestamp>TimeSpan.FromSeconds(30))return null;
    return new ClientLocation {Latitude=position.Location.Latitude,Longitude=position.Location.Longitude};
   }
  }
  public void Dispose() {watcher.Stop();watcher.Dispose();}
 }
}
