// Queue each type the instance table realized as a field-closure root
// (ct_expand.slang). The closure gives its arguments, element types, fields
// and payloads checked rows, so 01c finds their native widths when it runs
// again for the execution rows: a realized Node<i32, i32> reaches its field
// Entry<i32, i32>, which no row of the job named before the table. One lane
// per table row; a lenient root reports only capacity and limit failures.
import hir_records;
import status;
import type_checker.canonical.canonical_api;
import type_checker.checked_type_graph;
import type_checker.substitution.ct_expand;
import type_checker.closure.instance_table;

StructuredBuffer<HirCore> compact_hir_core;
RWStructuredBuffer<uint> status;

static const uint TYPE_REF_INSTANCE = 3u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    ct_expand_begin_run(row, 0u);
    uint rows = instance_table_counts[IT_COUNT_FLAGS] != 0u ? 0u
        : min(instance_table_counts[IT_COUNT_ROWS], it_row_capacity());
    if (row >= rows) return;
    uint2 realized = instance_row_refs[row];
    if (realized.x != TYPE_REF_INSTANCE + 1u || realized.y >= checked_type_capacity()) return;
    uint id = ct_ref(TYPE_REF_INSTANCE, realized.y);
    if (!ct_is_resolved(id) || !ct_closed(id)) return;
    uint index = it_entry_of_row(row, instance_table_counts[IT_COUNT_ENTRIES]);
    uint4 entry = instance_table[2u * index];
    uint token = compact_hir_core[entry.x + (row - entry.w)].token_start;
    if (!ct_expand_push(id, ct_expand_word(token, 0u, true)))
        record_min_token_error(status, token, 6u, 0x474e0001u);
}
