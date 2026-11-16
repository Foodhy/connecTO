using System.Text.Json;

namespace ConnecTOWin.Protocol;

public sealed record TrustedDevice(Guid Id, string Name, DateTime TrustedAt);

public static class AppleDate
{
    private static readonly DateTime Epoch = new(2001, 1, 1, 0, 0, 0, DateTimeKind.Utc);

    public static double ToSeconds(DateTime date) => (date.ToUniversalTime() - Epoch).TotalSeconds;

    public static DateTime FromSeconds(double seconds) => Epoch.AddSeconds(seconds);
}

public sealed class TrustedDeviceStore
{
    private readonly string path;

    public TrustedDeviceStore(string? path = null)
    {
        this.path = path ?? DefaultPath();
    }

    public static string DefaultPath()
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        return System.IO.Path.Combine(root, "connecTO", "trusted-devices.json");
    }

    public IReadOnlyList<TrustedDevice> Load()
    {
        if (!File.Exists(path))
        {
            return [];
        }

        try
        {
            using var document = JsonDocument.Parse(File.ReadAllBytes(path));
            if (document.RootElement.ValueKind != JsonValueKind.Array)
            {
                return [];
            }

            var devices = new List<TrustedDevice>();
            foreach (var item in document.RootElement.EnumerateArray())
            {
                if (!item.TryGetProperty("id", out var idNode) || !Guid.TryParse(idNode.GetString(), out var id))
                {
                    continue;
                }

                var name = item.TryGetProperty("name", out var nameNode) ? nameNode.GetString() ?? "" : "";
                var trustedAt = item.TryGetProperty("trustedAt", out var when) && when.TryGetDouble(out var seconds)
                    ? AppleDate.FromSeconds(seconds)
                    : DateTime.UnixEpoch;
                devices.Add(new TrustedDevice(id, name, trustedAt));
            }

            return devices;
        }
        catch (JsonException)
        {
            return [];
        }
        catch (IOException)
        {
            return [];
        }
    }

    public void Save(IReadOnlyList<TrustedDevice> devices)
    {
        var directory = System.IO.Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        using var stream = File.Create(path);
        using var writer = new Utf8JsonWriter(stream);
        writer.WriteStartArray();
        foreach (var device in devices)
        {
            writer.WriteStartObject();
            writer.WriteString("id", device.Id.ToString("D").ToUpperInvariant());
            writer.WriteString("name", device.Name);
            writer.WriteNumber("trustedAt", AppleDate.ToSeconds(device.TrustedAt));
            writer.WriteEndObject();
        }

        writer.WriteEndArray();
    }

    public void Upsert(TrustedDevice device)
    {
        var devices = Load().Where(item => item.Id != device.Id).ToList();
        devices.Add(device);
        Save(devices);
    }
}
