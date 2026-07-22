// Validate declaration initializers, assignments, and returns from dense
// compact HIR. Scalar compatibility is checked here. Aggregate structure stays
// in the type-instance passes, while this boundary rejects a definite
// aggregate/non-aggregate category mismatch.

import gpu_index;
import status;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> compact_expr_scalar_type;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_return_type_token;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_STMT_LET = 1u;
static const uint HIR_STMT_RETURN = 2u;
static const uint HIR_STMT_CONST = 4u;
static const uint HIR_STMT_ASSIGN = 5u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_VOID = 1u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_INVALID = 0u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint SCALAR_TYPE_SHIFT = 28u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }
uint scalar_type(uint node)
{
    return valid_hir(node) ? compact_expr_scalar_type[node] >> SCALAR_TYPE_SHIFT : TY_UNKNOWN;
}
bool known_scalar(uint ty) { return ty != TY_UNKNOWN && ty <= TY_STRING; }

uint declaration_token(uint token)
{
    if (!valid_token(token)) return INVALID;
    uint decl = visible_decl[token];
    return valid_token(decl) ? decl : token;
}

bool aggregate_decl_ref(uint token)
{
    uint decl = declaration_token(token);
    return valid_token(decl) && decl_type_ref_tag[decl] == TYPE_REF_INSTANCE;
}

bool aggregate_type_node(uint node)
{
    if (!valid_hir(node)) return false;
    uint token = compact_hir_core[node].token_start;
    return valid_token(token) && type_expr_ref_tag[token] == TYPE_REF_INSTANCE;
}

uint scalar_decl_type(uint token)
{
    if (!valid_token(token) || aggregate_decl_ref(token)) return TY_UNKNOWN;
    uint ty = visible_type[token];
    if (known_scalar(ty)) return ty;
    uint decl = visible_decl[token];
    if (valid_token(decl))
    {
        ty = visible_type[decl];
        if (known_scalar(ty)) return ty;
    }
    ty = call_return_type[token];
    return known_scalar(ty) ? ty : TY_UNKNOWN;
}

uint expression_token(uint node)
{
    return valid_hir(node) ? compact_hir_core[node].token_start : INVALID;
}

bool expression_type_ref(uint node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_hir(node)) return false;
    tag = semantic_expr_ref_tag_by_hir[node];
    payload = semantic_expr_ref_payload_by_hir[node];
    return tag != TYPE_REF_INVALID;
}

bool assignable(uint dst, uint src)
{
    if (dst == src) return true;
    if (dst == TY_INT) return src == TY_UINT || src == TY_CHAR;
    if (dst == TY_UINT) return src == TY_INT || src == TY_CHAR;
    if (dst == TY_FLOAT) return src == TY_INT || src == TY_UINT || src == TY_CHAR;
    return false;
}

void validate_pair(uint expected, uint actual, uint error_token)
{
    if (!known_scalar(expected) || !known_scalar(actual) || assignable(expected, actual)) return;
    record_min_token_error(
        status,
        valid_token(error_token) ? error_token : 0u,
        ERR_ASSIGN_MISMATCH,
        expected * 256u + actual);
}

void validate_decl(HirPayload stmt)
{
    // The declaration's compact type node is the authoritative annotation.
    // Symbol visibility may legitimately map a declaration token through a
    // different namespace row, so do not reinterpret aggregate annotations as
    // scalar void while aggregate validation owns the full type relation.
    if (aggregate_type_node(stmt.d)) return;
    uint expected = scalar_decl_type(stmt.b);
    uint actual = scalar_type(stmt.c);
    validate_pair(expected, actual, expression_token(stmt.c));
}

void validate_assignment(HirPayload stmt)
{
    uint target_token = expression_token(stmt.b);
    if (aggregate_decl_ref(target_token)) return;
    validate_pair(scalar_type(stmt.b), scalar_type(stmt.c), expression_token(stmt.c));
}

void validate_return(uint node, HirCore core, HirPayload stmt)
{
    if (!valid_token(core.token_start)) return;
    uint fn = compact_hir_nearest_fn[node];
    if (!valid_hir(fn)) return;
    uint fn_token = compact_hir_payload[fn].b;
    if (!valid_token(fn_token)) return;
    uint expected_ref_tag = fn_return_ref_tag[fn_token];
    uint expected = call_return_type[fn_token];
    if (valid_hir(stmt.b))
    {
        uint actual_scalar = scalar_type(stmt.b);
        uint actual_ref_tag = TYPE_REF_INVALID;
        uint actual_ref_payload = INVALID;
        bool actual_ref_known = known_scalar(actual_scalar) ||
                                expression_type_ref(
                                    stmt.b, actual_ref_tag, actual_ref_payload);
        bool expected_ref_known = expected_ref_tag != TYPE_REF_INVALID ||
                                  known_scalar(expected);
        bool actual_is_instance = !known_scalar(actual_scalar) &&
                                  actual_ref_tag == TYPE_REF_INSTANCE;
        if (expected_ref_known && actual_ref_known &&
            ((expected_ref_tag == TYPE_REF_INSTANCE) != actual_is_instance))
        {
            record_min_token_error(
                status,
                valid_token(expression_token(stmt.b)) ? expression_token(stmt.b) : core.token_start,
                ERR_ASSIGN_MISMATCH,
                0u);
            return;
        }
    }
    if (expected_ref_tag == TYPE_REF_INSTANCE) return;
    if (!known_scalar(expected)) return;

    if (!valid_hir(stmt.b))
    {
        if (expected != TY_VOID && valid_token(call_return_type_token[fn_token]))
            validate_pair(expected, TY_VOID, core.token_start);
        return;
    }
    validate_pair(expected, scalar_type(stmt.b), expression_token(stmt.b));
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(node)) return;
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    if (core.kind != HIR_STMT && core.kind != HIR_LET_STMT &&
        core.kind != HIR_RETURN_STMT && core.kind != HIR_ASSIGN_EXPR)
        return;

    if (payload.a == HIR_STMT_LET ||
        (core.kind == HIR_STMT && payload.a == HIR_STMT_CONST))
        validate_decl(payload);
    else if (payload.a == HIR_STMT_ASSIGN)
        validate_assignment(payload);
    else if (payload.a == HIR_STMT_RETURN)
        validate_return(node, core, payload);
}
