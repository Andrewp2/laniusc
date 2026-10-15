import primitive_types;
import integer_words;
// Validate boolean control conditions and logical operands from dense compact
// HIR after scalar expression types have reached their pointer-jump fixed
// point. No raw parser node or token scan participates in this pass.

import hir_records;
import hir_expr_semantics;
import gpu_index;
import status;
import type_checker.checked_index_reference;
import type_checker.argument_context;
import type_checker.float_literal_selection;
import type_checker.owned_literal_context;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirSemanticFacts> compact_hir_semantic_facts;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> compact_hir_nearest_loop;
StructuredBuffer<uint> compact_hir_expr_parent;
StructuredBuffer<uint> compact_const_value;
StructuredBuffer<uint> compact_const_type;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> compact_expr_scalar_type;
StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint HIR_STMT = 7u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_BREAK_STMT = 12u;
static const uint HIR_CONTINUE_STMT = 13u;
static const uint HIR_EXPR = 14u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_STMT_IF = 3u;
static const uint HIR_STMT_FOR = 7u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_NE = 8u;
static const uint HIR_EXPR_LT = 9u;
static const uint HIR_EXPR_GT = 10u;
static const uint HIR_EXPR_LE = 11u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_ADD = 14u;
static const uint HIR_EXPR_SUB = 15u;
static const uint HIR_EXPR_MUL = 16u;
static const uint HIR_EXPR_AND = 17u;
static const uint HIR_EXPR_OR = 18u;
static const uint HIR_EXPR_MOD = 19u;
static const uint HIR_EXPR_DIV = 20u;
static const uint HIR_EXPR_BIT_OR = 21u;
static const uint HIR_EXPR_BIT_XOR = 22u;
static const uint HIR_EXPR_BIT_AND = 23u;
static const uint HIR_EXPR_SHL = 24u;
static const uint HIR_EXPR_SHR = 25u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_CAST = 36u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_POINTER = 8u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_BAD_HIR = 6u;
static const uint ERR_LOOP_CONTROL = 7u;
static const uint ERR_INTEGER_LITERAL_RANGE = 24u;
static const uint ERR_FLOAT_LITERAL = 25u;
static const uint ERR_COMPUTED_FLOAT_CONSTANT = 26u;
static const uint ERR_INVALID_CAST = 27u;
static const uint DISPATCH_X_STRIDE = 16776960u;

[ForceInline]
uint active_hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
uint scalar_type(uint node)
{
    return valid_hir(node) ? compact_expr_scalar_type[node] >> SCALAR_TYPE_SHIFT : TY_UNKNOWN;
}

void record_bool_mismatch(uint node, uint ty)
{
    if (ty == TY_UNKNOWN || ty == TY_BOOL) return;
    uint token = valid_hir(node) ? compact_hir_core[node].token_start : 0u;
    record_min_token_error(status, token, ERR_ASSIGN_MISMATCH, TY_BOOL * 256u + ty);
}

bool is_array_type(uint ty)
{
    return (ty >= TY_ARRAY_BASE && ty < TY_STRUCT_BASE) ||
           ty >= TY_ARRAY_BASE + TY_GENERIC_BASE;
}

bool assignable_to_int(uint ty)
{
    return ty == TY_UNKNOWN || scalar_is_integer(ty);
}

bool numeric_operand_ok(uint ty)
{
    return ty == TY_UNKNOWN || scalar_is_integer(ty) || scalar_is_float(ty);
}

bool integer_operand_ok(uint ty) { return assignable_to_int(ty); }
bool equality_operand_ok(uint ty)
{
    return ty == TY_UNKNOWN || (!is_array_type(ty) && ty != TY_STRING);
}

bool integer_binary(uint form)
{
    return form == HIR_EXPR_MOD || form == HIR_EXPR_BIT_OR ||
           form == HIR_EXPR_BIT_XOR || form == HIR_EXPR_BIT_AND ||
           form == HIR_EXPR_SHL || form == HIR_EXPR_SHR;
}

