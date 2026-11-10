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

    /// <summary>"Make legal" / "Make mine" results waiting for the user's confirmation, by slot.</summary>
    public System.Collections.Concurrent.ConcurrentDictionary<string, (PKM Original, PKM Result, string Label)> Pending { get; } = new();

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
        Pending.Clear();
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
    public void Set(SlotRef r, PKM pk, EntityImportSettings? settings = null, bool recordUndo = true, string? label = null, UndoLink? link = null)
    {
        var sav = Sav;
        if (IsLocked(r))
            throw new EngineException(Tr.T($"Questo slot è protetto dal gioco (es. Pokémon in squadra di lotta)."));
        if (pk.GetType() != sav.PKMType)
        {
            var converted = EntityConverter.ConvertToType(pk, sav.PKMType, out var res);
            pk = converted ?? throw new EngineException(Tr.T($"Impossibile convertire il Pokémon per questo gioco ({res})."));
        }
        var before = recordUndo ? Get(r).Clone() : null;
        var s = settings ?? EditSettings;
        if (r.Party)
            sav.SetPartySlotAtIndex(pk, r.Slot, s);
        else
            sav.SetBoxSlotAtIndex(pk, r.Box, r.Slot, s);
        Dirty = true;
        if (before is not null)
            Record(new UndoEntry(r, before, label ?? Tr.T($"Modifica"), Link: link, After: Get(r).Clone()));
    }

    public void Clear(SlotRef r, bool recordUndo = true, string? label = null, UndoLink? link = null)
    {
        var sav = Sav;
        var before = recordUndo ? Get(r).Clone() : null;
        if (r.Party)
            sav.DeletePartySlot(r.Slot);
        else
            sav.SetBoxSlotAtIndex(sav.BlankPKM, r.Box, r.Slot, EntityImportSettings.None);
        Dirty = true;
        if (before is not null)
            Record(new UndoEntry(r, before, label ?? Tr.T($"Elimina"), Link: link, After: Get(r).Clone()));
    }

    /// <summary>Undo step that changes nothing here but is undone together with its partner (copy to another save).</summary>
    public void Mark(SlotRef r, string label, UndoLink link)
    {
        var current = Get(r).Clone();
        Record(new UndoEntry(r, current, label, Link: link, After: current.Clone()));
    }

    private void Record(UndoEntry e)
    {
        _undo.Push(e);
        _redo.Clear();
        if (_undo.Count > 200)
            TrimUndo();
    }

    /// <summary>Records a whole-save snapshot (used before bulk operations such as sorting or living dex).</summary>
    public void Snapshot(string label)
    {
        _undo.Push(new UndoEntry(null, null, label, Sav.Clone()));
        _redo.Clear();
    }

    public UndoEntry? Undo() => Step(_undo, _redo);
    public UndoEntry? Redo() => Step(_redo, _undo);

    // ---------- linked steps (transfers between two saves) ----------

    private static bool Same(PKM a, PKM b) =>
        a.Species == b.Species && a.Form == b.Form && a.PID == b.PID && a.EncryptionConstant == b.EncryptionConstant
        && a.Nickname == b.Nickname && a.CurrentLevel == b.CurrentLevel;

    private UndoEntry? FindLinked(long id, bool undo) => (undo ? _undo : _redo).FirstOrDefault(e => e.Link?.Id == id);

    /// <summary>Throws when the partner slot was changed after the transfer (undoing would overwrite that change).</summary>
    private void ValidateLinked(long id, bool undo)
    {
        if (Save is null) return;
        var e = FindLinked(id, undo);
        if (e is not { Ref: { } r, After: { } after }) return;
        if (!Same(Get(r), after))
            throw new EngineException(Tr.T($"Non posso annullare il trasferimento: nell'altro salvataggio lo slot {r.Box + 1}·{r.Slot + 1} è stato modificato dopo. Annulla prima quella modifica nell'altro salvataggio."));
    }

    /// <summary>Applies the partner entry of a linked step (wherever it is in the stack).</summary>
    private void ApplyLinked(long id, bool undo)
    {
        if (Save is null) return;
        var from = undo ? _undo : _redo;
        var to = undo ? _redo : _undo;
        var e = FindLinked(id, undo);
        if (e is null) return;
        var rest = from.Where(x => !ReferenceEquals(x, e)).Reverse().ToArray();
        from.Clear();
        foreach (var x in rest) from.Push(x);
        Restore(e, to);
    }
    public string? UndoLabel => _undo.TryPeek(out var e) ? e.Label : null;
    public string? RedoLabel => _redo.TryPeek(out var e) ? e.Label : null;

    private UndoEntry? Step(Stack<UndoEntry> from, Stack<UndoEntry> to)
    {
        if (!from.TryPeek(out var e))
            return null;
        bool undo = ReferenceEquals(from, _undo);
        // A transfer between two saves is one step: both sides go back (or forward) together.
        if (e.Link is { } link && !ReferenceEquals(link.Other, this))
            link.Other.ValidateLinked(link.Id, undo);
        from.Pop();
        Restore(e, to);
        if (e.Link is { } l && !ReferenceEquals(l.Other, this))
            l.Other.ApplyLinked(l.Id, undo);
        return e;
    }

    private void Restore(UndoEntry e, Stack<UndoEntry> to)
    {
        if (e.Whole is { } whole)
        {
            to.Push(new UndoEntry(null, null, e.Label, Sav.Clone()));
            Replace(whole);
        }
        else if (e.Ref is { } r && e.Entity is { } pk)
        {
            to.Push(new UndoEntry(r, Get(r).Clone(), e.Label, Link: e.Link, After: pk.Clone()));
            if (pk.Species == 0)
            {
                if (r.Party) Sav.SetPartySlotAtIndex(Sav.BlankPKM, r.Slot, EntityImportSettings.None);
                else Sav.SetBoxSlotAtIndex(Sav.BlankPKM, r.Box, r.Slot, EntityImportSettings.None);
            }
            else if (r.Party) Sav.SetPartySlotAtIndex(pk, r.Slot, EntityImportSettings.None);
            else Sav.SetBoxSlotAtIndex(pk, r.Box, r.Slot, EntityImportSettings.None);
        }
        Dirty = true;
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

/// <summary>
/// One undo step. <see cref="After"/> is what the slot holds right after the step was recorded,
/// used to check that a linked partner slot wasn't changed in the meantime.
/// </summary>
public sealed record UndoEntry(SlotRef? Ref, PKM? Entity, string Label, SaveFile? Whole = null, UndoLink? Link = null, PKM? After = null);

/// <summary>Ties two undo steps in two different saves (a transfer): undoing one undoes the other.</summary>
public sealed record UndoLink(Session Other, long Id);
