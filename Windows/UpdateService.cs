using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;

namespace justQuit.Windows;

public sealed class UpdateService
{
    public const string DefaultFeedUrl = "https://raw.githubusercontent.com/agraja38/app-update-feeds/main/justquit-windows/update.json";

    private static readonly HttpClient HttpClient = CreateHttpClient();
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    public async Task CheckForUpdatesAsync(AppModel model, bool silent)
    {
        model.IsCheckingForUpdates = true;
        model.HasCheckedForUpdates = false;
        model.UpdateErrorMessage = string.Empty;
        model.AvailableUpdate = null;
        model.AvailableUpdateSizeBytes = null;
        model.RaiseDerivedStateChanged();

        try
        {
            var json = await GetStringNoCacheAsync(model.UpdateFeedUrl);
            var feed = JsonSerializer.Deserialize<UpdateFeed>(json, JsonOptions);
            if (feed is null)
            {
                throw new InvalidOperationException("The update feed could not be read.");
            }

            var currentVersion = GetCurrentVersion();
            if (!Version.TryParse(feed.Version, out var latestVersion) || latestVersion <= currentVersion)
            {
                model.AvailableUpdate = null;
                if (!silent)
                {
                    model.StatusMessage = "This is the latest version.";
                }

                return;
            }

            model.AvailableUpdate = feed;
            model.AvailableUpdateSizeBytes = feed.SizeBytes;
            model.StatusMessage = $"Update {feed.Version} is available.";
        }
        catch (Exception ex)
        {
            model.AvailableUpdate = null;
            model.AvailableUpdateSizeBytes = null;
            model.UpdateErrorMessage = ex is JsonException
                ? "The update feed format is invalid."
                : ex.Message;
            if (!silent)
            {
                model.StatusMessage = "Could not check for updates.";
            }
        }
        finally
        {
            model.IsCheckingForUpdates = false;
            model.HasCheckedForUpdates = true;
            model.RaiseDerivedStateChanged();
        }
    }

    public async Task InstallUpdateAsync(AppModel model)
    {
        var update = model.AvailableUpdate;
        if (update is null)
        {
            model.StatusMessage = "No update is ready to install.";
            return;
        }

        model.IsInstallingUpdate = true;
        model.StatusMessage = $"Downloading update {update.Version}...";

        try
        {
            var downloadUrl = ResolveDownloadUrl(update.DownloadUrl);
            var installerPath = await DownloadInstallerAsync(update, downloadUrl);

            model.StatusMessage = $"Installing update {update.Version}...";
            var launcherPath = CreateUpdateLauncher(installerPath);
            Process.Start(new ProcessStartInfo
            {
                FileName = launcherPath,
                UseShellExecute = true,
            });

            System.Windows.Application.Current.Shutdown();
        }
        catch (Exception ex)
        {
            model.UpdateErrorMessage = ex.Message;
            model.StatusMessage = "Could not install the update.";
            model.IsInstallingUpdate = false;
        }

        return;
    }

    private static Version GetCurrentVersion()
    {
        var informationalVersion = Assembly.GetExecutingAssembly()
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
            .InformationalVersion
            ?.Split('+', 2)[0];

        return Version.TryParse(informationalVersion, out var version)
            ? version
            : Assembly.GetExecutingAssembly().GetName().Version ?? new Version(1, 0, 0);
    }

    private static Uri ResolveDownloadUrl(string downloadUrl)
    {
        var resolved = downloadUrl;
        if (RuntimeInformation.ProcessArchitecture == Architecture.Arm64)
        {
            resolved = resolved.Replace("justQuit-Setup-x64.exe", "justQuit-Setup-ARM64.exe", StringComparison.OrdinalIgnoreCase);
            resolved = resolved.Replace("justquit-setup-x64.exe", "justQuit-Setup-ARM64.exe", StringComparison.OrdinalIgnoreCase);
        }

        return new Uri(resolved);
    }