bool numeric_binary(uint form)
{
    return form == HIR_EXPR_ADD || form == HIR_EXPR_SUB ||
           form == HIR_EXPR_MUL || form == HIR_EXPR_DIV ||
           form == HIR_EXPR_LT || form == HIR_EXPR_GT ||
           form == HIR_EXPR_LE || form == HIR_EXPR_GE;
}

bool equality_binary(uint form)
{
    return form == HIR_EXPR_EQ || form == HIR_EXPR_NE;
}

bool binary_operand_ok(uint form, uint ty)
{
    if (integer_binary(form)) return integer_operand_ok(ty);
    if (numeric_binary(form)) return numeric_operand_ok(ty);
    if (equality_binary(form)) return equality_operand_ok(ty);
    return true;
}

bool pointer_offset_binary(uint form, uint left_ty, uint right_ty)
{
    return (form == HIR_EXPR_ADD || form == HIR_EXPR_SUB) &&
        left_ty == TY_POINTER && assignable_to_int(right_ty);
}

bool null_pointer_constant(uint node)
{
    return valid_hir(node) && compact_hir_payload[node].a == HIR_EXPR_INT &&
        compact_hir_payload[node].b == 0u && compact_hir_payload[node].c == 0u;
}

bool pointer_equality_ok(uint form, HirPayload payload, uint left_ty, uint right_ty)
{
    if (!equality_binary(form) ||
        (left_ty != TY_POINTER && right_ty != TY_POINTER)) return false;
    return (left_ty == TY_POINTER && right_ty == TY_POINTER) ||
        (left_ty == TY_POINTER && right_ty == TY_INT && null_pointer_constant(payload.c)) ||
        (right_ty == TY_POINTER && left_ty == TY_INT && null_pointer_constant(payload.b));
}

void record_mismatch(uint node, uint detail)
{
    uint token = valid_hir(node) ? compact_hir_core[node].token_start : 0u;
    record_min_token_error(status, token, ERR_ASSIGN_MISMATCH, detail);
}

void validate_binary(uint node, HirPayload payload)
{
    uint form = payload.a;
    if (!integer_binary(form) && !numeric_binary(form) && !equality_binary(form)) return;
    uint left_ty = scalar_type(payload.b);
    uint right_ty = scalar_type(payload.c);
    if (pointer_offset_binary(form, left_ty, right_ty)) return;
    if (pointer_equality_ok(form, payload, left_ty, right_ty)) return;
    if (equality_binary(form) &&
        (left_ty == TY_POINTER || right_ty == TY_POINTER))
    {
        record_mismatch(left_ty == TY_POINTER ? payload.c : payload.b, form);
        return;
    }
    if (!binary_operand_ok(form, left_ty))
    {
        record_mismatch(payload.b, form);
        return;
    }
    if (!binary_operand_ok(form, right_ty)) { record_mismatch(payload.c, form); return; }
    // Integer widths and signedness are checked type identity. Only an
    // unsuffixed literal can take the opposite operand's type via context.
    bool shift = form == HIR_EXPR_SHL || form == HIR_EXPR_SHR;
    if (!shift && left_ty != TY_UNKNOWN && right_ty != TY_UNKNOWN && left_ty != right_ty)
        record_mismatch(payload.c, left_ty * 256u + right_ty);
}

bool instance_is_array_or_slice(uint node)
{
    if (!valid_hir(node)) return false;
    uint tag = semantic_expr_ref_tag_by_hir[node];
    uint instance = semantic_expr_ref_payload_by_hir[node];
    if (tag != TYPE_REF_INSTANCE)
    {
        // Nested indexing can retain a stale scalar cache from its base.
        // The complete checked named projection establishes its result kind.
        if (!checked_named_index_reference(node, active_hir_count(), gParams.n_tokens,
            compact_hir_core, compact_hir_payload, visible_decl, decl_type_ref_tag,
            decl_type_ref_payload, type_instance_kind, type_instance_elem_ref_tag,
            type_instance_elem_ref_payload, tag, instance) || tag != TYPE_REF_INSTANCE)
            return false;
    }
    // Admission depends on the referent container, while the base expression
    // keeps its reference type for storage and call/assignment checking.
    uint container;
    return checked_index_container(tag, instance, type_instance_kind,
        type_instance_elem_ref_tag, type_instance_elem_ref_payload, container);
}

