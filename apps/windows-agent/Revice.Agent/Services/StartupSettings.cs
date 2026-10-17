using Microsoft.Win32;
namespace Revice.Agent.Services;
internal static class StartupSettings
{
    private const string RunKey=@"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string PreferenceKey=@"Software\Revice";
    public static bool Enabled { get {using var p=Registry.CurrentUser.OpenSubKey(PreferenceKey);return p?.GetValue("StartWithWindows") is int value ? value!=0 : true;} }
    public static void Set(bool enabled) {
        using var run=Registry.CurrentUser.CreateSubKey(RunKey);
        if(enabled)run.SetValue("ReviceAgent","\""+Environment.ProcessPath+"\" --startup");else run.DeleteValue("ReviceAgent",false);
        using var preferences=Registry.CurrentUser.CreateSubKey(PreferenceKey);preferences.SetValue("StartWithWindows",enabled?1:0,RegistryValueKind.DWord);
    }
    public static void Refresh() => Set(Enabled);
}
