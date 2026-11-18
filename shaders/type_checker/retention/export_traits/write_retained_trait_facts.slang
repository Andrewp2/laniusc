// Export step write_retained_trait_facts: one lane per HIR row index, in three roles.
//
//   Directory: each staged declaration row writes its rt_dir_trait column
//   (first predicate record, predicate count, first binding record, binding
//   count). A trait impl also checks its accepted header (status, trait
//   root, trait DeclId against its retained trait term) and that it binds
//   exactly its trait's required members.
//   Predicate: each exported generic-bound predicate writes its record at
//   its owner's block: (owner, ordinal, subject term, trait term) and its
//   trait DeclId and bound source span. The ordinal is the bound row's rank
//   among the owner's predicates in HIR (source) order.
//   Binding: each method of a trait impl writes its record at its impl's
//   block: the required member's DeclId (in the trait's defining unit), the
//   method's DeclId (its native callable identity), the receiver mode.
//
// Every fact comes from the predicate and method validators' accepted
// columns (retained_trait_fact_export.slang). A fact the producers did not accept, an
// identity that disagrees between two producers, or an owner block that is
// not contiguous raises an invariant and marks the owner's entry
// incomplete through its statistics (step 15). Trait terms come from the
// keys claimed in classify_retained_trait_facts.
import shared.syntax.hir_records;
import type_checker.canonicalization.canonical_api;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.export_lane_index;
import type_checker.retention.export_types.retained_export_type_rows;
import type_checker.retention.export_rows.retained_body_source_tables;
import type_checker.retention.export_traits.retained_trait_fact_export;

void fail(uint row, uint code)
{
    rt_invariant(code);
    stat_add(row, RT_STAT_UNTRANSLATED, 1u);
}

uint trait_base() { return rt_x_counts[RT_X_BASE + RT_A_TRAITS]; }

void write_record(uint record, uint4 t0, uint4 t1)
{
    rt_traits[record * RT_TRAIT_WORDS + 0u] = t0;
    rt_traits[record * RT_TRAIT_WORDS + 1u] = t1;
}

void directory_lane(uint row)
{
    uint entry = rt_x_row[row].y;
    if (entry == RT_INVALID) return;
    uint base = trait_base();
    uint4 scan = tscan_at(row);
    uint4 own = rt_x_tflags[row];
    uint bindings = rt_x_counts[RT_X_TRAIT_TOTAL + 2u];
    rt_dir_trait[entry] = uint4(base + scan.z, own.z, base + bindings + scan.w, own.w);
    if (!trait_impl_row(row))
    {
        // An impl naming a trait row that is not a trait impl would keep
        // its RT_UNKNOWN trait term (step 10) without a check.
        if (compact_hir_core[row].kind == HIR_IMPL && valid_row(compact_hir_payload[row].b)) fail(row, RT_INV_TRAIT_FACT);
        return;
    }

    // The checker resolves its trait reference from this canonical row:
    // 00b copies payload.b and direct_type_expr_child reads that copy.
    // Comparing those copies is not an independent identity check.
    HirPayload payload = compact_hir_payload[row];
    if (!accepted_trait_impl(row, payload.b))
    {
        fail(row, RT_INV_TRAIT_FACT);
        return;
    }
    // The impl head's trait term (its signature's second word).
    uint reference = predicate_fact(F_REFERENCE, row);
    uint trait_decl = exported_trait_decl(payload.b);
    uint sig = rt_dir[entry * RT_DIR_WORDS + 1u].z;
    if (trait_decl == RT_INVALID || sig == RT_INVALID)
    {
        fail(row, RT_INV_TRAIT_IDENTITY);
        return;
    }
    uint term = exported_trait_term(payload.b);
    rt_sigs[sig + 1u] = term;
    if (term == RT_UNKNOWN)
    {
        fail(row, RT_INV_TRAIT_FACT);
        return;
    }
    if (!owned_by(term, rt_x_row[row].x, 0u))
    {
        stat_add(row, RT_STAT_OWNERSHIP, 1u);
        rt_invariant(RT_INV_OWNERSHIP);
    }
    // The validators reject a missing, extra or duplicate member, so an
    // accepted impl binds each required member once.
    uint required = trait_reference_required_count(reference);
    if (required != own.w || predicate_fact(F_CONTRACT_COUNT, row) != own.w) fail(row, RT_INV_TRAIT_FACT);
}

