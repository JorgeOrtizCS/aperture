namespace Aperture_WebAPI.Models
{
    public class StateCheckRequestDto
    {
        public int ContentObjectId { get; set; }
        public UserState State { get; set; }
    }
}