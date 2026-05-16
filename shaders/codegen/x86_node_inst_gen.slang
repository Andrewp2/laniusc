// x86_64 node-local virtual instruction generation.
//
// This is the Pareas-style instruction generation counterpart to
// x86_node_inst_counts: each HIR node owns instruction rows assigned by
// x86_node_inst_location_record, and this pass fills those rows with virtual
// instruction records. It consumes attributed HIR/backend records only.

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
StructuredBuffer<uint> hir_expr_int_value;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint4> x86_const_value_record;
StructuredBuffer<uint> x86_const_value_status;
StructuredBuffer<uint4> x86_local_literal_record;
StructuredBuffer<uint> x86_local_literal_status;
StructuredBuffer<uint4> x86_param_reg_record;
StructuredBuffer<uint> x86_param_reg_status;
StructuredBuffer<uint4> x86_call_record;
StructuredBuffer<uint> call_record_status;
StructuredBuffer<uint4> x86_call_abi_record;
StructuredBuffer<uint> call_abi_status;
StructuredBuffer<uint4> x86_intrinsic_call_record;
StructuredBuffer<uint> x86_intrinsic_call_status;
StructuredBuffer<uint4> x86_node_inst_range_record;
StructuredBuffer<uint> x86_node_inst_range_status;
StructuredBuffer<uint4> x86_node_inst_location_record;
StructuredBuffer<uint> x86_node_inst_location_status;
StructuredBuffer<uint4> x86_node_tree_record;

RWStructuredBuffer<uint4> x86_node_value_record;
RWStructuredBuffer<uint4> x86_virtual_inst_record;
RWStructuredBuffer<uint4> x86_virtual_inst_args;
RWStructuredBuffer<uint> x86_virtual_inst_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint MAX_X86_INSTS = 256u;
static const uint X86_CONST_VALUES_OK = 1u;
static const uint X86_LOCAL_LITERALS_OK = 1u;
static const uint X86_PARAM_REGS_OK = 1u;
static const uint X86_CALL_RECORDS_OK = 1u;
static const uint X86_CALL_ABI_OK = 1u;
static const uint X86_INTRINSIC_CALLS_OK = 1u;
static const uint X86_NODE_INST_RANGE_OK = 1u;
static const uint X86_NODE_INST_LOCATIONS_OK = 1u;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_ERR_NODE_VIRTUAL_INST = 11u;

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
static const uint EXPR_RECORD_RIGHT = 2u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
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

static const uint X86_CONST_VALUE_LITERAL = 1u;
static const uint X86_LOCAL_LITERAL_TOP_LEVEL = 1u;

static const uint X86_NODE_VALUE_NONE = 0u;
static const uint X86_NODE_VALUE_VREG = 1u;
static const uint X86_NODE_VALUE_IMM_I32 = 2u;
static const uint X86_NODE_VALUE_PARAM = 3u;

static const uint X86_VINST_NONE = 0u;
static const uint X86_VINST_IMM_I32 = 1u;
static const uint X86_VINST_PARAM = 2u;
static const uint X86_VINST_UNARY = 3u;
static const uint X86_VINST_BINARY = 4u;
static const uint X86_VINST_COMPARE = 5u;
static const uint X86_VINST_CALL = 6u;
static const uint X86_VINST_INTRINSIC = 7u;
static const uint X86_VINST_ALIAS = 8u;
static const uint X86_VINST_RETURN = 9u;
static const uint X86_VINST_BRANCH = 10u;
static const uint X86_VINST_LOOP = 11u;
static const uint X86_VINST_TRANSFER = 12u;
static const uint X86_NODE_INST_PADDING = 7u;
static const uint X86_INTRINSIC_TEXT_WRITE = 1u;

