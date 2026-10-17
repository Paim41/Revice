using Microsoft.Win32;
using Revice.Agent.Services;

namespace Revice.Agent.UI;

public sealed class AgentForm : Form
{
    private readonly AgentService agent;
    private readonly NotifyIcon tray;
    private readonly System.Windows.Forms.Timer timer = new();
    private readonly TextBox gateway = new() { PlaceholderText = "https://your-gateway.workers.dev" };
    private readonly TextBox deviceName = new();
    private readonly TextBox code = new() { MaxLength=6, PlaceholderText="Six-digit pairing code" };
    private readonly NumericUpDown interval = new() { Minimum=30, Maximum=3600, Value=60, Width=140 };
    private readonly Label status=Volt.Label("Starting…",11,true), lastSync=Volt.Label("Last sync: Never"), pairingStatus=Volt.Label("Not paired");
    private readonly MetricTile cpu=new("CPU",Volt.Lime), ram=new("Memory / RAM",Volt.Cyan), battery=new("Battery",Volt.Lime), uptime=new("Uptime",Volt.Cyan), sync=new("Last successful sync",Volt.Cyan);
    private readonly FlowLayoutPanel left=new(), right=new();
    private readonly TableLayoutPanel columns=new() { Dock=DockStyle.Fill, ColumnCount=2, RowCount=1, AutoScroll=true, Padding=new Padding(22,0,22,18) };
    private readonly RichTextBox log=new() { ReadOnly=true, Height=190, BorderStyle=BorderStyle.None, BackColor=Volt.Background, ForeColor=Volt.Muted };
    private readonly ComboBox filter=new() { DropDownStyle=ComboBoxStyle.DropDownList, Width=180 };
    private readonly Queue<(DateTime At,string Level,string Message)> events=new();
    private readonly List<Button> actions=new();
    private readonly Dictionary<string,MetricTile> drives=new();
    private readonly VoltCard live;
    private readonly ToolStripMenuItem trayStatus=new("Starting…") { Enabled=false };
    private bool exiting, busy, exitRequested;
    

