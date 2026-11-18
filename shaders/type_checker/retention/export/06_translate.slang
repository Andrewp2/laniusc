// Export step 6: one lane per canonical record of the current height.
// Translates the record into a store term: children through the term and
// parameter maps (all of lower height, so already translated), a NAMED
// declaration triple into a DeclId, and an ENV owner (a callee HIR row + 1)
// into the callee's DeclId. Writes the job's canonical-ID -> TermId map.
// A record that cannot translate maps to RT_UNKNOWN; exporting a reference
// to it later is an invariant failure, not a silently unbound term.
import shared.syntax.hir_records;
import type_checker.canonicalization.canonical_api;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.common;

uint fail(uint record)
{
    rt_x_term_map[record] = RT_UNKNOWN;
    InterlockedAdd(rt_x_counts[RT_X_UNTRANSLATED], 1u);
    return RT_UNKNOWN;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = export_lane(dtid);
    uint height = rt_x_counts[RT_X_ROUND];
    if (height >= RT_X_HEIGHTS) return;
    uint count = rt_x_counts[RT_X_BUCKET + height];
    if (lane >= count) return;
    uint record = rt_x_order[rt_x_counts[RT_X_BUCKET_BASE + height] - count + lane];

    uint4 head = ct_head[record];
    uint kind = head.x & 0xffu;
    uint arity = (head.x >> 8u) & 0xffu;
    uint type_slots = head.x >> 16u;
    uint3 words = head.yzw;
    if (kind == CT_KIND_NAMED)
    {
        uint decl = rt_intern_decl(uint4(words.x, words.y, RT_NS_NOMINAL, words.z));
        if (decl == RT_INVALID) { fail(record); return; }
        words = uint3(decl, ct_extra[record].y, 0u);
    }
    else if (kind == CT_KIND_ENV)
    {
        uint owner = 0u;
        if (words.x != 0u)
        {
            owner = intern_row_decl(words.x - 1u);
            if (owner == RT_INVALID) { fail(record); return; }
        }
        words.x = owner;
    }
    else if (kind != CT_KIND_ARRAY && kind != CT_KIND_SLICE && kind != CT_KIND_REF &&
        kind != CC_KIND_VALUE && kind != CC_KIND_CAST && kind != CC_KIND_COUNT)
    {
        fail(record);
        return;
    }
    RtTermKey key = rt_key_begin(kind, arity, type_slots, words);
    uint base = ct_meta[record].x;
    for (uint index = 0u; index < arity; index++)
    {
        uint child = translate_ref(ct_args[base + index]);
        rt_x_args[base + index] = child;
        if (!rt_is_resolved(child)) { fail(record); return; }
        rt_key_fold(key, child);
    }
    RtJobArgs args;
    args.base = base;
    uint term = rt_intern_term(key, args);
    if (!rt_is_term(term)) { fail(record); return; }
    rt_x_term_map[record] = term;
}
