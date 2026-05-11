using Microsoft.Win32;

namespace justQuit.Windows;

public sealed class LaunchAtLoginService
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "justQuit";

    public void SetEnabled(bool enabled)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true)
                ?? Registry.CurrentUser.CreateSubKey(RunKeyPath);

            if (enabled)
            {
                key?.SetValue(ValueName, $"\"{Environment.ProcessPath}\"");
            }
            else
            {
                key?.DeleteValue(ValueName, false);
            }
        }
        catch
        {
        }
    }
}
