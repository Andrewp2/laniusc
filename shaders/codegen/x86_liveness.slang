// Direct x86_64 liveness over GPU backend use-edge records.
//
// Each lane owns one virtual register and derives a conservative live interval
// from explicit def-use edge rows. This keeps liveness tied to backend records
// rather than to source/token positions or lowering's operand layout.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_vreg_kind;
StructuredBuffer<uint> lower_status;
StructuredBuffer<uint> x86_use_key;
StructuredBuffer<uint> x86_use_value;
StructuredBuffer<uint> x86_vreg_use_count;
StructuredBuffer<uint> use_status;

RWStructuredBuffer<uint> x86_live_start;
RWStructuredBuffer<uint> x86_live_end;
RWStructuredBuffer<uint> liveness_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint MAX_X86_VREGS = 8u;
static const uint MAX_X86_OPERANDS = 4u;
static const uint MAX_X86_USE_EDGES = MAX_X86_VREGS * MAX_X86_OPERANDS + 1u;
static const uint X86_LOWER_OK = 1u;
static const uint X86_USE_EDGES_OK = 1u;
static const uint X86_LIVENESS_OK = 1u;
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

uint use_key_user(uint key)
{
    return key & 0xffffu;
}

uint use_key_slot(uint key)
{
    return (key >> 16u) & 0xffffu;
}

bool use_edge_row_valid(uint edge_i, uint vreg_count)
{
    uint value_vreg = x86_use_value[edge_i];
    uint key = x86_use_key[edge_i];
    if (value_vreg == INVALID)
        return key == INVALID;
    uint user_vreg = use_key_user(key);
    uint slot = use_key_slot(key);
    if (!valid_vreg(value_vreg, vreg_count) || slot >= MAX_X86_OPERANDS)
        return false;
    if (edge_i == MAX_X86_VREGS * MAX_X86_OPERANDS)
        return user_vreg == vreg_count;
    return user_vreg < vreg_count;
}

uint counted_uses(uint vreg)
{
    uint count = 0u;
    [loop]
    for (uint edge_i = 0u; edge_i < MAX_X86_USE_EDGES; edge_i += 1u)
    {
        if (x86_use_value[edge_i] == vreg)
            count += 1u;
    }
    return count;
}

bool graph_valid(uint vreg_count)
{
    if (lower_status[0u] != X86_LOWER_OK || lower_status[1u] != 0u ||
        use_status[0u] != X86_USE_EDGES_OK || use_status[1u] != 0u ||
        use_status[3u] != vreg_count || vreg_count == 0u ||
        vreg_count > MAX_X86_VREGS)
        return false;

    [loop]
    for (uint vreg = 0u; vreg < MAX_X86_VREGS; vreg += 1u)
    {
        if (vreg >= vreg_count)
            break;
        if (!valid_vreg_kind(x86_vreg_kind[vreg]))
            return false;
        if (x86_vreg_use_count[vreg] != counted_uses(vreg))
            return false;
    }

    [loop]
    for (uint edge_i = 0u; edge_i < MAX_X86_USE_EDGES; edge_i += 1u)
    {
        if (!use_edge_row_valid(edge_i, vreg_count))
            return false;
    }
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint vreg = linear_dispatch_id(tid);
    uint vreg_count = use_status[3u];
    bool ok = graph_valid(vreg_count);

    if (vreg < min(vreg_count, MAX_X86_VREGS) && ok)
    {
        uint start = vreg;
        uint end = vreg;
        [loop]
        for (uint edge_i = 0u; edge_i < MAX_X86_USE_EDGES; edge_i += 1u)
        {
            if (x86_use_value[edge_i] == vreg)
                end = max(end, use_key_user(x86_use_key[edge_i]));
        }
        x86_live_start[vreg] = start;
        x86_live_end[vreg] = max(start, end);
    }
    else if (vreg < MAX_X86_VREGS)
    {
        x86_live_start[vreg] = INVALID;
        x86_live_end[vreg] = INVALID;
    }

    if (vreg == 0u)
    {
        liveness_status[0u] = ok ? X86_LIVENESS_OK : 0u;
        liveness_status[1u] = ok ? 0u : (use_status[1u] == 0u ? X86_ERR_UNSUPPORTED_RETURN : use_status[1u]);
        liveness_status[2u] = ok ? INVALID : use_status[2u];
        liveness_status[3u] = ok ? vreg_count : 0u;
    }
}