void validate_index(uint node, HirPayload payload)
{
    uint base_ty = scalar_type(payload.b);
    if (base_ty != TY_UNKNOWN && !is_array_type(base_ty) &&
        !instance_is_array_or_slice(payload.b))
    {
        record_mismatch(node, base_ty);
        return;
    }
    uint index_ty = scalar_type(payload.c);
    if (!assignable_to_int(index_ty))
        record_mismatch(payload.c, TY_INT * 256u + index_ty);
}

bool cast_numeric(uint ty) { return scalar_is_integer(ty) || scalar_is_float(ty); }

// `value as T` converts between integer and floating scalars and from bool to
// an integer. payload.b is the operand and payload.d the target type's first
// token, where the type collector publishes its checked reference; the `as`
// token is just before it. The detail packs (source << 16) | target, with 0
// for a type that is not a primitive scalar.
void validate_cast(uint node, HirPayload payload)
{
    uint target_token = payload.d;
    if (target_token == 0u || target_token >= gParams.n_tokens) return;
    uint target_tag = type_expr_ref_tag[target_token];
    // An unresolved target type reports its own error.
    if (target_tag == 0u) return;
    uint target = target_tag == TYPE_REF_SCALAR ? type_expr_ref_payload[target_token] : TY_UNKNOWN;
    uint source = scalar_type(payload.b);
    if (source == TY_UNKNOWN)
    {
        if (!valid_hir(payload.b)) return;
        uint source_tag = semantic_expr_ref_tag_by_hir[payload.b];
        // An operand with no checked type reports its own error.
        if (source_tag == 0u) return;
        source = source_tag == TYPE_REF_SCALAR ? semantic_expr_ref_payload_by_hir[payload.b] : TY_UNKNOWN;
    }
    if (cast_numeric(target) &&
        (cast_numeric(source) || (source == TY_BOOL && scalar_is_integer(target)))) return;
    uint source_code = scalar_is_known(source) ? source : 0u;
    uint target_code = scalar_is_known(target) ? target : 0u;
    record_min_token_error(status, target_token - 1u, ERR_INVALID_CAST,
        (source_code << 16u) | target_code);
}

// Type-only generic applications need not run expression inference rounds.
// Their accepted operand role still owns the literal's exact diagnostic width.
uint checked_literal_scalar(uint node)
{
    uint owned = checked_owned_numeric_literal_context(node, active_hir_count(), gParams.n_tokens,
        compact_hir_core, compact_hir_payload, compact_hir_expr_parent, compact_const_type,
        compact_const_value, type_expr_ref_tag, type_expr_ref_payload);
    return owned != 0u ? owned : scalar_type(node);
}

bool literal_is_under_unary_minus(uint node)
{
    // Forwarding wrappers do not change which unary expression owns a
    // magnitude. This agrees with the source operand decoder for signed minima.
    for (uint step = 0u; step < active_hir_count() && valid_hir(node); step++)
    {
        uint parent = compact_hir_expr_parent[node];
        if (!valid_hir(parent) || parent == node) return false;
        HirCore core = compact_hir_core[parent];
        HirPayload payload = compact_hir_payload[parent];
        if (payload.b != node) return false;
        if (core.kind == HIR_UNARY_EXPR && payload.a == 13u) return true;
        if (!hir_is_forward_expression(core.kind, payload.a)) return false;
        node = parent;
    }
    return false;
}

