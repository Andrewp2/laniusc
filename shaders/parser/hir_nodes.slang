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
StructuredBuffer<uint> ll1_status;

RWStructuredBuffer<uint> hir_kind;
RWStructuredBuffer<uint> hir_token_pos;

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

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHir.uses_ll1 != 0u ? min(gHir.n, ll1_status[5u]) : gHir.n;
}

uint classify(uint prod)
{
    if (prod == 0u)
        return HIR_FILE;
    if ((prod >= 3u && prod <= 11u) || prod == 171u || prod == 173u || prod == 196u ||
        (prod >= 203u && prod <= 210u))
        return HIR_ITEM;
    if (prod == 12u)
        return HIR_FN;
    if (prod == 46u)
        return HIR_PARAM;
    if (prod == 49u || prod == 50u || prod == 220u)
        return HIR_TYPE;
    if (prod == 51u || prod == 65u)
        return HIR_BLOCK;
    if (prod == 52u || prod == 53u || prod == 61u || prod == 62u)
        return HIR_STMT;
    if (prod == 54u)
        return HIR_LET_STMT;
    if (prod == 55u)
        return HIR_RETURN_STMT;
    if (prod == 56u)
        return HIR_IF_STMT;
    if (prod == 57u)
        return HIR_WHILE_STMT;
    if (prod == 59u)
        return HIR_BREAK_STMT;
    if (prod == 60u)
        return HIR_CONTINUE_STMT;
    if (prod == 72u || prod == 155u)
        return HIR_EXPR;
    if ((prod >= 74u && prod <= 85u))
        return HIR_ASSIGN_EXPR;
    if ((prod >= 86u && prod <= 123u))
        return HIR_BINARY_EXPR;
    if ((prod >= 124u && prod <= 130u) || prod == 135u || prod == 136u)
        return HIR_UNARY_EXPR;
    if (prod == 131u || prod == 137u)
        return HIR_POSTFIX_EXPR;
    if (prod == 132u)
        return HIR_CALL_EXPR;
    if (prod == 133u)
        return HIR_INDEX_EXPR;
    if (prod == 134u)
        return HIR_MEMBER_EXPR;
    if (prod == 142u)
        return HIR_ARRAY_EXPR;
    if (prod == 144u)
        return HIR_NAME_EXPR;
    if ((prod >= 145u && prod <= 148u) || prod == 153u || prod == 154u)
        return HIR_LITERAL_EXPR;
    if (prod == 172u)
        return HIR_CONST_ITEM;
    if (prod == 14u)
        return HIR_TYPE_ALIAS_ITEM;
    if (prod == 174u)
        return HIR_ENUM_ITEM;
    if (prod == 197u)
        return HIR_STRUCT_ITEM;
    if (prod == 212u)
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
}
