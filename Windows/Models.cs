using System.Windows.Media;

namespace justQuit.Windows;

public sealed class RunningAppInfo
{
    public required int ProcessId { get; init; }
    public required string Name { get; init; }
    public required string AppKey { get; init; }
    public required string IdentifierText { get; init; }
    public required string? ExecutablePath { get; init; }
    public required ImageSource? Icon { get; init; }
    public required bool IsBackgroundApp { get; init; }
    public required bool CanBeQuit { get; init; }
}

public sealed class RunningAppRow
{
    public required RunningAppInfo App { get; init; }
    public required string Name { get; init; }
    public required ImageSource? Icon { get; init; }
    public required string ActionText { get; init; }
    public required bool CanToggle { get; init; }
}

public sealed class QuitProfile
{
    public required string Name { get; init; }
    public required List<string> ExcludedAppKeys { get; init; }
    public required List<string> IncludedBackgroundAppKeys { get; init; }
}

public sealed class ExportedSettings
{
    public required List<string> ExcludedAppKeys { get; init; }
    public required List<string> IncludedBackgroundAppKeys { get; init; }
    public required List<QuitProfile> Profiles { get; init; }
    public required bool ConfirmLargeQuitsEnabled { get; init; }
    public required int ConfirmationThreshold { get; init; }
    public required bool CountdownEnabled { get; init; }
    public required int CountdownSeconds { get; init; }
    public required bool NotificationsEnabled { get; init; }
    public required bool HotkeyEnabled { get; init; }
    public required bool LaunchAtLoginEnabled { get; init; }
    public string LicenseKey { get; init; } = string.Empty;
    public required string UpdateFeedUrl { get; init; }
}

public sealed class UpdateFeed
{
    public required string Version { get; init; }
    public required string DownloadUrl { get; init; }
    public string? ReleaseNotesUrl { get; init; }
    public string? Notes { get; init; }
    public long? SizeBytes { get; init; }
}

public sealed class RestoreSession
{
    public required List<string> ExecutablePaths { get; init; }
    public required List<string> AppNames { get; init; }
    public required DateTime CreatedAt { get; init; }
    public int Count => ExecutablePaths.Count;
}

public sealed class QuitSummary
{
    public required List<string> TargetNames { get; init; }
    public required List<string> TargetAppKeys { get; init; }
    public int Count => TargetNames.Count;
    public string Message => $"Asked {Count} app(s) to quit: {string.Join(", ", TargetNames)}";
}

public sealed class PersistedSettings
{
    public List<string> ExcludedAppKeys { get; set; } = [];
    public List<string> IncludedBackgroundAppKeys { get; set; } = [];
    public List<QuitProfile> Profiles { get; set; } = [];
    public bool ConfirmLargeQuitsEnabled { get; set; } = true;
    public int ConfirmationThreshold { get; set; } = 5;
    public bool CountdownEnabled { get; set; }
    public int CountdownSeconds { get; set; } = 5;
    public bool NotificationsEnabled { get; set; } = true;
    public bool HotkeyEnabled { get; set; }
    public bool LaunchAtLoginEnabled { get; set; }
    public bool FirstRunCompleted { get; set; }
    public string LicenseKey { get; set; } = string.Empty;
    public string UpdateFeedUrl { get; set; } = UpdateService.DefaultFeedUrl;
    public RestoreSession? LastRestoreSession { get; set; }
}
