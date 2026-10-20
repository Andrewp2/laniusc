// Realized expression types of the instance table's virtual rows
// (instance_table.slang). One lane per virtual row: its template row's
// expression reference, substituted under the entry's tagged environment
// and realized as checked rows. A closed reference is kept as it is. A row
// whose realization meets a row another lane is realizing stays pending for
// the next dispatch (06_table_rows); the final dispatch (06a) fails it
// instead. Included by both entry files.
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_subst;
import type_checker.substitution.source_slots;
import type_checker.substitution.ct_rows;
import type_checker.substitution.ct_realize;
import type_checker.closure.instance_closure;
import type_checker.closure.instance_table;

StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;

static const uint INVALID = 0xffffffffu;
// Failure codes beside ct_realize's (CT_REALIZE_*).
static const uint ROW_FAILED_REFERENCE = 0x100u;
static const uint ROW_FAILED_SUBSTITUTION = 0x200u;

// The entry holding virtual row `row`: the last entry whose base is at or
// below it. Bases increase with the entry index.
uint it_entry_of_row(uint row, uint entries)
{
    uint lo = 0u;
    uint hi = entries;
    while (hi - lo > 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        if (instance_table[2u * mid].w <= row) lo = mid;
        else hi = mid;
    }
    return lo;
}

// The expression reference of a template row. Every template is a local
// body today (source IT_SOURCE_LOCAL: this job's HIR); a dependency's
// bodies (D_PLAN D7c) will be a second source read here.
uint2 template_expr_ref(uint source, uint template_row)
{
    if (source != IT_SOURCE_LOCAL) return uint2(INVALID, 0u);
    return uint2(semantic_expr_ref_tag_by_hir[template_row], semantic_expr_ref_payload_by_hir[template_row]);
}

void fail_row(uint row, uint failure)
{
    instance_row_refs[row] = uint2(IT_ROW_FAILED, failure);
    uint ignored;
    InterlockedAdd(instance_table_counts[IT_COUNT_FAILED], 1u, ignored);
}

void realize_row(uint row, bool final_dispatch)
{
    uint rows = instance_table_counts[IT_COUNT_FLAGS] != 0u ? 0u
        : min(instance_table_counts[IT_COUNT_ROWS], it_row_capacity());
    if (row >= rows || instance_row_refs[row].x != 0u) return;
    uint index = it_entry_of_row(row, instance_table_counts[IT_COUNT_ENTRIES]);
    uint4 entry = instance_table[2u * index];
    uint template_row = entry.x + (row - entry.w);
    uint2 template_ref = template_expr_ref(instance_table[2u * index + 1u].z, template_row);
    uint tag = template_ref.x;
    uint payload = template_ref.y;
    if (tag == INVALID)
    {
        fail_row(row, ROW_FAILED_REFERENCE);
        return;
    }
    uint reference = ct_ref(tag, payload);
    // A row without a type, or with a closed one, reads as the template's.
    if (reference == CT_UNKNOWN || ct_closed(reference))
    {
        instance_row_refs[row] = uint2(tag + 1u, payload);
        return;
    }
    CtSpare spare = ct_spare_none();
    uint bound = ct_subst(SourceSlots(), entry.z, reference, true, spare);
    if (!ct_is_resolved(bound))
    {
        fail_row(row, ROW_FAILED_SUBSTITUTION);
        return;
    }
    uint failure;
    uint2 operand = ct_realize(bound, failure);
    if (failure == CT_REALIZE_BUSY && !final_dispatch) return;
    if (failure != 0u)
    {
        fail_row(row, failure);
        return;
    }
    instance_row_refs[row] = uint2(operand.x + 1u, operand.y);
}
