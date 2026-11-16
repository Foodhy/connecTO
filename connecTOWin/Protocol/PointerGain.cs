namespace ConnecTOWin.Protocol;

public static class PointerGain
{
    public static (double Dx, double Dy) CursorDelta(double dx, double dy)
    {
        var distance = Math.Sqrt((dx * dx) + (dy * dy));
        var gain = 1.0 + Math.Min(distance, 40) / 20;
        return (dx * gain, dy * gain);
    }
}

public static class CaptureMath
{
    public static int BitRate(int width, int height)
    {
        var pixels = Math.Max(width * height, 1);
        var scaled = 5_000_000L * pixels / (1280 * 720);
        return (int)Math.Min(20_000_000L, Math.Max(2_000_000L, scaled));
    }

    public static (int Width, int Height) OutputSize(int sourceWidth, int sourceHeight, int longSide)
    {
        var nativeLong = (double)Math.Max(sourceWidth, sourceHeight);
        var requested = Math.Min(nativeLong, Math.Max(longSide, 960));
        var scale = Math.Min(1.0, requested / Math.Max(nativeLong, 1));
        var width = Even((int)Math.Round(sourceWidth * scale));
        var height = Even((int)Math.Round(sourceHeight * scale));
        return (width, height);
    }

    public static int Even(int value)
    {
        var rounded = value & ~1;
        return Math.Max(2, rounded);
    }
}
