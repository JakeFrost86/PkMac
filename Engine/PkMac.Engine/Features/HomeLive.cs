using HomeLive.Core;
using HomeLive.DeviceExecutor;
using PKHeX.Core;
using SysBot.Base;

namespace PkMac.Engine.Features;

/// <summary>
/// HOME Live (Manu098vm/HOME-Live-Plugin): view and dump the Pokémon stored in Pokémon HOME
/// running on a Switch with sys-botbase. Read-only by design, like the original plugin.
/// </summary>
public sealed class HomeLiveFeature(Session s)
{
    private DeviceExecutor<DeviceState>? _exec;
    private readonly Dictionary<int, List<HomeWrapper?>> _cache = new();

    public const int BoxCount = HomeDataOffsets.HomeBoxCount;
    public const int SlotCount = HomeDataOffsets.HomeSlotCount;

    public object Connect(string ip, int port)
    {
        Disconnect();
        var state = new DeviceState
        {
            Connection = new SwitchConnectionConfig { IP = ip, Port = port, Protocol = SwitchProtocol.WiFi },
            InitialRoutine = RoutineType.ReadWrite,
        };
        var exec = new DeviceExecutor<DeviceState>(state);
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(20));
        try
        {
            exec.RunAsync(cts.Token).GetAwaiter().GetResult();
            exec.Connect(cts.Token).GetAwaiter().GetResult();
        }
        catch (Exception ex)
        {
            try { exec.Disconnect(); } catch { }
            throw new EngineException($"HOME Live: {ex.Message}");
        }
        _exec = exec;
        _cache.Clear();
        return new { connected = true, boxes = BoxCount, slots = SlotCount, supportedVersion = HomeDataOffsets.HomeSupportedVersion };
    }

    public object Disconnect()
    {
        try { _exec?.Disconnect(); } catch { }
        _exec = null;
        return true;
    }

    private DeviceExecutor<DeviceState> Exec => _exec ?? throw new EngineException("HOME Live non è connesso.");

    private List<HomeWrapper?> Load(int box)
    {
        if ((uint)box >= BoxCount)
            throw new EngineException("Box HOME non valido.");
        if (_cache.TryGetValue(box, out var cached))
            return cached;
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        var data = Exec.ReadBoxData(box, cts.Token).GetAwaiter().GetResult();
        var list = PokeHandler.GenerateEntitiesFromBoxBin(data);
        _cache[box] = list;
        return list;
    }

    public object ReadBox(int box)
    {
        var list = Load(box);
        var sav = s.Save;
        var slots = list.Select((w, i) =>
        {
            var r = new SlotRef(false, box, i);
            if (w?.PKM is not { } raw)
                return (object)new { @ref = r.ToJson(), empty = true };
            var converted = sav is null ? null : Convert(w, sav, out _);
            var shown = converted ?? raw;
            return new
            {
                @ref = r.ToJson(),
                empty = false,
                pokemon = Describe.Slot(s, r, shown, withLegality: converted is not null),
                transferable = converted is not null,
                tracker = w.Tracker.ToString("X16"),
            };
        }).ToArray();
        return new { box, slots };
    }

    /// <summary>Prefers the game-specific data block matching the open save, then falls back to HOME conversion.</summary>
    private static PKM? Convert(HomeWrapper w, SaveFile sav, out EntityConverterResult result)
    {
        result = EntityConverterResult.Success;
        try
        {
            PKM? direct = sav.PKMType.Name switch
            {
                nameof(PK9) when w.HasPK9() => w.ConvertToPK9(),
                nameof(PA9) when w.HasPA9() => w.ConvertToPA9(),
                nameof(PK8) when w.HasPK8() => w.ConvertToPK8(),
                nameof(PB8) when w.HasPB8() => w.ConvertToPB8(),
                nameof(PA8) when w.HasPA8() => w.ConvertToPA8(),
                nameof(PB7) when w.HasPB7() => w.ConvertToPB7(),
                _ => null,
            };
            if (direct is not null)
                return direct;
            return w.BackwardTransfer(sav.PKMType, out result);
        }
        catch
        {
            result = EntityConverterResult.NoTransferRoute;
            return null;
        }
    }

    public object Import(int homeBox, int homeSlot, SlotRef target)
    {
        var w = Load(homeBox).ElementAtOrDefault(homeSlot) ?? throw new EngineException("Slot HOME vuoto.");
        var pk = Convert(w, s.Sav, out var result) ?? throw new EngineException($"Questo Pokémon non può essere portato in questo gioco ({result}).");
        s.Set(target, pk, settings: default(EntityImportSettings), label: "Importa da HOME");
        return Describe.Detail(s, target, s.Get(target));
    }

    public object Dump(string dir, int fromBox, int toBox, string format)
    {
        var fmt = format switch
        {
            "encrypted" => DumpFormat.Encrypted,
            "both" => DumpFormat.EncAndDec,
            _ => DumpFormat.Decrypted,
        };
        fromBox = Math.Clamp(fromBox, 0, BoxCount - 1);
        toBox = Math.Clamp(toBox, fromBox, BoxCount - 1);
        int files = 0;
        for (int b = fromBox; b <= toBox; b++)
        {
            var path = Path.Combine(dir, $"Box {b + 1:000}");
            foreach (var w in Load(b))
            {
                if (w is null) continue;
                w.Dump(fmt, path);
                files++;
            }
            Program.Event("progress", new { task = "homeDump", done = b - fromBox + 1, total = toBox - fromBox + 1 });
        }
        return new { files, dir };
    }
}
