// Compact row-parallel aggregate copy emission.
//
// x86_node_inst_gen validates aggregate copy sites and reserves their virtual
// instruction ranges. This pass walks the compact generation worklist and emits
// one aggregate element per invocation, using DispatchThreadID.z as the element
// ordinal instead of making one HIR-node invocation loop over the aggregate
// width.

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
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> x86_struct_access_record;
StructuredBuffer<uint4> x86_struct_store_record;
StructuredBuffer<uint> x86_decl_layout_record;
StructuredBuffer<uint> x86_param_reg_record;
StructuredBuffer<uint> x86_node_inst_range_info;
StructuredBuffer<uint4> x86_node_inst_location_record;
StructuredBuffer<uint> x86_node_inst_gen_input_status;
StructuredBuffer<uint2> x86_node_inst_gen_node_record;
StructuredBuffer<uint> x86_node_func;

RWStructuredBuffer<uint4> x86_virtual_inst_record;
RWStructuredBuffer<uint4> x86_virtual_inst_args;
RWStructuredBuffer<uint> x86_virtual_inst_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_INST_GEN_INPUTS_OK = 1u;
static const uint X86_ERR_NODE_VIRTUAL_INST = 11u;
static const uint X86_VINST_ERROR_AGG_COPY_LOCATION = 3012u;
static const uint X86_VINST_ERROR_AGG_COPY_WIDTH = 3011u;
static const uint X86_VINST_ERROR_AGG_RET_SOURCE_LOCATION = 2622u;
static const uint X86_VINST_ERROR_AGG_RET_COPY_WIDTH = 2623u;
static const uint X86_AGG_COPY_MAX_WIDTH = 65535u;

static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint STMT_RECORD_KIND_CONST = 4u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint HIR_EXPR_NAME = 2u;
static const uint X86_DECL_LAYOUT_STRIDE = 4u;
static const uint X86_DECL_LAYOUT_KIND_MASK = 0x0fu;
static const uint X86_DECL_LAYOUT_KIND_BITS = 4u;
static const uint X86_PARAM_REG_STRIDE = 6u;
static const uint X86_PARAM_REG_ARG_REG_MASK = 0x0fu;
static const uint X86_NODE_INST_RANGE_COUNT_MASK = 0x0fffffffu;
static const uint X86_STRUCT_ACCESS_STRIDE = 3u;
static const uint X86_STRUCT_ACCESS_KIND_BITS = 4u;
static const uint X86_STRUCT_ACCESS_KIND_MASK = 0x0fu;
static const uint X86_STRUCT_ACCESS_MEMBER = 1u;
static const uint X86_VINST_LOAD_LOCAL = 13u;
static const uint X86_VINST_STORE_LOCAL = 14u;
static const uint X86_VINST_COPY_AGG_RET = 23u;
static const uint X86_VINST_LOAD_PARAM_SLOT = 26u;
static const uint X86_AGG_SOURCE_LOCAL = 1u;
static const uint X86_AGG_SOURCE_PARAM = 2u;

uint aggregate_source_payload_offset(uint source_kind, uint payload, uint offset)
{
    if (source_kind == X86_AGG_SOURCE_PARAM)
        return pack_u16_pair(unpack_u16_pair_low(payload), unpack_u16_pair_high(payload) + offset);
    return payload + offset;
}

uint param_aggregate_payload_base(uint payload)
{
    return unpack_u16_pair_low(payload);
}

uint param_aggregate_payload_ordinal(uint payload)
{
    return unpack_u16_pair_high(payload);
}

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint aggregate_ordinal(uint3 tid)
{
    return tid.z;
}

uint gen_worklist_base()
{
    return 0u;
}

uint gen_worklist_count()
{
    return min(
        x86_node_inst_gen_input_status[4u],
        min(gParams.n_hir_nodes, gParams.inst_capacity));
}

