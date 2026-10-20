// Instance table keys (instance_table.slang): one lane per closure
// instance. An exported instance of a local function row enters the table
// with its key (function row, ct_shash of its tagged environment) and the
// row count of the function's subtree; every other instance gets an INVALID
// key. Lanes count the entries and their rows.
import hir_records;
import type_checker.canonical.canonical_api;
import type_checker.closure.instance_closure;
import type_checker.closure.instance_table;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirLinks> compact_hir_links;

static const uint INVALID = 0xffffffffu;
static const uint HIR_FN = 3u;
static const uint EXPORT_DONE = 1u;

uint hir_count()
{
    uint rows; uint stride;
    compact_hir_core.GetDimensions(rows, stride);
    return min(compact_hir_count[0u], rows);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint index = dtid.x + dtid.y * 16776960u;
    if (index >= it_instances()) return;
    uint4 instance = instance_closure_instances[2u * index];
    uint4 extra = instance_closure_instances[2u * index + 1u];
    uint function = instance.y;
    uint4 key = uint4(INVALID, 0u, 0u, 0u);
    if (extra.z == EXPORT_DONE && function < hir_count() && compact_hir_core[function].kind == HIR_FN)
    {
        uint end = compact_hir_links[function].subtree_end;
        if (end > function && end <= hir_count())
        {
            uint2 hash = ct_shash(instance.x);
            key = uint4(function, hash.x, hash.y, end - function);
        }
    }
    instance_table_keys[index] = key;
    if (key.x == INVALID) return;
    uint ignored;
    InterlockedAdd(instance_table_counts[IT_COUNT_ENTRIES], 1u, ignored);
    uint before;
    InterlockedAdd(instance_table_counts[IT_COUNT_ROWS], key.w, before);
    if (before > it_row_capacity() || key.w > it_row_capacity() - before) it_flag(IT_FLAG_ROWS);
}
