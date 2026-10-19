// Expected argument types are checked caller-side references: the declared
// parameter type under the call's expected environment (call_env.slang),
// substituted over canonical IDs and realized as a checked row. Each argument
// owns one row; imported patterns are consumed only on their declaration
// page. This relation provides context to expressions without replacing their
// accepted actual types or inferring a type from native storage width.
import hir_records;
import status;
import dependency_interface;
import type_checker.argument_context;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_dependency;
import type_checker.substitution.ct_subst;
import type_checker.substitution.ct_rows;
import type_checker.substitution.ct_realize;
import type_checker.substitution.source_slots;
import type_checker.substitution.call_env;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_array_element_count;
StructuredBuffer<uint> compact_array_element_start;
StructuredBuffer<uint> compact_array_element_row_count;
StructuredBuffer<HirArrayElement> compact_array_elements;
StructuredBuffer<uint> call_arg_row_count_out;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_call_node;
StructuredBuffer<uint> call_arg_row_ordinal;
StructuredBuffer<uint> call_arg_param_row;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_ref_tag;
StructuredBuffer<uint> call_param_row_ref_payload;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> call_dependency_unit_id;
StructuredBuffer<uint> call_dependency_local_index;
RWStructuredBuffer<uint> argument_expected_ref_tag;
RWStructuredBuffer<uint> argument_expected_ref_payload;
RWStructuredBuffer<uint> call_inference_state;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint DEPTH_LIMIT = 64u;
static const uint ARRAY_LITERAL = 24u;

uint hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }

// The alias root of dependency type node `t` of the resident page.
uint dependency_root(uint t)
{
    uint count = dependency_type_count();
    uint root = t < count ? canonical_type_roots[t] : INVALID;
    return root < count ? root : INVALID;
}

// The canonical declared type of the argument's parameter, or CT_UNKNOWN.
uint parameter_pattern(uint row, uint token, bool dotted)
{
    if (call_dependency_library_id[token] == INVALID)
    {
        uint parameter = call_arg_param_row[row];
        if (parameter >= min(call_param_row_count_out[0u], gParams.n_hir_nodes)) return CT_UNKNOWN;
        return ct_ref(call_param_row_ref_tag[parameter], call_param_row_ref_payload[parameter]);
    }
    uint library = call_dependency_library_id[token];
    uint unit = call_dependency_unit_id[token];
    uint local = call_dependency_local_index[token];
    uint ordinal = call_arg_row_ordinal[row];
    uint type = INVALID;
    uint declaration = dependency_find_declaration(library, unit, local);
    if (declaration < dependency_declaration_count())
    {
        uint signature = dependency_root(dependency_declaration_word(declaration * 14u + 7u));
        if (signature == INVALID || dependency_type_word(signature * 9u) != 7u) return CT_UNKNOWN;
        uint start = dependency_type_word(signature * 9u + 3u);
        uint count = dependency_type_word(signature * 9u + 4u);
        uint edges = dependency_count(5u);
        if (count == 0u || ordinal >= count - 1u || start > edges || count > edges - start) return CT_UNKNOWN;
        type = dependency_type_edge_word(start + ordinal);
    }
    else
    {
        uint method = dependency_find_method(library, unit, local);
        if (method >= dependency_member_count()) return CT_UNKNOWN;
        type = dependency_method_parameter_type(method, ordinal + (dotted ? 1u : 0u));
    }
    return type < dependency_type_count() ? ct_dependency_state(type) : CT_UNKNOWN;
}

// The array literal `levels` levels inside `literal` (through first
// elements), or INVALID.
uint nested_literal(uint literal, uint levels)
{
    for (uint level = 0u; level < levels && literal != INVALID; level++)
    {
        uint first = compact_array_element_start[literal];
        literal = compact_array_element_count[literal] != 0u &&
            first < min(compact_array_element_row_count[0u], gParams.n_hir_nodes)
            ? argument_context_root(compact_array_elements[first].value, hir_count(),
                compact_hir_core, compact_hir_payload) : INVALID;
        if (literal >= hir_count() || compact_hir_core[literal].kind != ARRAY_LITERAL) literal = INVALID;
    }
    return literal;
}

