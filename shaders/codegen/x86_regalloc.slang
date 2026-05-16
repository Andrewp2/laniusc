// Direct x86_64 register allocation over GPU liveness records.
//
// The current backend slice still emits a narrow instruction set, but this pass
// allocates from value/liveness records instead of recognizing source tokens or
// exact vreg layouts. Immediate operands stay unallocated unless they are the
// final syscall argument; non-immediate temps receive deterministic caller-save
// registers based on live-overlap rank.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_vreg_kind;
StructuredBuffer<uint> x86_live_start;
StructuredBuffer<uint> x86_live_end;
StructuredBuffer<uint> liveness_status;
StructuredBuffer<uint> x86_return_vreg;

RWStructuredBuffer<uint> x86_phys_reg;
RWStructuredBuffer<uint> regalloc_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint MAX_X86_VREGS = 8u;
static const uint X86_LIVENESS_OK = 1u;
static const uint X86_REGALLOC_OK = 1u;
static const uint X86_REG_EAX = 0u;
static const uint X86_REG_ECX = 1u;
static const uint X86_REG_EDX = 2u;
static const uint X86_REG_ESI = 6u;
static const uint X86_REG_RDI = 7u;
static const uint X86_REG_R8D = 8u;
static const uint X86_REG_R9D = 9u;
static const uint X86_VREG_IMM_I32 = 1u;
static const uint X86_VREG_BINARY_I32 = 2u;
static const uint X86_VREG_BRANCH_I32 = 3u;
static const uint X86_VREG_COMPARE_I32 = 4u;
static const uint X86_VREG_CALL_I32 = 5u;
static const uint X86_ERR_REGALLOC = 5u;

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

bool interval_valid(uint vreg)
{
    return x86_live_start[vreg] != INVALID && x86_live_end[vreg] != INVALID &&
           x86_live_start[vreg] <= x86_live_end[vreg];
}

bool intervals_overlap(uint a, uint b)
{
    return interval_valid(a) && interval_valid(b) &&
           x86_live_start[a] <= x86_live_end[b] && x86_live_start[b] <= x86_live_end[a];
}

bool needs_physical_register(uint vreg, uint return_vreg)
{
    uint kind = x86_vreg_kind[vreg];
    if (kind == X86_VREG_IMM_I32)
        return vreg == return_vreg;
    return true;
}

uint temp_register_for_rank(uint rank)
{
    if (rank == 0u) return X86_REG_ECX;
    if (rank == 1u) return X86_REG_EDX;
    if (rank == 2u) return X86_REG_ESI;
    if (rank == 3u) return X86_REG_R8D;
    if (rank == 4u) return X86_REG_R9D;
    return INVALID;
}

uint allocation_for_vreg(uint vreg, uint vreg_count, uint return_vreg)
{
    if (!needs_physical_register(vreg, return_vreg))
        return INVALID;

    uint kind = x86_vreg_kind[vreg];
    if (vreg == return_vreg)
        return kind == X86_VREG_IMM_I32 ? X86_REG_RDI : X86_REG_EAX;

    uint rank = 0u;
    [loop]
    for (uint other = 0u; other < MAX_X86_VREGS; other += 1u)
    {
        if (other >= vreg_count || other >= vreg)
            break;
        if (other != return_vreg && needs_physical_register(other, return_vreg) &&
            intervals_overlap(vreg, other))
            rank += 1u;
    }
    return temp_register_for_rank(rank);
}

bool allocation_inputs_valid(uint vreg_count, uint return_vreg)
{
    if (liveness_status[0u] != X86_LIVENESS_OK || vreg_count == 0u ||
        vreg_count > MAX_X86_VREGS || !valid_vreg(return_vreg, vreg_count))
        return false;

    [loop]
    for (uint vreg = 0u; vreg < MAX_X86_VREGS; vreg += 1u)
    {
        if (vreg >= vreg_count)
            break;
        if (!valid_vreg_kind(x86_vreg_kind[vreg]) || !interval_valid(vreg))
            return false;
        if (needs_physical_register(vreg, return_vreg) &&
            allocation_for_vreg(vreg, vreg_count, return_vreg) == INVALID)
            return false;
    }
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint vreg = linear_dispatch_id(tid);
    uint vreg_count = liveness_status[3u];
    uint return_vreg = x86_return_vreg[0u];
    bool ok = allocation_inputs_valid(vreg_count, return_vreg);

    if (vreg < min(vreg_count, MAX_X86_VREGS))
        x86_phys_reg[vreg] = ok ? allocation_for_vreg(vreg, vreg_count, return_vreg) : INVALID;
    else if (vreg < MAX_X86_VREGS)
        x86_phys_reg[vreg] = INVALID;

    if (vreg == 0u)
    {
        regalloc_status[0u] = ok ? X86_REGALLOC_OK : 0u;
        regalloc_status[1u] = ok ? 0u : (liveness_status[1u] == 0u ? X86_ERR_REGALLOC : liveness_status[1u]);
        regalloc_status[2u] = ok ? INVALID : liveness_status[2u];
        regalloc_status[3u] = ok ? vreg_count : 0u;
    }
}
