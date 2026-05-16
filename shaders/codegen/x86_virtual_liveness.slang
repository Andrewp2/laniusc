// x86_64 virtual-register liveness over virtual instruction use edges.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint4> x86_virtual_inst_record;
StructuredBuffer<uint> x86_virtual_use_key;
StructuredBuffer<uint> x86_virtual_use_value;
StructuredBuffer<uint> x86_virtual_vreg_use_count;
StructuredBuffer<uint> x86_virtual_use_status;

RWStructuredBuffer<uint> x86_virtual_live_start;
RWStructuredBuffer<uint> x86_virtual_live_end;
RWStructuredBuffer<uint> x86_virtual_liveness_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint MAX_X86_INSTS = 256u;
static const uint MAX_X86_OPERANDS = 4u;
static const uint MAX_X86_VIRTUAL_USE_EDGES = MAX_X86_INSTS * MAX_X86_OPERANDS + 1u;
static const uint X86_VIRTUAL_USE_OK = 1u;
static const uint X86_VIRTUAL_LIVENESS_OK = 1u;
static const uint X86_ERR_VIRTUAL_LIVENESS = 14u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint use_key_user(uint key)
{
    return key & 0xffffu;
}

uint use_key_slot(uint key)
{
    return (key >> 16u) & 0xffffu;
}

bool has_value_def(uint row, uint inst_count)
{
    if (row >= inst_count)
        return false;
    uint4 inst = x86_virtual_inst_record[row];
    return inst.x != INVALID && inst.z != 0u && inst.w == row;
}

uint counted_uses(uint row)
{
    uint count = 0u;
    [loop]
    for (uint edge_i = 0u; edge_i < MAX_X86_VIRTUAL_USE_EDGES; edge_i += 1u)
    {
        if (x86_virtual_use_value[edge_i] == row)
            count += 1u;
    }
    return count;
}

bool edge_valid(uint edge_i, uint inst_count)
{
    uint value = x86_virtual_use_value[edge_i];
    uint key = x86_virtual_use_key[edge_i];
    if (value == INVALID)
        return key == INVALID;
    uint user = use_key_user(key);
    uint slot = use_key_slot(key);
    return value < inst_count &&
           user < inst_count &&
           slot < MAX_X86_OPERANDS &&
           has_value_def(value, inst_count);
}

bool graph_valid(uint inst_count)
{
    if (x86_virtual_use_status[0u] != X86_VIRTUAL_USE_OK ||
        x86_virtual_use_status[1u] != 0u ||
        x86_virtual_use_status[3u] != inst_count ||
        inst_count > MAX_X86_INSTS)
        return false;

    [loop]
    for (uint row = 0u; row < MAX_X86_INSTS; row += 1u)
    {
        if (row >= inst_count)
            break;
        if (has_value_def(row, inst_count) &&
            x86_virtual_vreg_use_count[row] != counted_uses(row))
            return false;
    }

    [loop]
    for (uint edge_i = 0u; edge_i < MAX_X86_VIRTUAL_USE_EDGES; edge_i += 1u)
    {
        if (!edge_valid(edge_i, inst_count))
            return false;
    }
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    uint inst_count = x86_virtual_use_status[3u];
    bool ok = graph_valid(inst_count);

    if (row < MAX_X86_INSTS)
    {
        if (ok && row < inst_count && has_value_def(row, inst_count))
        {
            uint start = row;
            uint end = row;
            [loop]
            for (uint edge_i = 0u; edge_i < MAX_X86_VIRTUAL_USE_EDGES; edge_i += 1u)
            {
                if (x86_virtual_use_value[edge_i] == row)
                    end = max(end, use_key_user(x86_virtual_use_key[edge_i]));
            }
            x86_virtual_live_start[row] = start;
            x86_virtual_live_end[row] = max(start, end);
        }
        else
        {
            x86_virtual_live_start[row] = INVALID;
            x86_virtual_live_end[row] = INVALID;
        }
    }

    if (row == 0u)
    {
        x86_virtual_liveness_status[0u] = ok ? X86_VIRTUAL_LIVENESS_OK : 0u;
        x86_virtual_liveness_status[1u] = ok ? 0u :
                                            (x86_virtual_use_status[1u] == 0u ?
                                             X86_ERR_VIRTUAL_LIVENESS :
                                             x86_virtual_use_status[1u]);
        x86_virtual_liveness_status[2u] = ok ? INVALID :
                                            (x86_virtual_use_status[1u] == 0u ?
                                             inst_count :
                                             x86_virtual_use_status[2u]);
        x86_virtual_liveness_status[3u] = ok ? inst_count : 0u;
    }
}
