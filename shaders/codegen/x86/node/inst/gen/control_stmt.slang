import gpu_index;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> x86_node_inst_range_info;
StructuredBuffer<uint4> x86_node_inst_location_record;
StructuredBuffer<uint> x86_node_inst_subtree_bound_start;
StructuredBuffer<uint> x86_node_inst_subtree_bound_end;
StructuredBuffer<uint> x86_node_inst_gen_input_status;
StructuredBuffer<uint2> x86_node_inst_gen_node_record;

RWStructuredBuffer<uint4> x86_virtual_inst_record;
RWStructuredBuffer<uint4> x86_virtual_inst_args;
RWStructuredBuffer<uint> x86_virtual_inst_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_INST_GEN_INPUTS_OK = 1u;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_ERR_NODE_VIRTUAL_INST = 11u;
static const uint HIR_STMT = 7u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_IF = 3u;
static const uint STMT_RECORD_KIND_WHILE = 6u;
static const uint X86_NODE_INST_RANGE_COUNT_MASK = 0x0fffffffu;
static const uint X86_VINST_BRANCH = 10u;
static const uint X86_VINST_ERROR_BRANCH_COND = 3101u;
static const uint X86_VINST_ERROR_BRANCH_LOCATION = 3102u;
static const uint X86_VINST_ERROR_BRANCH_TARGET = 3103u;

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint virtual_inst_count()
{
    return min(x86_virtual_inst_status[3u], gParams.inst_capacity);
}

bool virtual_row_in_stream(uint row)
{
    return row != INVALID && row < virtual_inst_count();
}

bool upstream_ok()
{
    return x86_node_inst_gen_input_status[0u] == X86_NODE_INST_GEN_INPUTS_OK &&
           x86_node_inst_gen_input_status[1u] == 0u &&
           x86_virtual_inst_status[0u] == X86_VIRTUAL_INST_OK &&
           x86_virtual_inst_status[1u] == 0u;
}

uint gen_worklist_count()
{
    return min(
        x86_node_inst_gen_input_status[4u],
        min(gParams.n_hir_nodes, gParams.inst_capacity));
}

