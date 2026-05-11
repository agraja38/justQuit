using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Text.Json;

namespace justQuit.Windows;

public sealed class AppModel : ObservableObject
{
    private readonly RunningAppService runningAppService = new();
    private readonly SettingsService settingsService = new();
    private readonly ObservableCollection<RunningAppInfo> runningApps = [];
    private readonly ObservableCollection<QuitProfile> profiles = [];

    private HashSet<string> excludedAppKeys = [];
    private HashSet<string> includedBackgroundAppKeys = [];
    private bool confirmLargeQuitsEnabled = true;
    private int confirmationThreshold = 5;
    private bool countdownEnabled;
    private int countdownSeconds = 5;
    private bool notificationsEnabled = true;
    private bool hotkeyEnabled;
    private bool launchAtLoginEnabled;
    private bool firstRunCompleted;
    private string licenseKey = string.Empty;
    private bool isProUnlocked;
    private string licenseId = string.Empty;
    private string licenseStatusMessage = "Activate justQuit Pro to unlock countdowns, confirmation, and profiles.";
    private string statusMessage = "Ready";
    private string newProfileName = string.Empty;
    private UpdateFeed? availableUpdate;
    private long? availableUpdateSizeBytes;
    private string updateErrorMessage = string.Empty;
    private bool isInstallingUpdate;
    private bool isCheckingForUpdates;
    private bool hasCheckedForUpdates;
    private RestoreSession? lastRestoreSession;
    private string searchText = string.Empty;
    private string updateFeedUrl = UpdateService.DefaultFeedUrl;

    public AppModel()
    {
        LoadPreferences();
    }

    public ObservableCollection<RunningAppInfo> RunningApps => runningApps;
    public IReadOnlyList<QuitProfile> Profiles => profiles;
    public IEnumerable<RunningAppRow> RegularApps => runningApps.Where(app => !app.IsBackgroundApp).Where(AppMatchesSearch).Select(ToRow);
    public IEnumerable<RunningAppRow> BackgroundApps => runningApps.Where(app => app.IsBackgroundApp).Where(AppMatchesSearch).Select(ToRow);
    public IEnumerable<RunningAppInfo> AppsToQuit => runningApps.Where(ShouldQuit);
    public int AppsToQuitCount => AppsToQuit.Count();
    public int ProtectedRegularAppCount => runningApps.Count(app => !app.IsBackgroundApp && IsExcluded(app));
    public int SkippedBackgroundAppCount => runningApps.Count(app => app.IsBackgroundApp && IsExcluded(app));
    public int IncludedBackgroundAppCount => runningApps.Count(app => app.IsBackgroundApp && ShouldQuit(app));

    public bool ConfirmLargeQuitsEnabled
    {
        get => confirmLargeQuitsEnabled;
        set { if (SetProperty(ref confirmLargeQuitsEnabled, value)) Persist(); }
    }

    public int ConfirmationThreshold
    {
        get => confirmationThreshold;
        set { if (SetProperty(ref confirmationThreshold, value)) Persist(); }
    }

    public bool CountdownEnabled
    {
        get => countdownEnabled;
        set { if (SetProperty(ref countdownEnabled, value)) Persist(); }
    }

    public int CountdownSeconds
    {
        get => countdownSeconds;
        set { if (SetProperty(ref countdownSeconds, value)) Persist(); }
    }

    public bool NotificationsEnabled
    {
        get => notificationsEnabled;
        set { if (SetProperty(ref notificationsEnabled, value)) Persist(); }
    }

    public bool HotkeyEnabled
    {
        get => hotkeyEnabled;
        set { if (SetProperty(ref hotkeyEnabled, value)) Persist(); }
    }

    public bool LaunchAtLoginEnabled
    {
        get => launchAtLoginEnabled;
        set { if (SetProperty(ref launchAtLoginEnabled, value)) Persist(); }
    }

    public bool FirstRunCompleted
    {
        get => firstRunCompleted;
        private set { if (SetProperty(ref firstRunCompleted, value)) Persist(); }
    }

    public string LicenseKey
    {
        get => licenseKey;
        set { if (SetProperty(ref licenseKey, value)) Persist(); }
    }

    public bool IsProUnlocked
    {
        get => isProUnlocked;
        private set
        {
            if (SetProperty(ref isProUnlocked, value))
            {
                OnPropertyChanged(nameof(ProBadgeText));
                OnPropertyChanged(nameof(LicenseActionButtonText));
                OnPropertyChanged(nameof(IsLicenseKeyEditable));
            }
        }
    }

