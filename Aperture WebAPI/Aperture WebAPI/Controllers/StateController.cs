using System.Web.Http;
using Aperture_WebAPI.Filters;
using Aperture_WebAPI.Models;
using Aperture_WebAPI.Services;

namespace Aperture_WebAPI.Controllers
{
    [RoutePrefix("api/state")]
    public class StateController : ApiController
    {
        private readonly StateManagementService
            _stateService;

        public StateController()
        {
            _stateService =
                new StateManagementService();
        }

        [HttpPost]
        [Route("check")]
        [TokenAuthorize]
        public IHttpActionResult Check(StateCheckRequestDto request)
        {
            StateCheckResponseDto response = _stateService.CheckState(request);

            return Ok(response);
        }
    }
}