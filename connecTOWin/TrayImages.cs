namespace ConnecTOWin;

public static class TrayImages
{
    public static Avalonia.Controls.WindowIcon Load(bool linked)
    {
        var png = Png(32, linked);
        return new Avalonia.Controls.WindowIcon(new MemoryStream(png));
    }

    private static byte[] Png(int size, bool linked)
    {
        var stride = (size * 4) + 1;
        var raw = new byte[stride * size];
        for (var y = 0; y < size; y++)
        {
            raw[y * stride] = 0;
            for (var x = 0; x < size; x++)
            {
                var on = linked ? Tablet(x, y, size) : Waves(x, y, size);
                var pixel = (y * stride) + 1 + (x * 4);
                raw[pixel] = on ? (byte)255 : (byte)0;
                raw[pixel + 1] = on ? (byte)255 : (byte)0;
                raw[pixel + 2] = on ? (byte)255 : (byte)0;
                raw[pixel + 3] = on ? (byte)255 : (byte)0;
            }
        }

        using var compressed = new MemoryStream();
        using (var zlib = new System.IO.Compression.ZLibStream(compressed, System.IO.Compression.CompressionLevel.Fastest, true))
        {
            zlib.Write(raw);
        }

        var payload = compressed.ToArray();
        using var png = new MemoryStream();
        png.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });
        Chunk(png, "IHDR",
        [
            0, 0, 0, (byte)size,
            0, 0, 0, (byte)size,
            8, 6, 0, 0, 0,
        ]);
        Chunk(png, "IDAT", payload);
        Chunk(png, "IEND", []);
        return png.ToArray();
    }

    private static bool Waves(int x, int y, int size)
    {
        var cx = size / 2.0;
        var cy = size / 2.0;
        var distance = Math.Sqrt(((x - cx) * (x - cx)) + ((y - cy) * (y - cy)));
        return (distance > 3 && distance < 5) || (distance > 8 && distance < 10) || (distance > 13 && distance < 15);
    }

    private static bool Tablet(int x, int y, int size)
    {
        var left = 8;
        var right = size - 8;
        var top = 4;
        var bottom = size - 4;
        if (x < left || x >= right || y < top || y >= bottom)
        {
            return false;
        }

        var edge = x == left || x == right - 1 || y == top || y == bottom - 1;
        var camera = Math.Abs(x - (size / 2)) < 2 && y > bottom - 6;
        return edge || camera;
    }

    private static void Chunk(Stream stream, string type, byte[] data)
    {
        var length = new byte[4];
        length[0] = (byte)(data.Length >> 24);
        length[1] = (byte)(data.Length >> 16);
        length[2] = (byte)(data.Length >> 8);
        length[3] = (byte)data.Length;
        stream.Write(length);
        var kind = System.Text.Encoding.ASCII.GetBytes(type);
        stream.Write(kind);
        stream.Write(data);
        var crc = Crc(kind, data);
        stream.Write(new[] { (byte)(crc >> 24), (byte)(crc >> 16), (byte)(crc >> 8), (byte)crc });
    }

    private static uint Crc(byte[] type, byte[] data)
    {
        var crc = 0xFFFFFFFFu;
        foreach (var value in type.Concat(data))
        {
            crc ^= value;
            for (var bit = 0; bit < 8; bit++)
            {
                var mask = (crc & 1) == 1 ? 0xEDB88320u : 0;
                crc = (crc >> 1) ^ mask;
            }
        }

        return ~crc;
    }
}
