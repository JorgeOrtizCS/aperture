using Aperture_WebAPI.Models;
using Aperture_WebAPI.Repositories;
using Newtonsoft.Json;

namespace Aperture_WebAPI.Services
{
    public class StateManagementService
    {
        private readonly ContentObjectRepository _repository;

        public StateManagementService()
        {
            _repository = new ContentObjectRepository();
        }

        public StateCheckResponseDto CheckState(
            StateCheckRequestDto request)
        {
            if (request == null)
            {
                return Denied(
                    0,
                    "Invalid request.");
            }

            if (request.ContentObjectId <= 0)
            {
                return Denied(
                    request.ContentObjectId,
                    "ContentObjectId is required.");
            }

            if (request.State == null)
            {
                return Denied(
                    request.ContentObjectId,
                    "State is required.");
            }

            ContentObject contentState =
                _repository.GetByContentObjectId(
                    request.ContentObjectId);

            if (contentState == null)
            {
                return Denied(
                    request.ContentObjectId,
                    "No state requirements exist for this content object.");
            }

            Requirements requirements;

            try
            {
                requirements = JsonConvert.DeserializeObject<Requirements>(contentState.Json);
            }
            catch (JsonException)
            {
                return Denied(
                    request.ContentObjectId,
                    "The content object's requirements JSON is invalid.");
            }

            if (requirements == null)
            {
                return Denied(
                    request.ContentObjectId,
                    "The content object has no requirements.");
            }

            bool fulfilled =
                CompareRequirements(
                    requirements,
                    request.State);

            if (!fulfilled)
            {
                return Denied(
                    request.ContentObjectId,
                    "Required conditions have not been fulfilled.");
            }

            return new StateCheckResponseDto
            {
                Success = true,

                AccessGranted = true,

                ContentObjectId =
                    request.ContentObjectId,

                Message =
                    "All required conditions have been fulfilled."
            };
        }

        private bool CompareRequirements(
            Requirements requirements,
            UserState state)
        {
            if (requirements.IsLoggedIn &&
                !state.IsLoggedIn)
            {
                return false;
            }

            return true;
        }

        private StateCheckResponseDto Denied(
            int contentObjectId,
            string message)
        {
            return new StateCheckResponseDto
            {
                Success = true,

                AccessGranted = false,

                ContentObjectId =
                    contentObjectId,

                Message = message
            };
        }
    }
}