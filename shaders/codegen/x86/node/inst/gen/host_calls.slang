import gpu_index;
import byte_packing;
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
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> hir_expr_string_len;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> x86_decl_layout_record;
StructuredBuffer<uint> x86_param_reg_record;
StructuredBuffer<uint2> x86_call_abi_record;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_start;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> x86_intrinsic_call_record;
StructuredBuffer<uint> x86_node_inst_range_info;
StructuredBuffer<uint4> x86_node_inst_location_record;
StructuredBuffer<uint> x86_node_inst_gen_input_status;
StructuredBuffer<uint2> x86_node_inst_gen_node_record;
StructuredBuffer<uint> x86_short_circuit_rhs_node;
StructuredBuffer<uint> x86_node_func;

RWStructuredBuffer<uint4> x86_virtual_inst_record;
RWStructuredBuffer<uint4> x86_virtual_inst_args;
RWStructuredBuffer<uint> x86_virtual_inst_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_INST_GEN_INPUTS_OK = 1u;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_ERR_NODE_VIRTUAL_INST = 11u;
static const uint X86_ERR_SHORT_CIRCUIT_CALL = 35u;
static const uint X86_VINST_ERROR_CALL_ARG0_NODE = 2106u;
static const uint X86_VINST_ERROR_CALL_ARG1_NODE = 2107u;
static const uint X86_VINST_ERROR_CALL_ARG0_OPERAND = 2108u;
static const uint X86_VINST_ERROR_CALL_ARG1_OPERAND = 2109u;
static const uint X86_VINST_ERROR_CALL_ARG2_OPERAND = 2117u;
static const uint X86_VINST_ERROR_CALL_ARG3_OPERAND = 2118u;
static const uint X86_BACKEND_MAX_PACKED_CALL_ARGS = 6u;
static const uint X86_CALL_ABI_ARG_COUNT_BITS = 8u;
static const uint X86_CALL_ABI_ARG_COUNT_MASK = 0xffu;
static const uint X86_CALL_ABI_RETURN_WIDTH_MAX = 0x00ffffffu;
static const uint X86_CALL_TARGET_HOST_TEXT_WRITE = 0xfffffffeu;
static const uint X86_CALL_TARGET_HOST_I32_TO_F32 = 0xfffffffdu;
static const uint X86_CALL_TARGET_HOST_OPEN_READ_PATH = 0xfffffffcu;
static const uint X86_CALL_TARGET_HOST_OPEN_WRITE_PATH = 0xfffffffbu;
static const uint X86_CALL_TARGET_HOST_READ_I32 = 0xfffffffau;
static const uint X86_CALL_TARGET_HOST_WRITE_I32 = 0xfffffff9u;
static const uint X86_CALL_TARGET_HOST_WRITE_BYTE = 0xfffffff8u;
static const uint X86_CALL_TARGET_HOST_WRITE_NEWLINE = 0xfffffff7u;
static const uint X86_CALL_TARGET_HOST_CLOSE_FILE = 0xfffffff6u;
static const uint X86_CALL_TARGET_HOST_PROCESS_EXIT = 0xfffffff5u;
static const uint X86_CALL_TARGET_HOST_SECURE_U32 = 0xfffffff4u;
static const uint X86_CALL_TARGET_HOST_ALLOC = 0xfffffff3u;
static const uint X86_CALL_TARGET_HOST_DEALLOC = 0xfffffff2u;
static const uint X86_CALL_TARGET_HOST_ARGC = 0xfffffff1u;
static const uint X86_CALL_TARGET_HOST_ARG_LEN = 0xfffffff0u;
static const uint X86_CALL_TARGET_HOST_ARG_READ = 0xffffffefu;
static const uint X86_CALL_TARGET_HOST_UNIX_SECONDS = 0xffffffeeu;
static const uint X86_CALL_TARGET_HOST_CURRENT_DIR_READ = 0xffffffedu;
static const uint X86_CALL_TARGET_HOST_VAR_COUNT = 0xffffffecu;
static const uint X86_CALL_TARGET_HOST_VAR_KEY_LEN = 0xffffffebu;
static const uint X86_CALL_TARGET_HOST_VAR_KEY_READ = 0xffffffeau;
static const uint X86_CALL_TARGET_HOST_VAR_LEN = 0xffffffe9u;
static const uint X86_CALL_TARGET_HOST_VAR_READ = 0xffffffe8u;
static const uint X86_CALL_TARGET_HOST_FS_READ = 0xffffffe7u;
static const uint X86_CALL_TARGET_HOST_FS_WRITE = 0xffffffe6u;
static const uint X86_CALL_TARGET_HOST_FS_OPEN_READ = 0xffffffe5u;
static const uint X86_CALL_TARGET_HOST_FS_OPEN_WRITE = 0xffffffe4u;
static const uint X86_CALL_TARGET_HOST_FS_OPEN_APPEND = 0xffffffe3u;
static const uint X86_CALL_TARGET_HOST_STDIN_READ = 0xffffffe2u;
static const uint X86_CALL_TARGET_HOST_STDOUT_WRITE = 0xffffffe1u;
static const uint X86_CALL_TARGET_HOST_STDERR_WRITE = 0xffffffe0u;
static const uint X86_INTRINSIC_TAG_BITS = 4u;
static const uint X86_INTRINSIC_TAG_MASK = 0xffu;
static const uint X86_NODE_INST_RANGE_COUNT_MASK = 0x0fffffffu;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_PATH_EXPR = 33u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_STRING = 28u;
static const uint X86_DECL_LAYOUT_STRIDE = 4u;
static const uint X86_DECL_LAYOUT_KIND_BITS = 4u;
static const uint X86_DECL_LAYOUT_KIND_MASK = 0x0fu;
static const uint X86_PARAM_REG_STRIDE = 6u;
static const uint X86_PARAM_REG_ARG_REG_MASK = 0x0fu;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint X86_AGG_SOURCE_LOCAL = 1u;
static const uint X86_AGG_SOURCE_PARAM = 2u;
static const uint X86_NODE_VALUE_VREG = 1u;
static const uint X86_NODE_VALUE_IMM_I32 = 2u;
static const uint X86_VINST_NONE = 0u;
static const uint X86_VINST_IMM_I32 = 1u;
static const uint X86_VINST_UNARY = 3u;
static const uint X86_VINST_HOST_TEXT_WRITE = 34u;
static const uint X86_VINST_HOST_OPEN_WRITE_PATH = 35u;
static const uint X86_VINST_HOST_WRITE_I32 = 36u;
static const uint X86_VINST_HOST_WRITE_BYTE = 37u;
static const uint X86_VINST_HOST_WRITE_NEWLINE = 38u;
static const uint X86_VINST_HOST_OPEN_READ_PATH = 39u;
static const uint X86_VINST_HOST_READ_I32 = 40u;
static const uint X86_VINST_HOST_PROCESS_EXIT = 41u;
static const uint X86_VINST_HOST_SECURE_U32 = 42u;
static const uint X86_VINST_HOST_ALLOC = 43u;
static const uint X86_VINST_HOST_DEALLOC = 44u;
static const uint X86_VINST_HOST_ARGC = 45u;
static const uint X86_VINST_HOST_ARG_LEN = 46u;
static const uint X86_VINST_HOST_ARG_READ = 47u;
static const uint X86_VINST_HOST_UNIX_SECONDS = 48u;
static const uint X86_VINST_HOST_CURRENT_DIR_READ = 49u;
static const uint X86_VINST_HOST_VAR_COUNT = 50u;
static const uint X86_VINST_HOST_VAR_KEY_LEN = 51u;
static const uint X86_VINST_HOST_VAR_KEY_READ = 52u;
static const uint X86_VINST_HOST_VAR_LEN = 53u;
static const uint X86_VINST_HOST_VAR_READ = 54u;
static const uint X86_VINST_HOST_CLOSE_FILE = 55u;
static const uint X86_VINST_HOST_FS_READ = 56u;
static const uint X86_VINST_HOST_FS_WRITE = 57u;
static const uint X86_VINST_HOST_FS_OPEN_READ = 58u;
static const uint X86_VINST_HOST_FS_OPEN_WRITE = 59u;
static const uint X86_VINST_HOST_FS_OPEN_APPEND = 60u;
static const uint X86_VINST_HOST_STDIN_READ = 61u;
static const uint X86_VINST_HOST_STDOUT_WRITE = 62u;
static const uint X86_VINST_HOST_STDERR_WRITE = 63u;
static const uint X86_OP_I32_TO_F32 = 4u;

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes;
}