    public AgentForm(AgentService service) {
        agent=service; Text="Revice Agent • 0.2.1"; Name="ReviceAgent021"; AutoScaleMode=AutoScaleMode.Dpi;
        Size=new Size(1180,900); StartPosition=FormStartPosition.CenterScreen; MinimumSize=new Size(650,650); BackColor=Volt.Background; ForeColor=Volt.Text; Font=Volt.Font();
        var header=new Panel { Dock=DockStyle.Top, Height=150, Padding=new Padding(26,18,26,12) };
        var heading=new FlowLayoutPanel { Dock=DockStyle.Left, Width=430, FlowDirection=FlowDirection.TopDown, WrapContents=false };
        heading.Controls.Add(Volt.Label("REVICE AGENT",25,true)); heading.Controls.Add(Volt.Label("CONNECT  •  SYNC  •  STAY IN CONTROL",9));
        var summary=new FlowLayoutPanel { Dock=DockStyle.Right, Width=330, FlowDirection=FlowDirection.TopDown, WrapContents=false };
        summary.Controls.Add(status); summary.Controls.Add(lastSync); var headerExit=Volt.Button("Exit Revice");headerExit.Click+=async(_,_)=>await ExitApplication();summary.Controls.Add(headerExit); header.Controls.Add(summary); header.Controls.Add(heading);
        Controls.Add(columns); Controls.Add(header);
        foreach(var flow in new[]{left,right}) { flow.Dock=DockStyle.Fill; flow.FlowDirection=FlowDirection.TopDown; flow.WrapContents=false; flow.AutoScroll=true; flow.Margin=new Padding(0,0,14,0); flow.Resize+=(_,_)=>ResizeCards(flow); }
        columns.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,48)); columns.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,52)); columns.Controls.Add(left,0,0); columns.Controls.Add(right,1,0);
        var connection=Card(left,"Connection","Configure your Revice gateway connection",175);
        AddInput(connection,gateway,"Gateway address");
        var device=Card(left,"Device Info","Identify this device on your network",240);
        AddInput(device,deviceName,"Device name"); device.Body.Controls.Add(Volt.Label("Sync interval (seconds)")); device.Body.Controls.Add(interval);
        device.Body.Controls.Add(Action("Save settings",()=> { agent.Configure(gateway.Text,deviceName.Text,(int)interval.Value); timer.Interval=agent.State.IntervalSeconds*1000; return Task.CompletedTask; },true));
        var startup=Card(left,"Startup","Launch Revice Agent automatically",140);
        var toggle=new CheckBox { Text="Start with Windows",AutoSize=true,ForeColor=Volt.Text,Padding=new Padding(0,6,0,6) };
        try { StartupSettings.Refresh(); } catch(Exception e) when(e is UnauthorizedAccessException or System.Security.SecurityException or IOException) { AddLog("ERROR","Could not register Windows startup."); }
        toggle.Checked=StartupSettings.Enabled;
        toggle.CheckedChanged+=(_,_)=> { try { StartupSettings.Set(toggle.Checked); AddLog("INFO","Startup preference saved."); } catch(Exception e) when(e is UnauthorizedAccessException or System.Security.SecurityException or IOException) { AddLog("ERROR","Startup preference could not be saved."); } };
        startup.Body.Controls.Add(toggle);
        var pairing=Card(left,"Pairing","Connect this computer to your Revice account",260);
        AddInput(pairing,code,"Pairing code");
        var buttons=new FlowLayoutPanel { AutoSize=true,WrapContents=true,MaximumSize=new Size(440,0) };
        buttons.Controls.Add(Action("Request pairing",()=>agent.Join(code.Text),true)); buttons.Controls.Add(Action("Check approval",()=>agent.CheckApproval(code.Text))); pairing.Body.Controls.Add(buttons);
        pairing.Body.Controls.Add(Action("Unpair",()=> { if(MessageBox.Show("Remove this computer's local credential and queue? Revoke it on the owner dashboard to disable its server credential too.","Unpair",MessageBoxButtons.YesNo)==DialogResult.Yes)agent.Unpair(); return Task.CompletedTask; }));
        pairing.Body.Controls.Add(pairingStatus);
        var actionCard=Card(left,"Actions","Synchronize real device observations",160);
        actionCard.Body.Controls.Add(Action("Sync now / refresh",agent.Tick,true));
        var exit=Volt.Button("Exit Revice"); exit.Click+=async(_,_)=>await ExitApplication(); actionCard.Body.Controls.Add(exit);
        live=Card(right,"Live Status","Real-time system information and sync status",650);
        foreach(var tile in new[]{cpu,ram,battery,uptime,sync})live.Body.Controls.Add(tile);
        var logs=Card(right,"Telemetry Log","Recent events • no credentials are logged",320);
        filter.Items.AddRange(["All events","INFO","SYNC","ERROR"]); filter.SelectedIndex=0; filter.SelectedIndexChanged+=(_,_)=>RenderLog(); logs.Body.Controls.Add(filter); logs.Body.Controls.Add(log);
        gateway.Text=agent.State.Gateway; deviceName.Text=agent.State.Name; interval.Value=Math.Clamp(agent.State.IntervalSeconds,30,3600);
        foreach(var c in new Control[]{gateway,deviceName,code,interval,filter}) { c.BackColor=Volt.Background; c.ForeColor=Volt.Text; c.Font=Volt.Font(11); }
        var menu=new ContextMenuStrip { BackColor=Volt.Surface,ForeColor=Volt.Text };
        menu.Items.Add("Open Revice Agent",null,(_,_)=>OpenWindow()); menu.Items.Add("Sync now",null,async(_,_)=>await Run("Sync",agent.Tick)); menu.Items.Add(trayStatus);
        menu.Items.Add("Settings",null,(_,_)=> { OpenWindow(); gateway.Focus(); }); menu.Items.Add("Exit",null,async(_,_)=>await ExitApplication());
        tray=new NotifyIcon { Text="Revice Agent",Icon=SystemIcons.Application,Visible=true,ContextMenuStrip=menu }; tray.DoubleClick+=(_,_)=>OpenWindow();
        timer.Interval=agent.State.IntervalSeconds*1000; timer.Tick+=async(_,_)=>await Run("Sync",agent.Tick);
        Shown+=async(_,_)=> { ResizeCards(left);ResizeCards(right);timer.Start();if(Environment.GetCommandLineArgs().Contains("--startup"))Hide();await Run("Refresh",agent.Tick); };
        Resize+=(_,_)=> { bool narrow=ClientSize.Width<900; columns.SetColumn(right,narrow?0:1);columns.SetRow(right,narrow?1:0);columns.RowCount=narrow?2:1;columns.ColumnStyles[0].Width=narrow?100:48;columns.ColumnStyles[1].Width=narrow?0:52; left.MinimumSize=new Size(0,narrow?1080:0);right.MinimumSize=new Size(0,narrow?1000:0); };
        FormClosing+=async(_,e)=> { if(exiting)return; if(e.CloseReason==CloseReason.UserClosing && agent.State.OwnerUid!=null) {e.Cancel=true;Hide();return;} e.Cancel=true;await ExitApplication(); };
        FormClosed+=(_,_)=> {timer.Dispose();tray.Visible=false;tray.Dispose();agent.Dispose();};
        RefreshMetrics(); AddLog("INFO","Agent 0.2.1 initialized. Existing settings loaded.");
    }
    private static VoltCard Card(FlowLayoutPanel parent,string title,string description,int height) {var card=new VoltCard(title,description,height);parent.Controls.Add(card);return card;}
    private static void ResizeCards(FlowLayoutPanel flow) {foreach(Control c in flow.Controls)c.Width=Math.Max(260,flow.ClientSize.Width-24);}
    private static void AddInput(VoltCard card,TextBox input,string label) {card.Body.Controls.Add(Volt.Label(label));input.Width=400;input.BorderStyle=BorderStyle.FixedSingle;input.Margin=new Padding(0,0,0,10);card.Body.Controls.Add(input);}
    private Button Action(string title,Func<Task> action,bool primary=false) {var b=Volt.Button(title,primary);actions.Add(b);b.Click+=async(_,_)=>await Run(title,action);return b;}
    public void OpenWindow() {if(exitRequested)return;Show();WindowState=FormWindowState.Normal;Activate();}
    protected override void WndProc(ref Message m) {if(m.Msg==SingleInstance.ShowMessage)OpenWindow();base.WndProc(ref m);}
    public async Task ExitApplication() {if(exitRequested)return;exitRequested=true;timer.Stop();agent.CancelPendingRequests();while(busy)await Task.Delay(25);exiting=true;Close();}
    private async Task Run(string name,Func<Task> action) {
        if(busy||exitRequested)return;busy=true;foreach(var b in actions)b.Enabled=false;status.Text="Working…";
        try {await action();if(!exitRequested)AddLog(name is "Sync" or "Refresh" or "Sync now / refresh" ? (agent.Status=="Synchronized"?"SYNC":agent.State.OwnerUid==null?"INFO":"ERROR") : "INFO",name+": "+(name=="Save settings"?"Settings saved":agent.Status));}
        catch(Exception e) when(e is InvalidOperationException or HttpRequestException or TaskCanceledException or IOException or System.Security.Cryptography.CryptographicException or System.Text.Json.JsonException) {if(!exitRequested)AddLog("ERROR",e is InvalidOperationException ? e.Message : "Action failed. Check connection and local storage.");}
        finally {busy=false;if(!IsDisposed&&!exitRequested){foreach(var b in actions)b.Enabled=true;RefreshMetrics();}}
    }
    private void RefreshMetrics() {
        status.Text=agent.Status;status.ForeColor=agent.Status=="Synchronized"?Volt.Lime:Volt.Cyan;lastSync.Text="Last sync: "+(agent.LastSync?.ToLocalTime().ToString("g")??"Never");trayStatus.Text=agent.Status;
        pairingStatus.Text=agent.State.OwnerUid==null?"Not paired / awaiting approval":"Paired to owner account";
        if(agent.Latest is not {} o)return;var r=o.Reading;
        cpu.UpdateValue(r.System.CpuPercent is null?"Sampling…":Volt.Percent(r.System.CpuPercent),r.System.CpuPercent);
        double? memory=r.System.RamTotalBytes>0?100.0*r.System.RamUsedBytes/r.System.RamTotalBytes:null;
        ram.UpdateValue($"{r.System.RamUsedBytes/1073741824.0:F1} / {r.System.RamTotalBytes/1073741824.0:F1} GiB  •  {Volt.Percent(memory)}",memory);
        battery.UpdateValue(r.Battery is null?"No battery":Volt.Percent(r.Battery.Percentage)+(r.Battery.Charging==true?" • Charging":""),r.Battery?.Percentage);
        uptime.UpdateValue(TimeSpan.FromSeconds(r.System.UptimeSeconds).ToString(@"d\d\ hh\:mm\:ss"));sync.UpdateValue(agent.LastSync?.ToLocalTime().ToString("g")??"Never");
        foreach(var old in drives.Keys.Except(o.Drives.Select(d=>d.Name)).ToArray()){live.Body.Controls.Remove(drives[old]);drives[old].Dispose();drives.Remove(old);}
        foreach(var d in o.Drives) {if(!drives.TryGetValue(d.Name,out var tile)){tile=new MetricTile(d.Name+" Drive",Volt.Cyan);drives.Add(d.Name,tile);live.Body.Controls.Add(tile);tile.Width=Math.Max(100,live.Body.ClientSize.Width-22);}double? used=d.TotalBytes>0?100.0*(d.TotalBytes-d.AvailableBytes)/d.TotalBytes:null;tile.UpdateValue($"{d.AvailableBytes/1073741824.0:F1} / {d.TotalBytes/1073741824.0:F1} GiB free • {Volt.Percent(used)} used",used);}
    }
    private void AddLog(string level,string message) {events.Enqueue((DateTime.Now,level,message));while(events.Count>150)events.Dequeue();RenderLog();}
    private void RenderLog() {log.Clear();foreach(var e in events.Where(e=>filter.SelectedIndex<=0||e.Level==filter.Text)){log.SelectionColor=e.Level=="ERROR"?Volt.Error:e.Level=="SYNC"?Volt.Lime:Volt.Muted;log.AppendText($"{e.At:HH:mm:ss}  [{e.Level}]  {e.Message}\n");}log.SelectionStart=log.TextLength;log.ScrollToCaret();}
}


