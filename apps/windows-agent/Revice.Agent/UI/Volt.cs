using System.Drawing.Drawing2D;
using System.Globalization;

namespace Revice.Agent.UI;

internal static class Volt
{
    public static readonly Color Background = ColorTranslator.FromHtml("#050807"), Surface = ColorTranslator.FromHtml("#111914"),
        Border = ColorTranslator.FromHtml("#29372D"), Lime = ColorTranslator.FromHtml("#B9F35A"), Cyan = ColorTranslator.FromHtml("#4EDFC3"),
        Text = ColorTranslator.FromHtml("#F4F8EE"), Muted = ColorTranslator.FromHtml("#93A28C"), Error = ColorTranslator.FromHtml("#EF4444");
        public static Font Font(float size = 10, bool heading = false) {
        var preferred=heading?"Space Grotesk":"Inter";
        var available=FontFamily.Families.Any(f=>f.Name==preferred);
        return new Font(available?preferred:"Segoe UI",size,heading?FontStyle.Bold:FontStyle.Regular);
    }
    public static string Percent(double? value) => value is { } n && double.IsFinite(n)
        ? Math.Round(n, 2, MidpointRounding.AwayFromZero).ToString("F2", CultureInfo.InvariantCulture) + "%" : "Unavailable";
    public static Label Label(string text, float size = 10, bool heading = false) => new() { Text = text, AutoSize = true, ForeColor = heading ? Text : Muted, Font = Font(size, heading), Margin = new Padding(0, 0, 0, 4) };
    public static Button Button(string text, bool primary = false) {
        var b = new Button { Text = text, AutoSize = true, MinimumSize = new Size(100, 34), Padding = new Padding(8, 2, 8, 2), FlatStyle = FlatStyle.Flat,
            BackColor = primary ? Lime : Surface, ForeColor = primary ? Background : Cyan, Font = Font(9, true), Cursor = Cursors.Hand, Margin = new Padding(0, 2, 8, 2) };
        b.FlatAppearance.BorderColor = Cyan; b.FlatAppearance.MouseOverBackColor = primary ? Color.FromArgb(206, 255, 130) : Border;
        return b;
    }
    public static GraphicsPath Rounded(Rectangle r, int radius) {
        var p = new GraphicsPath(); int d = radius * 2;
        p.AddArc(r.X,r.Y,d,d,180,90); p.AddArc(r.Right-d,r.Y,d,d,270,90);
        p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90); p.AddArc(r.X,r.Bottom-d,d,d,90,90); p.CloseFigure(); return p;
    }
}

internal sealed class VoltCard : Panel
{
    public FlowLayoutPanel Body { get; } = new() { Dock = DockStyle.Top, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = false, BackColor = Volt.Surface };
    public VoltCard(string title, string description, int height) {
        DoubleBuffered = true; SetStyle(ControlStyles.ResizeRedraw, true); Height = height; Padding = new Padding(12); Margin = new Padding(0,0,0,10); BackColor = Volt.Background;
        Controls.Add(Body); Body.SizeChanged += (_,_) => Height = Body.Height + Padding.Vertical; Body.Controls.Add(Volt.Label(title,12,true)); if(description.Length > 0) Body.Controls.Add(Volt.Label(description,9));
        Body.Resize += (_,_) => { foreach(Control c in Body.Controls) { if(c is TextBox || c is MetricTile || c is RichTextBox) c.Width = Math.Max(100,Body.ClientSize.Width - 2); } };
    }
    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var path = Volt.Rounded(new Rectangle(0,0,Width-1,Height-1),14);
        using var fill = new SolidBrush(Volt.Surface); using var pen = new Pen(Volt.Border);
        e.Graphics.FillPath(fill,path); e.Graphics.DrawPath(pen,path); base.OnPaint(e);
    }
}

internal sealed class MetricTile : Control
{
    public string Caption { get; }
    private string reading = "Waiting for observation";
    private double? percentage;
    private readonly Color accent;
    public MetricTile(string caption, Color color) { Caption=caption; accent=color; Height=48; Width=440; DoubleBuffered=true; Margin=new Padding(0,0,0,6); AccessibleName=caption; }
    public void UpdateValue(string value, double? percent = null) { reading=value; percentage=percent; AccessibleDescription=value; Invalidate(); }
    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
        using var path=Volt.Rounded(new Rectangle(0,0,Width-1,Height-1),10); using var border=new Pen(Volt.Border);
        e.Graphics.DrawPath(border,path);
        float scale=DeviceDpi/96f;
        using var label=Volt.Font(9); using var value=Volt.Font(10,true);
        TextRenderer.DrawText(e.Graphics,Caption,label,new Rectangle((int)(10*scale),(int)(5*scale),(int)(110*scale),(int)(24*scale)),Volt.Muted,TextFormatFlags.EndEllipsis);
        TextRenderer.DrawText(e.Graphics,reading,value,new Rectangle((int)(125*scale),(int)(5*scale),Width-(int)(135*scale),(int)(30*scale)),Volt.Text,TextFormatFlags.EndEllipsis);
        if(percentage is {} n && double.IsFinite(n)) {
            using var track=new SolidBrush(Volt.Border); using var fill=new SolidBrush(accent);
            e.Graphics.FillRectangle(track,14,Height-12,Width-28,4);
            e.Graphics.FillRectangle(fill,14,Height-12,(float)((Width-28)*Math.Clamp(n,0,100)/100),4);
        }
        base.OnPaint(e);
    }
}

