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
    if ((prod >= 3u && prod <= 7u) || prod == 146u || prod == 148u || prod == 171u ||
        (prod >= 178u && prod <= 180u))
        return HIR_ITEM;
    if (prod == 8u)
        return HIR_FN;
    if (prod == 22u)
        return HIR_PARAM;
    if (prod == 25u || prod == 26u || prod == 190u)
        return HIR_TYPE;
    if (prod == 27u || prod == 36u || prod == 40u)
        return HIR_BLOCK;
    if (prod == 28u || prod == 29u || prod == 37u)
        return HIR_STMT;
    if (prod == 30u)
        return HIR_LET_STMT;
    if (prod == 31u)
        return HIR_RETURN_STMT;
    if (prod == 32u)
        return HIR_IF_STMT;
    if (prod == 33u)
        return HIR_WHILE_STMT;
    if (prod == 34u)
        return HIR_BREAK_STMT;
    if (prod == 35u)
        return HIR_CONTINUE_STMT;
    if (prod == 47u || prod == 130u)
        return HIR_EXPR;
    if ((prod >= 49u && prod <= 60u))
        return HIR_ASSIGN_EXPR;
    if ((prod >= 62u && prod <= 98u))
        return HIR_BINARY_EXPR;
    if ((prod >= 99u && prod <= 105u) || prod == 110u || prod == 111u)
        return HIR_UNARY_EXPR;
    if (prod == 106u || prod == 112u)
        return HIR_POSTFIX_EXPR;
    if (prod == 107u)
        return HIR_CALL_EXPR;
    if (prod == 108u)
        return HIR_INDEX_EXPR;
    if (prod == 109u)
        return HIR_MEMBER_EXPR;
    if (prod == 117u)
        return HIR_ARRAY_EXPR;
    if (prod == 119u)
        return HIR_NAME_EXPR;
    if ((prod >= 120u && prod <= 123u) || prod == 128u || prod == 129u)
        return HIR_LITERAL_EXPR;
    if (prod == 147u)
        return HIR_CONST_ITEM;
    if (prod == 149u)
        return HIR_ENUM_ITEM;
    if (prod == 172u)
        return HIR_STRUCT_ITEM;
    if (prod == 182u)
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
