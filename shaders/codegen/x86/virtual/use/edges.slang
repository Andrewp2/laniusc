// x86_64 virtual-instruction def-use expansion.
//
// This pass consumes node-generated virtual instruction records and writes
// explicit use-edge rows for virtual registers. It is the virtual-instruction
// counterpart of the older expression-vreg use edge pass.

import gpu_index;
import byte_packing;
import bit_packing;
import prefix_scan;
import scatter;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
    uint virtual_use_edge_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint4> x86_virtual_inst_record;
StructuredBuffer<uint4> x86_virtual_inst_args;
StructuredBuffer<uint> x86_virtual_inst_status;
StructuredBuffer<uint> x86_virtual_use_count;
StructuredBuffer<uint> x86_virtual_use_scan_local_prefix;
StructuredBuffer<uint> x86_virtual_use_scan_block_prefix;

RWStructuredBuffer<uint> x86_virtual_use_key;
RWStructuredBuffer<uint> x86_virtual_use_value;
RWStructuredBuffer<uint> x86_virtual_use_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WG_SIZE = 256u;
static const uint INVALID = 0xffffffffu;
static const uint MAX_X86_OPERANDS = 6u;
static const uint X86_USE_KEY_SLOT_BITS = 3u;
static const uint X86_USE_KEY_SLOT_MASK = 0x7u;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_VIRTUAL_USE_OK = 1u;
static const uint X86_ERR_VIRTUAL_USE = 13u;

static const uint X86_VINST_IMM_I32 = 1u;
static const uint X86_VINST_PARAM = 2u;
static const uint X86_VINST_UNARY = 3u;
static const uint X86_VINST_BINARY = 4u;
static const uint X86_VINST_COMPARE = 5u;
static const uint X86_VINST_INTRINSIC = 7u;
static const uint X86_VINST_ALIAS = 8u;
static const uint X86_VINST_RETURN = 9u;
static const uint X86_VINST_BRANCH = 10u;
static const uint X86_VINST_LOOP = 11u;
static const uint X86_VINST_TRANSFER = 12u;
static const uint X86_VINST_LOAD_LOCAL = 13u;
static const uint X86_VINST_STORE_LOCAL = 14u;
static const uint X86_VINST_LOAD_LOCAL_INDEX = 15u;
static const uint X86_VINST_STORE_LOCAL_IMM = 16u;
static const uint X86_VINST_FOR_ARRAY_BRANCH = 17u;
static const uint X86_VINST_FOR_ARRAY_LOAD = 18u;
static const uint X86_VINST_FOR_ARRAY_INC_JMP = 19u;
static const uint X86_VINST_CALL_MIXED = 20u;
static const uint X86_VINST_LOAD_PARAM_INDEX = 21u;
static const uint X86_VINST_STORE_RET_PTR = 22u;
static const uint X86_VINST_STORE_LOCAL_INDEX = 30u;
static const uint X86_VINST_STORE_PARAM_INDEX = 32u;
static const uint X86_VINST_HOST_TEXT_WRITE = 34u;
static const uint X86_VINST_HOST_OPEN_WRITE_PATH = 35u;
static const uint X86_VINST_HOST_WRITE_I32 = 36u;
static const uint X86_VINST_HOST_WRITE_BYTE = 37u;
static const uint X86_VINST_HOST_WRITE_NEWLINE = 38u;
static const uint X86_VINST_HOST_READ_I32 = 40u;
static const uint X86_VINST_HOST_PROCESS_EXIT = 41u;
static const uint X86_VINST_HOST_ALLOC = 43u;
static const uint X86_VINST_HOST_DEALLOC = 44u;
static const uint X86_VINST_HOST_ARG_LEN = 46u;
static const uint X86_VINST_HOST_ARG_READ = 47u;
static const uint X86_VINST_HOST_CURRENT_DIR_READ = 49u;
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
static const uint X86_VINST_HOST_FILL_SECURE_BYTES = 64u;
static const uint X86_VINST_HOST_FS_REMOVE_FILE = 65u;
static const uint X86_VINST_HOST_FS_CREATE_DIR = 66u;
static const uint X86_VINST_HOST_FS_REMOVE_DIR = 67u;
static const uint X86_VINST_HOST_FS_RENAME = 68u;
static const uint X86_VINST_HOST_TIME_MONOTONIC_READ = 69u;
static const uint X86_VINST_HOST_TIME_SYSTEM_READ = 70u;
static const uint X86_VINST_HOST_TIME_SLEEP_MS_I32 = 71u;
static const uint X86_VINST_HOST_REALLOC = 72u;
static const uint X86_VINST_HOST_ALLOC_FAILED = 73u;
static const uint X86_ARG_SCALAR = 1u;