uint gen_worklist_node(uint order_row)
{
    return x86_node_inst_gen_node_record[order_row].x;
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

uint resolve_expr(uint node)
{
    return valid_node(node) ? x86_expr_resolved_node[node] : INVALID;
}

uint expr_result_root(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    return valid_node(root) ? root : resolve_expr(node);
}

bool range_for_node(uint node, out uint2 range)
{
    range = uint2(INVALID, 0u);
    if (!valid_node(node))
        return false;
    range = uint2(x86_node_inst_location_record[node].x, x86_node_inst_range_info[node]);
    return range.x != INVALID && range.y != INVALID;
}

uint range_count(uint2 range)
{
    return range.y & X86_NODE_INST_RANGE_COUNT_MASK;
}

bool location_for_node_local(uint node, uint local_i, out uint location)
{
    location = INVALID;
    if (!valid_node(node) || !upstream_ok())
        return false;
    if (local_i < 4u)
    {
        uint4 locations = x86_node_inst_location_record[node];
        if (local_i == 0u) location = locations.x;
        else if (local_i == 1u) location = locations.y;
        else if (local_i == 2u) location = locations.z;
        else location = locations.w;
        if (virtual_row_in_stream(location))
            return true;
    }
    uint2 range = uint2(INVALID, 0u);
    if (!range_for_node(node, range) || local_i >= range_count(range))
        return false;
    uint range_row = range.x + local_i;
    if (range_row < range.x || !virtual_row_in_stream(range_row))
        return false;
    location = range_row;
    return true;
}

bool value_vreg_for_candidate(uint node, out uint vreg)
{
    vreg = INVALID;
    uint2 range = uint2(INVALID, 0u);
    if (!range_for_node(node, range) || range_count(range) == 0u)
        return false;
    return location_for_node_local(node, 0u, vreg);
}

bool value_vreg_for_node(uint node, out uint vreg)
{
    uint resolved = resolve_expr(node);
    if (value_vreg_for_candidate(resolved, vreg))
        return true;
    uint root = expr_result_root(node);
    if (root != resolved && value_vreg_for_candidate(root, vreg))
        return true;
    vreg = INVALID;
    return false;
}

bool subtree_instruction_bounds(uint root, out uint first_row, out uint after_row)
{
    first_row = INVALID;
    after_row = INVALID;
    if (!valid_node(root))
        return false;
    first_row = x86_node_inst_subtree_bound_start[root];
    after_row = x86_node_inst_subtree_bound_end[root];
    return virtual_row_in_stream(first_row) &&
           after_row != INVALID &&
           after_row <= virtual_inst_count() &&
           after_row >= first_row;
}

bool first_instruction_row_in_subtree(uint root, out uint row)
{
    row = INVALID;
    uint after_row = INVALID;
    return subtree_instruction_bounds(root, row, after_row);
}

bool row_after_subtree(uint root, out uint row)
{
    row = INVALID;
    uint first_row = INVALID;
    return subtree_instruction_bounds(root, first_row, row);
}

void write_status_error_detail(uint node, uint detail)
{
    publish_stage_error_first4(
        x86_virtual_inst_status,
        X86_ERR_NODE_VIRTUAL_INST,
        node,
        detail);
}

void write_inst(uint row, uint node, uint local_i, uint op, uint dst, uint4 args)
{
    if (row >= gParams.inst_capacity)
    {
        write_status_error_detail(node, row);
        return;
    }
    x86_virtual_inst_record[row] = uint4(node, local_i, op, dst);
    x86_virtual_inst_args[row] = args;
}

bool is_control_stmt(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = stmt_slot(node, 0u);
    return ((hir_kind[node] == HIR_IF_STMT || hir_kind[node] == HIR_STMT) &&
            kind == STMT_RECORD_KIND_IF) ||
           ((hir_kind[node] == HIR_WHILE_STMT || hir_kind[node] == HIR_STMT) &&
            kind == STMT_RECORD_KIND_WHILE);
}

bool emit_if_stmt(uint node)
{
    uint cond_node = stmt_slot(node, 1u);
    uint else_node = stmt_slot(node, 3u);
    uint cond = INVALID;
    uint false_target = INVALID;
    uint after_target = INVALID;
    uint branch_row = INVALID;
    if (!value_vreg_for_node(cond_node, cond))
    {
        write_status_error_detail(node, X86_VINST_ERROR_BRANCH_COND);
        return false;
    }
    if (valid_node(else_node))
    {
        if (!first_instruction_row_in_subtree(else_node, false_target) ||
            !row_after_subtree(else_node, after_target))
        {
            write_status_error_detail(node, X86_VINST_ERROR_BRANCH_TARGET);
            return false;
        }
    }
    else if (!row_after_subtree(node, false_target))
    {
        write_status_error_detail(node, X86_VINST_ERROR_BRANCH_TARGET);
        return false;
    }
    if (!location_for_node_local(node, 0u, branch_row))
    {
        write_status_error_detail(node, X86_VINST_ERROR_BRANCH_LOCATION);
        return false;
    }
    write_inst(branch_row, node, 0u, X86_VINST_BRANCH, INVALID, uint4(cond, false_target, 0u, 0u));
    if (valid_node(else_node))
    {
        uint join = INVALID;
        if (!location_for_node_local(node, 1u, join))
        {
            write_status_error_detail(node, X86_VINST_ERROR_BRANCH_LOCATION);
            return false;
        }
        write_inst(join, node, 1u, X86_VINST_BRANCH, INVALID, uint4(INVALID, after_target, 0u, 0u));
    }
    return true;
}

bool emit_while_stmt(uint node)
{
    uint cond_node = stmt_slot(node, 1u);
    uint body_node = stmt_slot(node, 2u);
    uint cond = INVALID;
    uint top = INVALID;
    uint after_target = INVALID;
    uint cond_branch = INVALID;
    uint body_jump = INVALID;
    if (!value_vreg_for_node(cond_node, cond))
    {
        write_status_error_detail(node, X86_VINST_ERROR_BRANCH_COND);
        return false;
    }
    if (!first_instruction_row_in_subtree(cond_node, top) ||
        !row_after_subtree(node, after_target) ||
        !location_for_node_local(node, 0u, cond_branch) ||
        !location_for_node_local(node, 1u, body_jump))
    {
        write_status_error_detail(node, X86_VINST_ERROR_BRANCH_LOCATION);
        return false;
    }
    write_inst(cond_branch, node, 0u, X86_VINST_BRANCH, INVALID, uint4(cond, after_target, 0u, 0u));
    write_inst(body_jump, node, 1u, X86_VINST_BRANCH, INVALID, uint4(INVALID, top, body_node, 0u));
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint order_row = linear_dispatch_id(tid);
    if (!upstream_ok() || order_row >= gen_worklist_count())
        return;
    uint node = gen_worklist_node(order_row);
    if (!is_control_stmt(node))
        return;
    uint kind = stmt_slot(node, 0u);
    bool ok = kind == STMT_RECORD_KIND_IF
                  ? emit_if_stmt(node)
                  : emit_while_stmt(node);
    if (!ok)
        write_status_error_detail(node, hir_kind[node]);
}
