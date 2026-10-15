// Produce aggregate-structure comparison requests from dense compact HIR and
// canonical checked expression references. One lane owns one statement HIR
// row; variable-length type arguments are expanded by the downstream scan and
// aggregate_args pass, never walked serially here.

import type_checker.checked_type_graph;
import type_checker.checked_type_identity;
import type_checker.checked_slots;
import hir_records;
import gpu_index;
import status;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> struct_init_field_expected_ref_tag;
StructuredBuffer<uint> struct_init_field_expected_ref_payload;
StructuredBuffer<uint> compact_fn_return_type;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
StructuredBuffer<uint> semantic_aggregate_decl_token_by_hir;
RWStructuredBuffer<uint> aggregate_compare_scan_input;
RWStructuredBuffer<uint> aggregate_compare_expected_instance;
RWStructuredBuffer<uint> aggregate_compare_actual_instance;
RWStructuredBuffer<uint> aggregate_compare_error_token;
RWStructuredBuffer<uint> aggregate_compare_error_detail;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_STMT_LET = 1u;
static const uint HIR_STMT_RETURN = 2u;
static const uint HIR_STMT_CONST = 4u;
static const uint HIR_STMT_ASSIGN = 5u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint TYPE_LEN_CONST_PARAM = 2u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint DISPATCH_X_STRIDE = 16776960u;

[ForceInline]
uint active_hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

void clear_request(uint node)
{
    aggregate_compare_scan_input[node] = 0u;
    aggregate_compare_expected_instance[node] = INVALID;
    aggregate_compare_actual_instance[node] = INVALID;
    aggregate_compare_error_token[node] = INVALID;
    aggregate_compare_error_detail[node] = 0u;
}

void declaration_ref(uint token, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(token)) return;
    uint decl = visible_decl[token];
    if (!valid_token(decl)) decl = token;
    tag = decl_type_ref_tag[decl];
    payload = decl_type_ref_payload[decl];
}

void type_node_ref(uint node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_hir(node)) return;
    uint token = compact_hir_core[node].token_start;
    if (!valid_token(token)) return;
    tag = type_expr_ref_tag[token];
    payload = type_expr_ref_payload[token];
}

void expression_ref(uint node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_hir(node)) return;
    tag = semantic_expr_ref_tag_by_hir[node];
    payload = semantic_expr_ref_payload_by_hir[node];
}

bool resolved_dependency_call(uint node)
{
    if (!valid_hir(node) || compact_hir_core[node].kind != HIR_CALL_EXPR)
        return false;
    uint callee = compact_hir_payload[node].a;
    if (!valid_hir(callee))
        return false;
    HirCore core = compact_hir_core[callee];
    HirPayload payload = compact_hir_payload[callee];
    uint token = core.kind == HIR_MEMBER_EXPR ? payload.c : payload.d;
    if (!valid_token(token)) token = core.token_start;
    return valid_token(token) && call_dependency_library_id[token] != INVALID;
}

bool same_named_identity(uint lhs, uint rhs)
{
    uint lhs_decl = type_instance_decl_token[lhs];
    uint rhs_decl = type_instance_decl_token[rhs];
    if (valid_token(lhs_decl) || valid_token(rhs_decl))
        return valid_token(lhs_decl) && lhs_decl == rhs_decl;
    return external_type_library_id[lhs] != INVALID &&
        external_type_unit_id[lhs] != INVALID && external_type_local_index[lhs] != INVALID &&
        external_type_library_id[lhs] == external_type_library_id[rhs] &&
        external_type_unit_id[lhs] == external_type_unit_id[rhs] &&
        external_type_local_index[lhs] == external_type_local_index[rhs];
}

// A slice destination borrows an array value at the outer boundary, as call
// arguments do: let, assignment, return and record fields view the array's
// storage. Element types are invariant; nested aggregates never convert.
bool array_borrow_matches(uint expected, uint actual)
{
    if (expected >= checked_type_capacity() || actual >= checked_type_capacity() ||
        type_instance_kind[expected] != TYPE_INSTANCE_SLICE ||
        type_instance_kind[actual] != TYPE_INSTANCE_ARRAY) return false;
    return checked_types_equal(CheckedSlots(), 
        type_instance_elem_ref_tag[expected], type_instance_elem_ref_payload[expected],
        type_instance_elem_ref_tag[actual], type_instance_elem_ref_payload[actual],
        !(checked_row_is_closed(expected) && checked_row_is_closed(actual)));
}

