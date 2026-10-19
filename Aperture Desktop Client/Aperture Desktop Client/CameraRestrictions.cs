namespace Aperture_Desktop_Client
{
    // Supplied by the sender and returned by the API, never recipient preferences.
    public sealed class CameraRestrictions
    {
        public bool Enabled { get; set; } = true;
        public bool BlockPhones { get; set; } = true;
        public bool BlockMultiplePeople { get; set; } = true;
        public bool RequireViewer { get; set; }

        public bool SameAs(CameraRestrictions other)
        {
            return other != null && Enabled == other.Enabled && BlockPhones == other.BlockPhones &&
                BlockMultiplePeople == other.BlockMultiplePeople && RequireViewer == other.RequireViewer;
        }
    }
}
