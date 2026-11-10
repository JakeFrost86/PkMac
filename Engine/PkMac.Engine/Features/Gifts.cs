using PKHeX.Core;

namespace PkMac.Engine.Features;

/// <summary>
/// Mystery Gift / Wonder Card album (Gen 4-7, LGPE), received flags, and the full event database
/// (PKHeX's bundled gifts + the downloaded EventsGallery) filtered for the open save.
/// </summary>
public static class Gifts
{
    // ---------- database ----------

    private static MysteryGift[] _all = [];
    private static int _allKey = -1;

    private static MysteryGift[] All
    {
        get
        {
            int key = EncounterEvent.EGDB_G4.Length + EncounterEvent.EGDB_G5.Length + EncounterEvent.EGDB_G6.Length
                    + EncounterEvent.EGDB_G7.Length + EncounterEvent.EGDB_G7GG.Length + EncounterEvent.EGDB_G8.Length
                    + EncounterEvent.EGDB_G8A.Length + EncounterEvent.EGDB_G8B.Length + EncounterEvent.EGDB_G9.Length
                    + EncounterEvent.EGDB_G9A.Length;
            if (key != _allKey || _all.Length == 0)
            {
                _all = EncounterEvent.GetAllEvents(sorted: true).ToArray();
                _allKey = key;
            }
            return _all;
        }
    }

    private static IMysteryGiftStorage? Storage(SaveFile sav) => (sav as IMysteryGiftStorageProvider)?.MysteryGiftStorage;

    private static DataMysteryGift[] LoadAlbum(SaveFile sav, IMysteryGiftStorage cards)
    {
        var count = cards.GiftCountMax;
        var result = new DataMysteryGift[sav is SAV4HGSS ? count + 1 : count];
        for (int i = 0; i < count; i++)
            result[i] = cards.GetMysteryGift(i);
        if (sav is SAV4HGSS hg)
            result[^1] = hg.LockCapsuleSlot;
        return result;
    }

    private static void SaveAlbum(SaveFile sav, IMysteryGiftStorage cards, DataMysteryGift[] album)
    {
        if (cards is MysteryBlock4 s4)
        {
            s4.IsDeliveryManActive = album.Any(g => !g.IsEmpty);
            MysteryBlock4.UpdateSlotPGT(album, sav is SAV4HGSS);
            if (sav is SAV4HGSS hgss)
                hgss.LockCapsuleSlot = (PCD)album[^1];
        }
        for (int i = 0; i < cards.GiftCountMax; i++)
            cards.SetMysteryGift(i, album[i]);
        if (cards is MysteryBlock5 s5)
            s5.EndAccess();
    }

    private static object Card(Session s, MysteryGift g, int? slot = null, int? id = null, bool? canAlbum = null, bool? canReceive = null)
    {
        var sav = s.Sav;
        if (g.IsEmpty)
            return new { slot, id, empty = true };
        string? itemName = null, itemKey = null;
        if (g.IsItem && g.ItemID > 0)
        {
            itemName = Describe.Name(s.Strings.Item, g.ItemID);
            itemKey = Describe.AssetKey(Describe.Name(s.English.Item, g.ItemID));
        }
        return new
        {
            slot,
            id,
            empty = false,
            type = g.Type,
            generation = g.Generation,
            cardId = g.CardID,
            title = g.CardTitle.Replace('　', ' ').Trim(),
            isEntity = g.IsEntity,
            isItem = g.IsItem,
            species = g.IsEntity ? g.Species : (ushort)0,
            speciesName = g.IsEntity ? Describe.Name(s.Strings.Species, g.Species) : null,
            form = g.Form,
            formKey = g.IsEntity && g.Species > 0 ? Describe.FormKey(s, g.Species, g.Form, sav.Context) : null,
            level = g.IsEntity ? g.Level : (byte)0,
            shiny = g.IsEntity && g.IsShiny,
            egg = g.IsEntity && g.IsEgg,
            heldItem = g.IsEntity && g.HeldItem > 0 ? Describe.Name(s.Strings.Item, g.HeldItem) : null,
            item = itemName,
            itemKey,
            quantity = g.IsItem ? g.Quantity : 0,
            ot = g.IsEntity ? g.OriginalTrainerName : null,
            used = SafeUsed(g),
            canAlbum,
            canReceive,
            languages = Languages(g),
        };
    }

