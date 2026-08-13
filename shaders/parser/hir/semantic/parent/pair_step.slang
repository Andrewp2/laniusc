// Follow a bounded run of two nearest-ancestor relations over one tree.

struct Params { uint n; uint uses_status_count; };
ConstantBuffer<Params> gHirSemantic;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> relation_link_in;
StructuredBuffer<uint> first_value_in;
StructuredBuffer<uint> second_value_in;
RWStructuredBuffer<uint> relation_link_out;
RWStructuredBuffer<uint> first_value_out;
RWStructuredBuffer<uint> second_value_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LINKS_PER_STEP = 16u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
uint active_node_count() { return gHirSemantic.uses_status_count != 0u ? min(gHirSemantic.n, tree_count_status[5u]) : gHirSemantic.n; }
bool valid_node(uint node) { return node != INVALID && node < active_node_count(); }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirSemantic.n) return;
    if (!valid_node(node)) {
        relation_link_out[node] = INVALID;
        first_value_out[node] = INVALID;
        second_value_out[node] = INVALID;
        return;
    }
    uint link = relation_link_in[node];
    uint first = first_value_in[node];
    uint second = second_value_in[node];
    for (uint hop = 0u; hop < LINKS_PER_STEP; ++hop) {
        if (!valid_node(link) || link == node || (valid_node(first) && valid_node(second))) {
            link = INVALID;
            break;
        }
        if (!valid_node(first)) first = first_value_in[link];
        if (!valid_node(second)) second = second_value_in[link];
        uint ancestor_link = relation_link_in[link];
        link = valid_node(first) && valid_node(second)
            ? INVALID
            : (valid_node(ancestor_link) ? ancestor_link : INVALID);
    }
    relation_link_out[node] = link;
    first_value_out[node] = valid_node(first) ? first : INVALID;
    second_value_out[node] = valid_node(second) ? second : INVALID;
}
