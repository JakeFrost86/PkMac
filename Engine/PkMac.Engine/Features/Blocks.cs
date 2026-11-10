using System.Globalization;
using System.Text.Json.Nodes;
using PKHeX.Core;

namespace PkMac.Engine.Features;

/// <summary>
/// SCBlock editor for Switch games (SW/SH, BD/SP via blocks where present, PLA, S/V, Z-A): every stored flag,
/// counter and value, with names from PKHeX's accessors. Named object blocks are opened in the <see cref="Inspector"/>.
/// </summary>
public static class Blocks
{
    private static readonly System.Runtime.CompilerServices.ConditionalWeakTable<SaveFile, SCBlockMetadata> Meta = new();

    public static SCBlockMetadata Metadata(SaveFile sav)
    {
        if (sav is not ISCBlockArray arr)
            throw new EngineException(Tr.T($"Questo gioco non usa blocchi di dati."));
        return Meta.GetValue(sav, _ => new SCBlockMetadata(arr.Accessor, [], []));
    }

    private static string TypeLabel(SCBlock b) => b.Type.IsBoolean() ? Tr.T($"Bool") : b.Type.ToString();

    private static string Pretty(string name)
    {
        // "KCurrentBox" -> "Current Box", "MyStatus" -> "My Status"
        var n = name.StartsWith('K') && name.Length > 1 && char.IsUpper(name[1]) ? name[1..] : name;
        var sb = new System.Text.StringBuilder();
        for (int i = 0; i < n.Length; i++)
        {
            if (i > 0 && char.IsUpper(n[i]) && !char.IsUpper(n[i - 1])) sb.Append(' ');
            sb.Append(n[i] == '_' ? ' ' : n[i]);
        }
        return sb.ToString();
    }

    public static object List(Session s, string? query, bool valuesOnly)
    {
        var sav = s.Sav;
        if (sav is not ISCBlockArray arr)
            return new { supported = false, blocks = Array.Empty<object>() };
        var meta = Metadata(sav);
        var q = query?.Trim() ?? "";
        var list = new List<(bool named, string name, object row)>();
        int index = 0;
        foreach (var b in arr.Accessor.BlockInfo)
        {
            var i = index++;
            var name = meta.GetBlockName(b, out var obj);
            bool simple = b.HasValue() || b.Type.IsBoolean();
            if (valuesOnly && !simple && obj is null) continue;
            var key = b.Key.ToString("X8");
            var label = name is null ? key : Pretty(name);
            if (q.Length > 0 && !label.Contains(q, StringComparison.OrdinalIgnoreCase) && !key.Contains(q, StringComparison.OrdinalIgnoreCase))
                continue;
            object? value = null;
            if (b.Type.IsBoolean()) value = b.Type == SCTypeCode.Bool2;
            else if (b.HasValue()) value = Convert.ToString(b.GetValue(), CultureInfo.InvariantCulture);
            list.Add((name is not null, label, new
            {
                key,
                index = i,
                name = label,
                named = name is not null,
                type = TypeLabel(b),
                size = b.Data.Length,
                value,
                editable = simple,
                hasObject = obj is not null && IsInspectable(obj),
            }));
        }
        // Named first, then by name.
        var sorted = list.OrderBy(x => !x.named).ThenBy(x => x.name, StringComparer.OrdinalIgnoreCase).Select(x => x.row).ToArray();
        return new { supported = true, total = arr.Accessor.BlockInfo.Count, blocks = sorted };
    }

    private static bool IsInspectable(object o) => Inspector.Describe(o).Count > 0;

    public static SCBlock Find(SaveFile sav, string key)
    {
        if (sav is not ISCBlockArray arr)
            throw new EngineException(Tr.T($"Questo gioco non usa blocchi di dati."));
        if (!uint.TryParse(key, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var k))
            throw new EngineException(Tr.T($"Chiave del blocco non valida."));
        return arr.Accessor.BlockInfo.FirstOrDefault(b => b.Key == k) ?? throw new EngineException(Tr.T($"Blocco non trovato."));
    }

    public static object? BlockObject(SaveFile sav, string key)
    {
        var b = Find(sav, key);
        Metadata(sav).GetBlockName(b, out var obj);
        return obj;
    }

    public static object Set(Session s, string key, JsonNode value)
    {
        var sav = s.Sav;
        var b = Find(sav, key);
        if (b.Type.IsBoolean())
        {
            bool v = value.GetValueKind() == System.Text.Json.JsonValueKind.True ||
                     (value.GetValueKind() == System.Text.Json.JsonValueKind.String && value.GetValue<string>() is "1" or "true");
            b.ChangeBooleanType(v ? SCTypeCode.Bool2 : SCTypeCode.Bool1);
        }
        else if (b.HasValue())
        {
            var text = value.GetValueKind() == System.Text.Json.JsonValueKind.String ? value.GetValue<string>() : value.ToJsonString();
            var t = b.Type.GetType();
            object parsed;
            try { parsed = Convert.ChangeType(text.Trim(), t, CultureInfo.InvariantCulture); }
            catch { throw new EngineException(Tr.T($"Valore non valido per un blocco {t.Name}.")); }
            b.SetValue(parsed);
        }
        else
        {
            throw new EngineException(Tr.T($"Questo blocco contiene dati strutturati: aprilo nell'ispettore."));
        }
        s.Dirty = true;
        object? now = b.Type.IsBoolean() ? b.Type == SCTypeCode.Bool2 : Convert.ToString(b.GetValue(), CultureInfo.InvariantCulture);
        return new { key, value = now };
    }
}
