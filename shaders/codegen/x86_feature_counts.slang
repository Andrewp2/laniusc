// x86_64 backend semantic feature summary.
//
// This pass measures HIR feature families from parser-owned HIR kind records.
// The host uses the tiny summary to size feature-specific backend record arrays
// before recording the full x86 pipeline.

import atomics;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;

RWStructuredBuffer<uint> x86_feature_record;

static const uint DISPATCH_X_STRIDE = 16776960u;

static const uint X86_FEATURE_ENUM = 1u << 0u;
static const uint X86_FEATURE_MATCH = 1u << 1u;
static const uint X86_FEATURE_AGGREGATE = 1u << 2u;
static const uint X86_FEATURE_CALL = 1u << 3u;

static const uint FEATURE_RECORD_MASK = 0u;
static const uint FEATURE_RECORD_ENUM_COUNT = 1u;
static const uint FEATURE_RECORD_MATCH_COUNT = 2u;
static const uint FEATURE_RECORD_AGGREGATE_COUNT = 3u;
static const uint FEATURE_RECORD_SCALAR_INST_CAPACITY = 4u;
static const uint FEATURE_RECORD_CALL_COUNT = 5u;
static const uint FEATURE_RECORD_PARAM_COUNT = 6u;

static const uint INVALID = 0xffffffffu;
static const uint HIR_PARAM = 4u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_BREAK_STMT = 12u;
static const uint HIR_CONTINUE_STMT = 13u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_ENUM_ITEM = 26u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_MATCH_EXPR = 34u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint STMT_RECORD_KIND_IF = 3u;
static const uint STMT_RECORD_KIND_CONST = 4u;
static const uint STMT_RECORD_KIND_ASSIGN = 5u;
static const uint STMT_RECORD_KIND_WHILE = 6u;
static const uint STMT_RECORD_KIND_FOR = 7u;
static const uint ASSIGN_OP_SET = 1u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
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

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

uint stmt_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
        slot,
        INVALID);
}

uint expr_form(uint node)
{
    return valid_node(node)
               ? row_major_load<uint>(
                     hir_expr_record,
                     node,
                     EXPR_RECORD_STRIDE,
                     EXPR_RECORD_FORM,
                     0u)
               : 0u;
}

bool expression_form_has_value_instr(uint form)
{
    return form == HIR_EXPR_NAME ||
           form == HIR_EXPR_INT ||
           form == HIR_EXPR_TRUE ||
           form == HIR_EXPR_FALSE ||
           form == HIR_EXPR_NOT ||
           form == HIR_EXPR_EQ ||
           form == HIR_EXPR_NE ||
           form == HIR_EXPR_LT ||
           form == HIR_EXPR_GT ||
           form == HIR_EXPR_LE ||
           form == HIR_EXPR_GE ||
           form == HIR_EXPR_NEG ||
           form == HIR_EXPR_ADD ||
           form == HIR_EXPR_SUB ||
           form == HIR_EXPR_MUL ||
           form == HIR_EXPR_AND ||
           form == HIR_EXPR_OR ||
           form == HIR_EXPR_MOD ||
           form == HIR_EXPR_DIV ||
           form == HIR_EXPR_BIT_OR ||
           form == HIR_EXPR_BIT_XOR ||
           form == HIR_EXPR_BIT_AND ||
           form == HIR_EXPR_SHL ||
           form == HIR_EXPR_SHR;
}