    // ---------- languages / regions ----------

    private static readonly int[] AllLanguages = [1, 2, 3, 4, 5, 7, 8, 9, 10];

    /// <summary>
    /// Languages a card can be received in (LanguageID: 1 JPN, 2 ENG, 3 FRE, 4 ITA, 5 GER, 7 SPA, 8 KOR, 9 CHS, 10 CHT).
    /// Empty = any language. Cards don't record the distribution country, only these restrictions.
    /// </summary>
    public static int[] Languages(MysteryGift g)
    {
        try
        {
            switch (g)
            {
                case WC9 w: return w.CanBeAnyLanguage() ? [] : AllLanguages.Where(w.CanHaveLanguage).ToArray();
                case WA9 w: return w.CanBeAnyLanguage() ? [] : AllLanguages.Where(w.CanHaveLanguage).ToArray();
                case WC8 w: return w.CanBeAnyLanguage() ? [] : AllLanguages.Where(w.CanHaveLanguage).ToArray();
                case WA8 w: return w.CanBeAnyLanguage() ? [] : AllLanguages.Where(w.CanHaveLanguage).ToArray();
                case WB8 w: return w.CanBeAnyLanguage() ? [] : AllLanguages.Where(w.CanHaveLanguage).ToArray();
                case WB7 w: return w.CanBeAnyLanguage() ? [] : AllLanguages.Where(w.CanHaveLanguage).ToArray();
                case WC7 w: return Fixed(w.Language, w.RestrictLanguage);
                case WC6 w: return Fixed(w.Language, w.RestrictLanguage);
                case PGF w: return Fixed(w.Language, w.RestrictLanguage);
                case PCD w: return Fixed(w.Gift.PK.Language, 0);
                case PGT w: return Fixed(w.PK.Language, 0);
            }
        }
        catch { }
        return [];
    }

    private static int[] Fixed(int language, int restrict) =>
        language is > 0 and <= 10 ? [language] : restrict is > 0 and <= 10 ? [restrict] : [];

    private static int[]?[]? _languages;
    private static int[] LanguagesAt(int i)
    {
        var cache = _languages ??= new int[]?[All.Length];
        return cache[i] ??= Languages(All[i]);
    }

    /// <summary>region: "" all, "any" valid everywhere, or a LanguageID (only cards restricted to languages that include it).</summary>
    private static bool MatchesRegion(int index, string? region)
    {
        if (string.IsNullOrEmpty(region)) return true;
        var langs = LanguagesAt(index);
        if (region == "any") return langs.Length == 0;
        return int.TryParse(region, out var lang) && langs.Length > 0 && langs.Contains(lang);
    }

    private static bool SafeUsed(MysteryGift g) { try { return g.GiftUsed; } catch { return false; } }

    private static Func<MysteryGift, bool> EntityFilter(SaveFile sav)
    {
        var f = PKHeX.Core.Searching.EntityPresenceFilters.GetFilterGift<MysteryGift>(sav.Context, sav.Generation);
        return g => g.IsEntity && g.Species > 0 && sav.CanReceiveGift(g) && (f is null || f(g));
    }

    private static bool AlbumCompatible(SaveFile sav, MysteryGift g, IReadOnlyCollection<string> types)
    {
        if (g is not DataMysteryGift || !g.IsCardCompatible(sav, out _))
            return false;
        if (types.Contains(g.Type))
            return true;
        return g is PCD { CanConvertToPGT: true } && types.Contains(nameof(PGT));
    }

