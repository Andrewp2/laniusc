// x86_64 per-node virtual instruction locations.
//
// Prefix scanning assigns each executable HIR node a compact instruction range.
// This pass expands that range into fixed local instruction slots so later
// correction passes can move individual node-local instructions, such as branch
// jumps, without changing the instruction generator contract.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint4> x86_node_inst_count_record;
StructuredBuffer<uint4> x86_node_inst_range_record;
StructuredBuffer<uint> x86_node_inst_range_status;

RWStructuredBuffer<uint4> x86_node_inst_location_record;
RWStructuredBuffer<uint> x86_node_inst_location_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_INST_RANGE_OK = 1u;
static const uint X86_NODE_INST_LOCATIONS_OK = 1u;
static const uint X86_ERR_NODE_INST_LOCATIONS = 16u;
static const uint MAX_X86_INSTS = 256u;
static const uint MAX_X86_NODE_LOCAL_INSTS = 4u;
static const uint HIR_IF_STMT = 10u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_IF = 3u;
static const uint X86_NODE_INST_BRANCH = 4u;
static const uint X86_NODE_INST_PADDING = 7u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool upstream_ok()
{
    return x86_node_inst_range_status[0u] == X86_NODE_INST_RANGE_OK &&
           x86_node_inst_range_status[1u] == 0u &&
           x86_node_inst_range_status[3u] <= MAX_X86_INSTS;
}

uint stmt_slot(uint node, uint slot)
{
    return hir_stmt_record[node * STMT_RECORD_STRIDE + slot];
}

void publish_error(uint detail)
{
    x86_node_inst_location_status[0u] = 0u;
    uint old_error = 0u;
    InterlockedCompareExchange(
        x86_node_inst_location_status[1u],
        0u,
        X86_ERR_NODE_INST_LOCATIONS,
        old_error);
    uint old_detail = INVALID;
    InterlockedMin(x86_node_inst_location_status[2u], detail, old_detail);
}

uint4 default_locations(uint start, uint count)
{
    uint4 locations = uint4(INVALID, INVALID, INVALID, INVALID);
    if (count > 0u) locations.x = start;
    if (count > 1u) locations.y = start + 1u;
    if (count > 2u) locations.z = start + 2u;
    if (count > 3u) locations.w = start + 3u;
    return locations;
}

bool padding_location_for_node(uint node, out uint location)
{
    location = INVALID;
    if (!valid_node(node))
        return false;

    uint4 count_record = x86_node_inst_count_record[node];
    uint4 range = x86_node_inst_range_record[node];
    if (count_record.x != node || range.x == INVALID || range.y == 0u ||
        range.y > MAX_X86_NODE_LOCAL_INSTS || range.x + range.y > MAX_X86_INSTS)
        return false;

    location = range.x + range.y - 1u;
    return location < MAX_X86_INSTS;
}

bool corrected_branch_locations(uint node, out uint4 locations)
{
    locations = uint4(INVALID, INVALID, INVALID, INVALID);
    if (!valid_node(node) ||
        hir_kind[node] != HIR_IF_STMT ||
        stmt_slot(node, 0u) != STMT_RECORD_KIND_IF)
        return false;

    uint cond_node = stmt_slot(node, 1u);
    uint then_node = stmt_slot(node, 2u);
    uint else_node = stmt_slot(node, 3u);
    uint cond_location = INVALID;
    uint then_location = INVALID;
    if (!padding_location_for_node(cond_node, cond_location))
        return false;
    if (valid_node(else_node) && !padding_location_for_node(then_node, then_location))
        return false;

    locations = uint4(cond_location, then_location, INVALID, INVALID);
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    bool ok = upstream_ok();
    if (node == 0u)
    {
        x86_node_inst_location_status[0u] = ok ? X86_NODE_INST_LOCATIONS_OK : 0u;
        x86_node_inst_location_status[1u] = ok ? 0u :
                                          (x86_node_inst_range_status[1u] == 0u ?
                                           X86_ERR_NODE_INST_LOCATIONS :
                                           x86_node_inst_range_status[1u]);
        x86_node_inst_location_status[2u] = ok ? INVALID :
                                          (x86_node_inst_range_status[1u] == 0u ?
                                           x86_node_inst_range_status[3u] :
                                           x86_node_inst_range_status[2u]);
        x86_node_inst_location_status[3u] = ok ? x86_node_inst_range_status[3u] : 0u;
    }

    if (!ok || !valid_node(node))
        return;

    uint4 count_record = x86_node_inst_count_record[node];
    uint4 range = x86_node_inst_range_record[node];
    uint count = range.y;
    if (hir_kind[node] == HIR_IF_STMT && count_record.z == X86_NODE_INST_BRANCH)
    {
        uint4 branch_locations = uint4(INVALID, INVALID, INVALID, INVALID);
        if (corrected_branch_locations(node, branch_locations))
        {
            x86_node_inst_location_record[node] = branch_locations;
            return;
        }
        publish_error(node);
        return;
    }

    if (count_record.x != node || range.x == INVALID || count > MAX_X86_NODE_LOCAL_INSTS ||
        range.x + count > MAX_X86_INSTS)
    {
        x86_node_inst_location_record[node] = uint4(INVALID, INVALID, INVALID, INVALID);
        publish_error(node);
        return;
    }

    x86_node_inst_location_record[node] = default_locations(range.x, count);
}
