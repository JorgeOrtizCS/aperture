namespace Aperture_WebAPI.Models
{
    public class StateCheckResponseDto
    {
        public bool Success { get; set; }
        public bool AccessGranted { get; set; }
        public int ContentObjectId { get; set; }
        public string Message { get; set; }
    }
}