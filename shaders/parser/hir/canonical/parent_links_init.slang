// Seed nearest-canonical-parent pointer jumping after raw aliases have already
// been projected at the early canonical identity boundary.

struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> canonical_flag;
StructuredBuffer<uint> canonical_prefix_before_raw;
RWStructuredBuffer<uint> parent_link_a;
RWStructuredBuffer<uint> parent_value_a;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }
uint active_count() { return gCanonical.uses_status_count != 0u ? min(gCanonical.raw_capacity, tree_count_status[5u]) : gCanonical.raw_capacity; }
bool valid(uint node) { return node != INVALID && node < active_count(); }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = tid(dtid);
    if (node >= gCanonical.raw_capacity) return;
    parent_link_a[node] = INVALID;
    parent_value_a[node] = INVALID;
    if (!valid(node)) return;
    uint ancestor = parent[node];
    uint span = max(1u, gCanonical.local_ancestor_span);
    for (uint hop = 0u; hop < span; ++hop)
    {
        if (!valid(ancestor) || ancestor == node) return;
        if (canonical_flag[ancestor] != 0u)
        {
            parent_value_a[node] = canonical_prefix_before_raw[ancestor];
            return;
        }
        if (hop + 1u == span) { parent_link_a[node] = ancestor; return; }
        uint next = parent[ancestor];
        if (!valid(next) || next == ancestor) return;
        ancestor = next;
    }
}
