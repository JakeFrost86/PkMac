using System.Text.Json.Nodes;

namespace PkMac.Engine;

/// <summary>Typed access to the "params" object of a request.</summary>
public sealed class Params(JsonObject obj)
{
    public JsonObject Raw => obj;

    public bool Has(string key) => obj.ContainsKey(key) && obj[key] is not null;

    public string Str(string key) => Opt<string>(key) ?? throw new EngineException(Tr.T($"Parametro mancante: {key}"));
    public string? OptStr(string key) => Opt<string>(key);
    public int Int(string key) => Has(key) ? obj[key]!.GetValue<int>() : throw new EngineException(Tr.T($"Parametro mancante: {key}"));
    public int Int(string key, int fallback) => Has(key) ? obj[key]!.GetValue<int>() : fallback;
    public bool Bool(string key, bool fallback = false) => Has(key) ? obj[key]!.GetValue<bool>() : fallback;

    public T? Opt<T>(string key)
    {
        if (!Has(key))
            return default;
        return obj[key]!.GetValue<T>();
    }

    public Params Obj(string key) => obj[key] as JsonObject is { } o ? new Params(o) : throw new EngineException(Tr.T($"Parametro mancante: {key}"));
    public Params? OptObj(string key) => obj[key] as JsonObject is { } o ? new Params(o) : null;

    public int[]? IntArray(string key) => obj[key] is JsonArray a ? a.Select(n => n!.GetValue<int>()).ToArray() : null;

    public SlotRef Slot(string key = "ref") => SlotRef.From(Obj(key));
}

/// <summary>Location of an entity inside the save: a box slot or a party slot.</summary>
public readonly record struct SlotRef(bool Party, int Box, int Slot)
{
    public static SlotRef From(Params p)
    {
        var kind = p.OptStr("kind") ?? "box";
        return kind == "party" ? new SlotRef(true, -1, p.Int("slot")) : new SlotRef(false, p.Int("box"), p.Int("slot"));
    }

    public JsonObject ToJson() => Party
        ? new JsonObject { ["kind"] = "party", ["slot"] = Slot }
        : new JsonObject { ["kind"] = "box", ["box"] = Box, ["slot"] = Slot };
}
