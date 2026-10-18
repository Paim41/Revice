using System.Diagnostics;
using System.Reflection;

namespace Revice.Agent.UI;

internal sealed class AboutDialog : Form
{
    internal static string AppVersion => Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0] ?? Application.ProductVersion;

    public AboutDialog()
    {
        Text = "About & Credits";
        Icon = BrandAssets.LoadIcon();
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(450, 355);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false; MinimizeBox = false;
        StartPosition = FormStartPosition.CenterParent;
        BackColor = Volt.Background; ForeColor = Volt.Text; Font = Volt.Font();
        var content = new FlowLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(24), FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true };
        var logo = new PictureBox { Size = new Size(64, 64), SizeMode = PictureBoxSizeMode.Zoom, Margin = new Padding(0, 0, 0, 8) };
        using var resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("Revice.AppIcon.png");
        if (resource != null) { using var original = Image.FromStream(resource); logo.Image = new Bitmap(original); }
        FormClosed += (_, _) => { logo.Image?.Dispose(); Icon?.Dispose(); };
        content.Controls.Add(logo);
        content.Controls.Add(Volt.Label("REVICE AGENT", 18, true));
        content.Controls.Add(Volt.Label("Revive the Device"));
        content.Controls.Add(Volt.Label("Developed by Paim41", 12, true));
        content.Controls.Add(Volt.Label("https://github.com/Paim41"));
        content.Controls.Add(Volt.Label("Version " + AppVersion + " • Windows x64"));
        var github = Volt.Button("View Developer on GitHub");
        github.Click += (_, _) => {
            try { Process.Start(new ProcessStartInfo("https://github.com/Paim41") { UseShellExecute = true }); }
            catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException) {
                MessageBox.Show(this, "Could not open your browser. Visit https://github.com/Paim41", "Open GitHub");
            }
        };
        content.Controls.Add(github);
        var close = Volt.Button("Close", true);
        close.Click += (_, _) => Close();
        content.Controls.Add(close); CancelButton = close; Controls.Add(content);
    }
}