    public string LicenseId
    {
        get => licenseId;
        private set
        {
            if (SetProperty(ref licenseId, value))
            {
                OnPropertyChanged(nameof(LicenseIdText));
            }
        }
    }

    public string LicenseStatusMessage
    {
        get => licenseStatusMessage;
        private set => SetProperty(ref licenseStatusMessage, value);
    }

    public string StatusMessage
    {
        get => statusMessage;
        set => SetProperty(ref statusMessage, value);
    }

    public string NewProfileName
    {
        get => newProfileName;
        set => SetProperty(ref newProfileName, value);
    }

    public UpdateFeed? AvailableUpdate
    {
        get => availableUpdate;
        set { if (SetProperty(ref availableUpdate, value)) RaiseDerivedStateChanged(); }
    }

    public long? AvailableUpdateSizeBytes
    {
        get => availableUpdateSizeBytes;
        set { if (SetProperty(ref availableUpdateSizeBytes, value)) RaiseDerivedStateChanged(); }
    }

    public string UpdateErrorMessage
    {
        get => updateErrorMessage;
        set { if (SetProperty(ref updateErrorMessage, value)) RaiseDerivedStateChanged(); }
    }

    public bool IsInstallingUpdate
    {
        get => isInstallingUpdate;
        set => SetProperty(ref isInstallingUpdate, value);
    }

    public bool IsCheckingForUpdates
    {
        get => isCheckingForUpdates;
        set { if (SetProperty(ref isCheckingForUpdates, value)) RaiseDerivedStateChanged(); }
    }

    public bool HasCheckedForUpdates
    {
        get => hasCheckedForUpdates;
        set { if (SetProperty(ref hasCheckedForUpdates, value)) RaiseDerivedStateChanged(); }
    }

    public RestoreSession? LastRestoreSession
    {
        get => lastRestoreSession;
        set
        {
            if (SetProperty(ref lastRestoreSession, value))
            {
                Persist();
                RaiseDerivedStateChanged();
            }
        }
    }

    public string SearchText
    {
        get => searchText;
        set
        {
            if (SetProperty(ref searchText, value))
            {
                RaiseDerivedStateChanged();
            }
        }
    }

    public string UpdateFeedUrl
    {
        get => updateFeedUrl;
        set { if (SetProperty(ref updateFeedUrl, value)) Persist(); }
    }

    public string CurrentVersion
    {
        get
        {
            var informationalVersion = Assembly.GetExecutingAssembly()
                .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
                .InformationalVersion
                ?.Split('+', 2)[0];

            if (!string.IsNullOrWhiteSpace(informationalVersion))
            {
                return informationalVersion;
            }

            return typeof(AppModel).Assembly.GetName().Version?.ToString(3) ?? "1.0.0";
        }
    }

    public string VersionBadgeText => $"Version {CurrentVersion}";
    public string WindowTitle => $"justQuit {CurrentVersion}";
    public string FooterText => $"Created by Agraja · v{CurrentVersion}";
    public string ProBadgeText => IsProUnlocked ? "Pro active" : "Pro";
    public string LicenseActionButtonText => IsProUnlocked ? "Remove License" : "Activate";
    public bool IsLicenseKeyEditable => !IsProUnlocked;
    public string LicenseIdText => string.IsNullOrWhiteSpace(LicenseId) ? string.Empty : $"License ID: {LicenseId}";

    public string UpdateStatusText
    {
        get
        {
            if (IsCheckingForUpdates) return "Checking for updates...";
            if (AvailableUpdate is not null) return $"Version {AvailableUpdate.Version} is ready.";
            if (HasCheckedForUpdates && string.IsNullOrEmpty(UpdateErrorMessage)) return "This is the latest version.";
            return $"Current version: {CurrentVersion}";
        }
    }

    public string AvailableUpdateVersionText => AvailableUpdate is null ? "No update available." : $"New version available: {AvailableUpdate.Version}";
    public string AvailableUpdateNotesText => AvailableUpdate?.Notes ?? string.Empty;
    public string AvailableUpdateSizeText => AvailableUpdateSizeBytes is null ? string.Empty : $"Update size: {FormatByteSize(AvailableUpdateSizeBytes.Value)}";
    public string LastRestoreSummaryText => LastRestoreSession is null ? "No recent session yet." : $"{LastRestoreSession.Count} app(s) saved from {DescribeRelativeTime(LastRestoreSession.CreatedAt)}.";
    public bool CanRestoreLastSession => LastRestoreSession is not null && LastRestoreSession.ExecutablePaths.Count > 0;

