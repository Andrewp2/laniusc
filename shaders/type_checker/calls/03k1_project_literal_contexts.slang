// One lane owns each numeric literal's checked context. Expression ancestry
// and checked sibling facts are immutable during this dispatch, so an outer
// annotation and an inner operand cannot race to relabel the same literal.
#include "array_literal_context_inputs.slang"
import primitive_types;
import type_checker.owned_literal_context;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_checked_rows;
import type_checker.substitution.ct_checked;
import type_checker.substitution.ct_subst;
import type_checker.checked_slots;
StructuredBuffer<uint> compact_hir_expr_parent;
StructuredBuffer<uint> compact_const_value;
StructuredBuffer<uint> compact_const_type;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
RWStructuredBuffer<uint> literal_context_type_by_hir;
RWStructuredBuffer<uint> call_inference_state;

uint numeric_context(uint2 reference, bool floating)
{
    return reference.x == 1u && (floating ? scalar_is_float(reference.y) : scalar_is_integer(reference.y)) ? reference.y : 0u;
}

bool integer_arithmetic_form(uint form)
{
    return (form >= 13u && form <= 16u) || (form >= 19u && form <= 25u);
}

uint checked_numeric_peer(uint node, bool floating)
{
    node = argument_context_root(node, active_hir_count(), compact_hir_core, compact_hir_payload);
    if (!valid_hir(node)) return 0u;
    // A numeric literal's default inference is not an independent type constraint.
    if (numeric_literal_accepts_context(node, floating ? 5u : 3u, active_hir_count(),
        compact_hir_core, compact_hir_payload, compact_hir_expr_parent)) return 0u;
    return numeric_context(uint2(call_inference_result_tag[node], call_inference_result_payload[node]), floating);
}

uint direct_range_literal_context(uint literal)
{
    // Range bounds are independent value roots in the expression forest.
    // Lexical ancestry selects the for statement; its recorded iterable and
    // endpoint identities establish ownership without adding value edges.
    uint ancestor = compact_hir_core[literal].parent;
    for (uint step = 0u; step < active_hir_count() && valid_hir(ancestor); step++)
    {
        HirCore owner = compact_hir_core[ancestor];
        HirPayload statement = compact_hir_payload[ancestor];
        if ((owner.kind == 30u || owner.kind == HIR_STMT) && statement.a == 7u)
        {
            uint iterable = argument_context_root(statement.c, active_hir_count(),
                compact_hir_core, compact_hir_payload);
            if (!valid_hir(iterable)) return 0u;
            HirCore core = compact_hir_core[iterable];
            HirPayload range = compact_hir_payload[iterable];
            if ((core.kind != 14u && core.kind != 16u) ||
                (range.a != 30u && range.a != 34u)) return 0u;
            uint start = argument_context_root(range.b, active_hir_count(),
                compact_hir_core, compact_hir_payload);
            uint end = argument_context_root(range.c, active_hir_count(),
                compact_hir_core, compact_hir_payload);
            if (start == literal) return checked_numeric_peer(end, false);
            if (end == literal) return checked_numeric_peer(start, false);
            // A literal inside an endpoint call or index is not the endpoint.
            return 0u;
        }
        if (owner.kind == HIR_STMT || owner.kind == HIR_LET_STMT ||
            owner.kind == HIR_RETURN_STMT || owner.kind == 25u ||
            owner.kind == 3u || owner.kind == 1u || owner.parent == ancestor) break;
        ancestor = owner.parent;
    }
    return 0u;
}

static const uint MATCH_ROLE_NONE = 0u;
static const uint MATCH_ROLE_PATTERN = 1u;
static const uint MATCH_ROLE_RESULT = 2u;

// The nearest enclosing match within the statement owns a literal that is an
// arm pattern (scrutinee context) or an arm result (the match's own context).
uint match_literal_role(uint node, out uint match)
{
    match = INVALID;
    uint parent = compact_hir_core[node].parent;
    for (uint depth = 0u; depth < 32u && valid_hir(parent); depth++)
    {
        HirCore core = compact_hir_core[parent];
        if (core.kind == 34u)
        {
            HirPayload value = compact_hir_payload[parent];
            uint count = min(compact_match_arm_count[0u], active_hir_count());
            if (value.b >= count || value.c > count - value.b) return MATCH_ROLE_NONE;
            match = parent;
            for (uint row = value.b; row < value.b + value.c; row++)
            {
                HirMatchArm arm = compact_match_arms[row];
                if (arm.owner != parent) continue;
                if (argument_context_root(arm.pattern, active_hir_count(),
                    compact_hir_core, compact_hir_payload) == node) return MATCH_ROLE_PATTERN;
                if (argument_context_root(arm.result, active_hir_count(),
                    compact_hir_core, compact_hir_payload) == node) return MATCH_ROLE_RESULT;
            }
            return MATCH_ROLE_NONE;
        }
        if (core.kind == HIR_STMT || core.kind == HIR_LET_STMT ||
            core.kind == HIR_RETURN_STMT || core.kind == 3u || core.kind == 1u) break;
        if (core.parent == parent) break;
        parent = core.parent;
    }
    return MATCH_ROLE_NONE;
}

