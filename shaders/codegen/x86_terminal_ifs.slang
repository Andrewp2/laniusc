// x86_64 terminal if/else projection.
//
// This pass consumes HIR statement records plus branch-block return rows and
// scatters one terminal if/else return record per owning function. Nested
// terminal ifs are also published under their enclosing branch-block node, so
// later passes can consume bounded nested branch shapes through records.

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
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> x86_node_func;
StructuredBuffer<uint4> x86_block_return_stmt_record;
StructuredBuffer<uint> x86_block_return_stmt_count;
StructuredBuffer<uint> x86_block_return_stmt_status;
StructuredBuffer<uint4> x86_return_call_record;
StructuredBuffer<uint> x86_return_call_status;

RWStructuredBuffer<uint4> x86_terminal_if_record;
RWStructuredBuffer<uint> x86_terminal_if_count;
RWStructuredBuffer<uint> x86_terminal_if_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_FN = 3u;
static const uint HIR_IF_STMT = 10u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_IF = 3u;
static const uint X86_BLOCK_RETURN_STMTS_OK = 1u;
static const uint X86_BLOCK_RETURN_STMT_BRANCH = 1u;
static const uint X86_RETURN_CALLS_OK = 1u;
static const uint X86_RETURN_CALL_BRANCH = 2u;
static const uint X86_TERMINAL_IFS_OK = 1u;
static const uint X86_TERMINAL_IF_ERR_DUPLICATE = 1u;

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

uint stmt_record_slot(uint node, uint slot)
{
    return hir_stmt_record[node * STMT_RECORD_STRIDE + slot];
}

bool block_returns_ok()
{
    return x86_block_return_stmt_status[0u] == X86_BLOCK_RETURN_STMTS_OK &&
           x86_block_return_stmt_status[1u] == 0u;
}

bool return_calls_ok()
{
    return x86_return_call_status[0u] == X86_RETURN_CALLS_OK &&
           x86_return_call_status[1u] == 0u;
}

bool has_if_ancestor_before_function(uint node)
{
    if (!valid_node(node))
        return false;

    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        uint p = parent[cur];
        if (!valid_node(p) || p == cur)
            return false;
        if (hir_kind[p] == HIR_FN)
            return false;
        if (hir_kind[p] == HIR_IF_STMT)
            return true;
        cur = p;
    }
    return false;
}

bool branch_return_expr(uint block_node, out uint ret_expr)
{
    ret_expr = INVALID;
    if (!valid_node(block_node) || x86_block_return_stmt_count[block_node] != 1u)
        return false;

    uint4 record = x86_block_return_stmt_record[block_node];
    if (record.x != block_node || record.w != X86_BLOCK_RETURN_STMT_BRANCH)
        return false;
    if (!valid_node(record.y) || !valid_node(record.z))
        return false;

    uint4 call_record = x86_return_call_record[record.y];
    ret_expr = call_record.x == record.y &&
               call_record.w == X86_RETURN_CALL_BRANCH &&
               valid_node(call_record.y) ?
               call_record.y :
               record.z;
    return true;
}

void publish_duplicate_error(uint if_node)
{
    x86_terminal_if_status[0u] = 0u;
    x86_terminal_if_status[1u] = X86_TERMINAL_IF_ERR_DUPLICATE;
    uint old_detail = 0u;
    InterlockedMin(x86_terminal_if_status[2u], if_node, old_detail);
}

bool terminal_return_arms(uint if_node, out uint cond_node, out uint then_expr, out uint else_expr)
{
    cond_node = INVALID;
    then_expr = INVALID;
    else_expr = INVALID;
    if (hir_kind[if_node] != HIR_IF_STMT ||
        stmt_record_slot(if_node, 0u) != STMT_RECORD_KIND_IF)
        return false;

    cond_node = stmt_record_slot(if_node, 1u);
    uint then_block = stmt_record_slot(if_node, 2u);
    uint else_block = stmt_record_slot(if_node, 3u);
    if (!valid_node(cond_node) || !valid_node(then_block) || !valid_node(else_block))
        return false;

    return branch_return_expr(then_block, then_expr) &&
           branch_return_expr(else_block, else_expr);
}

bool enclosing_if_branch_block(uint node, out uint block_node)
{
    block_node = INVALID;
    if (!valid_node(node))
        return false;

    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        uint p = parent[cur];
        if (!valid_node(p) || p == cur)
            return false;
        if (hir_kind[p] == HIR_FN)
            return false;
        if (hir_kind[p] == HIR_IF_STMT)
        {
            block_node = cur;
            return valid_node(block_node);
        }
        cur = p;
    }
    return false;
}

