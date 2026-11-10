using PKHeX.Core;
using PkMac.Engine.Features;

namespace PkMac.Engine;

/// <summary>Routes RPC method names to handlers. All handlers run one at a time.</summary>
public sealed class Dispatcher
{
    private readonly Session _s = new();
    private readonly Dictionary<string, Func<Params, object?>> _methods;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly LiveHex _liveHex;
    private readonly HomeLiveFeature _home;

    public Dispatcher()
    {
        _s.SetLanguage("it");
        AutoLegality.Configure(new Params(new()));
        AutoLegality.LoadEvents();
        _liveHex = new LiveHex(_s);
        _home = new HomeLiveFeature(_s);

        _methods = new()
        {
            ["hello"] = _ => new
            {
                versions = Versions.Get(),
                plugins = new[]
                {
                    new { id = "legality", name = "Controllo legalità", source = "PKHeX.Core" },
                    new { id = "checksum", name = "Verifica checksum al salvataggio", source = "PkMac" },
                    new { id = "alm", name = "Auto Legality Mod", source = "santacrab2/PKHeX-Plugins" },
                    new { id = "livehex", name = "LiveHeX", source = "santacrab2/PKHeX-Plugins" },
                    new { id = "homelive", name = "HOME Live", source = "Manu098vm/HOME-Live-Plugin" },
                    new { id = "pokefilename", name = "PokeFilename", source = "architdate/PokeFilename" },
                    new { id = "sorting", name = "Ordinamento Pokédex regionali", source = "foohyfooh/PKHeXPluginPile" },
                    new { id = "special", name = "Pokémon speciali", source = "foohyfooh/PKHeXPluginPile" },
                },
            },
            ["setLanguage"] = p => { _s.SetLanguage(p.Str("lang")); return true; },

            // ---- save ----
            ["open"] = p => SaveIO.Open(_s, p.Str("path"), p.OptStr("entry")),
            ["info"] = _ => SaveIO.Info(_s),
            ["save"] = p => SaveIO.Save(_s, p.OptStr("path"), p.Bool("backup", true)),
            ["checksum"] = _ => SaveIO.Checksum(_s),
            ["backups"] = p => SaveIO.Backups(_s, p.OptStr("path")),
            ["restoreBackup"] = p => SaveIO.RestoreBackup(_s, p.Str("backup")),
            ["close"] = _ => { _s.Close(); return true; },

            // ---- storage ----
            ["box"] = p => Storage.Box(_s, p.Int("box")),
            ["boxes"] = _ => Storage.BoxList(_s),
            ["party"] = _ => Storage.Party(_s),
            ["pokemon"] = p => Storage.Pokemon(_s, p.Slot()),
            ["update"] = p => Storage.Update(_s, p.Slot(), p.Obj("changes")),
            ["delete"] = p => Storage.Delete(_s, p.Slot()),
            ["move"] = p => Storage.Move(_s, p.Slot("from"), p.Slot("to"), p.Bool("copy")),
            ["renameBox"] = p => Storage.RenameBox(_s, p.Int("box"), p.Str("name")),
            ["search"] = p => Storage.Search(_s, p.Str("query")),
            ["stats"] = _ => Storage.Overview(_s),
            ["undo"] = _ => Storage.UndoRedo(_s, undo: true),
            ["redo"] = _ => Storage.UndoRedo(_s, undo: false),
            ["exportPk"] = p => Storage.ExportPk(_s, p.Slot(), p.Str("dir")),
            ["exportBox"] = p => Storage.ExportBox(_s, p.Int("box"), p.Str("dir")),
            ["importPk"] = p => Storage.ImportPk(_s, p.Str("path"), p.Slot()),
            ["exportShowdown"] = p => Storage.ExportShowdown(_s, p.Slot()),
            ["heal"] = p => Storage.Heal(_s, p.Slot()),
            ["maxStats"] = p => Storage.MaxStats(_s, p.Slot()),

            // ---- data sources ----
            ["lists"] = _ => DataLists.All(_s),
            ["speciesInfo"] = p => DataLists.Species(_s, (ushort)p.Int("species"), (byte)p.Int("form", 0)),

            // ---- trainer ----
            ["trainer"] = _ => TrainerInfo.Get(_s),
            ["setTrainer"] = p => TrainerInfo.Set(_s, p),

            // ---- Auto Legality Mod ----
            ["almConfigure"] = p => AutoLegality.Configure(p),
            ["legalize"] = p => AutoLegality.Legalize(_s, p.Slot()),
            ["legalizeBox"] = p => AutoLegality.LegalizeBox(_s, p.Int("box")),
            ["importShowdown"] = p => AutoLegality.ImportShowdown(_s, p.Str("text"), p.Int("box"), p.Int("slot", 0)),
            ["createPokemon"] = p => AutoLegality.Create(_s, p.Slot(), (ushort)p.Int("species"), (byte)p.Int("form", 0), p.Bool("shiny")),
            ["eventsStatus"] = _ => AutoLegality.EventsStatus(),
            ["downloadEvents"] = _ => AutoLegality.DownloadEvents(),
            ["livingDex"] = p => AutoLegality.LivingDex(_s, p.Int("startBox", 0), p.Bool("shiny"), p.Bool("forms")),

            // ---- PluginPile ----
            ["sortOptions"] = p => Sorting.Options(_s, p.Bool("areas")),
            ["sort"] = p => Sorting.Sort(_s, p),
            ["findSpecial"] = _ => SpecialFinder.Find(_s),

            // ---- PokeFilename ----
            ["namerOptions"] = _ => FileNaming.Options(),
            ["setNamer"] = p => FileNaming.Set(p),
            ["renameFolder"] = p => FileNaming.RenameFolder(p.Str("dir")),

            // ---- LiveHeX ----
            ["liveConnect"] = p => _liveHex.Connect(p.Str("ip"), p.Int("port", 6000)),
            ["liveDisconnect"] = _ => _liveHex.Disconnect(),
            ["liveStatus"] = _ => _liveHex.Status(),
            ["liveReadBox"] = p => _liveHex.ReadBox(p.Int("box")),
            ["liveWriteBox"] = p => _liveHex.WriteBox(p.Int("box")),

            // ---- HOME Live ----
            ["homeConnect"] = p => _home.Connect(p.Str("ip"), p.Int("port", 6000)),
            ["homeDisconnect"] = _ => _home.Disconnect(),
            ["homeBox"] = p => _home.ReadBox(p.Int("box")),
            ["homeImport"] = p => _home.Import(p.Int("homeBox"), p.Int("homeSlot"), p.Slot()),
            ["homeDump"] = p => _home.Dump(p.Str("dir"), p.Int("fromBox", 0), p.Int("toBox", 299), p.OptStr("format") ?? "decrypted"),
        };
    }

    public object? Invoke(string method, Params p)
    {
        if (!_methods.TryGetValue(method, out var handler))
            throw new EngineException($"Metodo sconosciuto: {method}");
        _gate.Wait();
        try { return handler(p); }
        finally { _gate.Release(); }
    }
}