    public bool ShouldQuit(RunningAppInfo app) => app.IsBackgroundApp ? app.CanBeQuit && includedBackgroundAppKeys.Contains(app.AppKey) : !excludedAppKeys.Contains(app.AppKey);
    public bool IsExcluded(RunningAppInfo app) => !ShouldQuit(app);
    public string ProtectionActionText(RunningAppInfo app) => app.IsBackgroundApp ? (!app.CanBeQuit ? "Unavailable" : (ShouldQuit(app) ? "Skip" : "Include")) : (ShouldQuit(app) ? "Protect" : "Unprotect");
    public void ToggleProtection(RunningAppInfo app)
    {
        if (app.IsBackgroundApp)
        {
            if (!app.CanBeQuit) return;
            if (!includedBackgroundAppKeys.Add(app.AppKey)) includedBackgroundAppKeys.Remove(app.AppKey);
        }
        else
        {
            if (!excludedAppKeys.Add(app.AppKey)) excludedAppKeys.Remove(app.AppKey);
        }

        Persist();
        RaiseDerivedStateChanged();
    }

    public void RefreshApps()
    {
        runningApps.Clear();
        foreach (var app in runningAppService.GetRunningApps()) runningApps.Add(app);
        RaiseDerivedStateChanged();
    }

    public QuitSummary? GetQuitSummary()
    {
        var targets = AppsToQuit.ToList();
        if (targets.Count == 0)
        {
            StatusMessage = "Nothing to quit";
            return null;
        }

        return new QuitSummary
        {
            TargetNames = targets.Select(app => app.Name).ToList(),
            TargetAppKeys = targets.Select(app => app.AppKey).ToList(),
        };
    }

    public QuitSummary? PerformQuitAll()
    {
        var targets = AppsToQuit.ToList();
        var summary = runningAppService.QuitApps(targets);
        if (summary is null)
        {
            StatusMessage = "Nothing to quit";
            return null;
        }

        LastRestoreSession = new RestoreSession
        {
            ExecutablePaths = targets.Where(app => !string.IsNullOrWhiteSpace(app.ExecutablePath)).Select(app => app.ExecutablePath!).Distinct(StringComparer.OrdinalIgnoreCase).ToList(),
            AppNames = targets.Select(app => app.Name).ToList(),
            CreatedAt = DateTime.Now,
        };

        StatusMessage = summary.Message;
        Task.Delay(TimeSpan.FromSeconds(1.2)).ContinueWith(_ => App.Current.Dispatcher.Invoke(RefreshApps));
        return summary;
    }

    public void RestoreLastSession()
    {
        if (!CanRestoreLastSession || LastRestoreSession is null)
        {
            StatusMessage = "No recent session to restore.";
            return;
        }

        runningAppService.RestoreApps(LastRestoreSession);
        StatusMessage = $"Restored {LastRestoreSession.Count} app(s).";
    }

    public bool ShouldAskForConfirmation(int appCount) => IsProUnlocked && ConfirmLargeQuitsEnabled && appCount >= ConfirmationThreshold;

    public void SaveCurrentAsProfile()
    {
        if (!IsProUnlocked)
        {
            StatusMessage = "Activate justQuit Pro to save profiles.";
            return;
        }

        var trimmedName = NewProfileName.Trim();
        if (string.IsNullOrWhiteSpace(trimmedName))
        {
            StatusMessage = "Type a profile name first.";
            return;
        }

        var existing = profiles.FirstOrDefault(profile => string.Equals(profile.Name, trimmedName, StringComparison.OrdinalIgnoreCase));
        if (existing is not null) profiles.Remove(existing);

        profiles.Add(new QuitProfile
        {
            Name = trimmedName,
            ExcludedAppKeys = excludedAppKeys.OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToList(),
            IncludedBackgroundAppKeys = includedBackgroundAppKeys.OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToList(),
        });

        SortProfiles();
        NewProfileName = string.Empty;
        Persist();
        OnPropertyChanged(nameof(Profiles));
        StatusMessage = $"Saved profile {trimmedName}.";
    }

    public void ApplyProfile(QuitProfile profile)
    {
        if (!IsProUnlocked)
        {
            StatusMessage = "Activate justQuit Pro to apply profiles.";
            return;
        }

        excludedAppKeys = profile.ExcludedAppKeys.ToHashSet(StringComparer.OrdinalIgnoreCase);
        includedBackgroundAppKeys = profile.IncludedBackgroundAppKeys.ToHashSet(StringComparer.OrdinalIgnoreCase);
        Persist();
        RaiseDerivedStateChanged();
        StatusMessage = $"Applied profile {profile.Name}.";
    }

