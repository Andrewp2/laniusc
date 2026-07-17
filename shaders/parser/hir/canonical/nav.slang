struct Params { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };

ConstantBuffer<Params> gCanonical;
StructuredBuffer<uint> canonical_count;
StructuredBuffer<HirCore> hir_core;
RWStructuredBuffer<HirLinks> hir_links;

static const uint INVALID = 0xffffffffu;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * 256u; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = tid(dtid);
    uint count = min(canonical_count[0u], gCanonical.canonical_capacity);
    if (row >= count) return;
    HirLinks links = hir_links[row];
    uint child = row + 1u;
    links.first_child = child < count && hir_core[child].parent == row ? child : INVALID;
    uint sibling = links.subtree_end;
    links.next_sibling = sibling < count && hir_core[sibling].parent == hir_core[row].parent
        ? sibling
        : INVALID;
    hir_links[row] = links;
}