uint mixed_arg_count(uint info)
{
    return info & 0xffu;
}

uint pack_count_error_extra(uint op, uint observed_count, uint supported_count)
{
    return ((op & 0xffu) << 24u) |
           ((observed_count & 0xfffu) << 12u) |
           (supported_count & 0xfffu);
}

uint mixed_arg_kind(uint info, uint ordinal)
{
    if (ordinal < 4u)
        return packed_u2_at_offset(info, 12u, ordinal);
    if (ordinal < 6u)
        return packed_u2_at_offset(info, 20u, ordinal - 4u);
    return 0u;
}

uint mixed_arg_payload(uint row, uint ordinal)
{
    uint4 args = x86_virtual_inst_args[row];
    uint payload_row = args.z;
    if (payload_row == INVALID || payload_row >= virtual_inst_count() || ordinal >= 6u)
        return INVALID;
    if (ordinal < 3u)
        return x86_virtual_inst_args[payload_row][ordinal];

    uint payload_row_hi = x86_virtual_inst_record[payload_row].w;
    if (payload_row_hi == INVALID || payload_row_hi >= virtual_inst_count())
        return INVALID;
    return x86_virtual_inst_args[payload_row_hi][ordinal - 3u];
}

uint mixed_scalar_operand_count(uint row)
{
    uint4 args = x86_virtual_inst_args[row];
    uint info = args.w;
    uint count = 0u;
    uint arg_count = mixed_arg_count(info);
    if (arg_count > 0u && mixed_arg_kind(info, 0u) == X86_ARG_SCALAR) count += 1u;
    if (arg_count > 1u && mixed_arg_kind(info, 1u) == X86_ARG_SCALAR) count += 1u;
    if (arg_count > 2u && mixed_arg_kind(info, 2u) == X86_ARG_SCALAR) count += 1u;
    if (arg_count > 3u && mixed_arg_kind(info, 3u) == X86_ARG_SCALAR) count += 1u;
    if (arg_count > 4u && mixed_arg_kind(info, 4u) == X86_ARG_SCALAR) count += 1u;
    if (arg_count > 5u && mixed_arg_kind(info, 5u) == X86_ARG_SCALAR) count += 1u;
    return count;
}

uint mixed_scalar_operand_at(uint row, uint slot)
{
    uint4 args = x86_virtual_inst_args[row];
    uint info = args.w;
    uint seen = 0u;
    uint arg_count = mixed_arg_count(info);
    if (arg_count > 0u && mixed_arg_kind(info, 0u) == X86_ARG_SCALAR)
    {
        if (seen == slot) return mixed_arg_payload(row, 0u);
        seen += 1u;
    }
    if (arg_count > 1u && mixed_arg_kind(info, 1u) == X86_ARG_SCALAR)
    {
        if (seen == slot) return mixed_arg_payload(row, 1u);
        seen += 1u;
    }
    if (arg_count > 2u && mixed_arg_kind(info, 2u) == X86_ARG_SCALAR)
    {
        if (seen == slot) return mixed_arg_payload(row, 2u);
        seen += 1u;
    }
    if (arg_count > 3u && mixed_arg_kind(info, 3u) == X86_ARG_SCALAR)
    {
        if (seen == slot) return mixed_arg_payload(row, 3u);
        seen += 1u;
    }
    if (arg_count > 4u && mixed_arg_kind(info, 4u) == X86_ARG_SCALAR)
    {
        if (seen == slot) return mixed_arg_payload(row, 4u);
        seen += 1u;
    }
    if (arg_count > 5u && mixed_arg_kind(info, 5u) == X86_ARG_SCALAR)
    {
        if (seen == slot) return mixed_arg_payload(row, 5u);
    }
    return INVALID;
}

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint virtual_inst_count()
{
    return min(x86_virtual_inst_status[3u], gParams.inst_capacity);
}

