// Seed one checked scalar result-type record per dense compact-HIR expression.
//
// Leaves consume type-checker facts directly. Operators whose result type is
// inherited link to an operand; the following pointer-jump pass resolves every
// chain in logarithmic parallel steps. Comparisons retain their bool result
// while backends can read the checked type of their operand rows.

import hir_records;
import gpu_index;
import checked_semantic_artifact;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;
StructuredBuffer<uint> call_generic_return_arg_node;
RWStructuredBuffer<uint> compact_expr_scalar_type_out;

static const uint INVALID = 0xffffffffu;
static const uint HIR_EXPR = 14u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_MATCH_EXPR = 34u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_NE = 8u;
static const uint HIR_EXPR_LT = 9u;
static const uint HIR_EXPR_GT = 10u;
static const uint HIR_EXPR_LE = 11u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_NEG = 13u;
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
static const uint HIR_EXPR_FLOAT = 27u;
static const uint HIR_EXPR_STRING = 28u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRING = 7u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint SCALAR_TYPE_SHIFT = 28u;
static const uint SCALAR_TYPE_LINK_MASK = 0x0fffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

uint checked_scalar_type(uint ty)
{
    return ty <= 8u ? ty : TY_UNKNOWN;
}

uint visible_type_for_token(uint token)
{
    if (!valid_token(token)) return TY_UNKNOWN;
    uint ty = checked_scalar_type(visible_type[token]);
    if (ty != TY_UNKNOWN) return ty;
    uint decl = visible_decl[token];
    if (valid_token(decl))
    {
        ty = checked_scalar_type(visible_type[decl]);
        if (ty != TY_UNKNOWN) return ty;
    }
    return checked_scalar_type(call_return_type[token]);
}

uint compact_call_result_type(uint call)
{
    return valid_hir(call)
               ? checked_scalar_type(semantic_calls_by_hir[call].return_type)
               : TY_UNKNOWN;
}

uint name_token_for_hir(uint node)
{
    if (!valid_hir(node)) return INVALID;
    uint kind = compact_hir_core[node].kind;
    if (kind != HIR_NAME_EXPR && kind != HIR_PATH_EXPR) return INVALID;
    uint token = compact_hir_payload[node].d;
    return valid_token(token) ? token : INVALID;
}

uint scalar_type_from_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR) return checked_scalar_type(payload);
    if (tag == TYPE_REF_GENERIC_PARAM && valid_token(payload))
    {
        uint slot = type_generic_param_slot_by_token[payload];
        return slot == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + slot;
    }
    return TY_UNKNOWN;
}

uint compact_index_result_type(uint index_node)
{
    if (!valid_hir(index_node) || compact_hir_core[index_node].kind != HIR_INDEX_EXPR)
        return TY_UNKNOWN;
    uint base = compact_hir_payload[index_node].b;
    uint token = name_token_for_hir(base);
    uint decl = valid_token(token) ? visible_decl[token] : INVALID;
    if (!valid_token(decl) || decl_type_ref_tag[decl] != TYPE_REF_INSTANCE)
        return TY_UNKNOWN;
    uint instance = decl_type_ref_payload[decl];
    if (!valid_token(instance)) return TY_UNKNOWN;
    uint kind = type_instance_kind[instance];
    if (kind != TYPE_INSTANCE_ARRAY && kind != TYPE_INSTANCE_SLICE)
        return TY_UNKNOWN;
    return scalar_type_from_ref(
        type_instance_elem_ref_tag[instance],
        type_instance_elem_ref_payload[instance]);
}

uint pack_scalar_type(uint ty, uint link)
{
    uint packed_link = valid_hir(link) && link < SCALAR_TYPE_LINK_MASK
                           ? link
                           : SCALAR_TYPE_LINK_MASK;
    return (checked_scalar_type(ty) << SCALAR_TYPE_SHIFT) | packed_link;
}

bool inherited_scalar_form(uint form)
{
    return form == HIR_EXPR_NEG || form == HIR_EXPR_ADD ||
           form == HIR_EXPR_SUB || form == HIR_EXPR_MUL ||
           form == HIR_EXPR_MOD || form == HIR_EXPR_DIV ||
           form == HIR_EXPR_BIT_OR || form == HIR_EXPR_BIT_XOR ||
           form == HIR_EXPR_BIT_AND || form == HIR_EXPR_SHL ||
           form == HIR_EXPR_SHR;
}

uint direct_result_type(uint node)
{
    if (!valid_hir(node)) return TY_UNKNOWN;
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    // Payload lanes are a kind-specific union. A call's payload.a is a dense
    // callee HIR ID, a member's payload.a is its member form, and an ordinary
    // expression's payload.a is an expression form. Always classify the node
    // before interpreting that lane; numeric overlap between a dense HIR ID
    // and an expression-form tag must never affect semantics.
    if (core.kind == HIR_CALL_EXPR)
        return compact_call_result_type(node);
    if (core.kind == HIR_NAME_EXPR)
        return visible_type_for_token(payload.d);
    if (core.kind == HIR_MEMBER_EXPR)
        return visible_type_for_token(payload.c);
    if (core.kind == HIR_INDEX_EXPR)
        return compact_index_result_type(node);
    if (core.kind == HIR_MATCH_EXPR)
        return visible_type_for_token(core.token_start);

    uint form = payload.a;
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE || form == HIR_EXPR_NOT ||
        form == HIR_EXPR_EQ || form == HIR_EXPR_NE || form == HIR_EXPR_LT ||
        form == HIR_EXPR_GT || form == HIR_EXPR_LE || form == HIR_EXPR_GE ||
        form == HIR_EXPR_AND || form == HIR_EXPR_OR)
        return TY_BOOL;
    if (form == HIR_EXPR_INT) return TY_INT;
    if (form == HIR_EXPR_FLOAT) return TY_FLOAT;
    if (form == HIR_EXPR_STRING) return TY_STRING;
    if (form == HIR_EXPR_NAME)
        return visible_type_for_token(payload.d);
    return TY_UNKNOWN;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (!valid_hir(node)) return;
    if (compact_hir_core[node].kind == HIR_CALL_EXPR)
    {
        uint call_link = call_generic_return_arg_node[node];
        if (valid_hir(call_link) && call_link != node)
        {
            compact_expr_scalar_type_out[node] =
                pack_scalar_type(TY_UNKNOWN, call_link);
            return;
        }
    }
    uint ty = direct_result_type(node);
    if (ty != TY_UNKNOWN)
    {
        compact_expr_scalar_type_out[node] = pack_scalar_type(ty, INVALID);
        return;
    }
    HirPayload payload = compact_hir_payload[node];
    uint link = inherited_scalar_form(payload.a) &&
                        valid_hir(payload.b) && payload.b != node
                    ? payload.b
                    : INVALID;
    compact_expr_scalar_type_out[node] = pack_scalar_type(TY_UNKNOWN, link);
}
