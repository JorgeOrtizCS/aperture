using System;
using System.Collections.Concurrent;
using System.Data.SqlClient;
using Aperture_WebAPI.Config;
using Aperture_WebAPI.Models;
namespace Aperture_WebAPI.Services {
 public class AuthenticationService {
  // The approved eight-table schema has no token table. Session tokens live only
  // in this IIS worker process and are lost on application restart/recycle.
  sealed class SessionToken {public int UserId;public DateTime ExpiresAt;}
  static readonly ConcurrentDictionary<string,SessionToken> Tokens=new ConcurrentDictionary<string,SessionToken>();
  public LoginResponse Login(LoginRequest request) {
   if(request==null || string.IsNullOrWhiteSpace(request.Username) || string.IsNullOrWhiteSpace(request.Password))return Failure("Username and password are required.");
   var user=FindUser(request.Username);if(user==null || !PasswordService.VerifyPassword(request.Password,user.PasswordHash))return Failure("Invalid username or password.");
   var token=TokenService.GenerateToken();var expires=DateTime.UtcNow.AddHours(8);Tokens[TokenService.HashToken(token)]=new SessionToken {UserId=user.Id,ExpiresAt=expires};
   return new LoginResponse {Success=true,Message="Login successful.",Token=token,ExpiresAt=expires,User=new UserInfo {Id=user.Id,Username=user.Username}};
  }
  static LoginResponse Failure(string message) {return new LoginResponse {Success=false,Message=message};}
  public bool Logout(string token) {SessionToken removed;return !string.IsNullOrWhiteSpace(token) && Tokens.TryRemove(TokenService.HashToken(token),out removed);}
  public ApplicationUser ValidateToken(string token) {
   if(string.IsNullOrWhiteSpace(token))return null;
   SessionToken session;var hash=TokenService.HashToken(token);if(!Tokens.TryGetValue(hash,out session))return null;
   if(session.ExpiresAt<=DateTime.UtcNow){Tokens.TryRemove(hash,out session);return null;}
   using(var db=new SqlConnection(ConnectionStrings.Database)) {db.Open();using(var c=new SqlCommand("SELECT UserID,Username,PasswordHash,DateCreated FROM Users WHERE UserID=@id",db)) {c.Parameters.AddWithValue("@id",session.UserId);using(var r=c.ExecuteReader()){if(!r.Read())return null;return new ApplicationUser {Id=r.GetInt32(0),Username=r.GetString(1),PasswordHash=r.GetString(2),CreatedAt=r.GetDateTime(3),IsActive=true};}}}
  }
  static ApplicationUser FindUser(string username) {
   using(var db=new SqlConnection(ConnectionStrings.Database)) {db.Open();using(var c=new SqlCommand("SELECT UserID,Username,PasswordHash,DateCreated FROM Users WHERE Username=@name",db)) {c.Parameters.AddWithValue("@name",username);using(var r=c.ExecuteReader()){if(!r.Read())return null;return new ApplicationUser {Id=r.GetInt32(0),Username=r.GetString(1),PasswordHash=r.GetString(2),CreatedAt=r.GetDateTime(3),IsActive=true};}}}
  }
 }
}