uint active_path_count()
{
    return path_count_out[0u];
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

uint expr_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_expr_record,
        node,
        EXPR_RECORD_STRIDE,
        slot,
        INVALID);
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_FORM) : 0u;
}

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_VALUE_TOKEN) : INVALID;
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
    if (valid_node(node) &&
        hir_kind[node] == HIR_PATH_EXPR &&
        node != resolved &&
        node != root &&
        value_vreg_for_candidate(node, vreg))
        return true;
    vreg = INVALID;
    return false;
}

uint decl_layout_word(uint decl_token, uint slot)
{
    return row_major_load<uint>(
        x86_decl_layout_record,
        decl_token,
        X86_DECL_LAYOUT_STRIDE,
        slot,
        INVALID);
}

uint decl_layout_base(uint decl_token)
{
    return decl_layout_word(decl_token, 0u);
}

uint decl_layout_width(uint decl_token)
{
    return decl_layout_word(decl_token, 1u);
}

uint decl_layout_info(uint decl_token)
{
    return decl_layout_word(decl_token, 2u);
}

uint decl_layout_kind(uint decl_token)
{
    uint info = decl_layout_info(decl_token);
    return info == INVALID ? 0u : info & X86_DECL_LAYOUT_KIND_MASK;
}

uint decl_layout_node(uint decl_token)
{
    uint info = decl_layout_info(decl_token);
    return info == INVALID ? INVALID : info >> X86_DECL_LAYOUT_KIND_BITS;
}