    public static object Database(Session s, string? query, int limit, int detail = -1, string? region = null)
    {
        var sav = s.Sav;
        var all = All;
        if (detail >= 0)
        {
            if ((uint)detail >= all.Length) throw new EngineException(Tr.T($"Dono non trovato."));
            var g = all[detail];
            return new { card = Card(s, g, id: detail), lines = g.GetDescription(s.Strings).ToArray() };
        }

        var cards = Storage(sav);
        var types = cards is null ? [] : LoadAlbum(sav, cards).Select(c => c.Type).Distinct().ToArray();
        var entity = EntityFilter(sav);
        var q = query?.Trim() ?? "";

        var hits = new List<object>();
        int total = 0;
        for (int i = 0; i < all.Length; i++)
        {
            var g = all[i];
            bool canReceive = entity(g);
            bool canAlbum = cards is not null && AlbumCompatible(sav, g, types);
            if (!canReceive && !canAlbum)
                continue;
            if (!MatchesRegion(i, region))
                continue;
            if (q.Length > 0)
            {
                var hay = $"{g.CardTitle} {g.CardID} {(g.IsEntity ? Describe.Name(s.Strings.Species, g.Species) : "")} {(g.IsItem ? Describe.Name(s.Strings.Item, g.ItemID) : "")} {g.OriginalTrainerName}";
                if (!hay.Contains(q, StringComparison.CurrentCultureIgnoreCase))
                    continue;
            }
            total++;
            if (hits.Count < limit)
                hits.Add(Card(s, g, id: i, canAlbum: canAlbum, canReceive: canReceive));
        }
        return new { total, shown = hits.Count, albumTypes = types, hasAlbum = cards is not null, items = hits };
    }

    // ---------- album ----------

    public static object Album(Session s)
    {
        var sav = s.Sav;
        var flagsObj = Storage(sav) as IMysteryGiftFlags;
        var cards = Storage(sav);
        if (cards is null)
        {
            return new
            {
                supported = false,
                message = sav.Generation >= 8
                    ? Tr.T($"In questo gioco i doni segreti si riscattano dal gioco online: puoi comunque aggiungere i Pokémon evento dal database qui accanto.")
                    : Tr.T($"Questo gioco non ha un album dei doni segreti: puoi comunque ricevere i Pokémon evento dal database."),
            };
        }
        var album = LoadAlbum(sav, cards);
        var received = new List<int>();
        if (flagsObj is not null)
            for (int i = 0; i < flagsObj.MysteryGiftReceivedFlagMax; i++)
                if (flagsObj.GetMysteryGiftReceivedFlag(i)) received.Add(i);
        return new
        {
            supported = true,
            capacity = album.Length,
            lockCapsuleSlot = sav is SAV4HGSS ? album.Length - 1 : -1,
            cards = album.Select((g, i) => new { card = Card(s, g, slot: i), lines = g.IsEmpty ? Array.Empty<string>() : g.GetDescription(s.Strings).ToArray() }).ToArray(),
            hasFlags = flagsObj is not null,
            flagMax = flagsObj?.MysteryGiftReceivedFlagMax ?? 0,
            received,
            canToggleUsed = album.FirstOrDefault() is not WR7,
        };
    }

    private static object PutGift(Session s, MysteryGift incoming, int slot)
    {
        var sav = s.Sav;
        var cards = Storage(sav) ?? throw new EngineException(Tr.T($"Questo gioco non ha un album dei doni segreti."));
        if (incoming is not DataMysteryGift gift)
            throw new EngineException(Tr.T($"Questo dono non può essere inserito nell'album."));
        if (!gift.IsCardCompatible(sav, out var msg))
            throw new EngineException(Tr.T($"Dono non compatibile con questo salvataggio. {msg}"));

