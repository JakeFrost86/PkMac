using PKHeX.Core;

namespace PkMac.Engine.Features;

/// <summary>Bag / inventory editor for every game PKHeX supports.</summary>
public static class Bag
{
    private static string PouchName(InventoryType t) => t switch
    {
        InventoryType.Items => "Strumenti",
        InventoryType.KeyItems => "Strumenti chiave",
        InventoryType.TMHMs => "MT e MN",
        InventoryType.Medicine => "Medicine",
        InventoryType.Berries => "Bacche",
        InventoryType.Balls => "Poké Ball",
        InventoryType.BattleItems => "Strumenti lotta",
        InventoryType.MailItems => "Lettere",
        InventoryType.PCItems => "Strumenti nel PC",
        InventoryType.FreeSpace => "Spazio libero",
        InventoryType.ZCrystals => "Cristalli Z",
        InventoryType.Candy => "Caramelle",
        InventoryType.Treasure => "Tesori",
        InventoryType.Ingredients => "Ingredienti",
        _ => t.ToString(),
    };

    private static string Symbol(InventoryType t) => t switch
    {
        InventoryType.KeyItems => "key.fill",
        InventoryType.TMHMs => "opticaldisc.fill",
        InventoryType.Medicine => "cross.vial.fill",
        InventoryType.Berries => "leaf.fill",
        InventoryType.Balls => "circle.circle.fill",
        InventoryType.BattleItems => "bolt.shield.fill",
        InventoryType.MailItems => "envelope.fill",
        InventoryType.PCItems => "desktopcomputer",
        InventoryType.ZCrystals => "diamond.fill",
        InventoryType.Candy => "birthday.cake.fill",
        InventoryType.Treasure => "crown.fill",
        InventoryType.Ingredients => "fork.knife",
        _ => "bag.fill",
    };

    /// <summary>
    /// Item ID in today's numbering (the one PKHeX's own item sprites use, bitem_N.png):
    /// Gen 2 and Gen 3 bags use older IDs. 0 when there is no equivalent.
    /// </summary>
    public static int SpriteId(SaveFile sav, int id)
    {
        try
        {
            int v = sav.Generation switch
            {
                1 => 0,
                2 => id <= byte.MaxValue ? ItemConverter.GetItemFuture2((byte)id) : 0,
                3 => ItemConverter.GetItemFuture3((ushort)id),
                _ => id,
            };
            return sav.Generation is 2 or 3 && v == 128 ? 0 : v; // 128 = no equivalent
        }
        catch { return 0; }
    }

    public static object Get(Session s)
    {
        var sav = s.Sav;
        var bag = sav.Inventory;
        var names = s.Strings.GetItemStrings(sav.Context, sav.Version);
        var english = s.English.GetItemStrings(sav.Context, sav.Version);
        string N(string[] list, int i) => (uint)i < (uint)list.Length && list[i].Length > 0 ? list[i] : $"#{i}";

        var pouches = bag.Pouches.Select((pouch, index) =>
        {
            var items = pouch.Items.Where(i => i.Index > 0 && i.Count > 0).Select(i => new
            {
                id = i.Index,
                count = i.Count,
                name = N(names, i.Index),
                key = Describe.AssetKey(N(english, i.Index)),
                sid = SpriteId(sav, i.Index),
                max = bag.GetMaxCount(pouch.Type, i.Index),
            }).ToArray();
            var allowed = pouch.GetAllItems().ToArray()
                .Where(id => id > 0 && id <= sav.MaxItemID && N(names, id) is { } n && !n.StartsWith('#') && !n.StartsWith('(') && n != "???")
                .Select(id => new { v = (int)id, t = N(names, id), key = Describe.AssetKey(N(english, id)), sid = SpriteId(sav, id) })
                .OrderBy(x => x.t, StringComparer.CurrentCultureIgnoreCase).ToArray();
            return new
            {
                index,
                type = pouch.Type.ToString(),
                name = PouchName(pouch.Type),
                symbol = Symbol(pouch.Type),
                capacity = pouch.Items.Length,
                maxCount = pouch.MaxCount,
                items,
                allowed,
            };
        }).ToArray();
        return new { pouches, supported = pouches.Length > 0 };
    }

    /// <summary>Replaces pouches: { pouches: [{ index, items: [{ id, count }] }] }.</summary>
    public static object Set(Session s, Params p)
    {
        var sav = s.Sav;
        var bag = sav.Inventory;
        if (p.Raw["pouches"] is not System.Text.Json.Nodes.JsonArray list)
            throw new EngineException(Tr.T($"Richiesta non valida."));

        foreach (var node in list)
        {
            if (node is not System.Text.Json.Nodes.JsonObject o) continue;
            var entry = new Params(o);
            var index = entry.Int("index", -1);
            if ((uint)index >= bag.Pouches.Count) continue;
            var pouch = bag.Pouches[index];

            var requested = new List<(ushort Id, int Count)>();
            if (o["items"] is System.Text.Json.Nodes.JsonArray items)
            {
                foreach (var it in items)
                {
                    if (it is not System.Text.Json.Nodes.JsonObject io) continue;
                    var ip = new Params(io);
                    var id = (ushort)Math.Clamp(ip.Int("id", 0), 0, ushort.MaxValue);
                    var count = ip.Int("count", 0);
                    if (id == 0 || count <= 0 || id > sav.MaxItemID || !pouch.CanContain(id)) continue;
                    count = Math.Min(count, bag.GetMaxCount(pouch.Type, id));
                    var at = requested.FindIndex(x => x.Id == id);
                    if (at >= 0) requested[at] = (id, Math.Min(requested[at].Count + count, bag.GetMaxCount(pouch.Type, id)));
                    else requested.Add((id, count));
                }
            }
            if (requested.Count > pouch.Items.Length)
                throw new EngineException(Tr.T($"La tasca {PouchName(pouch.Type)} contiene al massimo {pouch.Items.Length} oggetti diversi."));

            var slots = pouch.Items;
            var existing = new Dictionary<int, InventoryItem>();
            foreach (var item in slots)
                if (item.Index > 0) existing.TryAdd(item.Index, item);
            for (int i = 0; i < slots.Length; i++)
            {
                if (i < requested.Count)
                {
                    var (id, count) = requested[i];
                    var item = existing.TryGetValue(id, out var kept) ? kept : pouch.GetEmpty(id, count);
                    item.Index = id;
                    item.Count = count;
                    slots[i] = item;
                }
                else
                {
                    slots[i] = pouch.GetEmpty();
                }
            }
        }
        bag.CopyTo(sav);
        s.Dirty = true;
        return Get(s);
    }

    /// <summary>Quick actions on one pouch: giveAll, maxAll, clear, sortName, sortCount.</summary>
    public static object Action(Session s, int pouchIndex, string action, int count)
    {
        var sav = s.Sav;
        var bag = sav.Inventory;
        if ((uint)pouchIndex >= bag.Pouches.Count)
            throw new EngineException(Tr.T($"Tasca non valida."));
        var pouch = bag.Pouches[pouchIndex];
        switch (action)
        {
            case "giveAll": pouch.GiveAllItems(bag, count); break;
            case "maxAll": pouch.ModifyAllCount(bag, count); break;
            case "clear": pouch.RemoveAll(); break;
            case "sortName": pouch.SortByName(s.Strings.GetItemStrings(sav.Context, sav.Version)); break;
            case "sortCount": pouch.SortByCount(reverse: true); break;
            default: throw new EngineException(Tr.T($"Azione sconosciuta."));
        }
        bag.CopyTo(sav);
        s.Dirty = true;
        return Get(s);
    }
}
