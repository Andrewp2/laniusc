// Export step 14e: one lane per HIR row. Links each BOUND row of a retained
// body (11_rows.slang: a bound path, a `&Trait` reference and the path
// inside it) to the predicate it spells. The row's r3.y becomes the
// predicate's ordinal in its function's predicate block, so the record is
// rt_traits[rt_dir_trait[entry].x + r3.y] and its t0.y ordinal equals r3.y.
// A consumer needs no source order or span to find it.
//
// The row's predicate root is the nearest row at or above it, inside the
// body, that is the bound node of an exported generic-bound predicate
// (trait-fact scan flag x, step 14b). The root's accepted owner must be the
// body's function, which is also the owner whose block step 14d filled. A
// bound row with no such root, or a root owned elsewhere, would leave a
// trait reference without its fact: it raises RT_INV_TRAIT_FACT and marks
// the function incomplete (step 15).
import hir_records;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.row_classes;
import type_checker.retention.export.common;
import type_checker.retention.export.trait_common;

static const uint MAX_BOUND_DEPTH = 64u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = export_lane(dtid);
    if (row >= hir_count() || rt_x_flags[row].x == 0u) return;
    uint rows_base = rt_x_counts[RT_X_BASE + RT_A_SEG_ROWS];
    if (rows_base == RT_INVALID || rt_x_counts[RT_X_BASE + RT_A_TRAITS] == RT_INVALID) return;
    uint function = body_function(row);
    if (function == 0xffffffffu || row == function) return;
    uint index = rows_base + rt_x_scan[row].x;
    uint4 r3 = rt_seg_rows[index * RT_ROW_WORDS + 3u];
    if (r3.z != RT_ROLE_BOUND) return;

    uint root = row;
    bool found = false;
    for (uint depth = 0u; depth < MAX_BOUND_DEPTH && root > function; depth++)
    {
        if (rt_x_tflags[root].x != 0u) { found = true; break; }
        root = compact_hir_core[root].parent;
        if (!valid_row(root)) break;
    }
    uint rank = found ? tscan_at(root).x - tscan_at(function).x : RT_NONE;
    if (!found || predicate_fact(F_OWNER, root) != function || rank >= rt_x_tflags[function].z)
    {
        rt_invariant(RT_INV_TRAIT_FACT);
        stat_add(function, RT_STAT_UNTRANSLATED, 1u);
        return;
    }
    r3.y = rank;
    rt_seg_rows[index * RT_ROW_WORDS + 3u] = r3;
}