    public void DeleteProfile(QuitProfile profile)
    {
        if (!IsProUnlocked)
        {
            StatusMessage = "Activate justQuit Pro to manage profiles.";
            return;
        }

        profiles.Remove(profile);
        Persist();
        OnPropertyChanged(nameof(Profiles));
        StatusMessage = $"Deleted profile {profile.Name}.";
    }

    public void ExportSettings(string filePath)
    {
        var payload = new ExportedSettings
        {
            ExcludedAppKeys = excludedAppKeys.OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToList(),
            IncludedBackgroundAppKeys = includedBackgroundAppKeys.OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToList(),
            Profiles = profiles.ToList(),
            ConfirmLargeQuitsEnabled = ConfirmLargeQuitsEnabled,
            ConfirmationThreshold = ConfirmationThreshold,
            CountdownEnabled = CountdownEnabled,
            CountdownSeconds = CountdownSeconds,
            NotificationsEnabled = NotificationsEnabled,
            HotkeyEnabled = HotkeyEnabled,
            LaunchAtLoginEnabled = LaunchAtLoginEnabled,
            LicenseKey = LicenseKey,
            UpdateFeedUrl = UpdateFeedUrl,
        };

        File.WriteAllText(filePath, JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true }));
        StatusMessage = "Exported settings.";
    }

    public void ImportSettings(string filePath)
    {
        var payload = JsonSerializer.Deserialize<ExportedSettings>(File.ReadAllText(filePath)) ?? throw new InvalidOperationException("The settings file could not be read.");
        excludedAppKeys = payload.ExcludedAppKeys.ToHashSet(StringComparer.OrdinalIgnoreCase);
        includedBackgroundAppKeys = payload.IncludedBackgroundAppKeys.ToHashSet(StringComparer.OrdinalIgnoreCase);
        profiles.Clear();
        foreach (var profile in payload.Profiles) profiles.Add(profile);
        confirmLargeQuitsEnabled = payload.ConfirmLargeQuitsEnabled;
        confirmationThreshold = payload.ConfirmationThreshold;
        countdownEnabled = payload.CountdownEnabled;
        countdownSeconds = payload.CountdownSeconds;
        notificationsEnabled = payload.NotificationsEnabled;
        hotkeyEnabled = payload.HotkeyEnabled;
        launchAtLoginEnabled = payload.LaunchAtLoginEnabled;
        licenseKey = payload.LicenseKey;
        LicenseId = string.Empty;
        updateFeedUrl = payload.UpdateFeedUrl;
        ActivateLicense();
        Persist();
        RaiseDerivedStateChanged();
        OnPropertyChanged(nameof(Profiles));
        OnPropertyChanged(nameof(ConfirmLargeQuitsEnabled));
        OnPropertyChanged(nameof(ConfirmationThreshold));
        OnPropertyChanged(nameof(CountdownEnabled));
        OnPropertyChanged(nameof(CountdownSeconds));
        OnPropertyChanged(nameof(NotificationsEnabled));
        OnPropertyChanged(nameof(HotkeyEnabled));
        OnPropertyChanged(nameof(LaunchAtLoginEnabled));
        OnPropertyChanged(nameof(LicenseKey));
        OnPropertyChanged(nameof(UpdateFeedUrl));
        StatusMessage = "Imported settings.";
    }

    public void MarkOnboardingCompleted() => FirstRunCompleted = true;

    public void ActivateLicense()
    {
        var result = LicenseService.Validate(LicenseKey);
        IsProUnlocked = result.IsValid;
        LicenseId = result.LicenseId ?? string.Empty;
        LicenseStatusMessage = result.Message;
        StatusMessage = result.Message;
        Persist();
    }

    public void RemoveLicense()
    {
        LicenseKey = string.Empty;
        IsProUnlocked = false;
        LicenseId = string.Empty;
        LicenseStatusMessage = "Activate justQuit Pro to unlock countdowns, confirmation, and profiles.";
        StatusMessage = "justQuit Pro license removed.";
        Persist();
    }

    internal void RaiseDerivedStateChanged()
    {
        OnPropertyChanged(nameof(RegularApps));
        OnPropertyChanged(nameof(BackgroundApps));
        OnPropertyChanged(nameof(AppsToQuit));
        OnPropertyChanged(nameof(AppsToQuitCount));
        OnPropertyChanged(nameof(ProtectedRegularAppCount));
        OnPropertyChanged(nameof(SkippedBackgroundAppCount));
        OnPropertyChanged(nameof(IncludedBackgroundAppCount));
        OnPropertyChanged(nameof(LastRestoreSummaryText));
        OnPropertyChanged(nameof(CanRestoreLastSession));
        OnPropertyChanged(nameof(UpdateStatusText));
        OnPropertyChanged(nameof(AvailableUpdateVersionText));
        OnPropertyChanged(nameof(AvailableUpdateNotesText));
        OnPropertyChanged(nameof(AvailableUpdateSizeText));
        OnPropertyChanged(nameof(VersionBadgeText));
        OnPropertyChanged(nameof(WindowTitle));
        OnPropertyChanged(nameof(FooterText));
        OnPropertyChanged(nameof(ProBadgeText));
    }

    private void LoadPreferences()
    {
        var settings = settingsService.Load();
        excludedAppKeys = settings.ExcludedAppKeys.ToHashSet(StringComparer.OrdinalIgnoreCase);
        includedBackgroundAppKeys = settings.IncludedBackgroundAppKeys.ToHashSet(StringComparer.OrdinalIgnoreCase);
        confirmLargeQuitsEnabled = settings.ConfirmLargeQuitsEnabled;
        confirmationThreshold = settings.ConfirmationThreshold;
        countdownEnabled = settings.CountdownEnabled;
        countdownSeconds = settings.CountdownSeconds;
        notificationsEnabled = settings.NotificationsEnabled;
        hotkeyEnabled = settings.HotkeyEnabled;
        launchAtLoginEnabled = settings.LaunchAtLoginEnabled;
        firstRunCompleted = settings.FirstRunCompleted;
        licenseKey = settings.LicenseKey;
        licenseId = string.Empty;
        lastRestoreSession = settings.LastRestoreSession;
        updateFeedUrl = settings.UpdateFeedUrl;
        profiles.Clear();
        foreach (var profile in settings.Profiles) profiles.Add(profile);
        ActivateLicense();
    }

    private void Persist()
    {
        settingsService.Save(new PersistedSettings
        {
            ExcludedAppKeys = excludedAppKeys.OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToList(),
            IncludedBackgroundAppKeys = includedBackgroundAppKeys.OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToList(),
            Profiles = profiles.ToList(),
            ConfirmLargeQuitsEnabled = ConfirmLargeQuitsEnabled,
            ConfirmationThreshold = ConfirmationThreshold,
            CountdownEnabled = CountdownEnabled,
            CountdownSeconds = CountdownSeconds,
            NotificationsEnabled = NotificationsEnabled,
            HotkeyEnabled = HotkeyEnabled,
            LaunchAtLoginEnabled = LaunchAtLoginEnabled,
            FirstRunCompleted = FirstRunCompleted,
            LicenseKey = LicenseKey,
            LastRestoreSession = LastRestoreSession,
            UpdateFeedUrl = UpdateFeedUrl,
        });
    }

    private bool AppMatchesSearch(RunningAppInfo app) => string.IsNullOrWhiteSpace(SearchText) || app.Name.Contains(SearchText, StringComparison.CurrentCultureIgnoreCase) || app.IdentifierText.Contains(SearchText, StringComparison.CurrentCultureIgnoreCase);

    private RunningAppRow ToRow(RunningAppInfo app) => new()
    {
        App = app,
        Name = app.Name,
        Icon = app.Icon,
        ActionText = ProtectionActionText(app),
        CanToggle = !app.IsBackgroundApp || app.CanBeQuit,
    };

    private void SortProfiles()
    {
        var ordered = profiles.OrderBy(profile => profile.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
        profiles.Clear();
        foreach (var profile in ordered) profiles.Add(profile);
    }

    private static string DescribeRelativeTime(DateTime timestamp)
    {
        var delta = DateTime.Now - timestamp;
        if (delta.TotalMinutes < 1) return "moments ago";
        if (delta.TotalHours < 1) return $"{Math.Max(1, (int)delta.TotalMinutes)} minute(s) ago";
        if (delta.TotalDays < 1) return $"{Math.Max(1, (int)delta.TotalHours)} hour(s) ago";
        return timestamp.ToString("g", CultureInfo.CurrentCulture);
    }

    private static string FormatByteSize(long value)
    {
        string[] suffixes = ["B", "KB", "MB", "GB"];
        double size = value;
        var suffixIndex = 0;
        while (size >= 1024 && suffixIndex < suffixes.Length - 1)
        {
            size /= 1024;
            suffixIndex++;
        }

        return $"{size:0.#} {suffixes[suffixIndex]}";
    }
}
