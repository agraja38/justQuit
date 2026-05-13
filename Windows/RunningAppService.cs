using System.Drawing;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace justQuit.Windows;

public sealed class RunningAppService
{
    private readonly Dictionary<string, ImageSource?> iconCache = new(StringComparer.OrdinalIgnoreCase);
    private readonly object iconCacheLock = new();

    public IReadOnlyList<RunningAppInfo> GetRunningApps()
    {
        var currentProcessId = Environment.ProcessId;
        using var currentProcess = Process.GetCurrentProcess();
        var currentSessionId = currentProcess.SessionId;
        var windowsByProcess = EnumerateTopLevelWindows()
            .Where(window => window.ProcessId != currentProcessId)
            .GroupBy(window => window.ProcessId)
            .ToDictionary(group => group.Key, group => group.ToList());

        var apps = new List<RunningAppInfo>();

        foreach (var process in Process.GetProcesses().Where(process => process.Id != currentProcessId))
        {
            try
            {
                if (process.SessionId != currentSessionId || process.HasExited)
                {
                    continue;
                }

                var processWindows = windowsByProcess.TryGetValue(process.Id, out var entries) ? entries : [];
                var hasRegularWindow = processWindows.Any(window => window.IsAltTabCandidate);
                var hasAnyTopLevelWindow = processWindows.Count > 0;

                if (!hasRegularWindow && !hasAnyTopLevelWindow)
                {
                    continue;
                }

                var executablePath = TryGetExecutablePath(process);
                var name = ResolveDisplayName(process, executablePath, processWindows);
                var appKey = (executablePath ?? $"{process.ProcessName}.process").ToLowerInvariant();
                var identifierText = executablePath ?? process.ProcessName;
                var canBeQuit = hasRegularWindow || processWindows.Any(window => window.CanBeQuit);

                apps.Add(new RunningAppInfo
                {
                    ProcessId = process.Id,
                    Name = name,
                    AppKey = appKey,
                    IdentifierText = identifierText,
                    ExecutablePath = executablePath,
                    Icon = GetCachedIcon(executablePath),
                    IsBackgroundApp = !hasRegularWindow,
                    CanBeQuit = canBeQuit,
                });
            }
            catch
            {
            }
            finally
            {
                process.Dispose();
            }
        }

        return apps
            .OrderBy(app => app.Name, StringComparer.CurrentCultureIgnoreCase)
            .ThenBy(app => app.IdentifierText, StringComparer.CurrentCultureIgnoreCase)
            .ToList();
    }

    public QuitSummary? QuitApps(IEnumerable<RunningAppInfo> apps)
    {
        var targets = apps.ToList();
        if (targets.Count == 0)
        {
            return null;
        }

        foreach (var app in targets)
        {
            TryCloseApp(app.ProcessId);
        }

        return new QuitSummary
        {
            TargetNames = targets.Select(app => app.Name).ToList(),
            TargetAppKeys = targets.Select(app => app.AppKey).ToList(),
        };
    }

