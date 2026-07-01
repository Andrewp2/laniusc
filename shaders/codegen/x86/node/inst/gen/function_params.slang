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
StructuredBuffer<uint> x86_decl_layout_record;
StructuredBuffer<uint4> x86_node_inst_location_record;
StructuredBuffer<uint> x86_node_inst_gen_input_status;
StructuredBuffer<uint2> x86_node_inst_gen_node_record;
StructuredBuffer<uint> x86_node_func;
StructuredBuffer<uint> x86_func_slot_by_node;
StructuredBuffer<uint> x86_param_reg_record;

RWStructuredBuffer<uint4> x86_virtual_inst_record;
RWStructuredBuffer<uint4> x86_virtual_inst_args;
RWStructuredBuffer<uint> x86_virtual_inst_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_INST_GEN_INPUTS_OK = 1u;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_ERR_NODE_VIRTUAL_INST = 11u;
static const uint HIR_FN = 3u;
static const uint HIR_PARAM = 4u;
static const uint X86_DECL_LAYOUT_STRIDE = 4u;
static const uint X86_DECL_LAYOUT_KIND_BITS = 4u;
static const uint X86_PARAM_REG_STRIDE = 6u;
static const uint X86_PARAM_REG_ARG_REG_MASK = 0x0fu;
static const uint X86_LOCATION_META_KIND_MASK = 0xf0000000u;
static const uint X86_LOCATION_META_PARAM_DECL = 0xd0000000u;
static const uint X86_LOCATION_META_PAYLOAD_MASK = 0x0fffffffu;
static const uint X86_VINST_IMM_I32 = 1u;
static const uint X86_VINST_PARAM = 2u;
static const uint X86_VINST_RETURN = 9u;
static const uint X86_VINST_STORE_LOCAL = 14u;
static const uint X86_VINST_ERROR_RETURN_LOCATION = 3003u;

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
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

uint decl_layout_word(uint row, uint slot)
{
    return row_major_load<uint>(
        x86_decl_layout_record,
        row,
        X86_DECL_LAYOUT_STRIDE,
        slot,
        INVALID);
}

uint decl_layout_base(uint row)
{
    return decl_layout_word(row, 0u);
}

uint decl_layout_info(uint row)
{
    return decl_layout_word(row, 2u);
}

uint decl_layout_node(uint row)
{
    uint info = decl_layout_info(row);
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

uint param_node_decl_token(uint param_node)
{
    if (!valid_node(param_node))
        return INVALID;
    uint meta = x86_node_inst_location_record[param_node].w;
    uint decl_token =
        (meta & X86_LOCATION_META_KIND_MASK) == X86_LOCATION_META_PARAM_DECL
            ? (meta & X86_LOCATION_META_PAYLOAD_MASK)
            : INVALID;
    return valid_token(decl_token) ? decl_token : INVALID;
}

uint param_node_reg_word(uint param_node, uint slot)
{
    uint decl_token = param_node_decl_token(param_node);
    return valid_token(decl_token) ? param_reg_word(decl_token, slot) : INVALID;
}

uint param_node_reg_owner(uint param_node)
{
    return param_node_reg_word(param_node, 0u);
}

uint param_node_reg_width(uint param_node)
{
    return param_node_reg_word(param_node, 1u);
}

uint param_node_reg_info(uint param_node)
{
    return param_node_reg_word(param_node, 2u);
}

uint param_node_reg_ordinal(uint param_node)
{
    return param_node_reg_word(param_node, 3u);
}

uint param_node_reg_arg_reg(uint param_node)
{
    uint info = param_node_reg_info(param_node);
    return info == INVALID ? INVALID : info & X86_PARAM_REG_ARG_REG_MASK;
}

uint param_node_reg_link(uint param_node)
{
    return param_node_decl_token(param_node);
}

uint4 param_node_reg_record(uint param_node)
{
    return uint4(
        param_node_reg_owner(param_node),
        param_node_reg_ordinal(param_node),
        param_node_reg_arg_reg(param_node),
        param_node_reg_width(param_node));
}

bool location_for_node_local(uint node, uint local_i, out uint location)
{
    location = INVALID;
    if (!valid_node(node) || !upstream_ok() || local_i >= 4u)
        return false;
    uint4 locations = x86_node_inst_location_record[node];
    if (local_i == 0u) location = locations.x;
    else if (local_i == 1u) location = locations.y;
    else if (local_i == 2u) location = locations.z;
    else location = locations.w;
    return virtual_row_in_stream(location);
}

bool local_slot_for_decl(uint decl_token, uint owner_fn, out uint slot)
{
    slot = INVALID;
    if (!valid_token(decl_token) || owner_fn == INVALID)
        return false;

    uint base = decl_layout_base(decl_token);
    uint decl_node = decl_layout_node(decl_token);
    if (base != INVALID && valid_node(decl_node) && x86_node_func[decl_node] == owner_fn)
    {
        slot = base;
        return true;
    }
    return false;
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

uint function_slot_for_node(uint fn_node)
{
    return valid_node(fn_node) ? x86_func_slot_by_node[fn_node] : INVALID;
}

bool compiled_function_node(uint node)
{
    return valid_node(node) &&
           hir_kind[node] == HIR_FN &&
           x86_node_func[node] == node &&
           function_slot_for_node(node) != INVALID;
}

bool emit_fn_end(uint node)
{
    if (!compiled_function_node(node))
        return false;

    uint value_row = INVALID;
    uint return_row = INVALID;
    if (!location_for_node_local(node, 0u, value_row) ||
        !location_for_node_local(node, 1u, return_row))
    {
        write_status_error_detail(node, X86_VINST_ERROR_RETURN_LOCATION);
        return false;
    }

    write_inst(value_row, node, 0u, X86_VINST_IMM_I32, value_row, uint4(0u, 0u, 0u, 0u));
    write_inst(return_row, node, 1u, X86_VINST_RETURN, INVALID, uint4(value_row, 0u, 0u, 0u));
    return true;
}

bool emit_param(uint node)
{
    if (!valid_node(node) || hir_kind[node] != HIR_PARAM)
        return false;

    uint load_row = INVALID;
    uint store_row = INVALID;
    uint decl_token = param_node_reg_link(node);
    uint local_slot = INVALID;
    if (param_node_reg_owner(node) != x86_node_func[node] ||
        param_node_reg_width(node) != 1u ||
        !valid_token(decl_token) ||
        !local_slot_for_decl(decl_token, x86_node_func[node], local_slot) ||
        !location_for_node_local(node, 0u, load_row) ||
        !location_for_node_local(node, 1u, store_row))
        return false;

    uint4 param_record = param_node_reg_record(node);
    write_inst(load_row, node, 0u, X86_VINST_PARAM, load_row, param_record);
    write_inst(store_row, node, 1u, X86_VINST_STORE_LOCAL, INVALID, uint4(local_slot, load_row, 0u, 0u));
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
    if (!valid_node(node) || (hir_kind[node] != HIR_FN && hir_kind[node] != HIR_PARAM))
        return;
    bool ok = hir_kind[node] == HIR_FN ? emit_fn_end(node) : emit_param(node);
    if (!ok)
        write_status_error_detail(node, hir_kind[node]);
}
