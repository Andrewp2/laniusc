import type_checker.constant_atoms_identity;
// Included by predicate collectors and validators. Syntax supplies ordered HIR
// roots; checked references supply type identity. Diagnostic token caches are
// never used as semantic keys.
import type_checker.scoped_type_hash;
import type_checker.scoped_type_equality;
import type_checker.scoped_type_stackless;
import type_checker.checked_type_graph;
import type_checker.concrete_type_closure;

uint predicate_argument_node(uint root, uint ordinal)
{
    if (!valid_node(root)) return INVALID;
    uint total = min(compact_type_arg_count[0u], gParams.n_hir_nodes);
    HirRange range = compact_type_arg_ranges[root];
    if (range.start > total || range.count > total - range.start || ordinal >= range.count)
        return INVALID;
    return compact_type_args[range.start + ordinal].value;
}

uint2 predicate_type_reference(uint node)
{
    uint token = valid_node(node) ? compact_hir_core[node].token_start : INVALID;
    return valid_token(token)
        ? uint2(type_expr_ref_tag[token], type_expr_ref_payload[token])
        : uint2(0u, INVALID);
}

bool predicate_closed_type(uint2 ref)
{
    if (ref.x == 1u) return ref.y != 0u && ref.y != INVALID;
    return ref.x == 3u && concrete_instance_is_closed<ScopedCheckedTypeGraph, CheckedSourceConstantGraph, CheckedSourceConstantEnvironment>(ref.y, checked_type_capacity(), gParams.n_tokens);
}

bool predicate_key_hash<Graph : IScopedTypeGraph>(uint2 subject, uint root,
    uint count, uint context, out uint hash)
{
    hash = 0u;
    if (count > 32u) return false;
    // The subject, then the ordered arguments, through one walk site.
    for (uint ordinal = 0u; ordinal <= count; ordinal++)
    {
        uint2 reference = ordinal == 0u ? subject
            : predicate_type_reference(predicate_argument_node(root, ordinal - 1u));
        uint reference_hash;
        if (!scoped_type_ref_hash_stackless<Graph>(reference.x, reference.y, context,
            checked_type_capacity(), gParams.n_tokens, reference_hash)) return false;
        hash = ordinal == 0u ? reference_hash : scoped_type_hash_mix(hash, reference_hash);
    }
    return true;
}

bool predicate_keys_equal<Graph : IScopedTypeGraph>(uint2 left_subject, uint left_root,
    uint left_context, uint2 right_subject, uint right_root, uint right_context, uint count)
{
    if (count > 32u) return false;
    // The subjects, then the ordered arguments, through one walk site.
    for (uint ordinal = 0u; ordinal <= count; ordinal++)
    {
        uint2 left = ordinal == 0u ? left_subject
            : predicate_type_reference(predicate_argument_node(left_root, ordinal - 1u));
        uint2 right = ordinal == 0u ? right_subject
            : predicate_type_reference(predicate_argument_node(right_root, ordinal - 1u));
        if (!scoped_type_refs_equal_stackless<Graph>(left.x, left.y, left_context,
            right.x, right.y, right_context, checked_type_capacity(), gParams.n_tokens))
            return false;
    }
    return true;
}
