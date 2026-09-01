using System;
using System.Threading.Tasks;
using Aperture_Desktop_Client.Models;

namespace Aperture_Desktop_Client.Services
{
    public class StateService
    {
        private readonly ApiClient _apiClient;

        public StateService(ApiClient apiClient)
        {
            _apiClient = apiClient;
        }

        public async Task<StateCheckResponseDto> CheckState(
            int contentObjectId)
        {
            var request =
                new StateCheckRequestDto
                {
                    ContentObjectId =
                        contentObjectId,

                    State =
                        new UserState
                        {
                            IsLoggedIn = true,

                            AccessDateTime =
                                DateTime.UtcNow
                        }
                };

            return await _apiClient.PostAsync
                <StateCheckRequestDto,
                 StateCheckResponseDto>(
                    "api/state/check",
                    request);
        }
    }
}
