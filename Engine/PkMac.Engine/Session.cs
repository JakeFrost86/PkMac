using PKHeX.Core;

namespace PkMac.Engine;

/// <summary>Holds the currently open save file plus per-session state (language, undo history).</summary>
public sealed class Session
{
    public SaveFile? Save { get; private set; }
    public string? Path { get; private set; }
    public string Language { get; private set; } = "it";
    public GameStrings Strings { get; private set; } = GameInfo.GetStrings("it");
    public GameStrings English { get; } = GameInfo.GetStrings("en");
    public bool Dirty { get; set; }
    /// <summary>Pick lists filtered for this save (each open save has its own).</summary>
    public FilteredGameDataSource Sources { get; private set; } = GameInfo.FilteredSources;

    private readonly Stack<UndoEntry> _undo = new();
    private readonly Stack<UndoEntry> _redo = new();

    /// <summary>Edits never rewrite trainer/handler data; imports use PKHeX defaults.</summary>
    public static readonly EntityImportSettings EditSettings = new(EntityImportOption.Disable, EntityImportOption.Enable, EntityImportOption.Disable);

    public SaveFile Sav => Save ?? throw new EngineException(Tr.T($"Nessun salvataggio aperto."));

    public void SetLanguage(string lang)
    {
        Language = lang;
        GameInfo.CurrentLanguage = lang;
        Strings = GameInfo.GetStrings(lang);
        GameInfo.Strings = Strings;
        if (Save is { } sav)
            Sources = new FilteredGameDataSource(sav, GameInfo.Sources);
    }

    /// <summary>Set when the save lives inside an Azurii zip (export, slot, iCloud copy or full backup).</summary>
    public Features.AzuriiZip.Container? Container { get; private set; }

    public void Load(SaveFile sav, string path, Features.AzuriiZip.Container? container = null)
    {
        Save = sav;
        Path = path;
        Container = container;
        Dirty = false;
        _undo.Clear();
        _redo.Clear();
        Sources = new FilteredGameDataSource(sav, GameInfo.Sources);
    }

    public void Close()
    {
        Save = null;
        Path = null;
        Container = null;
        Dirty = false;
        _undo.Clear();
        _redo.Clear();
    }

    public void Replace(SaveFile sav)
    {
        Save = sav;
        Sources = new FilteredGameDataSource(sav, GameInfo.Sources);
    }

    // ---------- slot access ----------

    public PKM Get(SlotRef r)
    {
        var sav = Sav;
        if (r.Party)
        {
            if (!sav.HasParty || (uint)r.Slot >= 6)
                throw new EngineException(Tr.T($"Slot squadra non valido."));
            return sav.GetPartySlotAtIndex(r.Slot);
        }
        if (!sav.HasBox || (uint)r.Box >= sav.BoxCount || (uint)r.Slot >= sav.BoxSlotCount)
            throw new EngineException(Tr.T($"Slot box non valido."));
        return sav.GetBoxSlotAtIndex(r.Box, r.Slot);
    }

    public bool IsLocked(SlotRef r) => !r.Party && Sav.IsBoxSlotOverwriteProtected(r.Box, r.Slot);

    /// <summary>Writes an entity to a slot, recording the previous content for undo.</summary>
    public void Set(SlotRef r, PKM pk, EntityImportSettings? settings = null, bool recordUndo = true, string? label = null)
    {
        var sav = Sav;
        if (IsLocked(r))
            throw new EngineException(Tr.T($"Questo slot è protetto dal gioco (es. Pokémon in squadra di lotta)."));
        if (pk.GetType() != sav.PKMType)
        {
            var converted = EntityConverter.ConvertToType(pk, sav.PKMType, out var res);
            pk = converted ?? throw new EngineException(Tr.T($"Impossibile convertire il Pokémon per questo gioco ({res})."));
        }
        if (recordUndo)
        {
            _undo.Push(new UndoEntry(r, Get(r).Clone(), label ?? Tr.T($"Modifica")));
            _redo.Clear();
            if (_undo.Count > 200)
                TrimUndo();
        }
        var s = settings ?? EditSettings;
        if (r.Party)
            sav.SetPartySlotAtIndex(pk, r.Slot, s);
        else
            sav.SetBoxSlotAtIndex(pk, r.Box, r.Slot, s);
        Dirty = true;
    }

    public void Clear(SlotRef r, bool recordUndo = true)
    {
        var sav = Sav;
        if (recordUndo)
        {
            _undo.Push(new UndoEntry(r, Get(r).Clone(), Tr.T($"Elimina")));
            _redo.Clear();
        }
        if (r.Party)
            sav.DeletePartySlot(r.Slot);
        else
            sav.SetBoxSlotAtIndex(sav.BlankPKM, r.Box, r.Slot, EntityImportSettings.None);
        Dirty = true;
    }

    /// <summary>Records a whole-save snapshot (used before bulk operations such as sorting or living dex).</summary>
    public void Snapshot(string label)
    {
        _undo.Push(new UndoEntry(null, null, label, Sav.Clone()));
        _redo.Clear();
    }

    public UndoEntry? Undo() => Step(_undo, _redo);
    public UndoEntry? Redo() => Step(_redo, _undo);
    public string? UndoLabel => _undo.TryPeek(out var e) ? e.Label : null;
    public string? RedoLabel => _redo.TryPeek(out var e) ? e.Label : null;

    private UndoEntry? Step(Stack<UndoEntry> from, Stack<UndoEntry> to)
    {
        if (!from.TryPop(out var e))
            return null;
        if (e.Whole is { } whole)
        {
            to.Push(new UndoEntry(null, null, e.Label, Sav.Clone()));
            Replace(whole);
        }
        else if (e.Ref is { } r && e.Entity is { } pk)
        {
            to.Push(new UndoEntry(r, Get(r).Clone(), e.Label));
            if (pk.Species == 0)
            {
                if (r.Party) Sav.SetPartySlotAtIndex(Sav.BlankPKM, r.Slot, EntityImportSettings.None);
                else Sav.SetBoxSlotAtIndex(Sav.BlankPKM, r.Box, r.Slot, EntityImportSettings.None);
            }
            else if (r.Party) Sav.SetPartySlotAtIndex(pk, r.Slot, EntityImportSettings.None);
            else Sav.SetBoxSlotAtIndex(pk, r.Box, r.Slot, EntityImportSettings.None);
        }
        Dirty = true;
        return e;
    }

    private void TrimUndo()
    {
        var keep = _undo.Take(150).Reverse().ToArray();
        _undo.Clear();
        foreach (var e in keep)
            _undo.Push(e);
    }

    public string BoxName(int box)
    {
        var sav = Sav;
        try
        {
            if (sav is IBoxDetailNameRead n)
            {
                var name = n.GetBoxName(box);
                if (!string.IsNullOrWhiteSpace(name))
                    return name;
            }
        }
        catch { /* some formats throw for unnamed boxes */ }
        return Tr.T($"Box {box + 1}");
    }
}

public sealed record UndoEntry(SlotRef? Ref, PKM? Entity, string Label, SaveFile? Whole = null);