// Codegen passing mode per value node; 4 marks an array viewed as a slice.
RWStructuredBuffer<uint> semantic_argument_mode_by_hir;

bool prepare_instance_compare(uint node, uint expected, uint actual, uint error_token)
{
    if (expected == actual || array_borrow_matches(expected, actual)) return true;
    // Concrete structural children can have different source rows, and body
    // replay can introduce private graph IDs. Their canonical IDs decide
    // before the symbolic request path, including nested elements.
    if (checked_row_is_closed(expected) && checked_row_is_closed(actual))
        return checked_types_equal(CheckedSlots(), TYPE_REF_INSTANCE, expected, TYPE_REF_INSTANCE, actual, false);
    if (expected >= checked_type_capacity() || actual >= checked_type_capacity()) return false;
    uint kind = type_instance_kind[expected];
    if (kind == 0u || kind != type_instance_kind[actual]) return false;
    if (kind == TYPE_INSTANCE_ARRAY || kind == TYPE_INSTANCE_SLICE || kind == 4u)
    {
        // Symbolic children are complete graphs too. Their source rows may
        // differ even when they name the same lexical parameter/application.
        return checked_types_equal(CheckedSlots(), TYPE_REF_INSTANCE, expected, TYPE_REF_INSTANCE, actual, true);
    }
    if (kind != TYPE_INSTANCE_NAMED || !same_named_identity(expected, actual))
        return false;
    uint count = type_instance_arg_count[expected];
    if (count != type_instance_arg_count[actual]) return false;
    if (count != 0u)
    {
        aggregate_compare_scan_input[node] = count;
        aggregate_compare_expected_instance[node] = expected;
        aggregate_compare_actual_instance[node] = actual;
        aggregate_compare_error_token[node] = error_token;
        aggregate_compare_error_detail[node] = 0u;
    }
    return true;
}

void validate_refs(uint node, uint expected_tag, uint expected_payload,
                   uint actual_tag, uint actual_payload, uint error_token,
                   uint expected_node, uint actual_node)
{
    if (expected_tag == TYPE_REF_INVALID || actual_tag == TYPE_REF_INVALID) return;
    if (expected_tag != TYPE_REF_INSTANCE && actual_tag != TYPE_REF_INSTANCE)
    {
        // Monomorphic nominal values retain legacy scalar reference tags.
        // Their stable declaration identities still constrain assignments;
        // equal field widths or scalar-shaped tags cannot make them equal.
        if (expected_tag == 1u && actual_tag == 1u)
        {
            uint expected_decl = valid_hir(expected_node)
                ? semantic_aggregate_decl_token_by_hir[expected_node] : INVALID;
            uint actual_decl = valid_hir(actual_node)
                ? semantic_aggregate_decl_token_by_hir[actual_node] : INVALID;
            if ((valid_token(expected_decl) || valid_token(actual_decl)) &&
                (!valid_token(expected_decl) || expected_decl != actual_decl))
                record_min_token_error(status, error_token, ERR_ASSIGN_MISMATCH, 0u);
        }
        return;
    }
    bool matches = expected_tag == actual_tag;
    if (matches && expected_tag == TYPE_REF_INSTANCE)
        matches = prepare_instance_compare(
            node, expected_payload, actual_payload, error_token);
    if (!matches)
        record_min_token_error(
            status,
            valid_token(error_token) ? error_token : 0u,
            ERR_ASSIGN_MISMATCH,
            0u);
}

