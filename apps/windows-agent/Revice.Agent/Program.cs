namespace Revice.Agent;

static class Program
{
    /// <summary>
    ///  The main entry point for the application.
    /// </summary>
    [STAThread]
    static void Main()
    {
        // To customize application configuration such as set high DPI settings or default font,
        // see https://aka.ms/applicationconfiguration.
        ApplicationConfiguration.Initialize();
        if (Environment.GetCommandLineArgs().Contains("--self-test")) {
            var directory = Environment.GetCommandLineArgs().Last();
            try {
                using var service = new Services.AgentService(directory);
                service.Configure("https://example.workers.dev", "Self test", 60);
                service.Tick().GetAwaiter().GetResult();
                if (service.Latest?.Reading.System.RamTotalBytes is not > 0) throw new Exception("Memory collector failed");
                if (service.Latest.Drives.Count == 0) throw new Exception("Drive collector failed");
                using var restored = new Services.AgentService(directory);
                if (restored.State.Credential != service.State.Credential) throw new Exception("DPAPI persistence failed");
                File.WriteAllText(Path.Combine(directory, "result.json"), System.Text.Json.JsonSerializer.Serialize(new { passed = true, observation = service.Latest }, Services.AgentService.Json));
                Environment.ExitCode = 0;
            } catch (Exception error) { File.WriteAllText(Path.Combine(directory, "result.json"), System.Text.Json.JsonSerializer.Serialize(new { passed = false, error = error.Message })); Environment.ExitCode = 1; }
            return;
        }
        using var mutex = new Mutex(false, "Local\\ReviceAgent");
        bool firstInstance;
        try { firstInstance = mutex.WaitOne(0); } catch (AbandonedMutexException) { firstInstance = true; }
        if (!firstInstance) { SingleInstance.ShowExisting(); return; }
        try { Application.Run(new UI.AgentForm(new Services.AgentService())); }
        catch (Exception error) when (error is IOException or System.Security.Cryptography.CryptographicException or System.Text.Json.JsonException) {
            MessageBox.Show("Agent state could not be opened. Preserve the local state file before resetting and re-pairing.", "Device Agent");
        }
        finally { mutex.ReleaseMutex(); }
    }    
}

