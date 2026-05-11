using System.Threading;

namespace justQuit.Windows;

public sealed class SingleInstanceManager : IDisposable
{
    private const string MutexName = @"Local\justQuitPrimaryMutex";
    private const string ShowWindowEventName = @"Local\justQuitShowWindowEvent";

    private readonly Mutex mutex;
    private readonly EventWaitHandle showWindowEvent;
    private readonly CancellationTokenSource cancellationTokenSource = new();
    private readonly Thread? listenerThread;

    public SingleInstanceManager()
    {
        mutex = new Mutex(true, MutexName, out var createdNew);
        showWindowEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ShowWindowEventName);
        IsPrimaryInstance = createdNew;

        if (IsPrimaryInstance)
        {
            listenerThread = new Thread(ListenForSignals)
            {
                IsBackground = true,
                Name = "justQuitSingleInstanceListener",
            };
            listenerThread.Start();
        }
    }

    public bool IsPrimaryInstance { get; }

    public event Action? ShowWindowRequested;

    public static void SignalExistingInstance()
    {
        try
        {
            using var existingEvent = EventWaitHandle.OpenExisting(ShowWindowEventName);
            existingEvent.Set();
        }
        catch
        {
        }
    }

    public void Dispose()
    {
        cancellationTokenSource.Cancel();
        showWindowEvent.Set();

        if (IsPrimaryInstance)
        {
            mutex.ReleaseMutex();
        }

        showWindowEvent.Dispose();
        mutex.Dispose();
        cancellationTokenSource.Dispose();
    }

    private void ListenForSignals()
    {
        while (!cancellationTokenSource.IsCancellationRequested)
        {
            showWindowEvent.WaitOne();
            if (cancellationTokenSource.IsCancellationRequested)
            {
                break;
            }

            ShowWindowRequested?.Invoke();
        }
    }
}
