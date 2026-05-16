// x86_64 node-local virtual instruction counts.
//
// This pass is the backend counterpart of Pareas' instruction-count stage:
// each attributed HIR node receives a local virtual instruction count. Prefix
// sums over these rows can later assign instruction locations without
// recognizing whole function bodies.

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
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint4> x86_node_tree_record;
StructuredBuffer<uint> x86_node_tree_status;
StructuredBuffer<uint4> x86_call_record;
StructuredBuffer<uint> call_record_status;
StructuredBuffer<uint4> x86_intrinsic_call_record;
StructuredBuffer<uint> x86_intrinsic_call_status;

RWStructuredBuffer<uint4> x86_node_inst_count_record;
RWStructuredBuffer<uint> x86_node_inst_scan_input;
RWStructuredBuffer<uint> x86_node_inst_count_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_TREE_OK = 1u;
static const uint X86_CALL_RECORDS_OK = 1u;
static const uint X86_INTRINSIC_CALLS_OK = 1u;
static const uint X86_NODE_INST_COUNTS_OK = 1u;
static const uint X86_ERR_NODE_INST_COUNTS = 10u;

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
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_LITERAL_EXPR = 23u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint STMT_RECORD_KIND_IF = 3u;
static const uint STMT_RECORD_KIND_CONST = 4u;
static const uint STMT_RECORD_KIND_ASSIGN = 5u;
static const uint STMT_RECORD_KIND_WHILE = 6u;

static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint HIR_EXPR_FORWARD = 1u;
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

static const uint X86_NODE_INST_NONE = 0u;
static const uint X86_NODE_INST_EXPR_VALUE = 1u;
static const uint X86_NODE_INST_CALL_VALUE = 2u;
static const uint X86_NODE_INST_STMT_VALUE = 3u;
static const uint X86_NODE_INST_BRANCH = 4u;
static const uint X86_NODE_INST_LOOP = 5u;
static const uint X86_NODE_INST_TRANSFER = 6u;
static const uint X86_NODE_INST_PADDING = 7u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool upstream_ok()
{
    return x86_node_tree_status[0u] == X86_NODE_TREE_OK &&
           x86_node_tree_status[1u] == 0u &&
           call_record_status[0u] == X86_CALL_RECORDS_OK &&
           call_record_status[1u] == 0u &&
           x86_intrinsic_call_status[0u] == X86_INTRINSIC_CALLS_OK &&
           x86_intrinsic_call_status[1u] == 0u;
}

uint stmt_slot(uint node, uint slot)
{
    return hir_stmt_record[node * STMT_RECORD_STRIDE + slot];
}

uint expr_form(uint node)
{
    return valid_node(node) ? hir_expr_record[node * EXPR_RECORD_STRIDE + EXPR_RECORD_FORM] : 0u;
}

uint expr_left(uint node)
{
    return valid_node(node) ? hir_expr_record[node * EXPR_RECORD_STRIDE + EXPR_RECORD_LEFT] : INVALID;
}

