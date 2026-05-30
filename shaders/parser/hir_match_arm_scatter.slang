// Publish pointer-jumped match arm and pattern-payload metadata.
//
// Arm rows and payload-pattern rows are disjoint HIR node kinds. The retained
// match-node/ordinal rows therefore also carry arm owner/rank for match-arm
// nodes so later semantic passes can work per arm instead of walking arm lists.

import atomics;
import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirMatch;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_match_arm_owner_a;
StructuredBuffer<uint> hir_match_arm_rank_a;
StructuredBuffer<uint> hir_match_arm_previous;
StructuredBuffer<uint> hir_match_payload_owner_a;
StructuredBuffer<uint> hir_match_payload_rank_a;

RWStructuredBuffer<uint> hir_match_arm_start;
RWStructuredBuffer<uint> hir_match_arm_count;
RWStructuredBuffer<uint> hir_match_arm_next;
RWStructuredBuffer<uint> hir_match_arm_payload_start;
RWStructuredBuffer<uint> hir_match_arm_payload_count;
RWStructuredBuffer<uint> hir_match_payload_owner_arm;
RWStructuredBuffer<uint> hir_match_payload_match_node;
RWStructuredBuffer<uint> hir_match_payload_ordinal;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirMatch.uses_ll1 != 0u ? min(gHirMatch.n, ll1_status[5u])
                                    : gHirMatch.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

void publish_arm(uint node)
{
    uint owner = hir_match_arm_owner_a[node];
    if (!valid_node(owner))
        return;

    uint ordinal = hir_match_arm_rank_a[node];
    uint previous = hir_match_arm_previous[node];
    atomic_u32_min(hir_match_arm_start, owner, node);
    atomic_u32_max(hir_match_arm_count, owner, ordinal + 1u);
    if (valid_node(previous))
        hir_match_arm_next[previous] = node;
    hir_match_payload_match_node[node] = owner;
    hir_match_payload_ordinal[node] = ordinal;
}

void publish_payload(uint node)
{
    uint owner = hir_match_payload_owner_a[node];
    if (!valid_node(owner))
        return;

    uint match_node = hir_match_arm_owner_a[owner];
    if (!valid_node(match_node))
        return;

    uint ordinal = hir_match_payload_rank_a[node];
    hir_match_payload_owner_arm[node] = owner;
    hir_match_payload_match_node[node] = match_node;
    hir_match_payload_ordinal[node] = ordinal;
    atomic_u32_min(hir_match_arm_payload_start, owner, node);
    atomic_u32_max(hir_match_arm_payload_count, owner, ordinal + 1u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirMatch.n || !valid_node(node))
        return;

    if (node_kind[node] == PROD_MATCH_ARM)
        publish_arm(node);

    publish_payload(node);
}