// Every literal field has its own checked expectation. Comparing only the
// enclosing nominal type loses disagreements inside fields such as Cell<T>.
void validate_struct_literal_fields(uint node)
{
    HirPayload literal = compact_hir_payload[node];
    uint start = literal.b;
    uint count = literal.c;
    uint total = min(compact_field_count[0u], gParams.n_tokens);
    if (start >= total || count > total - start) return;
    for (uint ordinal = 0u; ordinal < count; ordinal++)
    {
        HirField field = compact_fields[start + ordinal];
        if (field.owner != node || !valid_token(field.name_token) || !valid_hir(field.value)) continue;
        uint expected_tag = struct_init_field_expected_ref_tag[field.name_token];
        uint expected_payload = struct_init_field_expected_ref_payload[field.name_token];
        uint actual_tag; uint actual_payload;
        expression_ref(field.value, actual_tag, actual_payload);
        if (expected_tag != TYPE_REF_INSTANCE || actual_tag == TYPE_REF_INVALID ||
            !checked_row_is_closed(expected_payload)) continue;
        if (!checked_types_equal(CheckedSlots(), expected_tag, expected_payload, actual_tag, actual_payload, false) &&
            !(actual_tag == TYPE_REF_INSTANCE && array_borrow_matches(expected_payload, actual_payload)))
            record_min_token_error(status, field.name_token, ERR_ASSIGN_MISMATCH, 0u);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (node >= gParams.n_hir_nodes) return;
    clear_request(node);
    if (!valid_hir(node)) return;

    HirCore core = compact_hir_core[node];
    HirPayload stmt = compact_hir_payload[node];
    if (core.kind == 28u)
    {
        validate_struct_literal_fields(node);
        return;
    }
    if (core.kind != HIR_STMT && core.kind != HIR_LET_STMT &&
        core.kind != HIR_RETURN_STMT && core.kind != HIR_ASSIGN_EXPR)
        return;

    uint expected_tag = TYPE_REF_INVALID;
    uint expected_payload = INVALID;
    uint actual_tag = TYPE_REF_INVALID;
    uint actual_payload = INVALID;
    uint error_token = core.token_start;
    uint expected_node = INVALID;

    if (stmt.a == HIR_STMT_LET ||
        (core.kind == HIR_STMT && stmt.a == HIR_STMT_CONST))
    {
        // An unannotated binding still has an accepted declaration type. Its
        // own dense semantic row carries that nominal identity; an absent
        // annotation row cannot be used as the expected identity.
        expected_node = valid_hir(stmt.d) ? stmt.d : node;
        type_node_ref(stmt.d, expected_tag, expected_payload);
        if (expected_tag == TYPE_REF_INVALID)
            declaration_ref(stmt.b, expected_tag, expected_payload);
        expression_ref(stmt.c, actual_tag, actual_payload);
        if (valid_hir(stmt.c)) error_token = compact_hir_core[stmt.c].token_start;
    }
    else if (stmt.a == HIR_STMT_ASSIGN)
    {
        expected_node = stmt.b;
        expression_ref(stmt.b, expected_tag, expected_payload);
        expression_ref(stmt.c, actual_tag, actual_payload);
        if (valid_hir(stmt.c)) error_token = compact_hir_core[stmt.c].token_start;
    }
    else if (stmt.a == HIR_STMT_RETURN)
    {
        if (!valid_token(core.token_start)) return;
        uint fn = compact_hir_nearest_fn[node];
        if (!valid_hir(fn)) return;
        uint fn_token = compact_hir_payload[fn].b;
        if (!valid_token(fn_token)) return;
        expected_tag = fn_return_ref_tag[fn_token];
        expected_payload = fn_return_ref_payload[fn_token];
        uint return_tag;
        uint return_payload;
        expected_node = compact_fn_return_type[fn];
        type_node_ref(compact_fn_return_type[fn], return_tag, return_payload);
        if (return_tag != TYPE_REF_INVALID)
        {
            expected_tag = return_tag;
            expected_payload = return_payload;
        }
        expression_ref(stmt.b, actual_tag, actual_payload);
        if (valid_hir(stmt.b)) error_token = compact_hir_core[stmt.b].token_start;
    }
    else
        return;

    // Persisted canonical call results are compared with local instances by
    // the dependency call-result relation after generic claims are resolved.
    // This pass remains authoritative for every other representation pair.
    uint expression_node = stmt.a == HIR_STMT_RETURN ? stmt.b : stmt.c;
    if (actual_tag == TYPE_REF_EXTERNAL_CANONICAL &&
        resolved_dependency_call(expression_node))
        return;

    // Let, assignment and return borrow an array as a slice view; codegen
    // captures the descriptor at the value node. Record fields build the
    // view inside the aggregate constructor instead.
    if (expected_tag == TYPE_REF_INSTANCE && actual_tag == TYPE_REF_INSTANCE &&
        expected_payload != actual_payload && valid_hir(expression_node) &&
        array_borrow_matches(expected_payload, actual_payload))
        semantic_argument_mode_by_hir[expression_node] = 4u;

    validate_refs(
        node,
        expected_tag,
        expected_payload,
        actual_tag,
        actual_payload,
        error_token,
        expected_node,
        expression_node);
}