void validate_integer_literal(uint node, HirCore core, HirPayload value)
{
    if (core.kind != 23u || value.a != HIR_EXPR_INT) return;
    uint type = checked_literal_scalar(node);
    if (!scalar_is_integer(type)) return;
    // Magnitude2^(bits-1) is admitted only beneath unary minus, where it
    // represents the signed minimum. The literal bits themselves stay intact.
    bool negative = literal_is_under_unary_minus(node);
    if (!integer_words_magnitude_fits(uint2(value.b, value.c), type, negative))
        record_min_token_error(status, core.token_start, ERR_INTEGER_LITERAL_RANGE, type);
}

void validate_float_literal(uint node, HirCore core, HirPayload value)
{
    if (core.kind != 23u || value.a != 27u) return;
    uint type = checked_literal_scalar(node);
    uint result;
    if (!selected_float_literal_status(compact_hir_semantic_facts[node].literal_status, type, result)) return;
    if (result != 0u)
        record_min_token_error(status, core.token_start, ERR_FLOAT_LITERAL,
            (type << 8u) | result);
}

// Absence of a function owner does not make a row a constant expression:
// module paths and declaration/type names also live outside functions. Check
// the parser-owned initializer and expression edges before rejecting a value.
bool module_constant_initializer_contains(uint node)
{
    uint count = active_hir_count();
    uint ancestor = compact_hir_core[node].parent;
    for (uint step = 0u; step < count && valid_hir(ancestor); step++)
    {
        HirCore owner = compact_hir_core[ancestor];
        if (owner.kind == 25u)
        {
            uint initializer = argument_context_root(compact_const_value[ancestor],
                count, compact_hir_core, compact_hir_payload);
            uint current = node;
            for (uint edge = 0u; edge < count && valid_hir(current); edge++)
            {
                if (current == initializer) return true;
                uint parent = compact_hir_expr_parent[current];
                if (parent == current) return false;
                current = parent;
            }
            return false;
        }
        if (owner.kind == 3u || owner.kind == 1u || owner.parent == ancestor) return false;
        ancestor = owner.parent;
    }
    return false;
}

void validate_computed_float_constant(uint node, HirCore core, HirPayload value)
{
    if (compact_hir_nearest_fn[node] != INVALID) return;
    bool binary = core.kind == HIR_BINARY_EXPR && scalar_is_float(scalar_type(value.b));
    bool reference = (core.kind == 22u || core.kind == 33u) && scalar_is_float(scalar_type(node));
    if ((!binary && !reference) || !module_constant_initializer_contains(node)) return;
    // Literals, forwarding, and unary sign changes have exact integer-bit
    // evaluation. Float arithmetic and constant-reference DAGs need the
    // portable IEEE evaluator before they can become exported constants.
    record_min_token_error(status, core.token_start, ERR_COMPUTED_FLOAT_CONSTANT,
        binary ? value.a : 0u);
}

void validate_loop_control(uint node, HirCore core)
{
    if (core.kind != HIR_BREAK_STMT && core.kind != HIR_CONTINUE_STMT) return;
    if (core.token_start >= gParams.n_tokens)
    {
        record_min_token_error(status, 0u, ERR_BAD_HIR, core.kind);
        return;
    }
    if (!valid_hir(compact_hir_nearest_loop[node]))
        record_min_token_error(status, core.token_start, ERR_LOOP_CONTROL, core.kind);
}

uint range_value_root(uint node)
{
    for (uint step = 0u; step < active_hir_count() && valid_hir(node); step++)
    {
        HirCore core = compact_hir_core[node];
        HirPayload value = compact_hir_payload[node];
        if (!hir_is_forward_expression(core.kind, value.a)) return node;
        if (value.b == node) return INVALID;
        node = value.b;
    }
    return INVALID;
}

