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
                    if (reference.x != 0u && reference.y != INVALID &&
                        instance_scoped_reference<TGraph>(reference.x, reference.y, scope,
                            type_capacity, tokens, type_instance_lookup_head, type_instance_lookup_next,
                            reference.x, reference.y)) return true;
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

// The same contexts for readers that compare types by canonical ID (03j). A
// struct-literal field whose declared row must be looked up under its scope
// instance is returned as DECLARED_CONTEXT_FIELD: `reference` is the field's
// declared row and `scope` the instance, for the reader to substitute by
// canonical ID instead of the hash and equality walk of
// instance_scoped_reference. Every other context, including a field that
// needs no lookup, resolves exactly as declared_expression_context does.
static const uint DECLARED_CONTEXT_NONE = 0u;
static const uint DECLARED_CONTEXT_REFERENCE = 1u;
static const uint DECLARED_CONTEXT_FIELD = 2u;

// instance_scoped_reference without its lookup: DECLARED_CONTEXT_FIELD when
// the row must be looked up under `context`.
uint field_scoped_reference<TGraph : IScopedTypeGraph>(uint2 field, uint context,
    uint type_capacity, uint token_capacity, out uint2 reference)
{
    reference = uint2(0u, INVALID);
    uint tag = field.x; uint payload = field.y;
    if (context != INVALID && ((context & 0x80000000u) != 0u || context >= type_capacity))
        return DECLARED_CONTEXT_NONE;
    if (tag == 2u && context != INVALID)
    {
        uint slot = payload < token_capacity ? TGraph.parameter_slot(payload) : INVALID;
        if (slot == INVALID || !TGraph.environment_argument(context, slot, tag, payload))
            return DECLARED_CONTEXT_NONE;
        // The argument is already checked in caller scope.
        context = INVALID;
    }
    if ((tag == 1u && payload != 0u && payload != INVALID) ||
        (tag == 2u && payload < token_capacity && TGraph.parameter_slot(payload) != INVALID))
    {
        reference = uint2(tag, payload);
        return DECLARED_CONTEXT_REFERENCE;
    }
    if (tag != 3u || payload >= type_capacity) return DECLARED_CONTEXT_NONE;
    uint kind = TGraph.metadata(payload, 0u);
    if (kind < 1u || kind > 4u) return DECLARED_CONTEXT_NONE;
    reference = uint2(tag, payload);
    return context == INVALID ? DECLARED_CONTEXT_REFERENCE : DECLARED_CONTEXT_FIELD;
}

// The statement contexts after the field contexts.
bool declared_statement_expression_context(uint node, out uint2 reference)
{
    reference = uint2(0u, INVALID);
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

// With `after_field`, the contexts after a field returned earlier.
uint declared_expression_context_or_field<TGraph : IScopedTypeGraph>(uint node,
    uint type_capacity, bool after_field, out uint2 reference, out uint scope)
{
    reference = uint2(0u, INVALID);
    scope = INVALID;
    if (!valid_hir(node)) return DECLARED_CONTEXT_NONE;
    if (!after_field)
    {
        if (argument_expected_ref_tag[node] != 0u && argument_expected_ref_payload[node] != INVALID)
        {
            reference = uint2(argument_expected_ref_tag[node], argument_expected_ref_payload[node]);
            return DECLARED_CONTEXT_REFERENCE;
        }
        uint tokens; uint stride;
        decl_type_ref_tag.GetDimensions(tokens, stride);
        if (assignment_expression_context<TGraph>(node, compact_hir_payload[node].d,
            active_hir_count(), tokens, type_capacity, reference)) return DECLARED_CONTEXT_REFERENCE;
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
                        uint2 declared = uint2(struct_init_field_expected_ref_tag[field.name_token],
                            struct_init_field_expected_ref_payload[field.name_token]);
                        uint context = struct_init_field_expected_context_instance[field.name_token];
                        uint tokens; uint stride;
                        struct_init_field_expected_context_instance.GetDimensions(tokens, stride);
                        if (declared.x == 0u || declared.y == INVALID) continue;
                        uint resolved = field_scoped_reference<TGraph>(declared, context,
                            type_capacity, tokens, reference);
                        if (resolved == DECLARED_CONTEXT_FIELD) scope = context;
                        if (resolved != DECLARED_CONTEXT_NONE) return resolved;
                    }
                }
            break;
        }
    }
    return declared_statement_expression_context(node, reference)
        ? DECLARED_CONTEXT_REFERENCE : DECLARED_CONTEXT_NONE;
}