uint param_reg_word(uint decl_token, uint slot)
{
    return row_major_load<uint>(
        x86_param_reg_record,
        decl_token,
        X86_PARAM_REG_STRIDE,
        slot,
        INVALID);
}

uint param_reg_owner(uint decl_token)
{
    return param_reg_word(decl_token, 0u);
}

uint param_reg_width(uint decl_token)
{
    return param_reg_word(decl_token, 1u);
}

uint param_reg_info(uint decl_token)
{
    return param_reg_word(decl_token, 2u);
}

uint param_reg_ordinal(uint decl_token)
{
    return param_reg_word(decl_token, 3u);
}

uint param_reg_arg_reg(uint decl_token)
{
    uint info = param_reg_info(decl_token);
    return info == INVALID ? INVALID : info & X86_PARAM_REG_ARG_REG_MASK;
}

uint4 param_reg_record(uint decl_token)
{
    return uint4(
        param_reg_owner(decl_token),
        param_reg_ordinal(decl_token),
        param_reg_arg_reg(decl_token),
        param_reg_width(decl_token));
}

bool resolved_decl_token_for_name_node(uint name_node, out uint decl_token)
{
    decl_token = INVALID;
    if (!valid_node(name_node) || expr_form(name_node) != HIR_EXPR_NAME)
        return false;
    uint path_i = path_id_by_owner_hir[name_node];
    if (path_i < active_path_count() &&
        resolved_value_status[path_i] == PATH_RESOLVE_STATUS_OK)
    {
        uint decl_i = resolved_value_decl[path_i];
        if (decl_i < active_hir_node_count())
        {
            uint resolved_token = decl_name_token[decl_i];
            if (valid_token(resolved_token))
            {
                decl_token = resolved_token;
                return true;
            }
        }
    }
    uint name_token = expr_value_token(name_node);
    if (!valid_token(name_token))
        return false;
    decl_token = visible_decl[name_token];
    return valid_token(decl_token);
}

bool decl_token_for_name_expr(uint node, out uint decl_token)
{
    decl_token = INVALID;
    uint resolved = resolve_expr(node);
    if (valid_node(resolved) &&
        expr_form(resolved) == HIR_EXPR_NAME &&
        resolved_decl_token_for_name_node(resolved, decl_token))
        return true;
    return valid_node(node) &&
           expr_form(node) == HIR_EXPR_NAME &&
           resolved_decl_token_for_name_node(node, decl_token);
}

bool decl_token_for_name(uint name_node, out uint decl_token)
{
    return decl_token_for_name_expr(name_node, decl_token);
}

bool aggregate_source_for_decl(uint decl_token, uint owner_fn, out uint source_kind, out uint payload, out uint width)
{
    source_kind = 0u;
    payload = INVALID;
    width = 0u;
    if (!valid_token(decl_token))
        return false;
    uint base = decl_layout_base(decl_token);
    uint decl_node = decl_layout_node(decl_token);
    uint kind = decl_layout_kind(decl_token);
    uint local_width = decl_layout_width(decl_token);
    if (base != INVALID && valid_node(decl_node) &&
        x86_node_func[decl_node] == owner_fn && kind != 0u && local_width > 1u)
    {
        source_kind = X86_AGG_SOURCE_LOCAL;
        payload = base;
        width = local_width;
        return true;
    }
    uint4 param = param_reg_record(decl_token);
    if (param.x == owner_fn && param.z != INVALID && param.w > 1u)
    {
        source_kind = X86_AGG_SOURCE_PARAM;
        payload = pack_u16_pair(param.z, 0u);
        width = param.w;
        return true;
    }
    return false;
}