// Capacity and limits have their own diagnostic; a busy row asks for
// another round.
void report(uint token, uint failure)
{
    if (failure == CT_REALIZE_CAPACITY || failure == CT_REALIZE_LIMIT)
        record_min_token_error(status, token, 6u, 0x474e0000u | failure);
    if (failure == CT_REALIZE_BUSY) { uint ignored; InterlockedAdd(call_inference_state[1u], 1u, ignored); }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    if (row >= min(call_arg_row_count_out[0u], gParams.n_hir_nodes)) return;
    uint call = call_arg_row_call_node[row];
    uint node = argument_context_root(call_arg_row_node[row], hir_count(),
        compact_hir_core, compact_hir_payload);
    if (call >= hir_count() || node >= hir_count()) return;
    uint callee = compact_hir_payload[call].a;
    if (callee >= hir_count()) return;
    bool dotted = compact_hir_core[callee].kind == 21u;
    uint token = dotted ? compact_hir_payload[callee].c : compact_hir_payload[callee].d;
    if (token >= gParams.n_tokens) token = compact_hir_core[callee].token_start;
    if (token >= gParams.n_tokens) return;
    uint pattern = parameter_pattern(row, token, dotted);
    if (!ct_is_resolved(pattern)) return;
    // An array literal gives a declared array pattern its own length at each
    // level it spells: the element pattern is substituted, then wrapped in
    // arrays of the literal lengths. An empty array gives no evidence below.
    uint depth = 0u;
    uint literal = compact_hir_core[node].kind == ARRAY_LITERAL ? node : INVALID;
    while (literal != INVALID && ct_kind(pattern) == CT_KIND_ARRAY)
    {
        if (depth == DEPTH_LIMIT) { report(token, CT_REALIZE_LIMIT); return; }
        pattern = ct_arg(pattern, 0u);
        depth++;
        literal = nested_literal(literal, 1u);
    }
    uint environment = ct_call_env(token).y;
    if (!ct_closed(pattern) && !ct_is_record(environment)) return;
    CtSpare spare = ct_spare_none();
    uint expected = ct_subst(SourceSlots(), environment, pattern, true, spare);
    for (uint level = depth; level != 0u && ct_is_resolved(expected); level--)
    {
        uint nested = nested_literal(node, level - 1u);
        uint length = hir_array_literal_length(compact_hir_core, compact_hir_payload, hir_count(),
            nested, compact_array_element_count[nested]);
        uint count = cc_intern_count(length, spare.record);
        expected = ct_is_resolved(count)
            ? ct_intern_small(CT_KIND_ARRAY, 2u, uint3(0u, 0u, 0u), uint2(expected, count),
                uint2(INVALID, 0u), spare.record)
            : CT_UNKNOWN;
    }
    if (!ct_is_resolved(expected))
    {
        // Context is optional until bindings become known; ordinary call
        // validation owns missing bindings. Capacity has its own diagnostic.
        uint overflow = ct_subst_counts[CT_SUBST_COUNT_OVERFLOW];
        if ((overflow & (CT_SUBST_OVERFLOW_MEMO | CT_SUBST_OVERFLOW_ROWS | CT_SUBST_OVERFLOW_CONSTANTS)) != 0u ||
            ct_counts[CT_COUNT_OVERFLOW] != 0u)
            report(token, CT_REALIZE_CAPACITY);
        else if ((overflow & CT_SUBST_OVERFLOW_WORK) != 0u) report(token, CT_REALIZE_LIMIT);
        return;
    }
    uint failure;
    uint2 operand = ct_realize(expected, failure);
    if (operand.x == 0u) { report(token, failure); return; }
    // Rows are unique per ID, so equal operands are equal types.
    if (argument_expected_ref_tag[node] == operand.x && argument_expected_ref_payload[node] == operand.y) return;
    argument_expected_ref_tag[node] = operand.x;
    argument_expected_ref_payload[node] = operand.y;
    uint ignored; InterlockedAdd(call_inference_state[1u], 1u, ignored);
}
