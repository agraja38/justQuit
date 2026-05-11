using System.IO;
using System.Text.Json;

namespace justQuit.Windows;

public sealed class SettingsService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
    };

    private readonly string settingsPath;

    public SettingsService()
    {
        var settingsDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "justQuit");
        Directory.CreateDirectory(settingsDirectory);
        settingsPath = Path.Combine(settingsDirectory, "settings.json");
    }

    public PersistedSettings Load()
    {
        try
        {
            if (!File.Exists(settingsPath))
            {
                var defaults = new PersistedSettings();
                Save(defaults);
                return defaults;
            }

            var json = File.ReadAllText(settingsPath);
            return JsonSerializer.Deserialize<PersistedSettings>(json, JsonOptions) ?? new PersistedSettings();
        }
        catch
        {
            return new PersistedSettings();
        }
    }

    public void Save(PersistedSettings settings)
    {
        var json = JsonSerializer.Serialize(settings, JsonOptions);
        File.WriteAllText(settingsPath, json);
    }
}
