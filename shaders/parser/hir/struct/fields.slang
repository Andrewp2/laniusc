// Clear parser-owned struct declaration and struct literal metadata.
//
// Follow-up struct passes seed grammar list links, pointer-jump field ordinals,
// and scatter owner/count records. This pass intentionally does not inspect
// source bytes, token spelling, helper names, or function bodies.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirStruct;

RWStructuredBuffer<uint> hir_struct_field_parent_struct;
RWStructuredBuffer<uint> hir_struct_field_ordinal;
RWStructuredBuffer<uint> hir_struct_field_type_node;
RWStructuredBuffer<uint> hir_struct_decl_field_start;
RWStructuredBuffer<uint> hir_struct_decl_field_count;
RWStructuredBuffer<uint> hir_struct_lit_head_node;
RWStructuredBuffer<uint> hir_struct_lit_context_stmt_node;
RWStructuredBuffer<uint> hir_struct_lit_field_start;
RWStructuredBuffer<uint> hir_struct_lit_field_count;
RWStructuredBuffer<uint> hir_struct_lit_field_parent_lit;
RWStructuredBuffer<uint> hir_struct_lit_field_value_node;

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
    if (node >= gHirStruct.n)
        return;

    hir_struct_field_parent_struct[node] = INVALID;
    hir_struct_field_ordinal[node] = INVALID;
    hir_struct_field_type_node[node] = INVALID;
    hir_struct_decl_field_start[node] = INVALID;
    hir_struct_decl_field_count[node] = 0u;
    hir_struct_lit_head_node[node] = INVALID;
    hir_struct_lit_context_stmt_node[node] = INVALID;
    hir_struct_lit_field_start[node] = INVALID;
    hir_struct_lit_field_count[node] = 0u;
    hir_struct_lit_field_parent_lit[node] = INVALID;
    hir_struct_lit_field_value_node[node] = INVALID;
}
