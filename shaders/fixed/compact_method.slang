// Lookup helpers for the compact method family.
//
// Canonical method rows are scattered in raw-source order, which is also the
// dense-HIR order. The canonical validator enforces strict ordering by
// `node`, so consumers can recover a family row without a HIR-capacity inverse
// table or a backend-visible payload overload.

public struct CompactMethodCore
{
    public uint node;
    public uint owner;
    public uint impl_node;
    public uint name_token;
};

public uint compact_method_row_for_hir(
    StructuredBuffer<CompactMethodCore> methods,
    uint method_count,
    uint hir)
{
    uint lo = 0u;
    uint hi = method_count;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (methods[mid].node < hir)
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo < method_count && methods[lo].node == hir ? lo : 0xffffffffu;
}
