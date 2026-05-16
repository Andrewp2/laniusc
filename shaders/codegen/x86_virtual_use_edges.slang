// x86_64 virtual-instruction def-use expansion.
//
// This pass consumes node-generated virtual instruction records and writes
// explicit use-edge rows for virtual registers. It is the virtual-instruction
// counterpart of the older expression-vreg use edge pass.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint4> x86_virtual_inst_record;
StructuredBuffer<uint4> x86_virtual_inst_args;
StructuredBuffer<uint> x86_virtual_inst_status;

RWStructuredBuffer<uint> x86_virtual_use_key;
RWStructuredBuffer<uint> x86_virtual_use_value;
RWStructuredBuffer<uint> x86_virtual_vreg_use_count;
RWStructuredBuffer<uint> x86_virtual_use_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint MAX_X86_INSTS = 256u;
static const uint MAX_X86_OPERANDS = 4u;
static const uint MAX_X86_VIRTUAL_USE_EDGES = MAX_X86_INSTS * MAX_X86_OPERANDS + 1u;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_VIRTUAL_USE_OK = 1u;
static const uint X86_ERR_VIRTUAL_USE = 13u;

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

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint virtual_inst_count()
{
    return min(x86_virtual_inst_status[3u], MAX_X86_INSTS);
}

bool upstream_ok()
{
    return x86_virtual_inst_status[0u] == X86_VIRTUAL_INST_OK &&
           x86_virtual_inst_status[1u] == 0u;
}

uint operand_count_for_row(uint row)
{
    uint op = x86_virtual_inst_record[row].z;
    uint4 args = x86_virtual_inst_args[row];
    if (op == X86_VINST_UNARY ||
        op == X86_VINST_ALIAS ||
        op == X86_VINST_RETURN)
        return 1u;
    if (op == X86_VINST_BRANCH ||
        op == X86_VINST_LOOP)
        return args.x == INVALID ? 0u : 1u;
    if (op == X86_VINST_INTRINSIC)
        return 1u;
    if (op == X86_VINST_CALL)
        return min(args.y, 2u);
    if (op == X86_VINST_BINARY || op == X86_VINST_COMPARE)
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
    if (op == X86_VINST_CALL)
    {
        if (slot == 0u) return args.z & 0xffffu;
        if (slot == 1u) return (args.z >> 16u) & 0xffffu;
        return INVALID;
    }
    if (op == X86_VINST_INTRINSIC)
        return slot == 0u ? args.y : INVALID;
    if (op == X86_VINST_ALIAS ||
        op == X86_VINST_RETURN ||
        op == X86_VINST_BRANCH ||
        op == X86_VINST_LOOP)
        return slot == 0u ? args.x : INVALID;
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
    return (slot << 16u) | (user_row & 0xffffu);
}

void publish_error(uint detail)
{
    x86_virtual_use_status[0u] = 0u;
    uint old_error = 0u;
    InterlockedCompareExchange(
        x86_virtual_use_status[1u],
        0u,
        X86_ERR_VIRTUAL_USE,
        old_error);
    uint old_detail = INVALID;
    InterlockedMin(x86_virtual_use_status[2u], detail, old_detail);
}

void write_use_edge(uint edge_i, uint user_row, uint value_row, uint slot)
{
    if (edge_i >= MAX_X86_VIRTUAL_USE_EDGES)
    {
        publish_error(user_row);
        return;
    }
    x86_virtual_use_key[edge_i] = pack_use_key(user_row, slot);
    x86_virtual_use_value[edge_i] = value_row;

    uint old_count = 0u;
    InterlockedAdd(x86_virtual_vreg_use_count[value_row], 1u, old_count);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    uint inst_count = virtual_inst_count();
    bool ok = upstream_ok() && x86_virtual_inst_status[3u] <= MAX_X86_INSTS;

    if (row == 0u)
    {
        x86_virtual_use_status[0u] = ok ? X86_VIRTUAL_USE_OK : 0u;
        x86_virtual_use_status[1u] = ok ? 0u :
                                      (x86_virtual_inst_status[1u] == 0u ?
                                       X86_ERR_VIRTUAL_USE :
                                       x86_virtual_inst_status[1u]);
        x86_virtual_use_status[2u] = ok ? INVALID :
                                      (x86_virtual_inst_status[1u] == 0u ?
                                       x86_virtual_inst_status[3u] :
                                       x86_virtual_inst_status[2u]);
        x86_virtual_use_status[3u] = ok ? inst_count : 0u;
    }

    if (!ok || row >= inst_count)
        return;

    uint4 inst = x86_virtual_inst_record[row];
    if (inst.x == INVALID || inst.z == 0u)
        return;

    uint operand_count = operand_count_for_row(row);
    [loop]
    for (uint slot = 0u; slot < MAX_X86_OPERANDS; slot += 1u)
    {
        if (slot >= operand_count)
            break;
        uint operand = operand_at(row, slot);
        if (!valid_virtual_value(operand, inst_count))
        {
            publish_error(row);
            return;
        }
        write_use_edge(row * MAX_X86_OPERANDS + slot, row, operand, slot);
    }
}
