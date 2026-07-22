// Validate boolean control conditions and logical operands from dense compact
// HIR after scalar expression types have reached their pointer-jump fixed
// point. No raw parser node or token scan participates in this pass.

import gpu_index;
import status;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_hir_nearest_loop;
StructuredBuffer<uint> compact_expr_scalar_type;
StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
StructuredBuffer<uint> type_instance_kind;
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
static const uint HIR_STMT_IF = 3u;
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
static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_BAD_HIR = 6u;
static const uint ERR_LOOP_CONTROL = 7u;
static const uint SCALAR_TYPE_SHIFT = 28u;
static const uint DISPATCH_X_STRIDE = 16776960u;

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
    return ty == TY_UNKNOWN || ty == TY_INT || ty == TY_UINT || ty == TY_CHAR;
}

bool numeric_operand_ok(uint ty)
{
    return ty == TY_UNKNOWN || ty == TY_INT || ty == TY_UINT ||
           ty == TY_FLOAT || ty == TY_CHAR;
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
    if (!binary_operand_ok(form, left_ty))
    {
        record_mismatch(payload.b, form);
        return;
    }
    uint right_ty = scalar_type(payload.c);
    if (!binary_operand_ok(form, right_ty)) record_mismatch(payload.c, form);
}

bool instance_is_array_or_slice(uint node)
{
    if (!valid_hir(node) || semantic_expr_ref_tag_by_hir[node] != TYPE_REF_INSTANCE)
        return false;
    uint instance = semantic_expr_ref_payload_by_hir[node];
    if (instance == INVALID || instance >= gParams.n_tokens) return false;
    uint kind = type_instance_kind[instance];
    return kind == TYPE_INSTANCE_ARRAY || kind == TYPE_INSTANCE_SLICE;
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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(node)) return;

    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    validate_loop_control(node, core);
    if (core.kind == HIR_INDEX_EXPR) validate_index(node, payload);
    if (core.kind == HIR_BINARY_EXPR) validate_binary(node, payload);
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