bool upstream_ok()
{
    return x86_virtual_inst_status[0u] == X86_VIRTUAL_INST_OK &&
           x86_virtual_inst_status[1u] == 0u;
}

uint use_edge_total(uint inst_count)
{
    if (inst_count == 0u)
        return 0u;
    uint last_row = inst_count - 1u;
    return global_exclusive_prefix(
               last_row,
               WG_SIZE,
               x86_virtual_use_scan_local_prefix,
               x86_virtual_use_scan_block_prefix) +
           x86_virtual_use_count[last_row];
}

uint operand_count_for_row(uint row)
{
    uint op = x86_virtual_inst_record[row].z;
    uint4 args = x86_virtual_inst_args[row];
    if (op == X86_VINST_UNARY ||
        op == X86_VINST_ALIAS ||
        op == X86_VINST_RETURN ||
        op == X86_VINST_STORE_LOCAL ||
        op == X86_VINST_LOAD_LOCAL_INDEX ||
        op == X86_VINST_LOAD_PARAM_INDEX ||
        op == X86_VINST_STORE_RET_PTR)
        return 1u;
    if (op == X86_VINST_BRANCH ||
        op == X86_VINST_LOOP)
        return args.x == INVALID ? 0u : 1u;
    if (op == X86_VINST_INTRINSIC)
        return 1u;
    if (op == X86_VINST_HOST_TEXT_WRITE)
        return 1u;
    if (op == X86_VINST_HOST_WRITE_NEWLINE)
        return 1u;
    if (op == X86_VINST_HOST_PROCESS_EXIT)
        return 1u;
    if (op == X86_VINST_HOST_ARG_LEN)
        return 1u;
    if (op == X86_VINST_HOST_VAR_KEY_LEN)
        return 1u;
    if (op == X86_VINST_HOST_CLOSE_FILE)
        return 1u;
    if (op == X86_VINST_HOST_READ_I32 ||
        op == X86_VINST_HOST_WRITE_I32 ||
        op == X86_VINST_HOST_WRITE_BYTE ||
        op == X86_VINST_HOST_ALLOC ||
        op == X86_VINST_HOST_CURRENT_DIR_READ ||
        op == X86_VINST_HOST_VAR_LEN ||
        op == X86_VINST_HOST_FS_OPEN_READ ||
        op == X86_VINST_HOST_FS_OPEN_WRITE ||
        op == X86_VINST_HOST_FS_OPEN_APPEND ||
        op == X86_VINST_HOST_STDIN_READ ||
        op == X86_VINST_HOST_STDOUT_WRITE ||
        op == X86_VINST_HOST_STDERR_WRITE ||
        op == X86_VINST_HOST_FILL_SECURE_BYTES ||
        op == X86_VINST_HOST_FS_REMOVE_FILE ||
        op == X86_VINST_HOST_FS_CREATE_DIR ||
        op == X86_VINST_HOST_FS_REMOVE_DIR ||
        op == X86_VINST_HOST_TIME_MONOTONIC_READ ||
        op == X86_VINST_HOST_TIME_SYSTEM_READ)
        return 2u;
    if (op == X86_VINST_HOST_TIME_SLEEP_MS_I32)
        return 1u;
    if (op == X86_VINST_CALL_MIXED)
        return mixed_scalar_operand_count(row);
    if (op == X86_VINST_HOST_DEALLOC)
        return 3u;
    if (op == X86_VINST_HOST_ARG_READ)
        return 3u;
    if (op == X86_VINST_HOST_VAR_KEY_READ)
        return 3u;
    if (op == X86_VINST_HOST_FS_READ ||
        op == X86_VINST_HOST_FS_WRITE)
        return 3u;
    if (op == X86_VINST_HOST_VAR_READ)
        return 4u;
    if (op == X86_VINST_HOST_FS_RENAME)
        return 4u;
    if (op == X86_VINST_HOST_REALLOC)
        return 4u;
    if (op == X86_VINST_HOST_ALLOC_FAILED)
        return 2u;
    if (op == X86_VINST_BINARY ||
        op == X86_VINST_COMPARE ||
        op == X86_VINST_STORE_LOCAL_INDEX ||
        op == X86_VINST_STORE_PARAM_INDEX)
        return 2u;
    return 0u;
}

