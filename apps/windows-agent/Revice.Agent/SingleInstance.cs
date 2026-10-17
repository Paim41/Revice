using System.Runtime.InteropServices;
namespace Revice.Agent;
internal static class SingleInstance
{
    public static readonly int ShowMessage = (int)RegisterWindowMessage("Revice.Agent.ShowWindow.v1");
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] private static extern uint RegisterWindowMessage(string message);
    [DllImport("user32.dll")] private static extern bool PostMessage(nint window,int message,nint wParam,nint lParam);
    public static void ShowExisting() => PostMessage((nint)0xffff,ShowMessage,0,0);
}