static const uint X86_OP_NEG_I32 = 1u;
static const uint X86_OP_NOT_BOOL = 2u;
static const uint X86_OP_ADD_I32 = 1u;
static const uint X86_OP_SUB_I32 = 2u;
static const uint X86_OP_MUL_I32 = 3u;
static const uint X86_OP_AND_BOOL = 4u;
static const uint X86_OP_OR_BOOL = 5u;
static const uint X86_OP_MOD_I32 = 6u;
static const uint X86_OP_DIV_I32 = 7u;
static const uint X86_OP_BIT_AND_I32 = 8u;
static const uint X86_OP_BIT_OR_I32 = 9u;
static const uint X86_OP_BIT_XOR = 10u;
static const uint X86_OP_SHL_I32 = 11u;
static const uint X86_OP_SHR_I32 = 12u;
static const uint X86_CMP_LT = 1u;
static const uint X86_CMP_GT = 2u;
static const uint X86_CMP_LE = 3u;
static const uint X86_CMP_GE = 4u;
static const uint X86_CMP_EQ = 5u;
static const uint X86_CMP_NE = 6u;

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

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool upstream_ok()
{
    return x86_node_inst_range_status[0u] == X86_NODE_INST_RANGE_OK &&
           x86_node_inst_range_status[1u] == 0u &&
           x86_node_inst_location_status[0u] == X86_NODE_INST_LOCATIONS_OK &&
           x86_node_inst_location_status[1u] == 0u &&
           x86_const_value_status[0u] == X86_CONST_VALUES_OK &&
           x86_const_value_status[1u] == 0u &&
           x86_local_literal_status[0u] == X86_LOCAL_LITERALS_OK &&
           x86_local_literal_status[1u] == 0u &&
           x86_param_reg_status[0u] == X86_PARAM_REGS_OK &&
           x86_param_reg_status[1u] == 0u &&
           call_record_status[0u] == X86_CALL_RECORDS_OK &&
           call_record_status[1u] == 0u &&
           call_abi_status[0u] == X86_CALL_ABI_OK &&
           call_abi_status[1u] == 0u &&
           x86_intrinsic_call_status[0u] == X86_INTRINSIC_CALLS_OK &&
           x86_intrinsic_call_status[1u] == 0u;
}

uint stmt_slot(uint node, uint slot)
{
    return hir_stmt_record[node * STMT_RECORD_STRIDE + slot];
}

uint expr_slot(uint node, uint slot)
{
    return hir_expr_record[node * EXPR_RECORD_STRIDE + slot];
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_FORM) : 0u;
}

uint expr_left(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_LEFT) : INVALID;
}

uint expr_right(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_RIGHT) : INVALID;
}

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_VALUE_TOKEN) : INVALID;
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

bool range_for_node(uint node, out uint4 range)
{
    range = uint4(INVALID, 0u, 0u, INVALID);
    if (!valid_node(node))
        return false;
    range = x86_node_inst_range_record[node];
    return range.x != INVALID && range.y != INVALID;
}

bool location_for_node_local(uint node, uint local_i, out uint location)
{
    location = INVALID;
    if (!valid_node(node) || local_i >= 4u)
        return false;
    if (x86_node_inst_location_status[0u] != X86_NODE_INST_LOCATIONS_OK ||
        x86_node_inst_location_status[1u] != 0u)
        return false;

    uint4 locations = x86_node_inst_location_record[node];
    if (local_i == 0u) location = locations.x;
    else if (local_i == 1u) location = locations.y;
    else if (local_i == 2u) location = locations.z;
    else location = locations.w;
    return location != INVALID && location < MAX_X86_INSTS;
}

bool has_location_for_node_local(uint node, uint local_i)
{
    uint location = INVALID;
    return location_for_node_local(node, local_i, location);
}

bool subtree_bounds(uint root, out uint start, out uint end)
{
    start = INVALID;
    end = INVALID;
    if (!valid_node(root))
        return false;

    uint4 tree = x86_node_tree_record[root];
    uint active_nodes = active_hir_node_count();
    if (tree.w == INVALID || tree.w <= root || tree.w > active_nodes)
        return false;

    start = root;
    end = tree.w;
    return true;
}

bool first_instruction_row_in_subtree(uint root, out uint row)
{
    row = INVALID;
    uint start = INVALID;
    uint end = INVALID;
    if (!subtree_bounds(root, start, end))
        return false;

    [loop]
    for (uint node = start; node < end; node += 1u)
    {
        [unroll]
        for (uint local_i = 0u; local_i < 4u; local_i += 1u)
        {
            uint candidate = INVALID;
            if (location_for_node_local(node, local_i, candidate) &&
                (row == INVALID || candidate < row))
                row = candidate;
        }
    }
    return row != INVALID;
}

