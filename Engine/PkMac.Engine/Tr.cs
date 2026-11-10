using System.Globalization;
using System.Text;
using System.Text.Json;

namespace PkMac.Engine;

/// <summary>
/// User-facing engine messages: Italian source text translated with the same table the app uses
/// (key = template with <c>%@</c> placeholders).
/// </summary>
public static class Tr
{
    private static Dictionary<string, string> _table = new();
    public static string Language { get; private set; } = "it";

    /// <summary>Loads the translation table for <paramref name="lang"/> from <paramref name="path"/> (app bundle Lang/xx.json).</summary>
    public static void Set(string lang, string? path)
    {
        Language = lang;
        _table = new();
        if (lang == "it" || path is null || !File.Exists(path)) return;
        try { _table = JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(path)) ?? new(); }
        catch (Exception e) { Program.Log($"lang: {e.Message}"); }
    }

    /// <summary>Exact-match translation of a runtime string (catalog names and similar).</summary>
    public static string S(string s) => _table.TryGetValue(s.Replace("%", "%%"), out var t) ? Fill(t, []) : s;

    public static string T(FormattableString s)
    {
        var fmt = s.Format;
        var args = s.GetArguments();
        var key = new StringBuilder();
        var vals = new List<string>();
        for (int i = 0; i < fmt.Length; i++)
        {
            char c = fmt[i];
            if (c == '{')
            {
                if (i + 1 < fmt.Length && fmt[i + 1] == '{') { key.Append('{'); i++; continue; }
                int end = fmt.IndexOf('}', i);
                var hole = fmt[(i + 1)..end];
                int cut = hole.IndexOfAny([',', ':']);
                int idx = int.Parse(cut < 0 ? hole : hole[..cut], CultureInfo.InvariantCulture);
                var arg = idx < args.Length ? args[idx] : null;
                vals.Add(string.Format(CultureInfo.CurrentCulture, "{0" + (cut < 0 ? "" : hole[cut..]) + "}", arg));
                key.Append("%@");
                i = end;
                continue;
            }
            if (c == '}' && i + 1 < fmt.Length && fmt[i + 1] == '}') { key.Append('}'); i++; continue; }
            if (c == '%') { key.Append("%%"); continue; }
            key.Append(c);
        }
        var template = _table.TryGetValue(key.ToString(), out var t) ? t : key.ToString();
        return Fill(template, vals);
    }

    public static string Fill(string template, IReadOnlyList<string> args)
    {
        var sb = new StringBuilder();
        int next = 0;
        for (int i = 0; i < template.Length; i++)
        {
            char c = template[i];
            if (c == '%' && i + 1 < template.Length)
            {
                char d = template[i + 1];
                if (d == '%') { sb.Append('%'); i++; continue; }
                if (d == '@') { sb.Append(next < args.Count ? args[next] : ""); next++; i++; continue; }
                int k = i + 1;
                while (k < template.Length && char.IsDigit(template[k])) k++;
                if (k > i + 1 && k + 1 < template.Length && template[k] == '$' && template[k + 1] == '@')
                {
                    int n = int.Parse(template[(i + 1)..k], CultureInfo.InvariantCulture);
                    sb.Append(n - 1 < args.Count ? args[n - 1] : "");
                    i = k + 1;
                    continue;
                }
            }
            sb.Append(c);
        }
        return sb.ToString();
    }
}