void predicate_lane(uint index)
{
    HirPredicate predicate = compact_predicates[index];
    uint owner = predicate_owner_row(predicate);
    if (owner == 0xffffffffu) return; // reported by step 14b
    uint bound = predicate.bound;
    uint base = trait_base();
    uint count = rt_x_tflags[owner].z;
    uint rank = tscan_at(bound).x - tscan_at(owner).x;
    bool inside = bound > owner && bound < compact_hir_links[owner].subtree_end;
    if (!inside || rank >= count)
    {
        // A nested owner's predicate precedes this one inside the owner:
        // the block would not be the owner's facts in source order.
        fail(owner, RT_INV_TRAIT_ORDER);
        return;
    }
    uint record = base + tscan_at(owner).z + rank;
    uint entry = rt_x_row[owner].y;
    uint decl = rt_x_row[owner].x;
    uint parent = rt_dir[entry * RT_DIR_WORDS].z;

    bool accepted = predicate_fact(F_STATUS, bound) == PREDICATE_STATUS_OK &&
        predicate_fact(F_OWNER, bound) == owner;
    uint trait_decl = accepted ? exported_trait_decl(bound) : RT_INVALID;

    // Subject: a type parameter by its declaration token (exact, so a
    // shadowing method parameter is not its impl's), or a scalar's code.
    uint subject = RT_UNKNOWN;
    uint token = predicate_fact(F_SUBJECT, bound);
    if (token != 0xffffffffu && (token & SUBJECT_SCALAR_BIT) != 0u)
    {
        uint code = token & ~SUBJECT_SCALAR_BIT;
        if (code >= 1u && code < RT_FIRST_TERM) subject = code;
    }
    else if (token != 0xffffffffu)
    {
        uint param = param_map_find(token);
        if (param != RT_INVALID && rt_param_key[param].y == RT_DOMAIN_TYPE) subject = rt_param_leaf(param);
    }

    uint applied = accepted ? exported_trait_term(bound) : RT_UNKNOWN;
    bool subject_ok = rt_is_term(subject) || rt_is_param_leaf(subject);
    bool complete = accepted && subject_ok && applied != RT_UNKNOWN;
    if (!complete) fail(owner, RT_INV_TRAIT_FACT);
    else if (!owned_by(subject, decl, parent) || !owned_by(applied, decl, parent))
    {
        stat_add(owner, RT_STAT_OWNERSHIP, 1u);
        rt_invariant(RT_INV_OWNERSHIP);
    }
    HirCore core = compact_hir_core[bound];
    uint file = compact_hir_links[bound].file_id;
    // Use the accepted trait-name anchor. A bound's canonical token_end
    // can include the delimiter after it; that delimiter is not an error
    // location. Arguments are carried by the term, not this name span.
    uint last_token = predicate_fact(F_BOUND_TOKEN, bound);
    bool valid_span = last_token != RT_INVALID && last_token >= core.token_start &&
        last_token < core.token_end && last_token < job_token_rows();
    if (!valid_span) fail(owner, RT_INV_TRAIT_FACT);
    uint2 span = valid_span ? token_bytes(core.token_start, last_token + 1u, file)
        : uint2(RT_INVALID, 0u);
    write_record(record,
        uint4(decl, RT_TRAIT_PREDICATE | (rank << 8u), subject, applied),
        uint4(trait_decl, file, span.x, span.y));
}

void binding_lane(uint index)
{
    uint impl = binding_impl_row(index);
    if (impl == 0xffffffffu) return;
    HirMethodCore method = compact_method_cores[index];
    uint node = method.node;
    uint base = trait_base();
    uint count = rt_x_tflags[impl].w;
    uint rank = tscan_at(node).y - tscan_at(impl).y;
    bool inside = node > impl && node < compact_hir_links[impl].subtree_end;
    if (!inside || rank >= count || rank > 0xffffu)
    {
        fail(impl, RT_INV_TRAIT_ORDER);
        return;
    }
    uint record = base + rt_x_counts[RT_X_TRAIT_TOTAL + 2u] + tscan_at(impl).w + rank;
    uint impl_decl = rt_x_row[impl].x;
    uint method_decl = rt_x_row[node].x;
    uint reference = predicate_fact(F_REFERENCE, impl);
    uint trait_decl = trait_reference_decl(reference);
    uint2 unit = trait_reference_unit(reference);
    uint receiver = compact_method_signatures[index].receiver_mode;
    uint symbol = predicate_fact(F_REQUIRED_SYMBOL, node);
    uint native = predicate_fact(F_NATIVE_SYMBOL, node);

    bool accepted = method.owner == impl && predicate_fact(F_METHOD_STATUS, node) == PREDICATE_STATUS_OK &&
        symbol != 0xffffffffu && (symbol & 0xc0000000u) == 0x80000000u && receiver <= 3u &&
        trait_decl != RT_INVALID && method_decl != RT_INVALID;
    uint required = RT_INVALID;
    if (accepted) required = rt_intern_decl(uint4(unit.x, unit.y, RT_NS_CALLABLE, symbol));
    // The method's DeclId is its native callable identity: the producer's
    // native symbol must be the key's local word.
    bool identical = accepted && required != RT_INVALID && rt_decl_key[method_decl].z == RT_NS_CALLABLE &&
        rt_decl_key[method_decl].w == native;
    // A local trait's required member is a row of that trait in this job.
    uint trait_row = trait_reference_row(reference);
    if (identical && trait_row != 0xffffffffu)
    {
        uint member = symbol & 0x7fffffffu;
        identical = valid_row(member) && container_of(member) == trait_row && rt_x_row[member].x == required;
    }
    if (!accepted) fail(impl, RT_INV_TRAIT_FACT);
    else if (!identical) fail(impl, RT_INV_TRAIT_IDENTITY);
    uint file = compact_hir_links[node].file_id;
    uint2 span = token_bytes(method.name_token, method.name_token + 1u, file);
    write_record(record,
        uint4(impl_decl, RT_TRAIT_BINDING | (min(receiver, 0xffu) << 8u) | (rank << 16u),
            accepted ? required : RT_INVALID, method_decl),
        uint4(trait_decl, symbol, file, span.x));
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = export_lane(dtid);
    if (trait_base() == RT_INVALID) return;
    if (lane < hir_count() && rt_x_flags[lane].z != 0u) directory_lane(lane);
    if (lane < predicate_rows()) predicate_lane(lane);
    if (lane < method_rows()) binding_lane(lane);
}
