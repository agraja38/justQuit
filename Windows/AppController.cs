using System.ComponentModel;
using System.Windows;
using System.Windows.Threading;

namespace justQuit.Windows;

public sealed class AppController : IDisposable
{
    private readonly AppModel model;
    private readonly MainWindow window;
    private readonly TrayIconService trayIconService;
    private readonly HotkeyService hotkeyService;
    private readonly DispatcherTimer refreshTimer;
    private readonly DispatcherTimer countdownTimer;
    private readonly LaunchAtLoginService launchAtLoginService;
    private readonly UpdateService updateService;

    private int countdownRemaining;
    private bool exitRequested;

    public AppController()
    {
        model = new AppModel();
        window = new MainWindow(model);
        trayIconService = new TrayIconService(model.CurrentVersion);
        hotkeyService = new HotkeyService();
        launchAtLoginService = new LaunchAtLoginService();
        updateService = new UpdateService();

        refreshTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(3),
        };
        refreshTimer.Tick += (_, _) => model.RefreshApps();

        countdownTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(1),
        };
        countdownTimer.Tick += OnCountdownTick;

        window.Closing += OnWindowClosing;
        window.QuitRequested += (_, _) => TriggerQuitFlow();
        window.CheckForUpdatesRequested += async (_, _) => await CheckForUpdatesAsync(false);
        window.InstallUpdateRequested += (_, _) => InstallUpdate();

        trayIconService.OpenGuiRequested += ShowMainWindow;
        trayIconService.QuitAllRequested += TriggerQuitFlow;
        trayIconService.RestoreRequested += () => model.RestoreLastSession();
        trayIconService.ExitRequested += ExitApplication;
        trayIconService.ProfileRequested += profile => model.ApplyProfile(profile);
        trayIconService.LeftClickRequested += () =>
        {
            if (countdownTimer.IsEnabled)
            {
                CancelCountdown();
            }
            else
            {
                TriggerQuitFlow();
            }
        };

        model.PropertyChanged += OnModelPropertyChanged;
    }

    public void Start(string[] args)
    {
        trayIconService.Start();
        model.RefreshApps();
        refreshTimer.Start();
        ApplyLaunchAtLogin();
        ApplyHotkey();
        trayIconService.UpdateProfiles(model.Profiles);

        _ = CheckForUpdatesAsync(true);

        if (!model.FirstRunCompleted)
        {
            ShowMainWindow();
            System.Windows.MessageBox.Show(
                "justQuit starts in the tray, supports profiles and quick toggles, and can trigger from the global hotkey Ctrl+Alt+J.",
                "Welcome to justQuit",
                System.Windows.MessageBoxButton.OK,
                System.Windows.MessageBoxImage.Information);
            model.MarkOnboardingCompleted();
        }

        if (args.Contains("--quit-now", StringComparer.OrdinalIgnoreCase))
        {
            TriggerQuitFlow();
            var shutdownTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
            shutdownTimer.Tick += (_, _) =>
            {
                shutdownTimer.Stop();
                ExitApplication();
            };
            shutdownTimer.Start();
        }
    }

    public void ShowMainWindow()
    {
        model.RefreshApps();
        if (!window.IsVisible)
        {
            window.Show();
        }

        if (window.WindowState == WindowState.Minimized)
        {
            window.WindowState = WindowState.Normal;
        }

        window.Activate();
    }

    public void Dispose()
    {
        refreshTimer.Stop();
        countdownTimer.Stop();
        hotkeyService.Dispose();
        trayIconService.Dispose();
    }

    private async Task CheckForUpdatesAsync(bool silent)
    {
        await updateService.CheckForUpdatesAsync(model, silent);
    }

    private async void InstallUpdate()
    {
        await updateService.InstallUpdateAsync(model);
    }

    private void TriggerQuitFlow()
    {
        if (countdownTimer.IsEnabled)
        {
            CancelCountdown();
            return;
        }

        var summary = model.GetQuitSummary();
        if (summary is null)
        {
            return;
        }

        if (model.ShouldAskForConfirmation(summary.Count))
        {
            var confirmation = System.Windows.MessageBox.Show(
                string.Join(", ", summary.TargetNames),
                $"Quit {summary.Count} app(s)?",
                System.Windows.MessageBoxButton.OKCancel,
                System.Windows.MessageBoxImage.Warning);

            if (confirmation != System.Windows.MessageBoxResult.OK)
            {
                model.StatusMessage = "Quit cancelled.";
                return;
            }
        }

        if (model.IsProUnlocked && model.CountdownEnabled && model.CountdownSeconds > 0)
        {
            countdownRemaining = model.CountdownSeconds;
            model.StatusMessage = $"Quitting in {countdownRemaining} seconds...";
            trayIconService.ShowCountdown(countdownRemaining);
            countdownTimer.Start();
            return;
        }

        ExecuteQuit();
    }

    private void ExecuteQuit()
    {
        CancelCountdown(clearStatus: false);

        var summary = model.PerformQuitAll();
        if (summary is null)
        {
            return;
        }

        trayIconService.ClearCountdown();
        if (model.NotificationsEnabled)
        {
            trayIconService.ShowNotification("justQuit finished", summary.Message);
        }
    }

    private void CancelCountdown(bool clearStatus = true)
    {
        countdownTimer.Stop();
        countdownRemaining = 0;
        trayIconService.ClearCountdown();
        if (clearStatus)
        {
            model.StatusMessage = "Countdown cancelled.";
        }
    }

    private void ExitApplication()
    {
        exitRequested = true;
        window.Close();
        System.Windows.Application.Current.Shutdown();
    }

    private void ApplyHotkey()
    {
        if (model.HotkeyEnabled)
        {
            hotkeyService.Register(window, TriggerQuitFlow);
        }
        else
        {
            hotkeyService.Unregister();
        }
    }

    private void ApplyLaunchAtLogin()
    {
        launchAtLoginService.SetEnabled(model.LaunchAtLoginEnabled);
    }

    private void OnCountdownTick(object? sender, EventArgs e)
    {
        countdownRemaining--;
        if (countdownRemaining <= 0)
        {
            countdownTimer.Stop();
            ExecuteQuit();
            return;
        }

        model.StatusMessage = $"Quitting in {countdownRemaining} seconds...";
        trayIconService.ShowCountdown(countdownRemaining);
    }

    private void OnWindowClosing(object? sender, CancelEventArgs e)
    {
        if (exitRequested)
        {
            return;
        }

        e.Cancel = true;
        window.Hide();
    }

    private void OnModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(AppModel.HotkeyEnabled))
        {
            ApplyHotkey();
        }
        else if (e.PropertyName is nameof(AppModel.LaunchAtLoginEnabled))
        {
            ApplyLaunchAtLogin();
        }
        else if (e.PropertyName is nameof(AppModel.Profiles))
        {
            trayIconService.UpdateProfiles(model.Profiles);
        }
    }
}
