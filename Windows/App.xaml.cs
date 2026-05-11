namespace justQuit.Windows;

public partial class App : System.Windows.Application
{
    private AppController? controller;
    private SingleInstanceManager? singleInstanceManager;

    protected override void OnStartup(System.Windows.StartupEventArgs e)
    {
        base.OnStartup(e);

        DispatcherUnhandledException += (_, args) =>
        {
            System.Windows.MessageBox.Show(args.Exception.Message, "justQuit error");
            args.Handled = true;
        };

        singleInstanceManager = new SingleInstanceManager();
        if (!singleInstanceManager.IsPrimaryInstance)
        {
            SingleInstanceManager.SignalExistingInstance();
            Shutdown();
            return;
        }

        controller = new AppController();
        controller.Start(e.Args);
        singleInstanceManager.ShowWindowRequested += OnShowWindowRequested;
    }

    protected override void OnExit(System.Windows.ExitEventArgs e)
    {
        if (singleInstanceManager is not null)
        {
            singleInstanceManager.ShowWindowRequested -= OnShowWindowRequested;
            singleInstanceManager.Dispose();
        }

        controller?.Dispose();
        base.OnExit(e);
    }

    private void OnShowWindowRequested()
    {
        Dispatcher.Invoke(() => controller?.ShowMainWindow());
    }
}