    public void RestoreApps(RestoreSession session)
    {
        foreach (var executablePath in session.ExecutablePaths.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                if (!File.Exists(executablePath))
                {
                    continue;
                }

                Process.Start(new ProcessStartInfo
                {
                    FileName = executablePath,
                    UseShellExecute = true,
                    WorkingDirectory = Path.GetDirectoryName(executablePath) ?? Environment.CurrentDirectory,
                });
            }
            catch
            {
            }
        }
    }

    private ImageSource? GetCachedIcon(string? executablePath)
    {
        if (string.IsNullOrWhiteSpace(executablePath))
        {
            return null;
        }

        lock (iconCacheLock)
        {
            if (iconCache.TryGetValue(executablePath, out var cachedIcon))
            {
                return cachedIcon;
            }
        }

        var icon = LoadAppIcon(executablePath);
        lock (iconCacheLock)
        {
            iconCache[executablePath] = icon;
        }

        return icon;
    }

    private static void TryCloseApp(int processId)
    {
        var windows = EnumerateTopLevelWindows()
            .Where(window => window.ProcessId == processId)
            .ToList();

        foreach (var window in windows.Where(window => window.CanBeQuit))
        {
            NativeMethods.PostMessage(window.Handle, NativeMethods.WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
        }

        try
        {
            using var process = Process.GetProcessById(processId);
            if (!process.HasExited)
            {
                process.CloseMainWindow();
            }
        }
        catch
        {
        }
    }

    private static IReadOnlyList<WindowInfo> EnumerateTopLevelWindows()
    {
        var windows = new List<WindowInfo>();

        NativeMethods.EnumWindows((handle, _) =>
        {
            if (!NativeMethods.IsWindow(handle))
            {
                return true;
            }

            NativeMethods.GetWindowThreadProcessId(handle, out var processId);
            if (processId == 0)
            {
                return true;
            }

            var title = GetWindowTitle(handle);
            var exStyle = NativeMethods.GetWindowLongPtr(handle, NativeMethods.GWL_EXSTYLE).ToInt64();
            var visible = NativeMethods.IsWindowVisible(handle);
            var owner = NativeMethods.GetWindow(handle, NativeMethods.GW_OWNER);
            var toolWindow = (exStyle & NativeMethods.WS_EX_TOOLWINDOW) != 0;
            var noActivate = (exStyle & NativeMethods.WS_EX_NOACTIVATE) != 0;
            var isAltTabCandidate = visible && owner == IntPtr.Zero && !toolWindow && !noActivate && !string.IsNullOrWhiteSpace(title);

            windows.Add(new WindowInfo
            {
                Handle = handle,
                ProcessId = unchecked((int)processId),
                Title = title,
                IsAltTabCandidate = isAltTabCandidate,
                CanBeQuit = owner == IntPtr.Zero,
            });

            return true;
        }, IntPtr.Zero);

        return windows;
    }

    private static string ResolveDisplayName(Process process, string? executablePath, IReadOnlyList<WindowInfo> windows)
    {
        if (!string.IsNullOrWhiteSpace(process.MainWindowTitle))
        {
            return process.MainWindowTitle;
        }

        var altTabTitle = windows.FirstOrDefault(window => window.IsAltTabCandidate && !string.IsNullOrWhiteSpace(window.Title))?.Title;
        if (!string.IsNullOrWhiteSpace(altTabTitle))
        {
            return altTabTitle!;
        }

        if (!string.IsNullOrWhiteSpace(executablePath))
        {
            return Path.GetFileNameWithoutExtension(executablePath);
        }

        return process.ProcessName;
    }

    private static string? TryGetExecutablePath(Process process)
    {
        try
        {
            var buffer = new StringBuilder(1024);
            var size = buffer.Capacity;
            if (NativeMethods.QueryFullProcessImageName(process.Handle, 0, buffer, ref size))
            {
                return buffer.ToString();
            }
        }
        catch
        {
        }

        try
        {
            return process.MainModule?.FileName;
        }
        catch
        {
            return null;
        }
    }

    private static ImageSource? LoadAppIcon(string? executablePath)
    {
        if (string.IsNullOrWhiteSpace(executablePath) || !File.Exists(executablePath))
        {
            return null;
        }

        try
        {
            using var icon = Icon.ExtractAssociatedIcon(executablePath);
            if (icon is null)
            {
                return null;
            }

            var source = Imaging.CreateBitmapSourceFromHIcon(
                icon.Handle,
                Int32Rect.Empty,
                BitmapSizeOptions.FromWidthAndHeight(24, 24));
            source.Freeze();
            return source;
        }
        catch
        {
            return null;
        }
    }

    private static string GetWindowTitle(IntPtr handle)
    {
        var length = NativeMethods.GetWindowTextLength(handle);
        if (length <= 0)
        {
            return string.Empty;
        }

        var builder = new StringBuilder(length + 1);
        NativeMethods.GetWindowText(handle, builder, builder.Capacity);
        return builder.ToString();
    }

    private sealed class WindowInfo
    {
        public required IntPtr Handle { get; init; }
        public required int ProcessId { get; init; }
        public required string Title { get; init; }
        public required bool IsAltTabCandidate { get; init; }
        public required bool CanBeQuit { get; init; }
    }
}
