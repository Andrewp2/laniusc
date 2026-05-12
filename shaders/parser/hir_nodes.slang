// Classify parse productions into coarse HIR-facing node kinds.
//
// This pass is intentionally one thread per production node. It does not lower
// the full tree yet; it creates the stable GPU-side bridge that later type and
// codegen passes can consume instead of rediscovering structure from tokens.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHir;

StructuredBuffer<uint> emit_stream;
StructuredBuffer<uint> emit_pos;
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint> ll1_status;

RWStructuredBuffer<uint> hir_kind;
RWStructuredBuffer<uint> hir_token_pos;
RWStructuredBuffer<uint> hir_token_file_id;

static const uint INVALID = 0xFFFFFFFFu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_NONE = 0u;
static const uint HIR_FILE = 1u;
static const uint HIR_ITEM = 2u;
static const uint HIR_FN = 3u;
static const uint HIR_PARAM = 4u;
static const uint HIR_TYPE = 5u;
static const uint HIR_BLOCK = 6u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_BREAK_STMT = 12u;
static const uint HIR_CONTINUE_STMT = 13u;
static const uint HIR_EXPR = 14u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_POSTFIX_EXPR = 18u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_CONST_ITEM = 25u;
static const uint HIR_ENUM_ITEM = 26u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_TYPE_ALIAS_ITEM = 29u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_MODULE_ITEM = 31u;
static const uint HIR_IMPORT_ITEM = 32u;
static const uint HIR_PATH_EXPR = 33u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHir.uses_ll1 != 0u ? min(gHir.n, ll1_status[5u]) : gHir.n;
}

uint hir_file_for_emit_pos(uint token_i)
{
    return token_i < gHir.n ? token_file_id[token_i] : INVALID;
}

uint classify(uint prod)
{
    if (prod == 0u)
        return HIR_FILE;
    if ((prod >= 3u && prod <= 11u) || prod == 191u || prod == 193u || prod == 231u ||
        (prod >= 240u && prod <= 247u))
        return HIR_ITEM;
    if (prod == 12u || prod == 13u)
        return HIR_FN;
    if (prod == 42u)
        return HIR_IMPORT_ITEM;
    if (prod == 45u)
        return HIR_MODULE_ITEM;
    if (prod == 46u)
        return HIR_PATH_EXPR;
    if (prod >= 53u && prod <= 55u)
        return HIR_PARAM;
    if (prod == 60u || prod == 61u || prod == 259u)
        return HIR_TYPE;
    if (prod == 62u || prod == 76u)
        return HIR_BLOCK;
    if (prod == 63u || prod == 64u || prod == 72u || prod == 73u)
        return HIR_STMT;
    if (prod == 65u)
        return HIR_LET_STMT;
    if (prod == 66u)
        return HIR_RETURN_STMT;
    if (prod == 67u)
        return HIR_IF_STMT;
    if (prod == 68u)
        return HIR_WHILE_STMT;
    if (prod == 69u)
        return HIR_FOR_STMT;
    if (prod == 70u)
        return HIR_BREAK_STMT;
    if (prod == 71u)
        return HIR_CONTINUE_STMT;
    if (prod == 83u || prod == 171u)
        return HIR_EXPR;
    if ((prod >= 85u && prod <= 96u))
        return HIR_ASSIGN_EXPR;
    if ((prod >= 97u && prod <= 134u))
        return HIR_BINARY_EXPR;
    if ((prod >= 135u && prod <= 141u) || prod == 146u || prod == 147u)
        return HIR_UNARY_EXPR;
    if (prod == 142u || prod == 148u)
        return HIR_POSTFIX_EXPR;
    if (prod == 143u)
        return HIR_CALL_EXPR;
    if (prod == 144u)
        return HIR_INDEX_EXPR;
    if (prod == 145u)
        return HIR_MEMBER_EXPR;
    if (prod == 155u)
        return HIR_ARRAY_EXPR;
    if (prod == 157u || prod == 179u)
        return HIR_NAME_EXPR;
    if ((prod >= 159u && prod <= 162u) || prod == 169u || prod == 170u ||
        (prod >= 180u && prod <= 182u))
        return HIR_LITERAL_EXPR;
    if (prod == 192u)
        return HIR_CONST_ITEM;
    if (prod == 14u)
        return HIR_TYPE_ALIAS_ITEM;
    if (prod == 194u)
        return HIR_ENUM_ITEM;
    if (prod == 232u)
        return HIR_STRUCT_ITEM;
    if (prod == 249u)
        return HIR_STRUCT_LITERAL_EXPR;
    return HIR_NONE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_node_count())
        return;

    hir_kind[i] = classify(emit_stream[i]);
    hir_token_pos[i] = emit_pos[i];
    hir_token_file_id[i] = hir_file_for_emit_pos(emit_pos[i]);
}