    private static async Task<string> DownloadInstallerAsync(UpdateFeed update, Uri primaryUrl)
    {
        Exception? lastError = null;
        foreach (var downloadUrl in GetDownloadCandidates(update, primaryUrl))
        {
            try
            {
                var installerPath = Path.Combine(Path.GetTempPath(), Path.GetFileName(downloadUrl.LocalPath));
                using var response = await HttpClient.GetAsync(downloadUrl, HttpCompletionOption.ResponseHeadersRead);
                if (!response.IsSuccessStatusCode)
                {
                    throw new HttpRequestException(
                        $"Download failed with {(int)response.StatusCode} ({response.ReasonPhrase}) for {downloadUrl}.",
                        null,
                        response.StatusCode);
                }

                await using var source = await response.Content.ReadAsStreamAsync();
                await using var destination = File.Create(installerPath);
                await source.CopyToAsync(destination);
                return installerPath;
            }
            catch (Exception ex)
            {
                lastError = ex;
            }
        }

        throw lastError ?? new InvalidOperationException("The update installer could not be downloaded.");
    }

    private static IEnumerable<Uri> GetDownloadCandidates(UpdateFeed update, Uri primaryUrl)
    {
        var installerName = RuntimeInformation.ProcessArchitecture == Architecture.Arm64
            ? "justQuit-Setup-ARM64.exe"
            : "justQuit-Setup-x64.exe";

        yield return primaryUrl;
        yield return new Uri($"https://raw.githubusercontent.com/agraja38/app-update-feeds/main/justquit-windows/{installerName}");
        yield return new Uri($"https://github.com/agraja38/app-update-feeds/releases/download/justquit-windows-v{update.Version}/{installerName}");
        yield return new Uri($"https://github.com/agraja38/app-update-feeds/releases/latest/download/{installerName}");
    }

    private static HttpClient CreateHttpClient()
    {
        var client = new HttpClient();
        client.DefaultRequestHeaders.UserAgent.ParseAdd("justQuit-Windows-Updater/1.0");
        client.DefaultRequestHeaders.CacheControl = new CacheControlHeaderValue { NoCache = true };
        client.DefaultRequestHeaders.Pragma.ParseAdd("no-cache");
        return client;
    }

    private static async Task<string> GetStringNoCacheAsync(string url)
    {
        var builder = new UriBuilder(url);
        var separator = string.IsNullOrEmpty(builder.Query) ? string.Empty : "&";
        builder.Query = $"{builder.Query.TrimStart('?')}{separator}t={DateTimeOffset.UtcNow.ToUnixTimeSeconds()}";
        using var request = new HttpRequestMessage(HttpMethod.Get, builder.Uri);
        request.Headers.CacheControl = new CacheControlHeaderValue { NoCache = true };
        request.Headers.Pragma.ParseAdd("no-cache");
        using var response = await HttpClient.SendAsync(request);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadAsStringAsync();
    }

    private static string CreateUpdateLauncher(string installerPath)
    {
        var launcherPath = Path.Combine(Path.GetTempPath(), $"justQuit-Update-{Guid.NewGuid():N}.cmd");
        var currentProcessId = Environment.ProcessId;
        var installPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Programs",
            "justQuit",
            "justQuit.exe");

        var script = string.Join(
            Environment.NewLine,
            "@echo off",
            $"set PID={currentProcessId}",
            ":waitloop",
            "tasklist /FI \"PID eq %PID%\" | find \"%PID%\" >nul",
            "if not errorlevel 1 (",
            "  timeout /t 1 /nobreak >nul",
            "  goto waitloop",
            ")",
            $"start \"\" /wait \"{installerPath}\" /VERYSILENT /NORESTART",
            $"if exist \"{installPath}\" start \"\" \"{installPath}\"",
            "del \"%~f0\"");

        File.WriteAllText(launcherPath, script);
        return launcherPath;
    }
}