// A lexical const annotation owns exactly its initializer's value root.
uint const_annotation_context(uint current, bool floating)
{
    uint ancestor = compact_hir_core[current].parent;
    for (uint depth = 0u; depth < 32u && valid_hir(ancestor); depth++)
    {
        HirCore owner = compact_hir_core[ancestor];
        if (owner.kind == 25u)
        {
            uint token = compact_hir_payload[ancestor].b;
            if (valid_token(token) && argument_context_root(compact_const_value[ancestor],
                active_hir_count(), compact_hir_core, compact_hir_payload) == current)
                return numeric_context(uint2(decl_type_ref_tag[token], decl_type_ref_payload[token]), floating);
            return 0u;
        }
        if (owner.kind == 3u || owner.kind == 1u || owner.parent == ancestor) break;
        ancestor = owner.parent;
    }
    return 0u;
}

bool array_instance(uint instance)
{
    return valid_instance(instance) && type_instance_kind[instance] == TYPE_INSTANCE_ARRAY;
}

// A struct-literal field type declared in its literal's scope, substituted
// under the literal's application `scope` (docs/canonical-type-ids.md), or
// CT_NONE. Rows written during inference are interned on demand, from one
// site.
uint substituted_field_type(uint field, uint scope)
{
    uint spare = CT_NONE;
    uint term = CT_UNKNOWN; uint environment = CT_UNKNOWN;
    [loop]
    for (uint operand = 0u; operand < 2u; operand++)
    {
        uint id = ct_intern_checked<CtCheckedRows>(TYPE_REF_INSTANCE, operand == 0u ? field : scope, spare);
        if (operand == 1u) { environment = id; break; }
        term = id;
        if (!ct_is_resolved(term)) return CT_NONE;
        if (ct_closed(term)) return ct_is_record(term) ? term : CT_NONE;
    }
    if (!ct_is_record(environment) || ct_kind(environment) != CT_KIND_NAMED) return CT_NONE;
    CtSpare substitution = ct_spare_none();
    uint id = ct_subst(CheckedSlots(), environment, term, true, substitution);
    return ct_is_record(id) ? id : CT_NONE;
}

// The numeric context of the elements `layers` array levels below canonical
// array `id` (`fallback` when a level is not an array).
uint canonical_array_element_context(uint id, uint layers, bool floating, uint fallback)
{
    for (uint layer = 0u; layer < layers; layer++)
    {
        if (ct_kind(id) != CT_KIND_ARRAY) return fallback;
        id = ct_arg(id, 0u);
        if (!ct_is_record(id)) return fallback;
    }
    if (ct_kind(id) != CT_KIND_ARRAY) return fallback;
    uint element = ct_arg(id, 0u);
    return numeric_context(uint2(element - 1u < SCALAR_USIZE ? 1u : 0u, element), floating);
}

// Which node the single declared-context read below answers for.
static const uint QUERY_OPERAND = 0u; // the current operand root
static const uint QUERY_MATCH = 1u;   // the match whose arm result is the operand
static const uint QUERY_ARRAY = 2u;   // an enclosing array literal layer