bool row_after_subtree(uint root, out uint row)
{
    row = INVALID;
    uint start = INVALID;
    uint end = INVALID;
    if (!subtree_bounds(root, start, end))
        return false;

    uint after = 0u;
    bool found = false;
    [loop]
    for (uint node = start; node < end; node += 1u)
    {
        [unroll]
        for (uint local_i = 0u; local_i < 4u; local_i += 1u)
        {
            uint candidate = INVALID;
            if (location_for_node_local(node, local_i, candidate))
            {
                uint candidate_after = candidate + 1u;
                after = found ? max(after, candidate_after) : candidate_after;
                found = true;
            }
        }
    }

    if (!found || after > x86_node_inst_location_status[3u])
        return false;
    row = after;
    return true;
}

bool has_call_record(uint node)
{
    if (!valid_node(node))
        return false;
    uint4 call = x86_call_record[node];
    return call.x != INVALID || call.y != INVALID || call.z != INVALID || call.w != INVALID;
}

bool call_value_node_for_expr(uint root, out uint call_node)
{
    call_node = INVALID;
    uint start = INVALID;
    uint end = INVALID;
    if (!subtree_bounds(root, start, end))
        return false;

    [loop]
    for (uint node = start; node < end; node += 1u)
    {
        if (hir_kind[node] == HIR_CALL_EXPR && has_call_record(node))
        {
            call_node = node;
            return true;
        }
    }
    return false;
}

uint pack_vreg_rows(uint a, uint b)
{
    return (a & 0xffffu) | ((b & 0xffffu) << 16u);
}

bool value_vreg_for_node(uint node, out uint vreg)
{
    vreg = INVALID;
    uint original = node;
    node = resolve_expr(node);
    uint call_node = INVALID;
    if ((!valid_node(node) || !has_location_for_node_local(node, 0u)) &&
        call_value_node_for_expr(original, call_node))
        node = call_node;
    uint4 range = uint4(INVALID, 0u, 0u, INVALID);
    if (!range_for_node(node, range) || range.y == 0u)
        return false;
    return location_for_node_local(node, 0u, vreg);
}

bool literal_value(uint node, out uint value)
{
    value = 0u;
    node = resolve_expr(node);
    if (!valid_node(node))
        return false;

    uint form = expr_form(node);
    if (form == HIR_EXPR_INT)
    {
        value = hir_expr_int_value[node];
        return true;
    }
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
    {
        value = form == HIR_EXPR_TRUE ? 1u : 0u;
        return true;
    }
    return false;
}