uint operand_at(uint row, uint slot)
{
    uint4 args = x86_virtual_inst_args[row];
    uint op = x86_virtual_inst_record[row].z;
    if (op == X86_VINST_UNARY)
        return slot == 0u ? args.y : INVALID;
    if (op == X86_VINST_BINARY || op == X86_VINST_COMPARE)
    {
        if (slot == 0u) return args.y;
        if (slot == 1u) return args.z;
        return INVALID;
    }
    if (op == X86_VINST_STORE_LOCAL_INDEX ||
        op == X86_VINST_STORE_PARAM_INDEX)
    {
        if (slot == 0u) return args.y;
        if (slot == 1u) return args.z;
        return INVALID;
    }
    if (op == X86_VINST_CALL_MIXED)
        return mixed_scalar_operand_at(row, slot);
    if (op == X86_VINST_INTRINSIC)
        return slot == 0u ? args.y : INVALID;
    if (op == X86_VINST_HOST_TEXT_WRITE)
        return slot == 0u ? args.x : INVALID;
    if (op == X86_VINST_HOST_WRITE_NEWLINE)
        return slot == 0u ? args.x : INVALID;
    if (op == X86_VINST_HOST_PROCESS_EXIT)
        return slot == 0u ? args.x : INVALID;
    if (op == X86_VINST_HOST_ARG_LEN)
        return slot == 0u ? args.x : INVALID;
    if (op == X86_VINST_HOST_VAR_KEY_LEN)
        return slot == 0u ? args.x : INVALID;
    if (op == X86_VINST_HOST_CLOSE_FILE)
        return slot == 0u ? args.x : INVALID;
    if (op == X86_VINST_HOST_READ_I32 ||
        op == X86_VINST_HOST_WRITE_I32 ||
        op == X86_VINST_HOST_WRITE_BYTE ||
        op == X86_VINST_HOST_ALLOC ||
        op == X86_VINST_HOST_CURRENT_DIR_READ ||
        op == X86_VINST_HOST_VAR_LEN ||
        op == X86_VINST_HOST_FS_OPEN_READ ||
        op == X86_VINST_HOST_FS_OPEN_WRITE ||
        op == X86_VINST_HOST_FS_OPEN_APPEND ||
        op == X86_VINST_HOST_STDIN_READ ||
        op == X86_VINST_HOST_STDOUT_WRITE ||
        op == X86_VINST_HOST_STDERR_WRITE ||
        op == X86_VINST_HOST_FILL_SECURE_BYTES ||
        op == X86_VINST_HOST_FS_REMOVE_FILE ||
        op == X86_VINST_HOST_FS_CREATE_DIR ||
        op == X86_VINST_HOST_FS_REMOVE_DIR ||
        op == X86_VINST_HOST_TIME_MONOTONIC_READ ||
        op == X86_VINST_HOST_TIME_SYSTEM_READ)
    {
        if (slot == 0u) return args.x;
        if (slot == 1u) return args.y;
        return INVALID;
    }
    if (op == X86_VINST_HOST_TIME_SLEEP_MS_I32)
        return slot == 0u ? args.x : INVALID;
    if (op == X86_VINST_HOST_DEALLOC)
    {
        if (slot == 0u) return args.x;
        if (slot == 1u) return args.y;
        if (slot == 2u) return args.z;
        return INVALID;
    }
    if (op == X86_VINST_HOST_ARG_READ)
    {
        if (slot == 0u) return args.x;
        if (slot == 1u) return args.y;
        if (slot == 2u) return args.z;
        return INVALID;
    }
    if (op == X86_VINST_HOST_FS_READ ||
        op == X86_VINST_HOST_FS_WRITE)
    {
        if (slot == 0u) return args.x;
        if (slot == 1u) return args.y;
        if (slot == 2u) return args.z;
        return INVALID;
    }
    if (op == X86_VINST_HOST_VAR_KEY_READ)
    {
        if (slot == 0u) return args.x;
        if (slot == 1u) return args.y;
        if (slot == 2u) return args.z;
        return INVALID;
    }
    if (op == X86_VINST_HOST_VAR_READ)
    {
        if (slot == 0u) return args.x;
        if (slot == 1u) return args.y;
        if (slot == 2u) return args.z;
        if (slot == 3u) return args.w;
        return INVALID;
    }
    if (op == X86_VINST_HOST_FS_RENAME)
    {
        if (slot == 0u) return args.x;
        if (slot == 1u) return args.y;
        if (slot == 2u) return args.z;
        if (slot == 3u) return args.w;
        return INVALID;
    }
    if (op == X86_VINST_HOST_REALLOC)
    {
        if (slot == 0u) return args.x;
        if (slot == 1u) return args.y;
        if (slot == 2u) return args.z;
        if (slot == 3u) return args.w;
        return INVALID;
    }
    if (op == X86_VINST_HOST_ALLOC_FAILED)
    {
        if (slot == 0u) return args.x;
        if (slot == 1u) return args.y;
        return INVALID;
    }
    if (op == X86_VINST_ALIAS ||
        op == X86_VINST_RETURN ||
        op == X86_VINST_STORE_LOCAL ||
        op == X86_VINST_LOAD_LOCAL_INDEX ||
        op == X86_VINST_LOAD_PARAM_INDEX ||
        op == X86_VINST_STORE_RET_PTR ||
        op == X86_VINST_BRANCH ||
        op == X86_VINST_LOOP)
        return slot == 0u ? ((op == X86_VINST_STORE_LOCAL ||
                              op == X86_VINST_LOAD_LOCAL_INDEX ||
                              op == X86_VINST_LOAD_PARAM_INDEX) ? args.y : args.x) : INVALID;
    return INVALID;
}

