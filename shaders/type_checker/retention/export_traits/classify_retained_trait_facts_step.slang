// Export step classify_retained_trait_facts: one lane per HIR row index, covering the predicate and
// method-core tables (both have at most one entry per HIR row). Writes the
// trait-fact scan flags (retained_trait_fact_export.slang): each exported generic-bound
// predicate marks its bound row (x) and counts at its owner (z); each method
// of a trait impl marks its row (y) and counts at its impl (w). A
// generic-bound predicate without an exportable owner is an invariant
// failure: its fact would otherwise be silently omitted.
import shared.syntax.hir_records;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export_traits.retained_trait_fact_export;
import type_checker.retention.export_types.retained_export_type_rows;

// The trait-fact scan's own counters (the 08 kernels read RT_X_SCAN_N and
// write their totals here when bound for this scan).

void publish_use_environment(uint row)
{
    uint slot = rt_x_use_env_slot[row];
    if (slot == 0u) return;
    uint use_index = rt_x_counts[RT_X_BASE + RT_A_USES] + rt_x_scan[row].y;
    uint term = rt_x_use_envs[slot - 1u].term;
    rt_uses[use_index * RT_USE_WORDS + 1u].x = term;
    if (term == RT_UNKNOWN)
        stat_add_at(body_function(row), row, RT_STAT_UNTRANSLATED, 1u);
}

bool same_trait_key(uint4 other, RtTermKey key, BoundArgs args, uint arity)
{
    if (other.x != key.head || other.y != key.words.x || other.z != key.words.y) return false;
    BoundArgs prior;
    prior.start = other.w;
    for (uint i = 0u; i < arity; i++)
        if (prior.arg(i) != args.arg(i)) return false;
    return true;
}

void stage_trait_term(uint node, uint arity, uint trait_decl)
{
    rt_x_trait_key[node].y = trait_decl;
    if (trait_decl == RT_INVALID || arity > MAX_TRAIT_ARGUMENTS) return;
    HirRange range = compact_type_arg_ranges[node];
    uint total = min(compact_type_arg_count[0u], hir_count());
    if (range.count != arity ||
        (arity != 0u && (range.start > total || arity > total - range.start))) return;
    uint mask = 0u;
    for (uint i = 0u; i < arity; i++)
    {
        HirTypeArg argument = compact_type_args[range.start + i];
        if (argument.owner != node || argument.ordinal != i) return;
        if (constant_operand(type_row_term(argument.value))) mask |= 1u << i;
    }
    RtTermKey key = rt_key_begin(RT_KIND_NAMED, arity, arity - countbits(mask), uint3(trait_decl, mask, 0u));
    BoundArgs args;
    args.start = range.start;
    for (uint i = 0u; i < arity; i++) rt_key_fold(key, args.arg(i));
    if (!key.ok) return;
    rt_x_trait_key[node] = uint4(key.head, trait_decl, mask, range.start);

    uint slots; uint stride;
    rt_x_trait_terms.GetDimensions(slots, stride);
    uint slot = rt_probe_start(key.hash.x, slots);
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint prior = rt_x_trait_terms[slot].x;
        if (prior == 0u)
        {
            DeviceMemoryBarrier();
            InterlockedCompareExchange(rt_x_trait_terms[slot].x, 0u, node + 1u, prior);
            if (prior == 0u)
            {
                rt_x_trait_terms[slot].y = rt_intern_term(key, args);
                rt_x_trait_term_slot[node] = slot + 1u;
                return;
            }
        }
        DeviceMemoryBarrier();
        if (same_trait_key(rt_x_trait_key[prior - 1u], key, args, arity))
        {
            rt_x_trait_term_slot[node] = slot + 1u;
            return;
        }
        slot = (slot + 1u) & (slots - 1u);
    }
    rt_invariant(RT_INV_TERM);
}

void stage_impl_trait(uint row)
{
    if (!trait_impl_row(row)) return;
    uint entry = rt_x_row[row].y;
    if (entry == RT_INVALID || rt_dir[entry * RT_DIR_WORDS + 1u].z == RT_INVALID) return;
    uint node = compact_hir_payload[row].b;
    if (!accepted_trait_impl(row, node)) return;
    uint decl = trait_reference_decl(predicate_fact(F_REFERENCE, row));
    stage_trait_term(node, predicate_fact(F_ARG_COUNT, row), decl);
}

public void classify_retained_trait_facts(uint lane)
{
    if (lane < hir_count())
    {
        publish_use_environment(lane);
        stage_impl_trait(lane);
    }
    if (lane < predicate_rows())
    {
        HirPredicate predicate = compact_predicates[lane];
        if ((predicate.metadata & 0xffu) == PREDICATE_GENERIC_BOUND)
        {
            uint owner = predicate_owner_row(predicate);
            if (owner == 0xffffffffu) rt_invariant(RT_INV_TRAIT_FACT);
            else
            {
                InterlockedOr(rt_x_tflags[predicate.bound].x, 1u);
                InterlockedAdd(rt_x_tflags[owner].z, 1u);
                uint bound = predicate.bound;
                if (predicate_fact(F_STATUS, bound) == PREDICATE_STATUS_OK &&
                    predicate_fact(F_OWNER, bound) == owner)
                {
                    uint decl = trait_reference_decl(predicate_fact(F_REFERENCE, bound));
                    stage_trait_term(bound, predicate_fact(F_ARG_COUNT, bound), decl);
                }
            }
        }
    }
    if (lane < method_rows())
    {
        uint impl = binding_impl_row(lane);
        if (impl != 0xffffffffu)
        {
            InterlockedOr(rt_x_tflags[compact_method_cores[lane].node].y, 1u);
            InterlockedAdd(rt_x_tflags[impl].w, 1u);
        }
    }
}