bool decl_literal_value(uint name_node, out uint value)
{
    value = 0u;
    name_node = resolve_expr(name_node);
    if (!valid_node(name_node) || expr_form(name_node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_value_token(name_node);
    if (!valid_token(name_token))
        return false;

    uint decl_token = visible_decl[name_token];
    if (!valid_token(decl_token))
        return false;

    uint4 const_record = x86_const_value_record[decl_token];
    if (const_record.x == X86_CONST_VALUE_LITERAL)
    {
        value = const_record.y;
        return true;
    }

    uint4 local_record = x86_local_literal_record[decl_token];
    if (local_record.w == X86_LOCAL_LITERAL_TOP_LEVEL)
    {
        value = local_record.z;
        return true;
    }
    return false;
}

bool param_record_for_name(uint name_node, out uint4 record)
{
    record = uint4(INVALID, INVALID, INVALID, INVALID);
    name_node = resolve_expr(name_node);
    if (!valid_node(name_node) || expr_form(name_node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_value_token(name_node);
    if (!valid_token(name_token))
        return false;

    uint decl_token = visible_decl[name_token];
    if (!valid_token(decl_token))
        return false;

    record = x86_param_reg_record[decl_token];
    return record.x != INVALID && record.z != INVALID;
}

bool local_decl_vreg_for_name(uint name_node, out uint vreg)
{
    vreg = INVALID;
    name_node = resolve_expr(name_node);
    if (!valid_node(name_node) || expr_form(name_node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_value_token(name_node);
    if (!valid_token(name_token))
        return false;

    uint decl_token = visible_decl[name_token];
    if (!valid_token(decl_token))
        return false;

    uint active_nodes = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < active_nodes; node += 1u)
    {
        uint stmt_kind = stmt_slot(node, 0u);
        if ((hir_kind[node] == HIR_LET_STMT || hir_kind[node] == HIR_STMT) &&
            (stmt_kind == STMT_RECORD_KIND_LET ||
             stmt_kind == STMT_RECORD_KIND_CONST ||
             stmt_kind == STMT_RECORD_KIND_ASSIGN) &&
            stmt_slot(node, 1u) == decl_token)
        {
            return location_for_node_local(node, 0u, vreg);
        }
    }
    return false;
}

uint unary_op_for_form(uint form)
{
    if (form == HIR_EXPR_NEG)
        return X86_OP_NEG_I32;
    if (form == HIR_EXPR_NOT)
        return X86_OP_NOT_BOOL;
    return 0u;
}

uint binary_op_for_form(uint form)
{
    if (form == HIR_EXPR_ADD)
        return X86_OP_ADD_I32;
    if (form == HIR_EXPR_SUB)
        return X86_OP_SUB_I32;
    if (form == HIR_EXPR_MUL)
        return X86_OP_MUL_I32;
    if (form == HIR_EXPR_AND)
        return X86_OP_AND_BOOL;
    if (form == HIR_EXPR_OR)
        return X86_OP_OR_BOOL;
    if (form == HIR_EXPR_MOD)
        return X86_OP_MOD_I32;
    if (form == HIR_EXPR_DIV)
        return X86_OP_DIV_I32;
    if (form == HIR_EXPR_BIT_AND)
        return X86_OP_BIT_AND_I32;
    if (form == HIR_EXPR_BIT_OR)
        return X86_OP_BIT_OR_I32;
    if (form == HIR_EXPR_BIT_XOR)
        return X86_OP_BIT_XOR;
    if (form == HIR_EXPR_SHL)
        return X86_OP_SHL_I32;
    if (form == HIR_EXPR_SHR)
        return X86_OP_SHR_I32;
    return 0u;
}

uint compare_op_for_form(uint form)
{
    if (form == HIR_EXPR_LT)
        return X86_CMP_LT;
    if (form == HIR_EXPR_GT)
        return X86_CMP_GT;
    if (form == HIR_EXPR_LE)
        return X86_CMP_LE;
    if (form == HIR_EXPR_GE)
        return X86_CMP_GE;
    if (form == HIR_EXPR_EQ)
        return X86_CMP_EQ;
    if (form == HIR_EXPR_NE)
        return X86_CMP_NE;
    return 0u;
}

void write_status_error(uint node)
{
    x86_virtual_inst_status[0u] = 0u;
    uint old_error = 0u;
    InterlockedCompareExchange(
        x86_virtual_inst_status[1u],
        0u,
        X86_ERR_NODE_VIRTUAL_INST,
        old_error);
    uint old_detail = INVALID;
    InterlockedMin(x86_virtual_inst_status[2u], node, old_detail);
}

void write_node_value(uint node, uint kind, uint value, uint aux0, uint aux1)
{
    x86_node_value_record[node] = uint4(kind, value, aux0, aux1);
}

void write_inst(uint row, uint node, uint local_i, uint op, uint dst, uint4 args)
{
    if (row >= MAX_X86_INSTS)
    {
        write_status_error(node);
        return;
    }
    x86_virtual_inst_record[row] = uint4(node, local_i, op, dst);
    x86_virtual_inst_args[row] = args;
}

bool emit_expr(uint node, uint4 range)
{
    uint row = INVALID;
    if (!location_for_node_local(node, 0u, row))
        return false;
    uint dst = row;
    uint form = expr_form(node);
    uint value = 0u;

    if (literal_value(node, value))
    {
        write_inst(row, node, 0u, X86_VINST_IMM_I32, dst, uint4(value, 0u, 0u, 0u));
        write_node_value(node, X86_NODE_VALUE_IMM_I32, value, dst, 0u);
        return true;
    }
    if (form == HIR_EXPR_NAME && decl_literal_value(node, value))
    {
        write_inst(row, node, 0u, X86_VINST_IMM_I32, dst, uint4(value, 0u, 0u, 0u));
        write_node_value(node, X86_NODE_VALUE_IMM_I32, value, dst, 0u);
        return true;
    }

    uint4 param_record = uint4(INVALID, INVALID, INVALID, INVALID);
    if (form == HIR_EXPR_NAME && param_record_for_name(node, param_record))
    {
        write_inst(row, node, 0u, X86_VINST_PARAM, dst, param_record);
        write_node_value(node, X86_NODE_VALUE_PARAM, dst, param_record.x, param_record.z);
        return true;
    }

    uint local_vreg = INVALID;
    if (form == HIR_EXPR_NAME && local_decl_vreg_for_name(node, local_vreg))
    {
        write_inst(row, node, 0u, X86_VINST_ALIAS, dst, uint4(local_vreg, 0u, 0u, 0u));
        write_node_value(node, X86_NODE_VALUE_VREG, dst, node, local_vreg);
        return true;
    }

    uint unary_op = unary_op_for_form(form);
    if (unary_op != 0u)
    {
        uint src = INVALID;
        if (!value_vreg_for_node(expr_left(node), src))
            return false;
        write_inst(row, node, 0u, X86_VINST_UNARY, dst, uint4(unary_op, src, 0u, 0u));
        write_node_value(node, X86_NODE_VALUE_VREG, dst, node, 0u);
        return true;
    }

    uint binary_op = binary_op_for_form(form);
    uint compare_op = compare_op_for_form(form);
    if (binary_op != 0u || compare_op != 0u)
    {
        uint left = INVALID;
        uint right = INVALID;
        if (!value_vreg_for_node(expr_left(node), left) ||
            !value_vreg_for_node(expr_right(node), right))
            return false;

        uint op = binary_op != 0u ? binary_op : compare_op;
        uint inst_kind = binary_op != 0u ? X86_VINST_BINARY : X86_VINST_COMPARE;
        write_inst(row, node, 0u, inst_kind, dst, uint4(op, left, right, 0u));
        write_node_value(node, X86_NODE_VALUE_VREG, dst, node, 0u);
        return true;
    }

    return false;
}

bool emit_call(uint node, uint4 range)
{
    uint row = INVALID;
    if (!location_for_node_local(node, 0u, row))
        return false;
    uint dst = row;
    uint4 intrinsic = x86_intrinsic_call_record[node];
    if (intrinsic.y == node && intrinsic.w != INVALID)
    {
        if (intrinsic.w != X86_INTRINSIC_TEXT_WRITE)
            return false;
        uint arg_vreg = INVALID;
        if (!value_vreg_for_node(intrinsic.z, arg_vreg))
            return false;
        write_inst(row, node, 0u, X86_VINST_INTRINSIC, INVALID, uint4(intrinsic.w, arg_vreg, intrinsic.z, 0u));
        return true;
    }

    uint4 call = x86_call_record[node];
    if (call.x == INVALID && call.y == INVALID && call.z == INVALID && call.w == INVALID)
        return false;

    uint4 abi = x86_call_abi_record[node * 2u];
    uint4 abi_args = x86_call_abi_record[node * 2u + 1u];
    uint target_row = INVALID;
    if (!first_instruction_row_in_subtree(abi.y, target_row))
        return false;

    uint arg_count = call.w;
    if (arg_count > 2u)
        return false;

    uint arg0_vreg = INVALID;
    uint arg1_vreg = INVALID;
    if (arg_count >= 1u && !value_vreg_for_node(abi_args.x, arg0_vreg))
        return false;
    if (arg_count >= 2u && !value_vreg_for_node(abi_args.y, arg1_vreg))
        return false;

    write_inst(
        row,
        node,
        0u,
        X86_VINST_CALL,
        dst,
        uint4(target_row, arg_count, pack_vreg_rows(arg0_vreg, arg1_vreg), abi.y));
    write_node_value(node, X86_NODE_VALUE_VREG, dst, node, abi.y);
    return true;
}

bool emit_stmt(uint node, uint4 range)
{
    uint row = INVALID;
    if (!location_for_node_local(node, 0u, row))
        return false;
    uint stmt_kind = stmt_slot(node, 0u);

    if ((hir_kind[node] == HIR_RETURN_STMT || hir_kind[node] == HIR_STMT) &&
        stmt_kind == STMT_RECORD_KIND_RETURN)
    {
        uint src = INVALID;
        if (!value_vreg_for_node(stmt_slot(node, 1u), src))
            return false;
        write_inst(row, node, 0u, X86_VINST_RETURN, INVALID, uint4(src, 0u, 0u, 0u));
        return true;
    }

    if ((hir_kind[node] == HIR_LET_STMT && stmt_kind == STMT_RECORD_KIND_LET) ||
        stmt_kind == STMT_RECORD_KIND_CONST ||
        stmt_kind == STMT_RECORD_KIND_ASSIGN)
    {
        uint src = INVALID;
        if (!value_vreg_for_node(stmt_slot(node, 2u), src))
            return false;
        write_inst(row, node, 0u, X86_VINST_ALIAS, row, uint4(src, stmt_kind, 0u, 0u));
        write_node_value(node, X86_NODE_VALUE_VREG, row, node, src);
        return true;
    }

    if ((hir_kind[node] == HIR_IF_STMT || hir_kind[node] == HIR_STMT) &&
        stmt_kind == STMT_RECORD_KIND_IF)
    {
        uint cond_node = stmt_slot(node, 1u);
        uint then_node = stmt_slot(node, 2u);
        uint else_node = stmt_slot(node, 3u);
        uint cond = INVALID;
        uint false_target = INVALID;
        uint after_target = INVALID;
        if (!value_vreg_for_node(cond_node, cond))
            return false;
        if (valid_node(else_node))
        {
            if (!first_instruction_row_in_subtree(else_node, false_target) ||
                !row_after_subtree(node, after_target))
                return false;
        }
        else if (!row_after_subtree(node, false_target))
            return false;

        write_inst(row, node, 0u, X86_VINST_BRANCH, INVALID, uint4(cond, false_target, 0u, 0u));
        if (valid_node(else_node))
        {
            uint join = INVALID;
            if (!location_for_node_local(node, 1u, join))
                return false;
            write_inst(join, node, 1u, X86_VINST_BRANCH, INVALID, uint4(INVALID, after_target, 0u, 0u));
        }
        return true;
    }

    if ((hir_kind[node] == HIR_WHILE_STMT || hir_kind[node] == HIR_STMT) &&
        stmt_kind == STMT_RECORD_KIND_WHILE &&
        range.y >= 2u)
    {
        uint cond = INVALID;
        uint join = INVALID;
        if (!value_vreg_for_node(stmt_slot(node, 1u), cond))
            return false;
        if (!location_for_node_local(node, 1u, join))
            return false;
        write_inst(row, node, 0u, X86_VINST_LOOP, INVALID, uint4(cond, join, 0u, 0u));
        write_inst(join, node, 1u, X86_VINST_LOOP, INVALID, uint4(cond, 0u, 0u, 0u));
        return true;
    }

    if (hir_kind[node] == HIR_BREAK_STMT || hir_kind[node] == HIR_CONTINUE_STMT)
    {
        write_inst(row, node, 0u, X86_VINST_TRANSFER, INVALID, uint4(hir_kind[node], 0u, 0u, 0u));
        return true;
    }

    return false;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    bool ok = upstream_ok();
    if (node == 0u)
    {
        x86_virtual_inst_status[0u] = ok ? X86_VIRTUAL_INST_OK : 0u;
        x86_virtual_inst_status[1u] = ok ? 0u : X86_ERR_NODE_VIRTUAL_INST;
        x86_virtual_inst_status[2u] = ok ? INVALID : 0u;
        x86_virtual_inst_status[3u] = ok ? x86_node_inst_location_status[3u] : 0u;
    }

    if (!ok || !valid_node(node))
        return;

    uint4 range = uint4(INVALID, 0u, 0u, INVALID);
    if (!range_for_node(node, range))
        return;

    if (range.y == 0u)
    {
        if (!has_location_for_node_local(node, 0u))
        {
            write_node_value(node, X86_NODE_VALUE_NONE, INVALID, 0u, 0u);
            return;
        }
    }

    if (range.z == X86_NODE_INST_PADDING)
        return;

    bool emitted = false;
    if (hir_kind[node] == HIR_CALL_EXPR)
        emitted = emit_call(node, range);
    else if (hir_kind[node] == HIR_STMT ||
             hir_kind[node] == HIR_RETURN_STMT ||
             hir_kind[node] == HIR_LET_STMT ||
             hir_kind[node] == HIR_IF_STMT ||
             hir_kind[node] == HIR_WHILE_STMT ||
             hir_kind[node] == HIR_BREAK_STMT ||
             hir_kind[node] == HIR_CONTINUE_STMT)
        emitted = emit_stmt(node, range);
    else if (hir_kind[node] == HIR_ASSIGN_EXPR ||
             hir_kind[node] == HIR_BINARY_EXPR ||
             hir_kind[node] == HIR_UNARY_EXPR ||
             hir_kind[node] == HIR_NAME_EXPR ||
             hir_kind[node] == HIR_LITERAL_EXPR)
        emitted = emit_expr(node, range);

    if (!emitted)
        write_status_error(node);
}
