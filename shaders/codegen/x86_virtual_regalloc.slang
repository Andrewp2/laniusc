// x86_64 register allocation over virtual-instruction liveness intervals.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint4> x86_virtual_inst_record;
StructuredBuffer<uint> x86_virtual_live_start;
StructuredBuffer<uint> x86_virtual_live_end;
StructuredBuffer<uint> x86_virtual_liveness_status;

RWStructuredBuffer<uint> x86_virtual_phys_reg;
RWStructuredBuffer<uint> x86_virtual_regalloc_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint MAX_X86_INSTS = 256u;
static const uint X86_VIRTUAL_LIVENESS_OK = 1u;
static const uint X86_VIRTUAL_REGALLOC_OK = 1u;
static const uint X86_ERR_VIRTUAL_REGALLOC = 15u;
static const uint X86_VINST_CALL = 6u;

static const uint X86_REG_EAX = 0u;
static const uint X86_REG_ECX = 1u;
static const uint X86_REG_EDX = 2u;
static const uint X86_REG_ESI = 6u;
static const uint X86_REG_EDI = 7u;
static const uint X86_REG_R8D = 8u;
static const uint X86_REG_R9D = 9u;
static const uint X86_REG_R10D = 10u;
static const uint X86_REG_R11D = 11u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

bool has_value_def(uint row, uint inst_count)
{
    if (row >= inst_count)
        return false;
    uint4 inst = x86_virtual_inst_record[row];
    return inst.x != INVALID && inst.z != 0u && inst.w == row;
}

bool interval_valid(uint row)
{
    return x86_virtual_live_start[row] != INVALID &&
           x86_virtual_live_end[row] != INVALID &&
           x86_virtual_live_start[row] <= x86_virtual_live_end[row];
}

bool intervals_overlap(uint a, uint b)
{
    return interval_valid(a) && interval_valid(b) &&
           x86_virtual_live_start[a] <= x86_virtual_live_end[b] &&
           x86_virtual_live_start[b] <= x86_virtual_live_end[a];
}

uint temp_register_for_rank(uint rank)
{
    if (rank == 0u) return X86_REG_EAX;
    if (rank == 1u) return X86_REG_ECX;
    if (rank == 2u) return X86_REG_EDX;
    if (rank == 3u) return X86_REG_ESI;
    if (rank == 4u) return X86_REG_EDI;
    if (rank == 5u) return X86_REG_R8D;
    if (rank == 6u) return X86_REG_R9D;
    if (rank == 7u) return X86_REG_R10D;
    if (rank == 8u) return X86_REG_R11D;
    return INVALID;
}

bool value_spans_call(uint row, uint inst_count)
{
    if (!interval_valid(row))
        return false;

    uint start = x86_virtual_live_start[row];
    uint end = x86_virtual_live_end[row];
    [loop]
    for (uint other = 0u; other < MAX_X86_INSTS; other += 1u)
    {
        if (other >= inst_count)
            break;
        if (other > start && other < end && x86_virtual_inst_record[other].z == X86_VINST_CALL)
            return true;
    }
    return false;
}

bool allocation_status_inputs_valid(uint inst_count)
{
    return x86_virtual_liveness_status[0u] == X86_VIRTUAL_LIVENESS_OK &&
           x86_virtual_liveness_status[1u] == 0u &&
           x86_virtual_liveness_status[3u] == inst_count &&
           inst_count <= MAX_X86_INSTS;
}

bool assigned_register_available(uint candidate, uint row, uint inst_count)
{
    [loop]
    for (uint other = 0u; other < MAX_X86_INSTS; other += 1u)
    {
        if (other >= inst_count || other >= row)
            break;
        if (has_value_def(other, inst_count) &&
            intervals_overlap(row, other) &&
            x86_virtual_phys_reg[other] == candidate)
            return false;
    }
    return true;
}

uint allocation_for_row(uint row, uint inst_count)
{
    if (!has_value_def(row, inst_count))
        return INVALID;

    [unroll]
    for (uint rank = 0u; rank < 9u; rank += 1u)
    {
        uint candidate = temp_register_for_rank(rank);
        if (candidate == X86_REG_EAX && value_spans_call(row, inst_count))
            continue;
        if (candidate != INVALID && assigned_register_available(candidate, row, inst_count))
            return candidate;
    }
    return INVALID;
}

bool allocate_all_rows(uint inst_count)
{
    [loop]
    for (uint row = 0u; row < MAX_X86_INSTS; row += 1u)
        x86_virtual_phys_reg[row] = INVALID;

    if (!allocation_status_inputs_valid(inst_count))
        return false;

    [loop]
    for (uint row = 0u; row < MAX_X86_INSTS; row += 1u)
    {
        if (row >= inst_count)
            break;
        if (!has_value_def(row, inst_count))
            continue;
        if (!interval_valid(row))
            return false;
        uint reg = allocation_for_row(row, inst_count);
        if (reg == INVALID)
            return false;
        x86_virtual_phys_reg[row] = reg;
    }
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    uint inst_count = x86_virtual_liveness_status[3u];
    if (row != 0u)
        return;

    bool ok = allocate_all_rows(inst_count);
    x86_virtual_regalloc_status[0u] = ok ? X86_VIRTUAL_REGALLOC_OK : 0u;
    x86_virtual_regalloc_status[1u] = ok ? 0u :
                                       (x86_virtual_liveness_status[1u] == 0u ?
                                        X86_ERR_VIRTUAL_REGALLOC :
                                        x86_virtual_liveness_status[1u]);
    x86_virtual_regalloc_status[2u] = ok ? INVALID :
                                       (x86_virtual_liveness_status[1u] == 0u ?
                                        inst_count :
                                        x86_virtual_liveness_status[2u]);
    x86_virtual_regalloc_status[3u] = ok ? inst_count : 0u;
}
