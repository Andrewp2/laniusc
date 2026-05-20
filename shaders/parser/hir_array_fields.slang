// Clear parser-owned array literal metadata.
//
// Follow-up array passes seed grammar list links, pointer-jump element
// ordinals, and scatter owner/count/next records. This pass intentionally does
// not inspect source bytes, token spelling, helper names, or function bodies.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirArray;

RWStructuredBuffer<uint> hir_array_lit_first_element;
RWStructuredBuffer<uint> hir_array_lit_element_count;
RWStructuredBuffer<uint> hir_array_element_parent_lit;
RWStructuredBuffer<uint> hir_array_element_ordinal;
RWStructuredBuffer<uint> hir_array_element_next;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirArray.n)
        return;

    hir_array_lit_first_element[node] = INVALID;
    hir_array_lit_element_count[node] = 0u;
    hir_array_element_parent_lit[node] = INVALID;
    hir_array_element_ordinal[node] = INVALID;
    hir_array_element_next[node] = INVALID;
}