void publish_nested_terminal_if(uint if_node, uint cond_node, uint then_expr, uint else_expr)
{
    x86_terminal_if_record[if_node] = uint4(if_node, cond_node, then_expr, else_expr);

    uint block_node = INVALID;
    if (!enclosing_if_branch_block(if_node, block_node))
        return;

    uint cur = if_node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        uint p = parent[cur];
        if (!valid_node(p) || p == cur || hir_kind[p] == HIR_FN)
            return;
        if (hir_kind[p] == HIR_IF_STMT)
        {
            x86_terminal_if_record[cur] = uint4(if_node, cond_node, then_expr, else_expr);
            return;
        }
        x86_terminal_if_record[p] = uint4(if_node, cond_node, then_expr, else_expr);
        cur = p;
    }
}

bool nearest_enclosing_if(uint node, out uint outer_if)
{
    outer_if = INVALID;
    if (!valid_node(node))
        return false;

    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        uint p = parent[cur];
        if (!valid_node(p) || p == cur || hir_kind[p] == HIR_FN)
            return false;
        if (hir_kind[p] == HIR_IF_STMT)
        {
            outer_if = p;
            return true;
        }
        cur = p;
    }
    return false;
}

void publish_nested_function_terminal_if(uint if_node)
{
    uint outer_if = INVALID;
    if (!nearest_enclosing_if(if_node, outer_if) ||
        has_if_ancestor_before_function(outer_if) ||
        stmt_record_slot(outer_if, 0u) != STMT_RECORD_KIND_IF)
        return;

    uint fn_node = x86_node_func[outer_if];
    uint outer_cond = stmt_record_slot(outer_if, 1u);
    uint outer_then_block = stmt_record_slot(outer_if, 2u);
    if (!valid_node(fn_node) || !valid_node(outer_cond) || !valid_node(outer_then_block))
        return;

    uint outer_then_expr = INVALID;
    if (!branch_return_expr(outer_then_block, outer_then_expr))
        return;

    uint prior_count = 0u;
    InterlockedAdd(x86_terminal_if_count[fn_node], 1u, prior_count);
    if (prior_count == 0u)
    {
        x86_terminal_if_record[fn_node] =
            uint4(outer_if, outer_cond, outer_then_expr, if_node);
    }
    else
    {
        publish_duplicate_error(if_node);
    }

    uint old_total = 0u;
    InterlockedAdd(x86_terminal_if_status[3u], 1u, old_total);
}

void scatter_terminal_if(uint if_node)
{
    uint cond_node = INVALID;
    uint then_expr = INVALID;
    uint else_expr = INVALID;
    bool simple_terminal = terminal_return_arms(if_node, cond_node, then_expr, else_expr);
    if (simple_terminal)
    {
        publish_nested_terminal_if(if_node, cond_node, then_expr, else_expr);
        publish_nested_function_terminal_if(if_node);
    }

    if (hir_kind[if_node] != HIR_IF_STMT ||
        stmt_record_slot(if_node, 0u) != STMT_RECORD_KIND_IF ||
        has_if_ancestor_before_function(if_node))
        return;

    uint fn_node = x86_node_func[if_node];
    uint top_cond_node = stmt_record_slot(if_node, 1u);
    uint then_block = stmt_record_slot(if_node, 2u);
    uint else_block = stmt_record_slot(if_node, 3u);
    if (!valid_node(fn_node) || !valid_node(top_cond_node) ||
        !valid_node(then_block) || !valid_node(else_block))
        return;

    uint top_then_expr = INVALID;
    uint top_else_expr = INVALID;
    bool direct_else = branch_return_expr(else_block, top_else_expr);
    if (!branch_return_expr(then_block, top_then_expr) || !direct_else)
        return;

    uint prior_count = 0u;
    InterlockedAdd(x86_terminal_if_count[fn_node], 1u, prior_count);
    if (prior_count == 0u)
    {
        x86_terminal_if_record[fn_node] =
            uint4(if_node, top_cond_node, top_then_expr, top_else_expr);
    }
    else
    {
        publish_duplicate_error(if_node);
    }

    uint old_total = 0u;
    InterlockedAdd(x86_terminal_if_status[3u], 1u, old_total);
}

void publish_upstream_error()
{
    x86_terminal_if_status[0u] = 0u;
    x86_terminal_if_status[1u] = block_returns_ok() ?
                                 x86_return_call_status[1u] :
                                 x86_block_return_stmt_status[1u];
    x86_terminal_if_status[2u] = block_returns_ok() ?
                                 x86_return_call_status[2u] :
                                 x86_block_return_stmt_status[2u];
    x86_terminal_if_status[3u] = 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (node_i == 0u)
    {
        x86_terminal_if_status[0u] = X86_TERMINAL_IFS_OK;
        x86_terminal_if_status[1u] = 0u;
        x86_terminal_if_status[2u] = INVALID;
    }

    if (!block_returns_ok() || !return_calls_ok())
    {
        if (node_i == 0u)
            publish_upstream_error();
        return;
    }

    if (node_i >= active_hir_node_count())
        return;

    scatter_terminal_if(node_i);
}