void validate_range_endpoint(uint endpoint, uint expected, uint statement)
{
    endpoint = range_value_root(endpoint);
    if (!valid_hir(endpoint))
    {
        record_mismatch(statement, expected * 256u + TY_UNKNOWN);
        return;
    }
    uint tag = semantic_expr_ref_tag_by_hir[endpoint];
    uint actual = tag == TYPE_REF_SCALAR
        ? semantic_expr_ref_payload_by_hir[endpoint] : TY_UNKNOWN;
    // Inference is closed here. Missing, noninteger, and differently sized
    // or signed accepted references are errors, never implicit conversions.
    if (tag != TYPE_REF_SCALAR || !scalar_is_integer(actual) || actual != expected)
        record_mismatch(endpoint, expected * 256u + actual);
}

void validate_direct_range(uint node, HirCore core, HirPayload statement)
{
    if ((core.kind != HIR_FOR_STMT && core.kind != HIR_STMT) ||
        statement.a != HIR_STMT_FOR) return;
    uint iterable = range_value_root(statement.c);
    uint binding_tag = statement.b < gParams.n_tokens ? decl_type_ref_tag[statement.b] : 0u;
    uint binding_payload = statement.b < gParams.n_tokens ? decl_type_ref_payload[statement.b] : INVALID;
    // Unsupported or unresolved iterables have no accepted binder contract.
    // Reject them here instead of allowing lowering to guess an integer.
    if (!valid_hir(iterable) || binding_tag < 1u || binding_tag > 3u || binding_payload == INVALID)
    {
        record_mismatch(node, TY_UNKNOWN);
        return;
    }
    HirCore iterable_core = compact_hir_core[iterable];
    HirPayload range = compact_hir_payload[iterable];
    if ((iterable_core.kind != HIR_EXPR && iterable_core.kind != HIR_BINARY_EXPR) ||
        range.a < 30u || range.a > 35u) return;
    uint expected_tag = statement.b < gParams.n_tokens
        ? decl_type_ref_tag[statement.b] : 0u;
    uint expected = expected_tag == TYPE_REF_SCALAR
        ? decl_type_ref_payload[statement.b] : TY_UNKNOWN;
    if (expected_tag != TYPE_REF_SCALAR || !scalar_is_integer(expected))
    {
        record_mismatch(node, expected);
        return;
    }
    if (range.a == 33u)
    {
        // An entirely unbounded range has no typed endpoint; its binder uses
        // the ordinary unsuffixed integer default.
        if (expected != TY_INT) record_mismatch(node, TY_INT * 256u + expected);
        return;
    }
    if (range.a == 30u || range.a == 31u || range.a == 34u)
        validate_range_endpoint(range.b, expected, node);
    if (range.a == 30u || range.a == 32u || range.a == 34u || range.a == 35u)
        validate_range_endpoint(range.c, expected, node);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(node)) return;

    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    validate_loop_control(node, core);
    validate_integer_literal(node, core, payload);
    validate_float_literal(node, core, payload);
    validate_computed_float_constant(node, core, payload);
    validate_direct_range(node, core, payload);
    if (core.kind == HIR_INDEX_EXPR) validate_index(node, payload);
    if (core.kind == HIR_BINARY_EXPR)
    {
        if (payload.a == HIR_EXPR_CAST) validate_cast(node, payload);
        else validate_binary(node, payload);
    }
    if (core.kind == HIR_IF_STMT ||
        (core.kind == HIR_STMT && payload.a == HIR_STMT_IF))
        record_bool_mismatch(payload.b, scalar_type(payload.b));

    if (core.kind != HIR_EXPR && core.kind != HIR_BINARY_EXPR &&
        core.kind != HIR_UNARY_EXPR)
        return;
    if (payload.a != HIR_EXPR_NOT && payload.a != HIR_EXPR_AND &&
        payload.a != HIR_EXPR_OR)
        return;

    record_bool_mismatch(payload.b, scalar_type(payload.b));
    if (payload.a != HIR_EXPR_NOT)
        record_bool_mismatch(payload.c, scalar_type(payload.c));
}
