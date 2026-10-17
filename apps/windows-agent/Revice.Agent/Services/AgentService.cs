using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Revice.Agent.Collectors;

namespace Revice.Agent.Services;

public sealed record AgentState(string Gateway, string Name, string DeviceId, string? OwnerUid, string Credential, long Sequence, int IntervalSeconds, List<Reading> Queue);

public sealed class AgentService : IDisposable
{
    public static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private readonly string statePath;
    private readonly HttpClient http = new() { Timeout = TimeSpan.FromSeconds(20) };
    private readonly SemaphoreSlim gate = new(1, 1);
    private readonly SystemCollector collector = new();
    public AgentState State { get; private set; }
    public Observation? Latest { get; private set; }
    public DateTimeOffset? LastSync { get; private set; }
    public string Status { get; private set; } = "Not paired";

    public AgentService(string? directory = null)
    {
        directory ??= Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Revice");
        Directory.CreateDirectory(directory); statePath = Path.Combine(directory, "agent.dat");
        if (File.Exists(statePath)) {
            var plain = ProtectedData.Unprotect(File.ReadAllBytes(statePath), null, DataProtectionScope.CurrentUser);
            State = JsonSerializer.Deserialize<AgentState>(plain, Json) ?? throw new InvalidDataException("Invalid agent state");
        } else State = new("", Environment.MachineName, Guid.NewGuid().ToString("N"), null, Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant(), 0, 60, []);
    }
    private void Save()
    {
        var encrypted = ProtectedData.Protect(JsonSerializer.SerializeToUtf8Bytes(State, Json), null, DataProtectionScope.CurrentUser);
        var temporary = statePath + ".tmp"; File.WriteAllBytes(temporary, encrypted); File.Move(temporary, statePath, true);
    }
    public void Configure(string gateway, string name, int interval)
    {
        if (!Uri.TryCreate(gateway.Trim(), UriKind.Absolute, out var uri) || uri.Scheme != "https" || !string.IsNullOrEmpty(uri.UserInfo) || uri.AbsolutePath != "/" || !string.IsNullOrEmpty(uri.Query)) throw new InvalidOperationException("Enter an HTTPS gateway origin, without a path or query.");
        if (name.Trim().Length is < 1 or > 80) throw new InvalidOperationException("Device name must be 1–80 characters.");
        if (State.OwnerUid != null && State.Gateway != uri.GetLeftPart(UriPartial.Authority)) throw new InvalidOperationException("Unpair before changing the gateway.");
        State = State with { Gateway = uri.GetLeftPart(UriPartial.Authority), Name = name.Trim(), IntervalSeconds = Math.Clamp(interval, 30, 3600) }; Save();
    }
    private async Task<JsonElement> Call(string path, object body, bool agent = false)
    {
        if (State.Gateway.Length == 0) throw new InvalidOperationException("Configure the gateway first.");
        using var request = new HttpRequestMessage(HttpMethod.Post, State.Gateway + path) { Content = JsonContent.Create(body, options: Json) };
        if (agent) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", State.Credential);
        using var response = await http.SendAsync(request);
        using var data = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        if (!response.IsSuccessStatusCode) throw new InvalidOperationException(data.RootElement.TryGetProperty("error", out var error) ? error.GetString() : "Gateway request failed");
        return data.RootElement.Clone();
    }
    public async Task Join(string code)
    {
        if (State.OwnerUid != null) throw new InvalidOperationException("Unpair this computer first.");
        if (code.Length != 6 || !code.All(char.IsAsciiDigit)) throw new InvalidOperationException("Enter the six-digit code from the owner dashboard.");
        Save();
        await Call("/v1/pairing/join", new { code, State.DeviceId, State.Credential, State.Name, platform = "windows" });
        Status = "Awaiting owner approval";
    }
    public async Task CheckApproval(string code)
    {
        var result = await Call("/v1/pairing/status", new { code, State.Credential });
        var state = result.GetProperty("state").GetString(); Status = "Pairing: " + state;
        if (state == "approved") { State = State with { OwnerUid = result.GetProperty("ownerUid").GetString() }; Save(); }
    }
    public async Task Tick()
    {
        if (!await gate.WaitAsync(0)) return;
        try {
            Latest = collector.Read(State.Sequence + 1);
            if (State.OwnerUid == null) { Status = "Local readings • Not paired"; return; }
            var queue = State.Queue.Where(r => DateTimeOffset.Parse(r.ObservedAt) > DateTimeOffset.UtcNow.AddDays(-7)).TakeLast(255).Append(Latest.Reading).ToList();
            State = State with { Sequence = Latest.Reading.SequenceId, Queue = queue }; Save();
            await Call("/v1/telemetry", new { State.OwnerUid, State.DeviceId, reading = Latest.Reading }, agent: true);
            State = State with { Queue = [] }; Save(); LastSync = DateTimeOffset.UtcNow; Status = "Synchronized";
        } catch (HttpRequestException) { Status = "Offline • Reading retained for retry"; }
        catch (TaskCanceledException) { Status = "Request timed out • Reading retained"; }
        catch (InvalidOperationException error) { Status = error.Message; }
        catch (IOException) { Status = "Local queue could not be saved; check disk access"; }
        finally { gate.Release(); }
    }
    public void Unpair()
    {
        if (gate.CurrentCount == 0) throw new InvalidOperationException("Wait for the current sync before unpairing.");
        State = State with { OwnerUid = null, DeviceId = Guid.NewGuid().ToString("N"), Credential = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant(), Sequence = 0, Queue = [] };
        Save(); Status = "Unpaired locally; revoke the old device on the owner dashboard";
    }
    public void CancelPendingRequests() => http.CancelPendingRequests();
    public void Dispose() { http.Dispose(); }
}