bool aggregate_source_for_name(uint name_node, uint owner_fn, out uint source_kind, out uint payload, out uint width)
{
    source_kind = 0u;
    payload = INVALID;
    width = 0u;
    uint decl_token = INVALID;
    if (!decl_token_for_name(name_node, decl_token))
        return false;
    return aggregate_source_for_decl(decl_token, owner_fn, source_kind, payload, width);
}

bool host_text_write_arg(uint arg_node, uint owner_fn, out uint payload, out uint len)
{
    payload = INVALID;
    len = INVALID;
    uint source_kind = 0u;
    uint width = 0u;
    if (aggregate_source_for_name(arg_node, owner_fn, source_kind, payload, width))
    {
        len = INVALID;
        return source_kind == X86_AGG_SOURCE_LOCAL && width >= 2u;
    }
    uint value_node = resolve_expr(arg_node);
    if (valid_node(value_node) &&
        hir_kind[value_node] == HIR_LITERAL_EXPR &&
        expr_form(value_node) == HIR_EXPR_STRING)
    {
        payload = value_node;
        len = hir_expr_string_len[value_node];
        return true;
    }
    return false;
}

bool host_path_arg(uint arg_node, uint owner_fn, out uint source_kind, out uint payload, out uint len)
{
    source_kind = 0u;
    payload = INVALID;
    len = INVALID;
    uint width = 0u;
    if (aggregate_source_for_name(arg_node, owner_fn, source_kind, payload, width))
    {
        len = INVALID;
        return (source_kind == X86_AGG_SOURCE_LOCAL ||
                source_kind == X86_AGG_SOURCE_PARAM) &&
               width >= 2u;
    }
    uint value_node = resolve_expr(arg_node);
    if (valid_node(value_node) &&
        hir_kind[value_node] == HIR_LITERAL_EXPR &&
        expr_form(value_node) == HIR_EXPR_STRING)
    {
        source_kind = 0u;
        payload = value_node;
        len = hir_expr_string_len[value_node];
        return true;
    }
    return false;
}

uint call_record_slot(uint call_node)
{
    if (!valid_node(call_node))
        return INVALID;
    uint projection = x86_intrinsic_call_record[call_node];
    uint slot = projection == INVALID ? INVALID : projection >> X86_INTRINSIC_TAG_BITS;
    return valid_token(slot) ? slot : INVALID;
}

uint call_abi_arg_count(uint2 abi)
{
    return abi.y & X86_CALL_ABI_ARG_COUNT_MASK;
}

uint call_abi_return_width(uint2 abi)
{
    return abi.y >> X86_CALL_ABI_ARG_COUNT_BITS;
}

bool host_call_target(uint target)
{
    return target >= X86_CALL_TARGET_HOST_STDERR_WRITE &&
           target <= X86_CALL_TARGET_HOST_TEXT_WRITE;
}

bool has_call_abi_record(uint2 abi)
{
    if (abi.x == INVALID || abi.y == INVALID || !host_call_target(abi.x))
        return false;
    uint arg_count = call_abi_arg_count(abi);
    uint return_width = call_abi_return_width(abi);
    return arg_count <= X86_BACKEND_MAX_PACKED_CALL_ARGS &&
           return_width != 0u &&
           return_width <= X86_CALL_ABI_RETURN_WIDTH_MAX;
}

bool host_text_write_abi(uint2 abi)
{
    return has_call_abi_record(abi) &&
           abi.x == X86_CALL_TARGET_HOST_TEXT_WRITE &&
           call_abi_arg_count(abi) == 2u &&
           call_abi_return_width(abi) == 1u;
}

bool host_i32_to_f32_abi(uint2 abi)
{
    return has_call_abi_record(abi) &&
           abi.x == X86_CALL_TARGET_HOST_I32_TO_F32 &&
           call_abi_arg_count(abi) == 1u &&
           call_abi_return_width(abi) == 1u;
}