        var album = LoadAlbum(sav, cards);
        if (gift is PCD { IsLockCapsule: true })
        {
            if (sav is not SAV4HGSS) throw new EngineException(Tr.T($"La Capsula Sigillo esiste solo in HeartGold/SoulSilver."));
            slot = album.Length - 1;
        }
        else
        {
            int last = sav is SAV4HGSS ? album.Length - 1 : album.Length;
            bool Free(int i, string type) => i < last && album[i].IsEmpty && album[i].Type == type;
            if (slot >= 0 && slot < album.Length && gift is PCD { CanConvertToPGT: true } p1 && album[slot] is PGT)
                gift = p1.Gift; // dropped on a PGT slot: store the deliverable gift
            else if (slot < 0 && gift is PCD { CanConvertToPGT: true } p2 && !Enumerable.Range(0, last).Any(i => Free(i, nameof(PCD))))
                gift = p2.Gift; // no free card slot: deliver it through the PGT queue
            if (slot < 0)
                slot = Array.FindIndex(album, a => a.IsEmpty && a.Type == gift.Type && (sav is not SAV4HGSS || Array.IndexOf(album, a) != album.Length - 1));
            if (slot < 0)
                throw new EngineException(Tr.T($"L'album dei doni è pieno: elimina una carta prima di aggiungerne un'altra."));
            // No gaps: move to the first empty slot of the same type.
            int firstEmpty = Array.FindIndex(album, a => a.IsEmpty && a.Type == gift.Type);
            if (firstEmpty >= 0 && firstEmpty < slot)
                slot = firstEmpty;
            if (sav is SAV4HGSS && slot == album.Length - 1)
                throw new EngineException(Tr.T($"Questo slot è riservato alla Capsula Sigillo."));
        }
        if ((uint)slot >= album.Length)
            throw new EngineException(Tr.T($"Slot dell'album non valido."));
        if (album[slot].Type != gift.Type)
            throw new EngineException(Tr.T($"Tipo di carta non compatibile con lo slot ({gift.Type} ≠ {album[slot].Type})."));

        s.Snapshot(Tr.T($"Dono segreto"));
        album[slot] = (DataMysteryGift)gift.Clone();
        SaveAlbum(sav, cards, album);
        // Mark the card id as received, like the game does.
        if (Storage(sav) is IMysteryGiftFlags flags && gift.CardID > 0 && gift.CardID < flags.MysteryGiftReceivedFlagMax)
            flags.SetMysteryGiftReceivedFlag(gift.CardID, true);
        s.Dirty = true;
        return Album(s);
    }

    public static object PutInAlbum(Session s, int id, int slot)
    {
        var all = All;
        if ((uint)id >= all.Length) throw new EngineException(Tr.T($"Dono non trovato."));
        return PutGift(s, all[id], slot);
    }

    public static object Delete(Session s, int slot)
    {
        var sav = s.Sav;
        var cards = Storage(sav) ?? throw new EngineException(Tr.T($"Questo gioco non ha un album dei doni segreti."));
        var album = LoadAlbum(sav, cards);
        if ((uint)slot >= album.Length) throw new EngineException(Tr.T($"Slot non valido."));
        s.Snapshot(Tr.T($"Elimina dono"));
        album[slot].Clear();
        int i = slot;
        while (i < album.Length - 1)
        {
            if (album[i + 1].IsEmpty || album[i + 1].Type != album[i].Type)
                break;
            i++;
            (album[i - 1], album[i]) = (album[i], album[i - 1]);
        }
        SaveAlbum(sav, cards, album);
        s.Dirty = true;
        return Album(s);
    }