uint gen_worklist_node(uint order_row)
{
    return x86_node_inst_gen_node_record[gen_worklist_base() + order_row].x;
}

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool upstream_ok()
{
    return x86_node_inst_gen_input_status[0u] == X86_NODE_INST_GEN_INPUTS_OK &&
           x86_node_inst_gen_input_status[1u] == 0u;
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

bool is_return_stmt_node(uint node)
{
    return valid_node(node) &&
           (hir_kind[node] == HIR_STMT || hir_kind[node] == HIR_RETURN_STMT) &&
           stmt_slot(node, 0u) == STMT_RECORD_KIND_RETURN;
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

uint decl_layout_width(uint row)
{
    return decl_layout_word(row, 1u);
}

uint decl_layout_info(uint row)
{
    return decl_layout_word(row, 2u);
}

uint decl_layout_kind(uint row)
{
    uint info = decl_layout_info(row);
    return info == INVALID ? 0u : info & X86_DECL_LAYOUT_KIND_MASK;
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

uint param_reg_arg_reg(uint decl_token)
{
    uint info = param_reg_info(decl_token);
    return info == INVALID
               ? INVALID
               : info & X86_PARAM_REG_ARG_REG_MASK;
}

uint4 param_reg_record(uint decl_token)
{
    return uint4(
        param_reg_owner(decl_token),
        0u,
        param_reg_arg_reg(decl_token),
        param_reg_width(decl_token));
}

bool decl_aggregate_width(uint decl_token, out uint width)
{
    width = 0u;
    if (valid_token(decl_token))
    {
        uint width_candidate = decl_layout_width(decl_token);
        if (decl_layout_base(decl_token) != INVALID &&
            decl_layout_kind(decl_token) != 0u &&
            width_candidate > 1u)
        {
            width = width_candidate;
            return true;
        }
        uint4 param = param_reg_record(decl_token);
        if (param.x != INVALID && param.w > 1u)
        {
            width = param.w;
            return true;
        }
    }
    return false;
}

uint struct_access_word(uint row, uint slot)
{
    return row_major_load<uint>(
        x86_struct_access_record,
        row,
        X86_STRUCT_ACCESS_STRIDE,
        slot,
        INVALID);
}

uint struct_access_kind(uint row)
{
    uint info = struct_access_word(row, 2u);
    return info == INVALID ? 0u : info & X86_STRUCT_ACCESS_KIND_MASK;
}

uint struct_access_payload0(uint row)
{
    return struct_access_word(row, 0u);
}

uint struct_access_payload1(uint row)
{
    return struct_access_word(row, 1u);
}

bool decl_token_for_name(uint name_node, out uint decl_token)
{
    decl_token = INVALID;
    name_node = resolve_expr(name_node);
    if (!valid_node(name_node) || expr_form(name_node) != HIR_EXPR_NAME)
        return false;

    uint name_token = expr_value_token(name_node);
    if (!valid_token(name_token))
        return false;

    decl_token = visible_decl[name_token];
    return valid_token(decl_token);
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

bool aggregate_source_for_decl(
    uint decl_token,
    uint owner_fn,
    out uint source_kind,
    out uint payload,
    out uint width)
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
        x86_node_func[decl_node] == owner_fn && kind != 0u && local_width > 0u)
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

bool aggregate_source_for_expr(
    uint expr_node,
    uint owner_fn,
    out uint source_kind,
    out uint payload,
    out uint width)
{
    source_kind = 0u;
    payload = INVALID;
    width = 0u;
    uint current = expr_node;
    uint offset = 0u;
    for (uint i = 0u; i < gParams.n_hir_nodes; i++)
    {
        if (valid_node(current) &&
            hir_kind[current] == HIR_MEMBER_EXPR &&
            struct_access_kind(current) == X86_STRUCT_ACCESS_MEMBER)
        {
            uint member_offset = struct_access_payload1(current);
            uint receiver = struct_access_payload0(current);
            if (member_offset == INVALID || !valid_node(receiver))
                return false;
            offset += member_offset;
            current = receiver;
            continue;
        }

        uint resolved = resolve_expr(current);
        if (valid_node(resolved) && resolved != current)
        {
            current = resolved;
            continue;
        }

        uint decl_token = INVALID;
        if (decl_token_for_name(current, decl_token))
        {
            if (!aggregate_source_for_decl(decl_token, owner_fn, source_kind, payload, width))
                return false;
            if (offset >= width)
                return false;
            payload = aggregate_source_payload_offset(source_kind, payload, offset);
            width -= offset;
            return true;
        }

        return false;
    }

    return false;
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
        if (location != INVALID && location < gParams.inst_capacity)
            return true;
    }

    uint2 range = uint2(INVALID, 0u);
    if (!range_for_node(node, range) || local_i >= range_count(range) ||
        range.x + local_i >= gParams.inst_capacity)
        return false;

    location = range.x + local_i;
    return true;
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

bool aggregate_let_copy_info(
    uint node,
    out uint dest_slot,
    out uint dest_width,
    out uint source_kind,
    out uint source_payload)
{
    dest_slot = INVALID;
    dest_width = 0u;
    source_kind = 0u;
    source_payload = INVALID;

    uint stmt_kind = stmt_slot(node, 0u);
    if (!((hir_kind[node] == HIR_LET_STMT || hir_kind[node] == HIR_STMT) &&
          (stmt_kind == STMT_RECORD_KIND_LET ||
           stmt_kind == STMT_RECORD_KIND_CONST)))
        return false;

    uint dest_decl = stmt_slot(node, 1u);
    uint init_expr = stmt_slot(node, 2u);
    if (!local_slot_for_decl(dest_decl, x86_node_func[node], dest_slot) ||
        !decl_aggregate_width(dest_decl, dest_width) ||
        dest_width <= 1u)
        return false;

    uint source_width = 0u;
    return aggregate_source_for_expr(
               init_expr,
               x86_node_func[node],
               source_kind,
               source_payload,
               source_width) &&
           source_width >= dest_width;
}

bool aggregate_return_source_copy_info(
    uint node,
    out uint width,
    out uint source_kind,
    out uint source_payload)
{
    width = 0u;
    source_kind = 0u;
    source_payload = INVALID;
    if (!is_return_stmt_node(node))
        return false;

    uint expr_node = stmt_slot(node, 1u);
    uint source_width = 0u;
    if (!aggregate_source_for_expr(
            expr_node,
            x86_node_func[node],
            source_kind,
            source_payload,
            source_width))
        return false;

    width = source_width;
    return width > 1u;
}

bool aggregate_struct_field_copy_info(
    uint node,
    out uint dest_slot,
    out uint dest_offset,
    out uint copy_width,
    out uint source_kind,
    out uint source_payload)
{
    dest_slot = INVALID;
    dest_offset = 0u;
    copy_width = 0u;
    source_kind = 0u;
    source_payload = INVALID;

    uint value_node = resolve_expr(node);
    if (!valid_node(value_node))
        return false;

    uint4 record = x86_struct_store_record[value_node];
    if (record.w != 0u ||
        !valid_node(record.z) ||
        record.y == INVALID)
        return false;

    uint dest_decl = record.x;
    uint dest_width = 0u;
    if (!local_slot_for_decl(dest_decl, x86_node_func[node], dest_slot) ||
        !decl_aggregate_width(dest_decl, dest_width) ||
        record.y >= dest_width)
        return false;

    uint source_node = resolve_expr(node);
    if (!valid_node(source_node))
        source_node = node;

    uint source_width = 0u;
    if (!aggregate_source_for_expr(
            source_node,
            x86_node_func[node],
            source_kind,
            source_payload,
            source_width) ||
        source_width <= 1u)
        return false;

    dest_offset = record.y;
    copy_width = min(source_width, dest_width - dest_offset);
    return copy_width > 1u;
}

void emit_aggregate_return_source_copy(uint node, uint ordinal)
{
    uint width = 0u;
    uint source_kind = 0u;
    uint source_payload = INVALID;
    if (!aggregate_return_source_copy_info(node, width, source_kind, source_payload))
        return;

    if (width > X86_AGG_COPY_MAX_WIDTH)
    {
        if (ordinal == 0u)
            write_status_error_detail(node, X86_VINST_ERROR_AGG_RET_COPY_WIDTH);
        return;
    }
    if (ordinal >= width)
        return;

    uint row = INVALID;
    if (!location_for_node_local(node, ordinal, row))
    {
        write_status_error_detail(node, X86_VINST_ERROR_AGG_RET_SOURCE_LOCATION);
        return;
    }

    write_inst(
        row,
        node,
        ordinal,
        X86_VINST_COPY_AGG_RET,
        INVALID,
        uint4(source_kind, source_payload, ordinal, 0u));
}

void emit_aggregate_struct_field_copy(uint node, uint ordinal)
{
    uint dest_slot = INVALID;
    uint dest_offset = 0u;
    uint copy_width = 0u;
    uint source_kind = 0u;
    uint source_payload = INVALID;
    if (!aggregate_struct_field_copy_info(
            node,
            dest_slot,
            dest_offset,
            copy_width,
            source_kind,
            source_payload))
        return;

    if (copy_width > X86_AGG_COPY_MAX_WIDTH)
    {
        if (ordinal == 0u)
            write_status_error_detail(node, X86_VINST_ERROR_AGG_COPY_WIDTH);
        return;
    }
    if (ordinal >= copy_width)
        return;

    uint load_row = INVALID;
    uint store_row = INVALID;
    if (!location_for_node_local(node, ordinal * 2u, load_row) ||
        !location_for_node_local(node, ordinal * 2u + 1u, store_row))
    {
        write_status_error_detail(node, X86_VINST_ERROR_AGG_COPY_LOCATION);
        return;
    }

    if (source_kind == X86_AGG_SOURCE_LOCAL)
    {
        write_inst(
            load_row,
            node,
            ordinal * 2u,
            X86_VINST_LOAD_LOCAL,
            load_row,
            uint4(source_payload + ordinal, 0u, 0u, 0u));
    }
    else if (source_kind == X86_AGG_SOURCE_PARAM)
    {
        uint source_base = param_aggregate_payload_base(source_payload);
        uint source_ordinal = param_aggregate_payload_ordinal(source_payload) + ordinal;
        write_inst(
            load_row,
            node,
            ordinal * 2u,
            X86_VINST_LOAD_PARAM_SLOT,
            load_row,
            uint4(source_base, source_ordinal, 0u, 0u));
    }
    else
    {
        write_status_error_detail(node, X86_VINST_ERROR_AGG_COPY_LOCATION);
        return;
    }

    write_inst(
        store_row,
        node,
        ordinal * 2u + 1u,
        X86_VINST_STORE_LOCAL,
        INVALID,
        uint4(dest_slot + dest_offset + ordinal, load_row, 0u, 0u));
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint order_row = linear_dispatch_id(tid);
    uint ordinal = aggregate_ordinal(tid);
    if (!upstream_ok() ||
        order_row >= gen_worklist_count() ||
        ordinal >= X86_AGG_COPY_MAX_WIDTH)
        return;

    uint node = gen_worklist_node(order_row);
    if (!valid_node(node))
        return;

    emit_aggregate_return_source_copy(node, ordinal);
    emit_aggregate_struct_field_copy(node, ordinal);

    uint dest_slot = INVALID;
    uint dest_width = 0u;
    uint source_kind = 0u;
    uint source_payload = INVALID;
    if (!aggregate_let_copy_info(node, dest_slot, dest_width, source_kind, source_payload))
        return;

    if (dest_width > X86_AGG_COPY_MAX_WIDTH)
    {
        if (ordinal == 0u)
            write_status_error_detail(node, X86_VINST_ERROR_AGG_COPY_WIDTH);
        return;
    }
    if (ordinal >= dest_width)
        return;

    uint load_row = INVALID;
    uint store_row = INVALID;
    if (!location_for_node_local(node, ordinal * 2u, load_row) ||
        !location_for_node_local(node, ordinal * 2u + 1u, store_row))
    {
        write_status_error_detail(node, X86_VINST_ERROR_AGG_COPY_LOCATION);
        return;
    }

    if (source_kind == X86_AGG_SOURCE_LOCAL)
    {
        write_inst(
            load_row,
            node,
            ordinal * 2u,
            X86_VINST_LOAD_LOCAL,
            load_row,
            uint4(source_payload + ordinal, 0u, 0u, 0u));
    }
    else if (source_kind == X86_AGG_SOURCE_PARAM)
    {
        uint source_base = param_aggregate_payload_base(source_payload);
        uint source_ordinal = param_aggregate_payload_ordinal(source_payload) + ordinal;
        write_inst(
            load_row,
            node,
            ordinal * 2u,
            X86_VINST_LOAD_PARAM_SLOT,
            load_row,
            uint4(source_base, source_ordinal, 0u, 0u));
    }
    else
    {
        write_status_error_detail(node, X86_VINST_ERROR_AGG_COPY_LOCATION);
        return;
    }

    write_inst(
        store_row,
        node,
        ordinal * 2u + 1u,
        X86_VINST_STORE_LOCAL,
        INVALID,
        uint4(dest_slot + ordinal, load_row, 0u, 0u));
}