bool valid_virtual_value(uint row, uint inst_count)
{
    if (row == INVALID || row >= inst_count)
        return false;
    uint4 inst = x86_virtual_inst_record[row];
    return inst.x != INVALID && inst.z != 0u && inst.w == row;
}

uint pack_use_key(uint user_row, uint slot)
{
    return (user_row << X86_USE_KEY_SLOT_BITS) |
           (slot & X86_USE_KEY_SLOT_MASK);
}

uint pack_error_extra(uint op, uint slot, uint operand, uint inst_count)
{
    uint operand_op = operand < inst_count ? x86_virtual_inst_record[operand].z : 0xffu;
    return ((slot & 0x07u) << 29u) |
           ((op & 0xffu) << 21u) |
           ((operand_op & 0xffu) << 13u) |
           (operand & 0x00001fffu);
}

void publish_error(uint detail, uint extra)
{
    publish_stage_error_min_detail_extra4(
        x86_virtual_use_status,
        X86_ERR_VIRTUAL_USE,
        detail,
        extra);
}

void write_use_edge(uint edge_i, uint user_row, uint value_row, uint slot)
{
    if (edge_i >= gParams.virtual_use_edge_capacity)
    {
        publish_error(user_row, value_row);
        return;
    }
    x86_virtual_use_key[edge_i] = pack_use_key(user_row, slot);
    x86_virtual_use_value[edge_i] = value_row;
}

