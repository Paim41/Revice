using System.Runtime.InteropServices;

namespace Revice.Agent.Collectors;

public sealed record Battery(double? Percentage, bool? Charging);
public sealed record Storage(long TotalBytes, long AvailableBytes);
public sealed record SystemMetrics(double? CpuPercent, ulong RamTotalBytes, ulong RamUsedBytes, long UptimeSeconds);
public sealed record Reading(int SchemaVersion, long SequenceId, string ObservedAt, string AgentVersion, Battery? Battery, Storage? Storage, SystemMetrics System);
public sealed record DriveMetric(string Name, long TotalBytes, long AvailableBytes);
public sealed record Observation(Reading Reading, IReadOnlyList<DriveMetric> Drives);

public sealed class SystemCollector
{
    private ulong? previousIdle, previousTotal;
    [StructLayout(LayoutKind.Sequential)] private struct NativeTime { public uint Low, High; public readonly ulong Value => ((ulong)High << 32) | Low; }
    [StructLayout(LayoutKind.Sequential)] private struct MemoryStatus {
        public uint Length, Load; public ulong TotalPhysical, AvailablePhysical, TotalPageFile, AvailablePageFile, TotalVirtual, AvailableVirtual, AvailableExtendedVirtual;
    }
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetSystemTimes(out NativeTime idle, out NativeTime kernel, out NativeTime user);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);

    public Observation Read(long sequence)
    {
        double? cpu = null;
        if (GetSystemTimes(out var idle, out var kernel, out var user)) {
            var total = kernel.Value + user.Value;
            if (previousTotal is { } old && previousIdle is { } oldIdle && total > old && idle.Value >= oldIdle)
                cpu = Math.Clamp(100.0 * (1.0 - (double)(idle.Value - oldIdle) / (total - old)), 0, 100);
            previousIdle = idle.Value; previousTotal = total;
        }
        var memory = new MemoryStatus { Length = (uint)Marshal.SizeOf<MemoryStatus>() };
        if (!GlobalMemoryStatusEx(ref memory)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Memory metrics unavailable");
        var power = SystemInformation.PowerStatus;
        Battery? battery = null;
        if (power.BatteryChargeStatus != BatteryChargeStatus.Unknown && !power.BatteryChargeStatus.HasFlag(BatteryChargeStatus.NoSystemBattery)) {
            var fraction = power.BatteryLifePercent;
            battery = new(fraction is >= 0 and <= 1 ? fraction * 100.0 : null, power.BatteryChargeStatus.HasFlag(BatteryChargeStatus.Charging));
        }
        var drives = new List<DriveMetric>();
        foreach (var drive in DriveInfo.GetDrives().Where(d => d.DriveType == DriveType.Fixed)) {
            try { if (drive.IsReady) drives.Add(new(drive.Name, drive.TotalSize, drive.AvailableFreeSpace)); }
            catch (IOException) { /* Disconnected drives are omitted, not reported as empty. */ }
            catch (UnauthorizedAccessException) { /* Access may differ across drives. */ }
        }
        var systemDrive = drives.FirstOrDefault(d => string.Equals(d.Name, Path.GetPathRoot(Environment.SystemDirectory), StringComparison.OrdinalIgnoreCase));
        var reading = new Reading(1, sequence, DateTimeOffset.UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ"), UI.AboutDialog.AppVersion, battery,
            systemDrive is null ? null : new(systemDrive.TotalBytes, systemDrive.AvailableBytes),
            new(cpu, memory.TotalPhysical, memory.TotalPhysical - memory.AvailablePhysical, Environment.TickCount64 / 1000));
        return new(reading, drives);
    }
}