uint checked_literal_context(uint literal)
{
    uint owned = checked_owned_numeric_literal_context(literal, active_hir_count(), gParams.n_tokens,
        compact_hir_core, compact_hir_payload, compact_hir_expr_parent, compact_const_type,
        compact_const_value, type_expr_ref_tag, type_expr_ref_payload);
    if (owned != 0u) return owned;
    bool floating = compact_hir_payload[literal].a == HIR_SEM_EXPR_FLOAT;
    uint range_context = floating ? 0u : direct_range_literal_context(literal);
    if (range_context != 0u) return range_context;
    uint current = literal;
    uint peer = 0u;
    // Declared contexts are read at one call site: each site inlines the
    // whole reader (~26k instructions), and three copies made this kernel
    // 87k and its dispatch ~50x slower than the same work at 34k. Each round
    // answers one query: the operand, then the match owning it as an arm
    // result, then (once the operand is an array element) each enclosing
    // array layer, innermost first. The parser owns an acyclic expression
    // forest, so the checked active row count bounds the operand climb;
    // array layers are bounded as in `expected_array_literal_instance`.
    uint query = literal;
    uint mode = QUERY_OPERAND;
    uint array_node = INVALID; uint array_layers = 0u; uint array_depth = 0u;
    uint operand_steps = 0u;
    // Set when a field context's substitution failed: the same query resumes
    // after that context.
    bool after_field = false;
    while (true)
    {
        if (mode == QUERY_OPERAND && !after_field)
        {
            if (operand_steps >= active_hir_count()) return peer;
            operand_steps++;
            uint context = const_annotation_context(current, floating);
            if (context != 0u) return context;
        }
        uint2 reference; uint scope;
        uint resolved = declared_expression_context_or_field<ScopedCheckedTypeGraph>(query,
            checked_type_capacity(), after_field, reference, scope);
        after_field = false;
        // A field declared in its literal's scope is substituted under the
        // literal's application by canonical ID.
        uint field = CT_NONE;
        if (resolved == DECLARED_CONTEXT_FIELD)
        {
            field = substituted_field_type(reference.y, scope);
            if (field == CT_NONE) { after_field = true; continue; }
        }
        bool declared = resolved != DECLARED_CONTEXT_NONE;
        if (mode == QUERY_ARRAY)
        {
            uint expected = declared && field == CT_NONE && reference.x == TYPE_REF_INSTANCE
                ? reference.y : INVALID;
            bool found = field != CT_NONE ? ct_kind(field) == CT_KIND_ARRAY : array_instance(expected);
            if (!found && query != array_node && call_inference_result_tag[query] == TYPE_REF_INSTANCE)
            {
                expected = call_inference_result_payload[query];
                found = array_instance(expected);
            }
            if (!found)
            {
                uint parent = compact_hir_core[query].parent;
                if (!valid_hir(parent) || compact_hir_core[parent].kind != HIR_ARRAY_EXPR) return peer;
                array_layers++; query = parent;
                if (++array_depth < 64u) continue;
            }
            if (field != CT_NONE && ct_kind(field) == CT_KIND_ARRAY)
                return canonical_array_element_context(field, array_layers, floating, peer);
            for (uint layer = 0u; layer < array_layers; layer++)
            {
                if (!array_instance(expected) ||
                    type_instance_elem_ref_tag[expected] != TYPE_REF_INSTANCE) return peer;
                expected = type_instance_elem_ref_payload[expected];
            }
            return array_instance(expected) ? numeric_context(uint2(
                type_instance_elem_ref_tag[expected], type_instance_elem_ref_payload[expected]), floating) : peer;
        }
        // A substituted field is a type row, never a numeric scalar.
        if (declared && field == CT_NONE)
        {
            uint context = numeric_context(reference, floating);
            if (context != 0u) return context;
        }
        if (mode == QUERY_OPERAND)
        {
            uint match;
            uint role = match_literal_role(current, match);
            if (role == MATCH_ROLE_PATTERN)
            {
                uint scrutinee = argument_context_root(compact_hir_payload[match].a,
                    active_hir_count(), compact_hir_core, compact_hir_payload);
                uint context = valid_hir(scrutinee) ? numeric_context(uint2(
                    call_inference_result_tag[scrutinee], call_inference_result_payload[scrutinee]),
                    floating) : 0u;
                if (context != 0u) return context;
            }
            else if (role == MATCH_ROLE_RESULT)
            {
                mode = QUERY_MATCH; query = match;
                continue;
            }
        }
        mode = QUERY_OPERAND;
        uint parent = compact_hir_expr_parent[current];
        if (!valid_hir(parent) || parent == current) return peer;
        HirCore core = compact_hir_core[parent];
        HirPayload value = compact_hir_payload[parent];
        if (core.kind == HIR_ARRAY_EXPR)
        {
            mode = QUERY_ARRAY; array_node = parent; query = parent;
            continue;
        }
        if (core.kind != 14u && core.kind != 16u && core.kind != 17u) return peer;
        if ((hir_is_forward_expression(core.kind, value.a) || value.a == 13u) && value.b == current)
        { current = parent; query = parent; continue; }
        if (core.kind != 16u || (value.b != current && value.c != current)) return peer;
        bool comparison = value.a >= 7u && value.a <= 12u;
        bool arithmetic = floating ? ((value.a >= 14u && value.a <= 16u) || value.a == 20u)
            : integer_arithmetic_form(value.a);
        if (!comparison && !arithmetic) return peer;
        bool shift = value.a == 24u || value.a == 25u;
        // The shift amount has an independent integer type and range.
        if (shift && value.c == current) return peer;
        if (!shift && peer == 0u)
            peer = checked_numeric_peer(value.b == current ? value.c : value.b, floating);
        if (comparison) return peer;
        current = parent; query = parent;
    }
    return peer;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = dtid.x + dtid.y * 16776960u;
    if (!valid_hir(node) || compact_hir_core[node].kind != HIR_SEM_KIND_LITERAL_EXPR ||
        (compact_hir_payload[node].a != HIR_SEM_EXPR_INT &&
         compact_hir_payload[node].a != HIR_SEM_EXPR_FLOAT)) return;
    uint type = checked_literal_context(node);
    if (literal_context_type_by_hir[node] != type)
    {
        uint previous = literal_context_type_by_hir[node];
        literal_context_type_by_hir[node] = type;
        // Preserve explicit context provenance, but request another fixed-point
        // round only when a reader observes a different effective scalar.
        // An absent context means the syntax category's default scalar.
        uint default_scalar = compact_hir_payload[node].a == HIR_SEM_EXPR_FLOAT
            ? SCALAR_F32 : SCALAR_I32;
        uint previous_scalar = previous == 0u ? default_scalar : previous;
        uint next_scalar = type == 0u ? default_scalar : type;
        if (previous_scalar != next_scalar)
        {
            uint ignored; InterlockedAdd(call_inference_state[1u], 1u, ignored);
        }
    }
}