bool host_abi(uint2 abi, uint target, uint arg_count)
{
    return has_call_abi_record(abi) &&
           abi.x == target &&
           call_abi_arg_count(abi) == arg_count &&
           call_abi_return_width(abi) == 1u;
}

uint call_abi_arg_count_for_call(uint call_node)
{
    uint call_slot = call_record_slot(call_node);
    if (call_slot == INVALID)
        return 0u;
    uint2 abi = x86_call_abi_record[call_slot];
    return has_call_abi_record(abi) ? call_abi_arg_count(abi) : 0u;
}

uint method_member_node_for_call(uint call_node)
{
    if (!valid_node(call_node))
        return INVALID;
    uint callee_node = hir_call_callee_node[call_node];
    if (valid_node(callee_node) && valid_node(hir_member_receiver_node[callee_node]))
        return callee_node;
    uint root = expr_result_root(callee_node);
    return valid_node(root) && valid_node(hir_member_receiver_node[root]) ? root : INVALID;
}

uint method_receiver_node_for_call(uint call_node)
{
    uint member_node = method_member_node_for_call(call_node);
    return valid_node(member_node) ? hir_member_receiver_node[member_node] : INVALID;
}

bool method_receiver_is_abi_arg(uint call_node)
{
    if (method_member_node_for_call(call_node) == INVALID)
        return false;
    uint explicit_count = hir_call_arg_count[call_node];
    return call_abi_arg_count_for_call(call_node) > explicit_count;
}