    /// <summary>{ received: [ids] } replaces received flags; { action: "clear" }; { slot, used } toggles a card.</summary>
    public static object SetFlags(Session s, Params p)
    {
        var sav = s.Sav;
        var cards = Storage(sav) ?? throw new EngineException(Tr.T($"Questo gioco non ha un album dei doni segreti."));
        s.Snapshot(Tr.T($"Doni ricevuti"));
        if (cards is IMysteryGiftFlags flags)
        {
            if (p.OptStr("action") == "clear")
                flags.ClearReceivedFlags();
            if (p.IntArray("received") is { } list)
            {
                flags.ClearReceivedFlags();
                foreach (var i in list)
                    if ((uint)i < flags.MysteryGiftReceivedFlagMax) flags.SetMysteryGiftReceivedFlag(i, true);
            }
        }
        if (p.Has("slot") && p.Has("used"))
        {
            var album = LoadAlbum(sav, cards);
            var slot = p.Int("slot");
            if ((uint)slot < album.Length && !album[slot].IsEmpty)
            {
                album[slot].GiftUsed = p.Bool("used");
                SaveAlbum(sav, cards, album);
            }
        }
        s.Dirty = true;
        return Album(s);
    }

    // ---------- receive as Pokémon ----------

    private static object ReceiveGift(Session s, MysteryGift g, SlotRef? target)
    {
        var sav = s.Sav;
        if (!g.IsEntity || g.Species == 0)
            throw new EngineException(Tr.T($"Questo dono non contiene un Pokémon."));
        if (!EntityFilter(sav)(g))
            throw new EngineException(Tr.T($"Questo Pokémon evento non può arrivare in {GameInfo.GetVersionName(sav.Version)}."));

        PKM pk;
        try { pk = g.ConvertToPKM(sav); }
        catch (Exception e) { throw new EngineException(Tr.T($"Impossibile generare il Pokémon dal dono: {e.Message}")); }

        if (pk.GetType() != sav.PKMType)
        {
            var conv = EntityConverter.ConvertToType(pk, sav.PKMType, out var res);
            pk = conv ?? throw new EngineException(Tr.T($"Questo Pokémon evento non è trasferibile in questo gioco ({res})."));
        }
        var errata = sav.EvaluateCompatibility(pk, s.Language);
        if (errata.Count > 0)
            throw new EngineException(Tr.T($"Non compatibile con questo gioco:\n") + string.Join("\n", errata));

        var r = target ?? FirstFree(sav);
        if (s.Get(r).Species != 0)
            throw new EngineException(Tr.T($"Lo slot scelto è occupato."));
        s.Set(r, pk, settings: default(EntityImportSettings), label: Tr.T($"Dono segreto"));
        return new { ok = true, @ref = r.ToJson(), detail = Describe.Detail(s, r, s.Get(r)) };
    }

    private static SlotRef FirstFree(SaveFile sav)
    {
        for (int b = 0; b < sav.BoxCount; b++)
            for (int i = 0; i < sav.BoxSlotCount; i++)
                if (sav.GetBoxSlotAtIndex(b, i).Species == 0 && !sav.IsBoxSlotOverwriteProtected(b, i))
                    return new SlotRef(false, b, i);
        throw new EngineException(Tr.T($"I box sono pieni."));
    }

    public static object Receive(Session s, int id, SlotRef? target)
    {
        var all = All;
        if ((uint)id >= all.Length) throw new EngineException(Tr.T($"Dono non trovato."));
        return ReceiveGift(s, all[id], target);
    }

    /// <summary>Imports a .wc*/.pgf/.pgt/.pcd/.wb7/.wr7… file: into the album, or as a Pokémon when a slot is given / no album.</summary>
    public static object ImportFile(Session s, string path, Params? reference)
    {
        var data = File.ReadAllBytes(path);
        var gift = MysteryGift.GetMysteryGift(data, System.IO.Path.GetExtension(path))
                   ?? throw new EngineException(Tr.T($"Il file non è un dono segreto riconosciuto."));
        if (reference is not null)
            return ReceiveGift(s, gift, SlotRef.From(reference));
        if (Storage(s.Sav) is not null && gift is DataMysteryGift && gift.Generation == s.Sav.Generation)
            return PutGift(s, gift, -1);
        return ReceiveGift(s, gift, null);
    }
}