bool write_operand_use_edge(uint row, uint inst_count, uint op, uint edge_base, uint slot)
{
    uint operand = operand_at(row, slot);
    if (!valid_virtual_value(operand, inst_count))
    {
        publish_error(row, pack_error_extra(op, slot, operand, inst_count));
        return false;
    }
    write_use_edge(edge_base + slot, row, operand, slot);
    return true;
}

bool validate_operand_record(uint row, uint op)
{
    if (op == X86_VINST_CALL_MIXED)
    {
        uint arg_count = mixed_arg_count(x86_virtual_inst_args[row].w);
        if (arg_count > MAX_X86_OPERANDS)
        {
            publish_error(
                row,
                pack_count_error_extra(op, arg_count, MAX_X86_OPERANDS));
            return false;
        }
    }
    return true;
}

bool validate_recorded_operand_count(
    uint row,
    uint op,
    out uint operand_count)
{
    operand_count = 0u;
    if (!validate_operand_record(row, op))
        return false;

    uint expected_count = operand_count_for_row(row);
    uint recorded_count = x86_virtual_use_count[row];
    if (recorded_count != expected_count || recorded_count > MAX_X86_OPERANDS)
    {
        publish_error(
            row,
            pack_count_error_extra(op, recorded_count, expected_count));
        return false;
    }

    operand_count = recorded_count;
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    uint inst_count = virtual_inst_count();
    bool ok = upstream_ok() && x86_virtual_inst_status[3u] <= gParams.inst_capacity;

    if (row == 0u)
    {
        uint use_edges = ok ? use_edge_total(inst_count) : 0u;
        if (use_edges > gParams.virtual_use_edge_capacity)
            ok = false;
        x86_virtual_use_status[0u] = ok ? X86_VIRTUAL_USE_OK : 0u;
        x86_virtual_use_status[1u] = ok ? 0u :
                                      (x86_virtual_inst_status[1u] == 0u ?
                                       X86_ERR_VIRTUAL_USE :
                                       x86_virtual_inst_status[1u]);
        x86_virtual_use_status[2u] = ok ? INVALID :
                                      (x86_virtual_inst_status[1u] == 0u ?
                                       x86_virtual_inst_status[3u] :
                                       x86_virtual_inst_status[2u]);
        x86_virtual_use_status[3u] = ok ? use_edges : 0u;
    }

    if (!ok || row >= inst_count)
        return;

    uint4 inst = x86_virtual_inst_record[row];
    if (inst.x == INVALID || inst.z == 0u)
        return;

    uint operand_count = 0u;
    if (!validate_recorded_operand_count(row, inst.z, operand_count))
        return;

    uint edge_base = global_exclusive_prefix(
        row,
        WG_SIZE,
        x86_virtual_use_scan_local_prefix,
        x86_virtual_use_scan_block_prefix);
    if (operand_count >= 1u && !write_operand_use_edge(row, inst_count, inst.z, edge_base, 0u))
        return;
    if (operand_count >= 2u && !write_operand_use_edge(row, inst_count, inst.z, edge_base, 1u))
        return;
    if (operand_count >= 3u && !write_operand_use_edge(row, inst_count, inst.z, edge_base, 2u))
        return;
    if (operand_count >= 4u && !write_operand_use_edge(row, inst_count, inst.z, edge_base, 3u))
        return;
}