bool call_arg_node_for_call(uint call_node, uint ordinal, out uint arg_node)
{
    arg_node = INVALID;
    if (!valid_node(call_node))
        return false;
    uint explicit_count = hir_call_arg_count[call_node];
    bool receiver_arg = method_receiver_is_abi_arg(call_node);
    if (receiver_arg)
    {
        if (ordinal == 0u)
        {
            arg_node = method_receiver_node_for_call(call_node);
            return valid_node(arg_node);
        }
        ordinal -= 1u;
    }
    if (ordinal >= explicit_count)
        return false;
    uint start = call_arg_row_start[call_node];
    uint count = call_arg_row_count[call_node];
    if (start == INVALID || ordinal >= count)
        return false;
    arg_node = call_arg_row_node[start + ordinal];
    return valid_node(arg_node);
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

bool call_is_in_short_circuit_rhs(uint call_node)
{
    return valid_node(call_node) &&
           hir_kind[call_node] == HIR_CALL_EXPR &&
           valid_node(x86_short_circuit_rhs_node[call_node]);
}

bool write_short_circuit_call_error(uint call_node)
{
    if (!call_is_in_short_circuit_rhs(call_node))
        return false;
    publish_stage_error_min_detail4(
        x86_virtual_inst_status,
        X86_ERR_SHORT_CIRCUIT_CALL,
        call_node);
    return true;
}

bool emit_host_call(uint node, uint2 abi)
{
    uint row = INVALID;
    if (!location_for_node_local(node, 0u, row))
        return false;
    uint dst = row;
    if (write_short_circuit_call_error(node))
        return false;
    if (host_i32_to_f32_abi(abi))
    {
        uint arg0_node = INVALID;
        uint src = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !value_vreg_for_node(arg0_node, src))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG0_OPERAND);
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_UNARY, dst, uint4(X86_OP_I32_TO_F32, src, 0u, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_PROCESS_EXIT, 1u))
    {
        uint arg0_node = INVALID;
        uint code_vreg = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !value_vreg_for_node(arg0_node, code_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG0_OPERAND);
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_HOST_PROCESS_EXIT, INVALID, uint4(code_vreg, 0u, 0u, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_SECURE_U32, 0u))
    {
        write_inst(row, node, 0u, X86_VINST_HOST_SECURE_U32, dst, uint4(0u, 0u, 0u, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_ARGC, 0u))
    {
        write_inst(row, node, 0u, X86_VINST_HOST_ARGC, dst, uint4(0u, 0u, 0u, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_UNIX_SECONDS, 0u))
    {
        write_inst(row, node, 0u, X86_VINST_HOST_UNIX_SECONDS, dst, uint4(0u, 0u, 0u, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_CURRENT_DIR_READ, 2u))
    {
        uint arg0_node = INVALID;
        uint arg1_node = INVALID;
        uint ptr_vreg = INVALID;
        uint len_vreg = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !call_arg_node_for_call(node, 1u, arg1_node) ||
            !value_vreg_for_node(arg0_node, ptr_vreg) ||
            !value_vreg_for_node(arg1_node, len_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG1_OPERAND);
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_HOST_CURRENT_DIR_READ, dst, uint4(ptr_vreg, len_vreg, 0u, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_VAR_COUNT, 0u))
    {
        write_inst(row, node, 0u, X86_VINST_HOST_VAR_COUNT, dst, uint4(0u, 0u, 0u, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_VAR_KEY_LEN, 1u))
    {
        uint arg0_node = INVALID;
        uint index_vreg = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !value_vreg_for_node(arg0_node, index_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG0_OPERAND);
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_HOST_VAR_KEY_LEN, dst, uint4(index_vreg, 0u, 0u, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_VAR_KEY_READ, 3u))
    {
        uint arg0_node = INVALID;
        uint arg1_node = INVALID;
        uint arg2_node = INVALID;
        uint index_vreg = INVALID;
        uint ptr_vreg = INVALID;
        uint len_vreg = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !call_arg_node_for_call(node, 1u, arg1_node) ||
            !call_arg_node_for_call(node, 2u, arg2_node) ||
            !value_vreg_for_node(arg0_node, index_vreg) ||
            !value_vreg_for_node(arg1_node, ptr_vreg) ||
            !value_vreg_for_node(arg2_node, len_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG2_OPERAND);
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_HOST_VAR_KEY_READ, dst, uint4(index_vreg, ptr_vreg, len_vreg, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_VAR_LEN, 2u))
    {
        uint arg0_node = INVALID;
        uint arg1_node = INVALID;
        uint ptr_vreg = INVALID;
        uint len_vreg = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !call_arg_node_for_call(node, 1u, arg1_node) ||
            !value_vreg_for_node(arg0_node, ptr_vreg) ||
            !value_vreg_for_node(arg1_node, len_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG1_OPERAND);
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_HOST_VAR_LEN, dst, uint4(ptr_vreg, len_vreg, 0u, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_VAR_READ, 4u))
    {
        uint arg0_node = INVALID;
        uint arg1_node = INVALID;
        uint arg2_node = INVALID;
        uint arg3_node = INVALID;
        uint key_ptr_vreg = INVALID;
        uint key_len_vreg = INVALID;
        uint value_ptr_vreg = INVALID;
        uint value_len_vreg = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !call_arg_node_for_call(node, 1u, arg1_node) ||
            !call_arg_node_for_call(node, 2u, arg2_node) ||
            !call_arg_node_for_call(node, 3u, arg3_node) ||
            !value_vreg_for_node(arg0_node, key_ptr_vreg) ||
            !value_vreg_for_node(arg1_node, key_len_vreg) ||
            !value_vreg_for_node(arg2_node, value_ptr_vreg) ||
            !value_vreg_for_node(arg3_node, value_len_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG3_OPERAND);
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_HOST_VAR_READ, dst, uint4(key_ptr_vreg, key_len_vreg, value_ptr_vreg, value_len_vreg));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_ARG_LEN, 1u))
    {
        uint arg0_node = INVALID;
        uint index_vreg = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !value_vreg_for_node(arg0_node, index_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG0_OPERAND);
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_HOST_ARG_LEN, dst, uint4(index_vreg, 0u, 0u, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_ARG_READ, 3u))
    {
        uint arg0_node = INVALID;
        uint arg1_node = INVALID;
        uint arg2_node = INVALID;
        uint index_vreg = INVALID;
        uint ptr_vreg = INVALID;
        uint len_vreg = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !call_arg_node_for_call(node, 1u, arg1_node) ||
            !call_arg_node_for_call(node, 2u, arg2_node) ||
            !value_vreg_for_node(arg0_node, index_vreg) ||
            !value_vreg_for_node(arg1_node, ptr_vreg) ||
            !value_vreg_for_node(arg2_node, len_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG2_OPERAND);
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_HOST_ARG_READ, dst, uint4(index_vreg, ptr_vreg, len_vreg, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_ALLOC, 2u))
    {
        uint arg0_node = INVALID;
        uint arg1_node = INVALID;
        uint size_vreg = INVALID;
        uint align_vreg = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !call_arg_node_for_call(node, 1u, arg1_node) ||
            !value_vreg_for_node(arg0_node, size_vreg) ||
            !value_vreg_for_node(arg1_node, align_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG1_OPERAND);
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_HOST_ALLOC, dst, uint4(size_vreg, align_vreg, 0u, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_DEALLOC, 3u))
    {
        uint arg0_node = INVALID;
        uint arg1_node = INVALID;
        uint arg2_node = INVALID;
        uint ptr_vreg = INVALID;
        uint size_vreg = INVALID;
        uint align_vreg = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !call_arg_node_for_call(node, 1u, arg1_node) ||
            !call_arg_node_for_call(node, 2u, arg2_node) ||
            !value_vreg_for_node(arg0_node, ptr_vreg) ||
            !value_vreg_for_node(arg1_node, size_vreg) ||
            !value_vreg_for_node(arg2_node, align_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG2_OPERAND);
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_HOST_DEALLOC, INVALID, uint4(ptr_vreg, size_vreg, align_vreg, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_OPEN_READ_PATH, 1u))
    {
        uint arg0_node = INVALID;
        uint path_source_kind = 0u;
        uint path_payload = INVALID;
        uint path_len = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !host_path_arg(arg0_node, x86_node_func[node], path_source_kind, path_payload, path_len))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG0_OPERAND);
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_HOST_OPEN_READ_PATH, dst, uint4(path_payload, path_len, path_source_kind, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_FS_OPEN_READ, 2u) ||
        host_abi(abi, X86_CALL_TARGET_HOST_FS_OPEN_WRITE, 2u) ||
        host_abi(abi, X86_CALL_TARGET_HOST_FS_OPEN_APPEND, 2u))
    {
        uint arg0_node = INVALID;
        uint arg1_node = INVALID;
        uint ptr_vreg = INVALID;
        uint len_vreg = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !call_arg_node_for_call(node, 1u, arg1_node) ||
            !value_vreg_for_node(arg0_node, ptr_vreg) ||
            !value_vreg_for_node(arg1_node, len_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG1_OPERAND);
            return false;
        }
        uint op = abi.x == X86_CALL_TARGET_HOST_FS_OPEN_READ
                      ? X86_VINST_HOST_FS_OPEN_READ
                      : abi.x == X86_CALL_TARGET_HOST_FS_OPEN_WRITE
                          ? X86_VINST_HOST_FS_OPEN_WRITE
                          : X86_VINST_HOST_FS_OPEN_APPEND;
        write_inst(row, node, 0u, op, dst, uint4(ptr_vreg, len_vreg, 0u, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_READ_I32, 2u))
    {
        uint arg0_node = INVALID;
        uint arg1_node = INVALID;
        uint handle_vreg = INVALID;
        uint fallback_vreg = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !call_arg_node_for_call(node, 1u, arg1_node) ||
            !value_vreg_for_node(arg0_node, handle_vreg) ||
            !value_vreg_for_node(arg1_node, fallback_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG1_OPERAND);
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_HOST_READ_I32, dst, uint4(handle_vreg, fallback_vreg, 0u, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_CLOSE_FILE, 1u))
    {
        uint arg0_node = INVALID;
        uint handle_vreg = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !value_vreg_for_node(arg0_node, handle_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG0_OPERAND);
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_HOST_CLOSE_FILE, dst, uint4(handle_vreg, 0u, 0u, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_OPEN_WRITE_PATH, 1u))
    {
        uint arg0_node = INVALID;
        uint path_source_kind = 0u;
        uint path_payload = INVALID;
        uint path_len = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !host_path_arg(arg0_node, x86_node_func[node], path_source_kind, path_payload, path_len))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG0_OPERAND);
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_HOST_OPEN_WRITE_PATH, dst, uint4(path_payload, path_len, path_source_kind, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_WRITE_I32, 2u) ||
        host_abi(abi, X86_CALL_TARGET_HOST_WRITE_BYTE, 2u))
    {
        uint arg0_node = INVALID;
        uint arg1_node = INVALID;
        uint handle_vreg = INVALID;
        uint value_vreg = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !call_arg_node_for_call(node, 1u, arg1_node) ||
            !value_vreg_for_node(arg0_node, handle_vreg) ||
            !value_vreg_for_node(arg1_node, value_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG0_OPERAND);
            return false;
        }
        uint op = abi.x == X86_CALL_TARGET_HOST_WRITE_I32
                      ? X86_VINST_HOST_WRITE_I32
                      : X86_VINST_HOST_WRITE_BYTE;
        write_inst(row, node, 0u, op, dst, uint4(handle_vreg, value_vreg, 0u, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_WRITE_NEWLINE, 1u))
    {
        uint arg0_node = INVALID;
        uint handle_vreg = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !value_vreg_for_node(arg0_node, handle_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG0_OPERAND);
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_HOST_WRITE_NEWLINE, dst, uint4(handle_vreg, 0u, 0u, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_FS_READ, 3u) ||
        host_abi(abi, X86_CALL_TARGET_HOST_FS_WRITE, 3u))
    {
        uint arg0_node = INVALID;
        uint arg1_node = INVALID;
        uint arg2_node = INVALID;
        uint handle_vreg = INVALID;
        uint ptr_vreg = INVALID;
        uint len_vreg = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !call_arg_node_for_call(node, 1u, arg1_node) ||
            !call_arg_node_for_call(node, 2u, arg2_node) ||
            !value_vreg_for_node(arg0_node, handle_vreg) ||
            !value_vreg_for_node(arg1_node, ptr_vreg) ||
            !value_vreg_for_node(arg2_node, len_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG2_OPERAND);
            return false;
        }
        uint op = abi.x == X86_CALL_TARGET_HOST_FS_READ
                      ? X86_VINST_HOST_FS_READ
                      : X86_VINST_HOST_FS_WRITE;
        write_inst(row, node, 0u, op, dst, uint4(handle_vreg, ptr_vreg, len_vreg, 0u));
        return true;
    }
    if (host_abi(abi, X86_CALL_TARGET_HOST_STDIN_READ, 2u) ||
        host_abi(abi, X86_CALL_TARGET_HOST_STDOUT_WRITE, 2u) ||
        host_abi(abi, X86_CALL_TARGET_HOST_STDERR_WRITE, 2u))
    {
        uint arg0_node = INVALID;
        uint arg1_node = INVALID;
        uint ptr_vreg = INVALID;
        uint len_vreg = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node) ||
            !call_arg_node_for_call(node, 1u, arg1_node) ||
            !value_vreg_for_node(arg0_node, ptr_vreg) ||
            !value_vreg_for_node(arg1_node, len_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG1_OPERAND);
            return false;
        }
        uint op = abi.x == X86_CALL_TARGET_HOST_STDIN_READ
                      ? X86_VINST_HOST_STDIN_READ
                      : abi.x == X86_CALL_TARGET_HOST_STDOUT_WRITE
                          ? X86_VINST_HOST_STDOUT_WRITE
                          : X86_VINST_HOST_STDERR_WRITE;
        write_inst(row, node, 0u, op, dst, uint4(ptr_vreg, len_vreg, 0u, 0u));
        return true;
    }
    if (host_text_write_abi(abi))
    {
        uint arg0_node = INVALID;
        uint arg1_node = INVALID;
        uint handle_vreg = INVALID;
        uint text_payload = INVALID;
        uint text_len = INVALID;
        if (!call_arg_node_for_call(node, 0u, arg0_node))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG0_NODE);
            return false;
        }
        if (!call_arg_node_for_call(node, 1u, arg1_node))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG1_NODE);
            return false;
        }
        if (!value_vreg_for_node(arg0_node, handle_vreg))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG0_OPERAND);
            return false;
        }
        if (!host_text_write_arg(arg1_node, x86_node_func[node], text_payload, text_len))
        {
            write_status_error_detail(node, X86_VINST_ERROR_CALL_ARG1_OPERAND);
            return false;
        }
        write_inst(row, node, 0u, X86_VINST_HOST_TEXT_WRITE, dst, uint4(handle_vreg, text_payload, text_len, arg1_node));
        uint payload_row = INVALID;
        if (location_for_node_local(node, 1u, payload_row))
            write_inst(payload_row, node, 1u, X86_VINST_NONE, INVALID, uint4(0u, 0u, 0u, 0u));
        return true;
    }
    return false;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint order_row = linear_dispatch_id(tid);
    if (!upstream_ok() || order_row >= gen_worklist_count())
        return;
    uint node = gen_worklist_node(order_row);
    if (!valid_node(node) || hir_kind[node] != HIR_CALL_EXPR)
        return;
    uint call_slot = call_record_slot(node);
    if (call_slot == INVALID)
        return;
    uint2 abi = x86_call_abi_record[call_slot];
    if (!has_call_abi_record(abi))
        return;
    if (!emit_host_call(node, abi))
        write_status_error_detail(node, hir_kind[node]);
}
