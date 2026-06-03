using System.Buffers;

namespace Athlon.Agent.Infrastructure;

public static class WorkspacePathFilter
{
    private static readonly SearchValues<char> DirectorySeparators =
        SearchValues.Create([Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar]);

    /// <summary>True when any path segment matches a configured ignore directory name.</summary>
    public static bool ShouldIgnorePath(string fullPath, IReadOnlyList<string> directoryNames)
    {
        ReadOnlySpan<char> span = fullPath.AsSpan();
        while (span.Length > 0)
        {
            var separatorIndex = span.IndexOfAny(DirectorySeparators);
            ReadOnlySpan<char> segment;
            if (separatorIndex < 0)
            {
                segment = span;
                span = ReadOnlySpan<char>.Empty;
            }
            else
            {
                segment = span[..separatorIndex];
                span = span[(separatorIndex + 1)..];
            }

            if (ShouldIgnoreEntryName(segment, directoryNames))
            {
                return true;
            }
        }

        return false;
    }

    public static bool ShouldIgnoreEntryName(string name, IReadOnlyList<string> directoryNames) =>
        directoryNames.Any(pattern => string.Equals(pattern, name, StringComparison.OrdinalIgnoreCase));

    private static bool ShouldIgnoreEntryName(ReadOnlySpan<char> segmentName, IReadOnlyList<string> directoryNames)
    {
        foreach (var pattern in directoryNames)
        {
            if (segmentName.Equals(pattern.AsSpan(), StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }
}
