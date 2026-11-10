using PKHeX.Core;
using PkMac.Engine.Features;

namespace PkMac.Engine;

/// <summary>Routes RPC method names to handlers. All handlers run one at a time.</summary>
public sealed class Dispatcher
{
    private readonly Session _s = new();
    /// <summary>Second save, opened side by side for transfers.</summary>
    private readonly Session _b = new();

    /// <summary>"save": "b" in the params targets the second save.</summary>
    private Session S(Params p) => p.OptStr("save") == "b" ? _b : _s;
    private readonly Dictionary<string, Func<Params, object?>> _methods;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly LiveHex _liveHex;
    private readonly HomeLiveFeature _home;

    public Dispatcher()
    {
        _s.SetLanguage("it");
        _b.SetLanguage("it");
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
                    new { id = "legality", name = Tr.T($"Controllo legalità"), source = "PKHeX.Core" },
                    new { id = "checksum", name = Tr.T($"Verifica checksum al salvataggio"), source = "PkMac" },
                    new { id = "alm", name = Tr.T($"Auto Legality Mod"), source = "santacrab2/PKHeX-Plugins" },
                    new { id = "livehex", name = "LiveHeX", source = "santacrab2/PKHeX-Plugins" },
                    new { id = "homelive", name = Tr.T($"HOME Live"), source = "Manu098vm/HOME-Live-Plugin" },
                    new { id = "pokefilename", name = "PokeFilename", source = "architdate/PokeFilename" },
                    new { id = "sorting", name = Tr.T($"Ordinamento Pokédex regionali"), source = "foohyfooh/PKHeXPluginPile" },
                    new { id = "special", name = Tr.T($"Pokémon speciali"), source = "foohyfooh/PKHeXPluginPile" },
                },
            },
            ["setLanguage"] = p => { _s.SetLanguage(p.Str("lang")); _b.SetLanguage(p.Str("lang")); Tr.Set(p.Str("lang"), p.OptStr("table")); return true; },

            // ---- save ----
            ["open"] = p => SaveIO.Open(S(p), p.Str("path"), p.OptStr("entry")),
            ["info"] = p => SaveIO.Info(S(p)),
            ["save"] = p => SaveIO.Save(S(p), p.OptStr("path"), p.Bool("backup", true)),
            ["checksum"] = p => SaveIO.Checksum(S(p)),
            ["backups"] = p => SaveIO.Backups(S(p), p.OptStr("path")),
            ["restoreBackup"] = p => SaveIO.RestoreBackup(S(p), p.Str("backup")),
            ["backupPolicy"] = p => SaveIO.SetBackupPolicy(p.Int("keep", 20), p.Int("days", 0)),
            ["backupStats"] = _ => SaveIO.BackupStats(),
            ["backupPrune"] = _ => SaveIO.PruneAllBackups(),
            ["backupDeleteAll"] = _ => SaveIO.DeleteAllBackups(),
            ["close"] = p => { S(p).Close(); return true; },

            // ---- storage ----
            ["box"] = p => Storage.Box(S(p), p.Int("box")),
            ["boxes"] = p => Storage.BoxList(S(p)),
            ["party"] = p => Storage.Party(S(p)),
            ["pokemon"] = p => Storage.Pokemon(S(p), p.Slot()),
            ["update"] = p => Storage.Update(S(p), p.Slot(), p.Obj("changes")),
            ["delete"] = p => Storage.Delete(S(p), p.Slot()),
            ["move"] = p => Storage.Move(S(p), p.Slot("from"), p.Slot("to"), p.Bool("copy")),
            ["renameBox"] = p => Storage.RenameBox(S(p), p.Int("box"), p.Str("name")),
            ["search"] = p => Storage.Search(S(p), p.Str("query")),
            ["stats"] = p => Storage.Overview(S(p)),
            ["undo"] = p => Storage.UndoRedo(S(p), undo: true),
            ["redo"] = p => Storage.UndoRedo(S(p), undo: false),
            ["exportPk"] = p => Storage.ExportPk(S(p), p.Slot(), p.Str("dir")),
            ["exportBox"] = p => Storage.ExportBox(S(p), p.Int("box"), p.Str("dir")),
            ["importPk"] = p => Storage.ImportPk(S(p), p.Str("path"), p.Slot()),
            ["exportShowdown"] = p => Storage.ExportShowdown(S(p), p.Slot()),
            ["heal"] = p => Storage.Heal(S(p), p.Slot()),
            ["maxStats"] = p => Storage.MaxStats(S(p), p.Slot()),

            // ---- data sources ----
            ["lists"] = p => DataLists.All(S(p)),
            ["speciesInfo"] = p => DataLists.Species(S(p), (ushort)p.Int("species"), (byte)p.Int("form", 0)),

            // ---- trainer ----
            ["trainer"] = p => TrainerInfo.Get(S(p)),
            ["setTrainer"] = p => TrainerInfo.Set(S(p), p),

            // ---- Auto Legality Mod ----
            ["almConfigure"] = p => AutoLegality.Configure(p),
            ["legalize"] = p => AutoLegality.Legalize(S(p), p.Slot()),
            ["legalizePreview"] = p => AutoLegality.Preview(S(p), p.Slot(), p.Bool("mine")),
            ["legalizeApply"] = p => AutoLegality.ApplyPending(S(p), p.Slot()),
            ["legalizeBox"] = p => AutoLegality.LegalizeBox(S(p), p.Int("box")),
            ["importShowdown"] = p => AutoLegality.ImportShowdown(S(p), p.Str("text"), p.Int("box"), p.Int("slot", 0)),
            ["createPokemon"] = p => AutoLegality.Create(S(p), p.Slot(), (ushort)p.Int("species"), (byte)p.Int("form", 0), p.Bool("shiny")),
            ["eventsStatus"] = _ => AutoLegality.EventsStatus(),
            ["downloadEvents"] = _ => AutoLegality.DownloadEvents(),
            ["livingDex"] = p => AutoLegality.LivingDex(S(p), p.Int("startBox", 0), p.Bool("shiny"), p.Bool("forms")),

            // ---- PluginPile ----
            ["sortOptions"] = p => Sorting.Options(S(p), p.Bool("areas")),
            ["sort"] = p => Sorting.Sort(S(p), p),
            ["findSpecial"] = p => SpecialFinder.Find(S(p)),

            // ---- PokeFilename ----
            ["namerOptions"] = _ => FileNaming.Options(),
            ["setNamer"] = p => FileNaming.Set(p),
            ["renameFolder"] = p => FileNaming.RenameFolder(p.Str("dir")),

            // ---- transfer between saves / boxes ----
            ["transfer"] = p => Transfer.Move(S(p.Obj("from")), p.Slot("fromRef"), S(p.Obj("to")), p.Slot("toRef"), p.Bool("copy")),
            ["transferCheck"] = p => Transfer.Check(S(p.Obj("from")), p.Slot("fromRef"), S(p.Obj("to"))),
            ["moveToBox"] = p => Transfer.MoveToBox(S(p), p.Slot("from"), p.Int("box"), p.Bool("copy")),

            // ---- bag ----
            ["bag"] = p => Bag.Get(S(p)),
            ["bagSet"] = p => Bag.Set(S(p), p),
            ["bagAction"] = p => Bag.Action(S(p), p.Int("pouch"), p.Str("action"), p.Int("count", -1)),

            // ---- events ----
            ["events"] = p => Events.Get(S(p)),
            ["eventsSet"] = p => Events.Set(S(p), p),

            // ---- pokédex ----
            ["dex"] = p => Pokedex.Get(S(p)),
            ["dexSet"] = p => Pokedex.Set(S(p), p),

            // ---- mystery gifts ----
            ["giftAlbum"] = p => Gifts.Album(S(p)),
            ["giftDb"] = p => Gifts.Database(S(p), p.OptStr("query"), p.Int("limit", 400), p.Int("detail", -1), p.OptStr("region")),
            ["giftReceive"] = p => Gifts.Receive(S(p), p.Int("id"), p.OptObj("ref") is { } gr ? SlotRef.From(gr) : null),
            ["giftToAlbum"] = p => Gifts.PutInAlbum(S(p), p.Int("id"), p.Int("slot", -1)),
            ["giftDelete"] = p => Gifts.Delete(S(p), p.Int("slot")),
            ["giftImportFile"] = p => Gifts.ImportFile(S(p), p.Str("path"), p.OptObj("ref")),
            ["giftFlags"] = p => Gifts.SetFlags(S(p), p),

            // ---- blocks & generic inspector ----
            ["blocks"] = p => Blocks.List(S(p), p.OptStr("query"), p.Bool("valuesOnly")),
            ["blockSet"] = p => Blocks.Set(S(p), p.Str("key"), p.Raw["value"]!),
            ["inspect"] = p => Inspector.Inspect(S(p), p),
            ["inspectSet"] = p => Inspector.Set(S(p), p),
            ["originLists"] = p => Describe.OriginLists(S(p), p.Int("version", 0), p.Bool("egg")),
            ["ribbons"] = p => Storage.Ribbons(S(p), p.Slot()),
            ["ribbonsSet"] = p => Storage.SetRibbons(S(p), p.Slot(), p),

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
            throw new EngineException(Tr.T($"Metodo sconosciuto: {method}"));
        _gate.Wait();
        try { return handler(p); }
        finally { _gate.Release(); }
    }
}
