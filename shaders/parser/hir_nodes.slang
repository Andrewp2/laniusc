// Classify parse productions into coarse HIR-facing node kinds.
//
// This pass is intentionally one thread per production node. It does not lower
// the full tree yet; it creates the stable GPU-side bridge that later type and
// codegen passes can consume instead of rediscovering structure from tokens.

import generated_parse_production_ids;

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
static const uint HIR_MATCH_EXPR = 34u;

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
    if (prod == PROD_FILE)
        return HIR_FILE;
    if (prod == PROD_ITEM_PUB || prod == PROD_ITEM_FN || prod == PROD_ITEM_EXTERN_FN ||
        prod == PROD_ITEM_IMPORT || prod == PROD_ITEM_MODULE ||
        prod == PROD_ITEM_TYPE_ALIAS || prod == PROD_ITEM_IMPL || prod == PROD_ITEM_TRAIT ||
        prod == PROD_ITEM_CONST || prod == PROD_ITEM_ENUM || prod == PROD_ITEM_STRUCT ||
        prod == PROD_PUB_FN || prod == PROD_PUB_EXTERN_FN || prod == PROD_PUB_CONST ||
        prod == PROD_PUB_TYPE_ALIAS || prod == PROD_PUB_ENUM || prod == PROD_PUB_STRUCT ||
        prod == PROD_PUB_IMPL || prod == PROD_PUB_TRAIT || prod == PROD_ENUM_VARIANT ||
        prod == PROD_TRAIT)
        return HIR_ITEM;
    if (prod == PROD_FN || prod == PROD_EXTERN_FN || prod == PROD_IMPL_FN)
        return HIR_FN;
    if (prod == PROD_IMPORT)
        return HIR_IMPORT_ITEM;
    if (prod == PROD_MODULE)
        return HIR_MODULE_ITEM;
    if (prod == PROD_PATH)
        return HIR_PATH_EXPR;
    if (prod == PROD_PARAM_NAMED || prod == PROD_PARAM_SELF ||
        prod == PROD_PARAM_SELF_REF)
        return HIR_PARAM;
    if (prod == PROD_TYPE_IDENT || prod == PROD_TYPE_ARRAY || prod == PROD_TYPE_REF)
        return HIR_TYPE;
    if (prod == PROD_FN_BLOCK || prod == PROD_IMPL_FN_BLOCK || prod == PROD_BLOCK)
        return HIR_BLOCK;
    if (prod == PROD_BLOCK_STMT || prod == PROD_EXPR_STMT || prod == PROD_ELSE_STMT)
        return HIR_STMT;
    if (prod == PROD_LET_STMT)
        return HIR_LET_STMT;
    if (prod == PROD_RETURN_STMT)
        return HIR_RETURN_STMT;
    if (prod == PROD_IF_STMT)
        return HIR_IF_STMT;
    if (prod == PROD_WHILE_STMT)
        return HIR_WHILE_STMT;
    if (prod == PROD_FOR_STMT)
        return HIR_FOR_STMT;
    if (prod == PROD_BREAK_STMT)
        return HIR_BREAK_STMT;
    if (prod == PROD_CONTINUE_STMT)
        return HIR_CONTINUE_STMT;
    if (prod == PROD_EXPR)
        return HIR_EXPR;
    if (prod == PROD_MATCH_EXPR)
        return HIR_MATCH_EXPR;
    if (prod >= PROD_ASSIGN && prod <= PROD_ASSIGN_END)
        return HIR_ASSIGN_EXPR;
    if (prod >= PROD_OREXPR && prod <= PROD_MUL_END)
        return HIR_BINARY_EXPR;
    if ((prod >= PROD_PRE_INC && prod <= PROD_BASE) ||
        prod == PROD_POSTFIX_INC || prod == PROD_POSTFIX_DEC)
        return HIR_UNARY_EXPR;
    if (prod == PROD_POSTFIX || prod == PROD_POSTFIX_END)
        return HIR_POSTFIX_EXPR;
    if (prod == PROD_POSTFIX_CALL)
        return HIR_CALL_EXPR;
    if (prod == PROD_POSTFIX_INDEX)
        return HIR_INDEX_EXPR;
    if (prod == PROD_POSTFIX_MEMBER)
        return HIR_MEMBER_EXPR;
    if (prod == PROD_ARRAY_LIT)
        return HIR_ARRAY_EXPR;
    if (prod == PROD_IDENT || prod == PROD_SELF_VALUE ||
        prod == PROD_PATTERN_IDENT)
        return HIR_NAME_EXPR;
    if (prod == PROD_INT || prod == PROD_FLOAT || prod == PROD_STRING ||
        prod == PROD_CHAR || prod == PROD_TRUE || prod == PROD_FALSE ||
        prod == PROD_PATTERN_INT || prod == PROD_PATTERN_TRUE || prod == PROD_PATTERN_FALSE)
        return HIR_LITERAL_EXPR;
    if (prod == PROD_CONST)
        return HIR_CONST_ITEM;
    if (prod == PROD_TYPE_ALIAS)
        return HIR_TYPE_ALIAS_ITEM;
    if (prod == PROD_ENUM)
        return HIR_ENUM_ITEM;
    if (prod == PROD_STRUCT)
        return HIR_STRUCT_ITEM;
    if (prod == PROD_STRUCT_LIT)
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
