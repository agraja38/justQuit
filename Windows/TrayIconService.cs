using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace justQuit.Windows;

public sealed class TrayIconService : IDisposable
{
    private readonly string versionText;
    private readonly NotifyIcon notifyIcon;
    private readonly ContextMenuStrip menu;
    private readonly ToolStripMenuItem restoreItem;
    private readonly ToolStripMenuItem profilesItem;
    private readonly Icon appIcon;
    private readonly ToolStripMenuItem countdownItem;
    private Icon? countdownIcon;

    public TrayIconService(string versionText)
    {
        this.versionText = versionText;
        menu = new ContextMenuStrip();
        menu.Items.Add("Created by Agraja").Enabled = false;
        menu.Items.Add($"Version {versionText}").Enabled = false;
        countdownItem = new ToolStripMenuItem("Countdown: off") { Enabled = false, Visible = false };
        menu.Items.Add(countdownItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Open GUI", null, (_, _) => OpenGuiRequested?.Invoke());
        menu.Items.Add("Quit All Eligible Apps", null, (_, _) => QuitAllRequested?.Invoke());
        restoreItem = new ToolStripMenuItem("Restore Last Session", null, (_, _) => RestoreRequested?.Invoke());
        menu.Items.Add(restoreItem);
        profilesItem = new ToolStripMenuItem("Apply Profile");
        menu.Items.Add(profilesItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Exit", null, (_, _) => ExitRequested?.Invoke());

        appIcon = LoadAppIcon();

        notifyIcon = new NotifyIcon
        {
            Icon = appIcon,
            Text = BuildTrayText(),
            Visible = false,
            ContextMenuStrip = menu,
        };

        notifyIcon.MouseUp += OnMouseUp;
    }

    public event Action? OpenGuiRequested;
    public event Action? QuitAllRequested;
    public event Action? RestoreRequested;
    public event Action<QuitProfile>? ProfileRequested;
    public event Action? ExitRequested;
    public event Action? LeftClickRequested;

    public void Start()
    {
        notifyIcon.Visible = true;
        ShowNotification("justQuit is running", "Created by Agraja. Left click the tray icon or use Ctrl+Alt+J.");
    }

    public void UpdateProfiles(IReadOnlyList<QuitProfile> profiles)
    {
        profilesItem.DropDownItems.Clear();
        profilesItem.Enabled = profiles.Count > 0;

        foreach (var profile in profiles)
        {
            profilesItem.DropDownItems.Add(profile.Name, null, (_, _) => ProfileRequested?.Invoke(profile));
        }
    }

    public void SetRestoreAvailable(bool isAvailable)
    {
        restoreItem.Enabled = isAvailable;
    }

    public void ShowCountdown(int seconds)
    {
        countdownItem.Text = $"Countdown: {seconds}s";
        countdownItem.Visible = true;
        notifyIcon.Text = $"justQuit - {seconds}s remaining";

        countdownIcon?.Dispose();
        countdownIcon = CreateCountdownIcon(seconds);
        notifyIcon.Icon = countdownIcon ?? appIcon;
    }

    public void ClearCountdown()
    {
        countdownItem.Visible = false;
        notifyIcon.Text = BuildTrayText();
        notifyIcon.Icon = appIcon;
        countdownIcon?.Dispose();
        countdownIcon = null;
    }

    public void ShowNotification(string title, string message)
    {
        notifyIcon.BalloonTipTitle = title;
        notifyIcon.BalloonTipText = message;
        notifyIcon.ShowBalloonTip(4000);
    }

    public void Dispose()
    {
        notifyIcon.Visible = false;
        notifyIcon.Dispose();
        countdownIcon?.Dispose();
        appIcon.Dispose();
        menu.Dispose();
    }

    private void OnMouseUp(object? sender, MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left)
        {
            LeftClickRequested?.Invoke();
        }
    }

    private static Icon LoadAppIcon()
    {
        var candidatePaths = new[]
        {
            Path.Combine(AppContext.BaseDirectory, "AppIcon.ico"),
            Path.Combine(AppContext.BaseDirectory, "assets", "AppIcon.ico"),
        };

        foreach (var path in candidatePaths)
        {
            if (File.Exists(path))
            {
                return new Icon(path);
            }
        }

        return SystemIcons.Application;
    }

    private string BuildTrayText()
    {
        return $"justQuit v{versionText}";
    }

    private Icon? CreateCountdownIcon(int seconds)
    {
        try
        {
            using var bitmap = appIcon.ToBitmap();
            using var graphics = Graphics.FromImage(bitmap);
            graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;

            var badgeRect = new Rectangle(bitmap.Width - 18, 0, 18, 18);
            using var badgeBrush = new SolidBrush(Color.FromArgb(220, 178, 45, 33));
            using var textBrush = new SolidBrush(Color.White);
            using var font = new Font("Segoe UI", 8, FontStyle.Bold, GraphicsUnit.Pixel);
            using var stringFormat = new StringFormat
            {
                Alignment = StringAlignment.Center,
                LineAlignment = StringAlignment.Center,
            };

            graphics.FillEllipse(badgeBrush, badgeRect);
            graphics.DrawString(seconds.ToString(), font, textBrush, badgeRect, stringFormat);

            var iconHandle = bitmap.GetHicon();
            using var tempIcon = Icon.FromHandle(iconHandle);
            var clonedIcon = (Icon)tempIcon.Clone();
            DestroyIcon(iconHandle);
            return clonedIcon;
        }
        catch
        {
            return null;
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);
}
