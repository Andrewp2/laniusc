import hir_records;

// Variant pattern wrappers can own their path directly or through the first
// child. Both page-local projection and retained match binding use this HIR
// relation, so they resolve the same declaration identity.
public uint checked_pattern_path(uint pattern, uint hir_count, uint path_count,
    StructuredBuffer<HirLinks> links, StructuredBuffer<uint> path_by_hir)
{
    if (pattern >= hir_count) return 0xffffffffu;
    uint path = path_by_hir[pattern];
    if (path < path_count) return path;
    uint child = links[pattern].first_child;
    path = child < hir_count ? path_by_hir[child] : 0xffffffffu;
    return path < path_count ? path : 0xffffffffu;
}
