using System.Globalization;
using System.Reflection;
using System.Text.Json.Nodes;
using PKHeX.Core;

namespace PkMac.Engine.Features;

/// <summary>
/// Reflection editor ("everything PKHeX can edit"): walks the public properties of the save file, its
/// sub-blocks and of a Pokémon, exposing every primitive/enum/string value with a public setter.
/// </summary>
public static class Inspector
{
    private static readonly HashSet<string> Hidden = new(StringComparer.Ordinal)
    {
        "Data", "Raw", "Buffer", "Memory", "State", "Metadata", "Blank", "BlankPKM", "Personal", "Inventory",
        "Context", "PKMType", "Extension", "ChecksumsValid", "ChecksumInfo", "Checksum", "Checksums", "Edited",
        "SIZE", "SIZE_STORED", "SIZE_PARTY", "EncryptedPartyData", "EncryptedBoxData", "DecryptedPartyData",
        "DecryptedBoxData", "Nickname_Trash", "OriginalTrainerTrash", "HandlingTrainerTrash", "NicknameTrash",
        "Accessor", "AllBlocks", "Blocks", "BoxData", "PartyData", "MysteryGiftStorage", "EventWork", "FlagWork",
        "SaveRevisionString", "Footer", "Header", "FileName", "FilePath", "FileFolder", "MetadataSource",
        "Version", "PartyBoxData", "BoxInfo", "BoxLayout", "Zukan", "PokeDex", "Dex", "Records", "BoxWallpapers",
    };

    private static bool IsSimple(Type t)
    {
        t = Nullable.GetUnderlyingType(t) ?? t;
        return t.IsPrimitive || t.IsEnum || t == typeof(string) || t == typeof(decimal);
    }

    private static bool IsChild(Type t) =>
        t.IsClass && t != typeof(string) && t.Namespace == "PKHeX.Core" &&
        !typeof(System.Collections.IEnumerable).IsAssignableFrom(t) && !typeof(Delegate).IsAssignableFrom(t) &&
        !typeof(PKM).IsAssignableFrom(t) && !typeof(SaveFile).IsAssignableFrom(t) && !typeof(MysteryGift).IsAssignableFrom(t);

    private static IEnumerable<PropertyInfo> Props(Type t) => t
        .GetProperties(BindingFlags.Instance | BindingFlags.Public)
        .Where(p => p.GetIndexParameters().Length == 0 && p.CanRead && !Hidden.Contains(p.Name) &&
                    !p.Name.StartsWith("Offset", StringComparison.Ordinal) && !p.Name.EndsWith("Offset", StringComparison.Ordinal) &&
                    !p.PropertyType.IsByRefLike && p.GetCustomAttribute<ObsoleteAttribute>() is null)
        .GroupBy(p => p.Name).Select(g => g.First())
        .OrderBy(p => p.Name, StringComparer.Ordinal);

    /// <summary>Describes the editable surface of <paramref name="o"/>.</summary>
    public static List<object> Describe(object o)
    {
        var result = new List<object>();
        foreach (var p in Props(o.GetType()))
        {
            var t = p.PropertyType;
            if (IsSimple(t))
            {
                object? v;
                try { v = p.GetValue(o); } catch { continue; }
                bool editable = p.SetMethod is { IsPublic: true };
                var u = Nullable.GetUnderlyingType(t) ?? t;
                string kind = u == typeof(bool) ? "bool" : u.IsEnum ? "enum" : u == typeof(string) ? "string"
                            : u == typeof(float) || u == typeof(double) || u == typeof(decimal) ? "float" : "int";
                object? min = null, max = null;
                if (kind == "int")
                {
                    min = Convert.ToString(u.GetField("MinValue")?.GetValue(null), CultureInfo.InvariantCulture);
                    max = Convert.ToString(u.GetField("MaxValue")?.GetValue(null), CultureInfo.InvariantCulture);
                }
                string[]? options = null;
                if (u.IsEnum)
                {
                    var names = Enum.GetNames(u);
                    if (names.Length <= 400) options = names;
                }
                result.Add(new
                {
                    name = p.Name,
                    kind,
                    type = u.Name,
                    value = kind switch
                    {
                        "bool" => (object?)(v is true),
                        "enum" => v?.ToString(),
                        _ => Convert.ToString(v, CultureInfo.InvariantCulture),
                    },
                    editable,
                    min,
                    max,
                    options,
                });
            }
            else if (IsChild(t))
            {
                object? v;
                try { v = p.GetValue(o); } catch { continue; }
                if (v is null) continue;
                result.Add(new { name = p.Name, kind = "object", type = t.Name, value = (object?)null, editable = false, min = (object?)null, max = (object?)null, options = (string[]?)null });
            }
        }
        return result;
    }

