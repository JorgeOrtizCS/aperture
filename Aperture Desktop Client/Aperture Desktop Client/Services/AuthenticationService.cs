using System.Threading.Tasks;
using Aperture_Desktop_Client.Models;

namespace Aperture_Desktop_Client.Services
{
    public class AuthenticationService
    {
        private readonly ApiClient _apiClient;

        public ApiClient ApiClient
        {
            get { return _apiClient; }
        }

        public UserDto CurrentUser
        {
            get;
            private set;
        }

        public bool IsLoggedIn
        {
            get
            {
                return !string.IsNullOrWhiteSpace(
                    _apiClient.Token);
            }
        }

        public AuthenticationService(
            ApiClient apiClient)
        {
            _apiClient = apiClient;
        }

        public async Task<LoginResponseDto> Login(
            string username,
            string password)
        {
            var request =
                new LoginRequestDto
                {
                    Username = username,
                    Password = password
                };

            LoginResponseDto response =
                await _apiClient.PostAsync
                    <LoginRequestDto, LoginResponseDto>(
                        "api/auth/login",
                        request);

            if (response != null &&
                response.Success &&
                !string.IsNullOrWhiteSpace(
                    response.Token))
            {
                _apiClient.SetToken(
                    response.Token);

                CurrentUser =
                    response.User;
            }

            return response;
        }

        public async Task Logout()
        {
            if (!IsLoggedIn)
                return;

            try
            {
                await _apiClient.PostAsync(
                    "api/auth/logout");
            }
            finally
            {
                _apiClient.ClearToken();

                CurrentUser = null;
            }
        }
    }
}