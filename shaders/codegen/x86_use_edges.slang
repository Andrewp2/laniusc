// Direct x86_64 def-use edge expansion over GPU backend value records.
//
// Lowering owns virtual-register definitions and operand records. This pass
// turns those operands into explicit use-edge rows so later liveness/register
// allocation stages consume backend records rather than rereading lowering's
// operand layout.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_vreg_kind;
StructuredBuffer<uint4> x86_vreg_args;
StructuredBuffer<uint> lower_status;
StructuredBuffer<uint> x86_return_vreg;

RWStructuredBuffer<uint> x86_use_key;
RWStructuredBuffer<uint> x86_use_value;
RWStructuredBuffer<uint> x86_vreg_use_count;
RWStructuredBuffer<uint> use_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint MAX_X86_VREGS = 8u;
static const uint MAX_X86_OPERANDS = 4u;
static const uint MAX_X86_USE_EDGES = MAX_X86_VREGS * MAX_X86_OPERANDS + 1u;
static const uint X86_LOWER_OK = 1u;
static const uint X86_USE_EDGES_OK = 1u;
static const uint X86_ERR_UNSUPPORTED_RETURN = 3u;
static const uint X86_VREG_IMM_I32 = 1u;
static const uint X86_VREG_BINARY_I32 = 2u;
static const uint X86_VREG_BRANCH_I32 = 3u;
static const uint X86_VREG_COMPARE_I32 = 4u;
static const uint X86_VREG_CALL_I32 = 5u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

bool valid_vreg(uint vreg, uint vreg_count)
{
    return vreg != INVALID && vreg < vreg_count;
}

bool valid_vreg_kind(uint kind)
{
    return kind == X86_VREG_IMM_I32 || kind == X86_VREG_BINARY_I32 ||
           kind == X86_VREG_BRANCH_I32 || kind == X86_VREG_COMPARE_I32 ||
           kind == X86_VREG_CALL_I32;
}

uint operand_count_for_kind(uint kind)
{
    if (kind == X86_VREG_BINARY_I32 || kind == X86_VREG_COMPARE_I32)
        return 2u;
    if (kind == X86_VREG_BRANCH_I32)
        return 4u;
    return 0u;
}

uint vreg_operand(uint user_vreg, uint slot)
{
    uint4 args = x86_vreg_args[user_vreg];
    if (slot == 0u)
        return args.x;
    if (slot == 1u)
        return args.y;
    if (slot == 2u)
        return args.z;
    if (slot == 3u)
        return args.w;
    return INVALID;
}

uint operand_count_for_vreg(uint vreg)
{
    uint kind = x86_vreg_kind[vreg];
    return operand_count_for_kind(kind);
}

bool vreg_record_valid(uint vreg, uint vreg_count)
{
    uint kind = x86_vreg_kind[vreg];
    if (!valid_vreg_kind(kind))
        return false;

    uint operand_count = operand_count_for_vreg(vreg);
    [loop]
    for (uint slot = 0u; slot < MAX_X86_OPERANDS; slot += 1u)
    {
        uint operand = vreg_operand(vreg, slot);
        if (slot < operand_count)
        {
            if (!valid_vreg(operand, vreg_count))
                return false;
        }
        else if (operand != INVALID)
        {
            return false;
        }
    }
    return true;
}

bool graph_valid(uint vreg_count, uint return_vreg)
{
    if (lower_status[0u] != X86_LOWER_OK || lower_status[1u] != 0u ||
        vreg_count == 0u || vreg_count > MAX_X86_VREGS ||
        !valid_vreg(return_vreg, vreg_count))
        return false;

    [loop]
    for (uint vreg = 0u; vreg < MAX_X86_VREGS; vreg += 1u)
    {
        if (vreg >= vreg_count)
            break;
        if (!vreg_record_valid(vreg, vreg_count))
            return false;
    }
    return true;
}

uint pack_use_key(uint user_vreg, uint slot)
{
    return (slot << 16u) | (user_vreg & 0xffffu);
}

void write_use_edge(uint edge_i, uint user_vreg, uint value_vreg, uint slot)
{
    if (edge_i >= MAX_X86_USE_EDGES)
        return;
    x86_use_key[edge_i] = pack_use_key(user_vreg, slot);
    x86_use_value[edge_i] = value_vreg;

    uint old_count = 0u;
    InterlockedAdd(x86_vreg_use_count[value_vreg], 1u, old_count);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint lane = linear_dispatch_id(tid);
    uint vreg_count = lower_status[3u];
    uint return_vreg = x86_return_vreg[0u];
    bool ok = graph_valid(vreg_count, return_vreg);

    if (ok && lane < min(vreg_count, MAX_X86_VREGS))
    {
        uint operand_count = operand_count_for_vreg(lane);
        [loop]
        for (uint slot = 0u; slot < MAX_X86_OPERANDS; slot += 1u)
        {
            if (slot >= operand_count)
                break;
            uint operand = vreg_operand(lane, slot);
            write_use_edge(lane * MAX_X86_OPERANDS + slot, lane, operand, slot);
        }
    }

    if (lane == 0u)
    {
        if (ok)
            write_use_edge(MAX_X86_VREGS * MAX_X86_OPERANDS, vreg_count, return_vreg, 0u);
        use_status[0u] = ok ? X86_USE_EDGES_OK : 0u;
        use_status[1u] = ok ? 0u : (lower_status[1u] == 0u ? X86_ERR_UNSUPPORTED_RETURN : lower_status[1u]);
        use_status[2u] = ok ? INVALID : lower_status[2u];
        use_status[3u] = ok ? vreg_count : 0u;
    }
}