    private static object Root(Session s, Params p, out PKM? pk, out SlotRef? r)
    {
        pk = null; r = null;
        var target = p.OptStr("target") ?? "save";
        switch (target)
        {
            case "pkm":
                r = p.Slot();
                pk = s.Get(r.Value).Clone();
                if (pk.Species == 0) throw new EngineException(Tr.T($"Slot vuoto."));
                return pk;
            case "block":
                return Blocks.BlockObject(s.Sav, p.Str("key")) ?? throw new EngineException(Tr.T($"Questo blocco non ha una struttura modificabile."));
            default:
                return s.Sav;
        }
    }

    private static object Walk(object root, JsonArray? path)
    {
        var o = root;
        if (path is null) return o;
        foreach (var n in path)
        {
            var name = n!.GetValue<string>();
            var prop = Props(o.GetType()).FirstOrDefault(x => x.Name == name) ?? throw new EngineException(Tr.T($"Proprietà sconosciuta: {name}"));
            if (!IsChild(prop.PropertyType)) throw new EngineException(Tr.T($"{name} non è una sezione."));
            o = prop.GetValue(o) ?? throw new EngineException(Tr.T($"{name} non è disponibile."));
        }
        return o;
    }

    public static object Inspect(Session s, Params p)
    {
        var root = Root(s, p, out _, out _);
        var o = Walk(root, p.Raw["path"] as JsonArray);
        return new { type = o.GetType().Name, props = Describe(o) };
    }

    public static object Set(Session s, Params p)
    {
        var root = Root(s, p, out var pk, out var r);
        var o = Walk(root, p.Raw["path"] as JsonArray);
        var name = p.Str("prop");
        var prop = Props(o.GetType()).FirstOrDefault(x => x.Name == name) ?? throw new EngineException(Tr.T($"Proprietà sconosciuta: {name}"));
        if (prop.SetMethod is not { IsPublic: true } || !IsSimple(prop.PropertyType))
            throw new EngineException(Tr.T($"{name} non è modificabile."));
        var u = Nullable.GetUnderlyingType(prop.PropertyType) ?? prop.PropertyType;
        var node = p.Raw["value"];
        object value;
        try
        {
            if (u == typeof(bool))
                value = node!.GetValueKind() is System.Text.Json.JsonValueKind.True ||
                        (node.GetValueKind() == System.Text.Json.JsonValueKind.String && node.GetValue<string>() is "true" or "1");
            else
            {
                var text = node is null ? "" : node.GetValueKind() == System.Text.Json.JsonValueKind.String ? node.GetValue<string>() : node.ToJsonString();
                value = u.IsEnum ? Enum.Parse(u, text.Trim(), ignoreCase: true)
                      : u == typeof(string) ? text
                      : Convert.ChangeType(text.Trim(), u, CultureInfo.InvariantCulture);
            }
        }
        catch (Exception e) when (e is not EngineException)
        {
            throw new EngineException(Tr.T($"Valore non valido per {name} ({u.Name})."));
        }

        if (pk is not null && r is { } slot)
        {
            prop.SetValue(o, value);
            if (pk is { } entity && ReferenceEquals(o, entity))
                entity.RefreshChecksum();
            s.Set(slot, pk, label: Tr.T($"Modifica {name}"));
            return new { ok = true, props = Describe(Walk(s.Get(slot), p.Raw["path"] as JsonArray)), detail = Features.Storage.Pokemon(s, slot) };
        }

        s.Snapshot(Tr.T($"Modifica {name}"));
        prop.SetValue(o, value);
        s.Dirty = true;
        return new { ok = true, props = Describe(o) };
    }
}
