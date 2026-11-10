using System.Collections;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace PkMac.Engine;

/// <summary>
/// Turns the engine's results (anonymous objects, records, arrays, dictionaries, PKHeX values) into JSON
/// by walking their public properties. Same output as System.Text.Json with <see cref="Program.Json"/>
/// (camelCase names, nulls omitted, enums as numbers), but without generic serializers built at run time,
/// so it also works when the engine is compiled ahead of time (NativeAOT) for iOS.
/// </summary>
public static class JsonOut
{
    private static readonly JsonNamingPolicy Naming = JsonNamingPolicy.CamelCase;
    private static readonly System.Collections.Concurrent.ConcurrentDictionary<Type, (string Name, PropertyInfo Prop)[]> Props = new();

    public static JsonNode? ToNode(object? value) => Convert(value, 0);

    private static JsonNode? Convert(object? value, int depth)
    {
        if (depth > 64)
            throw new InvalidOperationException("JSON troppo annidato.");
        switch (value)
        {
            case null: return null;
            case JsonNode n: return n.Parent is null ? n : n.DeepClone();
            case string s: return JsonValue.Create(s);
            case bool b: return JsonValue.Create(b);
            case char c: return JsonValue.Create(c.ToString());
            case int i: return JsonValue.Create(i);
            case uint u: return JsonValue.Create(u);
            case long l: return JsonValue.Create(l);
            case ulong ul: return JsonValue.Create(ul);
            case short sh: return JsonValue.Create(sh);
            case ushort us: return JsonValue.Create(us);
            case byte by: return JsonValue.Create(by);
            case sbyte sb: return JsonValue.Create(sb);
            case double d: return JsonValue.Create(d);
            case float f: return JsonValue.Create(f);
            case decimal m: return JsonValue.Create(m);
            case DateTime dt: return JsonValue.Create(dt);
            case DateTimeOffset dto: return JsonValue.Create(dto);
            case DateOnly date: return JsonValue.Create(date.ToString("yyyy-MM-dd"));
            case Guid g: return JsonValue.Create(g);
            case Enum e: return JsonValue.Create(System.Convert.ToInt64(e));
            case byte[] bytes: return JsonValue.Create(System.Convert.ToBase64String(bytes));
            case IDictionary dict:
            {
                var o = new JsonObject();
                foreach (DictionaryEntry kv in dict)
                    o[kv.Key.ToString() ?? ""] = Convert(kv.Value, depth + 1);
                return o;
            }
            case IEnumerable list:
            {
                var a = new JsonArray();
                foreach (var item in list)
                    a.Add(Convert(item, depth + 1));
                return a;
            }
        }

        var obj = new JsonObject();
        foreach (var (name, prop) in Props.GetOrAdd(value.GetType(), Describe))
        {
            var v = prop.GetValue(value);
            if (v is null) continue;
            obj[name] = Convert(v, depth + 1);
        }
        return obj;
    }

    private static (string, PropertyInfo)[] Describe(Type t) =>
        t.GetProperties(BindingFlags.Public | BindingFlags.Instance)
            .Where(p => p.CanRead && p.GetIndexParameters().Length == 0 && p.GetCustomAttribute<JsonIgnoreAttribute>() is null)
            .Select(p => (p.GetCustomAttribute<JsonPropertyNameAttribute>()?.Name ?? Naming.ConvertName(p.Name), p))
            .ToArray();
}