uint resolve_expr(uint node)
{
    [loop]
    for (uint guard = 0u; guard < 64u; guard += 1u)
    {
        if (!valid_node(node))
            return INVALID;
        if (expr_form(node) != HIR_EXPR_FORWARD)
            return node;
        node = expr_left(node);
    }
    return INVALID;
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

bool has_call_record(uint node)
{
    uint4 call = x86_call_record[node];
    return call.x != INVALID || call.y != INVALID || call.z != INVALID || call.w != INVALID;
}

bool has_intrinsic_call_record(uint node)
{
    uint4 call = x86_intrinsic_call_record[node];
    return call.y == node && call.w != INVALID;
}

bool is_call_callee_node(uint node)
{
    if (!valid_node(node))
        return false;

    uint active_nodes = active_hir_node_count();
    [loop]
    for (uint call_node = 0u; call_node < active_nodes; call_node += 1u)
    {
        if (hir_kind[call_node] != HIR_CALL_EXPR)
            continue;
        uint callee = hir_call_callee_node[call_node];
        uint resolved_callee = resolve_expr(callee);
        uint node_end = x86_node_tree_record[node].w;
        bool node_contains_callee = callee != INVALID &&
                                    node <= callee &&
                                    node_end != INVALID &&
                                    callee < node_end;
        if (callee == node || resolved_callee == node || node_contains_callee)
            return true;
    }
    return false;
}

uint branch_padding_count(uint node)
{
    uint parent = x86_node_tree_record[node].x;
    if (!valid_node(parent))
        return 0u;

    uint parent_kind = hir_kind[parent];
    if (parent_kind == HIR_IF_STMT && stmt_slot(parent, 0u) == STMT_RECORD_KIND_IF)
    {
        if (stmt_slot(parent, 1u) == node)
            return 1u;
        if (stmt_slot(parent, 2u) == node && valid_node(stmt_slot(parent, 3u)))
            return 1u;
    }

    return 0u;
}

void publish_upstream_error(uint node)
{
    uint old_error = 0u;
    InterlockedCompareExchange(
        x86_node_inst_count_status[1u],
        0u,
        X86_ERR_NODE_INST_COUNTS,
        old_error);
    uint old_detail = INVALID;
    InterlockedMin(x86_node_inst_count_status[2u], node, old_detail);
}

void write_count(uint node, uint count, uint kind, uint payload)
{
    x86_node_inst_count_record[node] = uint4(node, count, kind, payload);
    x86_node_inst_scan_input[node] = count;
    if (count != 0u)
    {
        uint old_count = 0u;
        InterlockedAdd(x86_node_inst_count_status[3u], 1u, old_count);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!upstream_ok())
    {
        if (node == 0u)
            publish_upstream_error(node);
        return;
    }

    if (!valid_node(node))
        return;

    uint tree_parent = x86_node_tree_record[node].x;
    uint kind = hir_kind[node];
    uint padding = branch_padding_count(node);

    if (kind == HIR_CALL_EXPR && (has_call_record(node) || has_intrinsic_call_record(node)))
    {
        write_count(node, 1u + padding, X86_NODE_INST_CALL_VALUE, tree_parent);
        return;
    }

    if (kind == HIR_RETURN_STMT && stmt_slot(node, 0u) == STMT_RECORD_KIND_RETURN)
    {
        write_count(node, 1u + padding, X86_NODE_INST_TRANSFER, stmt_slot(node, 1u));
        return;
    }

    if (kind == HIR_IF_STMT && stmt_slot(node, 0u) == STMT_RECORD_KIND_IF)
    {
        write_count(node, 0u, X86_NODE_INST_BRANCH, stmt_slot(node, 1u));
        return;
    }

    if (kind == HIR_WHILE_STMT && stmt_slot(node, 0u) == STMT_RECORD_KIND_WHILE)
    {
        write_count(node, 2u, X86_NODE_INST_LOOP, stmt_slot(node, 1u));
        return;
    }

    if ((kind == HIR_LET_STMT && stmt_slot(node, 0u) == STMT_RECORD_KIND_LET) ||
        stmt_slot(node, 0u) == STMT_RECORD_KIND_CONST ||
        stmt_slot(node, 0u) == STMT_RECORD_KIND_ASSIGN)
    {
        write_count(node, 1u + padding, X86_NODE_INST_STMT_VALUE, stmt_slot(node, 2u));
        return;
    }

    if (kind == HIR_BREAK_STMT || kind == HIR_CONTINUE_STMT)
    {
        write_count(node, 1u + padding, X86_NODE_INST_TRANSFER, tree_parent);
        return;
    }

    uint form = expr_form(node);
    if ((kind == HIR_ASSIGN_EXPR ||
         kind == HIR_BINARY_EXPR ||
         kind == HIR_UNARY_EXPR ||
         kind == HIR_NAME_EXPR ||
         kind == HIR_LITERAL_EXPR) &&
        expression_form_has_value_instr(form))
    {
        if (is_call_callee_node(node))
        {
            write_count(node, padding, padding == 0u ? X86_NODE_INST_NONE : X86_NODE_INST_PADDING, tree_parent);
            return;
        }
        write_count(node, 1u + padding, X86_NODE_INST_EXPR_VALUE, form);
        return;
    }

    if (padding != 0u)
    {
        write_count(node, padding, X86_NODE_INST_PADDING, tree_parent);
        return;
    }

    write_count(node, 0u, X86_NODE_INST_NONE, tree_parent);
}
