using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;

namespace justQuit.Windows;

public sealed class HotkeyService : IDisposable
{
    private readonly NativeMethods.LowLevelKeyboardProc keyboardProc;
    private Action? handler;
    private IntPtr hookHandle;
    private bool ctrlPressed;
    private bool altPressed;
    private bool hotkeyPressed;

    public HotkeyService()
    {
        keyboardProc = HookCallback;
    }

    public void Register(Window window, Action onPressed)
    {
        handler = onPressed;
        RegisterHook();
    }

    public void Unregister()
    {
        if (hookHandle == IntPtr.Zero)
        {
            return;
        }

        NativeMethods.UnhookWindowsHookEx(hookHandle);
        hookHandle = IntPtr.Zero;
        ctrlPressed = false;
        altPressed = false;
        hotkeyPressed = false;
    }

    public void Dispose()
    {
        Unregister();
    }

    private void RegisterHook()
    {
        Unregister();

        using var process = Process.GetCurrentProcess();
        var moduleName = process.MainModule?.ModuleName;
        var moduleHandle = NativeMethods.GetModuleHandle(moduleName);
        hookHandle = NativeMethods.SetWindowsHookEx(NativeMethods.WH_KEYBOARD_LL, keyboardProc, moduleHandle, 0);
    }

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode < 0)
        {
            return NativeMethods.CallNextHookEx(hookHandle, nCode, wParam, lParam);
        }

        var keyboardData = Marshal.PtrToStructure<NativeMethods.KbdLlHookStruct>(lParam);
        var message = wParam.ToInt32();

        if (message is NativeMethods.WM_KEYDOWN or NativeMethods.WM_SYSKEYDOWN)
        {
            UpdateModifierState(keyboardData.VkCode, isPressed: true);

            if (keyboardData.VkCode == NativeMethods.VK_J && ctrlPressed && altPressed && !hotkeyPressed)
            {
                hotkeyPressed = true;
                System.Windows.Application.Current.Dispatcher.BeginInvoke(handler ?? (() => { }));
                return new IntPtr(1);
            }
        }
        else if (message is NativeMethods.WM_KEYUP or NativeMethods.WM_SYSKEYUP)
        {
            UpdateModifierState(keyboardData.VkCode, isPressed: false);
            if (keyboardData.VkCode == NativeMethods.VK_J)
            {
                hotkeyPressed = false;
            }
        }

        return NativeMethods.CallNextHookEx(hookHandle, nCode, wParam, lParam);
    }

    private void UpdateModifierState(uint vkCode, bool isPressed)
    {
        if (vkCode is NativeMethods.VK_LCONTROL or NativeMethods.VK_RCONTROL)
        {
            ctrlPressed = isPressed;
        }
        else if (vkCode is NativeMethods.VK_LMENU or NativeMethods.VK_RMENU)
        {
            altPressed = isPressed;
        }

        if (!ctrlPressed || !altPressed)
        {
            hotkeyPressed = false;
        }
    }
}
