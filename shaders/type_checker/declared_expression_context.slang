// Declaration, return, assignment, field, and argument contexts are complete checked
// references. The including pass supplies immutable context columns.
import type_checker.scoped_reference_lookup;
import type_checker.scoped_type_equality;
#include "assignment_expression_context.slang"

bool statement_expression_context(uint node, uint statement, out uint2 reference)
{
    reference = uint2(0u, INVALID);
    if (!valid_hir(statement)) return false;
    uint kind = compact_hir_core[statement].kind;
    HirPayload value = compact_hir_payload[statement];
    if ((kind == HIR_STMT || kind == HIR_LET_STMT) && (value.a == 1u || value.a == 4u) &&
        argument_context_root(value.c, active_hir_count(), compact_hir_core, compact_hir_payload) == node &&
        valid_hir(value.d) && valid_token(value.b))
        reference = uint2(decl_type_ref_tag[value.b], decl_type_ref_payload[value.b]);
    else if (kind == HIR_RETURN_STMT && value.a == 2u &&
        argument_context_root(value.b, active_hir_count(), compact_hir_core, compact_hir_payload) == node)
    {
        uint function = compact_hir_nearest_fn[statement];
        uint token = valid_hir(function) ? compact_hir_payload[function].b : INVALID;
        if (valid_token(token)) reference = uint2(fn_return_ref_tag[token], fn_return_ref_payload[token]);
    }
    return reference.x != 0u && reference.y != INVALID;
}

bool declared_expression_context<TGraph : IScopedTypeGraph>(uint node,
    uint type_capacity, out uint2 reference)
{
    reference = uint2(0u, INVALID);
    if (!valid_hir(node)) return false;
    if (argument_expected_ref_tag[node] != 0u && argument_expected_ref_payload[node] != INVALID)
    {
        reference = uint2(argument_expected_ref_tag[node], argument_expected_ref_payload[node]);
        return true;
    }
    uint tokens; uint stride;
    decl_type_ref_tag.GetDimensions(tokens, stride);
    if (assignment_expression_context<TGraph>(node, compact_hir_payload[node].d,
        active_hir_count(), tokens, type_capacity, reference)) return true;
    // Postfix syntax can retain intermediate ancestors even when a field's
    // durable value is the call itself. Ancestry only selects a candidate
    // record; the parser-owned field value identity decides ownership.
    uint literal = compact_hir_core[node].parent;
    for (uint depth = 0u; depth < 32u && valid_hir(literal); depth++)
    {
        uint kind = compact_hir_core[literal].kind;
        if (kind == HIR_STMT || kind == HIR_LET_STMT || kind == HIR_RETURN_STMT || kind == 3u || kind == 1u)
            break;
        if (kind != 28u)
        {
            uint parent = compact_hir_core[literal].parent;
            if (parent == literal) break;
            literal = parent;
            continue;
        }
        HirPayload value = compact_hir_payload[literal];
        uint count = min(compact_field_count[0u], active_hir_count());
        if (value.b < count && value.c <= count - value.b)
            for (uint row = value.b; row < value.b + value.c; row++)
            {
                HirField field = compact_fields[row];
                if (field.owner == literal &&
                    argument_context_root(field.value, active_hir_count(), compact_hir_core, compact_hir_payload) == node &&
                    valid_token(field.name_token))
                {
                    reference = uint2(struct_init_field_expected_ref_tag[field.name_token],
                        struct_init_field_expected_ref_payload[field.name_token]);
                    uint scope = struct_init_field_expected_context_instance[field.name_token];
                    uint tokens; uint stride;
                    struct_init_field_expected_context_instance.GetDimensions(tokens, stride);
#ifdef DECLARED_CONTEXT_CANONICAL
                    // The includer reads the checked graph through canonical
                    // IDs (checked_canonical.slang).
                    if (reference.x != 0u && reference.y != INVALID &&
                        canonical_scoped_reference<DECLARED_CONTEXT_CANONICAL>(reference.x, reference.y, scope, tokens,
                            reference.x, reference.y)) return true;
#else
                    if (reference.x != 0u && reference.y != INVALID &&
                        instance_scoped_reference<TGraph>(reference.x, reference.y, scope,
                            type_capacity, tokens, type_instance_lookup_head, type_instance_lookup_next,
                            reference.x, reference.y)) return true;
#endif
                }
            }
        break;
    }
    if (statement_expression_context(node, compact_hir_payload[node].d, reference)) return true;
    uint current = node;
    for (uint depth = 0u; depth < 32u; depth++)
    {
        uint parent = compact_hir_core[current].parent;
        if (!valid_hir(parent) || parent == current) return false;
        if (statement_expression_context(node, parent, reference)) return true;
        if (!hir_is_forward_expression(compact_hir_core[parent].kind, compact_hir_payload[parent].a)) return false;
        current = parent;
    }
    return false;
}