uint scalar_base_inst_count(uint node)
{
    uint kind = hir_kind[node];
    uint stmt_kind = stmt_slot(node, 0u);

    if (kind == HIR_PARAM)
        return 2u;
    if (kind == HIR_CALL_EXPR)
        return 2u;
    if (kind == HIR_RETURN_STMT || stmt_kind == STMT_RECORD_KIND_RETURN)
        return 1u;
    if ((kind == HIR_LET_STMT || kind == HIR_STMT) &&
        (stmt_kind == STMT_RECORD_KIND_LET || stmt_kind == STMT_RECORD_KIND_CONST))
        return 1u;
    if (kind == HIR_STMT && stmt_kind == STMT_RECORD_KIND_ASSIGN)
    {
        uint op = stmt_slot(node, 3u);
        return op == ASSIGN_OP_SET ? 1u : 3u;
    }
    if (kind == HIR_BREAK_STMT || kind == HIR_CONTINUE_STMT)
        return 1u;
    if (kind == HIR_INDEX_EXPR || kind == HIR_MEMBER_EXPR || kind == HIR_PATH_EXPR)
        return 1u;
    if (kind == HIR_ASSIGN_EXPR ||
        kind == HIR_BINARY_EXPR ||
        kind == HIR_UNARY_EXPR ||
        kind == HIR_NAME_EXPR ||
        kind == HIR_LITERAL_EXPR)
        return expression_form_has_value_instr(expr_form(node)) ? 1u : 0u;
    return 0u;
}

uint scalar_control_padding(uint node)
{
    uint stmt_kind = stmt_slot(node, 0u);
    uint kind = hir_kind[node];
    if (kind == HIR_IF_STMT && stmt_kind == STMT_RECORD_KIND_IF)
    {
        uint count = valid_node(stmt_slot(node, 1u)) ? 1u : 0u;
        if (valid_node(stmt_slot(node, 2u)) && valid_node(stmt_slot(node, 3u)))
            count += 1u;
        return count;
    }
    if (kind == HIR_WHILE_STMT && stmt_kind == STMT_RECORD_KIND_WHILE)
    {
        uint count = valid_node(stmt_slot(node, 1u)) ? 1u : 0u;
        if (valid_node(stmt_slot(node, 2u)))
            count += 1u;
        return count;
    }
    if ((kind == HIR_FOR_STMT || kind == HIR_STMT) && stmt_kind == STMT_RECORD_KIND_FOR)
    {
        uint count = valid_node(stmt_slot(node, 2u)) ? 3u : 0u;
        if (valid_node(stmt_slot(node, 3u)))
            count += 1u;
        return count;
    }
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (node >= active_hir_node_count())
        return;

    uint kind = hir_kind[node];
    if (kind == HIR_ENUM_ITEM)
    {
        atomic_u32_or(x86_feature_record, FEATURE_RECORD_MASK, X86_FEATURE_ENUM);
        atomic_u32_add(x86_feature_record, FEATURE_RECORD_ENUM_COUNT, 1u);
    }
    if (kind == HIR_MATCH_EXPR)
    {
        atomic_u32_or(x86_feature_record, FEATURE_RECORD_MASK, X86_FEATURE_MATCH);
        atomic_u32_add(x86_feature_record, FEATURE_RECORD_MATCH_COUNT, 1u);
    }
    if (kind == HIR_CALL_EXPR)
    {
        atomic_u32_or(x86_feature_record, FEATURE_RECORD_MASK, X86_FEATURE_CALL);
        atomic_u32_add(x86_feature_record, FEATURE_RECORD_CALL_COUNT, 1u);
    }
    if (kind == HIR_PARAM)
        atomic_u32_add(x86_feature_record, FEATURE_RECORD_PARAM_COUNT, 1u);
    if (kind == HIR_ARRAY_EXPR ||
        kind == HIR_STRUCT_ITEM ||
        kind == HIR_STRUCT_LITERAL_EXPR)
    {
        atomic_u32_or(x86_feature_record, FEATURE_RECORD_MASK, X86_FEATURE_AGGREGATE);
        atomic_u32_add(x86_feature_record, FEATURE_RECORD_AGGREGATE_COUNT, 1u);
    }

    uint scalar_count = scalar_base_inst_count(node) + scalar_control_padding(node);
    if (scalar_count != 0u)
        atomic_u32_add(x86_feature_record, FEATURE_RECORD_SCALAR_INST_CAPACITY, scalar_count);
}
