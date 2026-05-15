using System.Windows;

namespace justQuit.Windows;

public partial class MainWindow : Window
{
    public MainWindow(AppModel model)
    {
        InitializeComponent();
        DataContext = model;
    }

    public event EventHandler? QuitRequested;
    public event EventHandler? CheckForUpdatesRequested;
    public event EventHandler? InstallUpdateRequested;

    private AppModel Model => (AppModel)DataContext;

    private void QuitAllClicked(object sender, RoutedEventArgs e) => QuitRequested?.Invoke(this, EventArgs.Empty);
    private async void RefreshClicked(object sender, RoutedEventArgs e) => await Model.RefreshAppsAsync();
    private void RestoreClicked(object sender, RoutedEventArgs e) => Model.RestoreLastSession();
    private void CheckForUpdatesClicked(object sender, RoutedEventArgs e) => CheckForUpdatesRequested?.Invoke(this, EventArgs.Empty);
    private void InstallUpdateClicked(object sender, RoutedEventArgs e) => InstallUpdateRequested?.Invoke(this, EventArgs.Empty);
    private void SaveProfileClicked(object sender, RoutedEventArgs e) => Model.SaveCurrentAsProfile();
    private async void LicenseActionClicked(object sender, RoutedEventArgs e)
    {
        if (Model.IsProUnlocked)
        {
            Model.RemoveLicense();
        }
        else
        {
            await Model.ActivateLicenseAsync();
        }
    }

    private void ExportSettingsClicked(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            FileName = "justQuit-settings.json",
            Filter = "JSON files (*.json)|*.json",
        };

        if (dialog.ShowDialog(this) == true)
        {
            try
            {
                Model.ExportSettings(dialog.FileName);
            }
            catch
            {
                Model.StatusMessage = "Could not export settings.";
            }
        }
    }

    private void ImportSettingsClicked(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Filter = "JSON files (*.json)|*.json",
            Multiselect = false,
        };

        if (dialog.ShowDialog(this) == true)
        {
            try
            {
                Model.ImportSettings(dialog.FileName);
            }
            catch
            {
                Model.StatusMessage = "Could not import settings.";
            }
        }
    }

    private void ApplyProfileClicked(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is QuitProfile profile)
        {
            Model.ApplyProfile(profile);
        }
    }

    private void DeleteProfileClicked(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is QuitProfile profile)
        {
            Model.DeleteProfile(profile);
        }
    }

    private void ProtectionButtonClicked(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is RunningAppRow row)
        {
            Model.ToggleProtection(row.App);
        }
    }
}
