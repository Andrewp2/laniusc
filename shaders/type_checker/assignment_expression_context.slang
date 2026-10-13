// Read the accepted destination type for an assignment's value. The including
// pass supplies declaration, member, and call facts; no RHS fact supplies its
// own expectation. Indexed destinations project the complete element reference.
import type_checker.argument_context;
import type_checker.checked_index_reference;
import type_checker.scoped_type_equality;
import hir_expr_semantics;

bool assignment_expression_context<TGraph : IScopedTypeGraph>(uint node,
    uint statement, uint hir_count, uint tokens, uint type_capacity,
    out uint2 reference)
{
    static const uint ABSENT = 0xffffffffu;
    reference = uint2(0u, ABSENT);
    if (node >= hir_count) return false;
    uint root = ABSENT; uint current = node; uint candidate = statement;
    for (uint depth = 0u; depth < 32u; depth++)
    {
        if (candidate < hir_count)
        {
            HirPayload assignment = compact_hir_payload[candidate];
            uint kind = compact_hir_core[candidate].kind;
            if ((kind == 15u || (kind == 7u && assignment.a == 5u)) &&
                argument_context_root(assignment.c, hir_count, compact_hir_core,
                    compact_hir_payload) == node)
            { root = assignment.b; break; }
            if (depth != 0u && !hir_is_forward_expression(kind, assignment.a)) return false;
        }
        uint parent = compact_hir_core[current].parent;
        if (parent >= hir_count || parent == current) return false;
        current = parent; candidate = parent;
    }
    uint indices = 0u;
    for (uint depth = 0u; depth < 64u; depth++)
    {
        if (root >= hir_count) return false;
        HirCore core = compact_hir_core[root];
        HirPayload value = compact_hir_payload[root];
        if ((core.kind == 14u || core.kind == 16u || core.kind == 17u) && value.a == 1u)
        { root = value.b; continue; }
        if (core.kind == 20u)
        { indices++; root = value.b; continue; }
        if (core.kind == 21u && value.c < tokens)
            reference = uint2(member_result_ref_tag[value.c], member_result_ref_payload[value.c]);
        else if (core.kind == 22u || core.kind == 33u)
        {
            uint token = value.d < tokens ? value.d : core.token_start;
            uint declaration = token < tokens ? visible_decl[token] : ABSENT;
            if (declaration < tokens)
                reference = uint2(decl_type_ref_tag[declaration], decl_type_ref_payload[declaration]);
        }
        else if (core.kind == 19u && indices != 0u)
        {
            // The inference snapshot precedes this pass. Reading a mutable
            // call-result row here could observe a sibling lane's publication.
            reference = uint2(call_inference_result_tag[root], call_inference_result_payload[root]);
        }
        break;
    }
    // Project indexed destinations through the authoritative graph reader,
    // preserving the final element reference when storing a reference itself.
    return checked_index_elements<TGraph>(indices, type_capacity,
        reference.x, reference.y);
}
