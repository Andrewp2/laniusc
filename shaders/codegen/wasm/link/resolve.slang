import codegen.wasm.link.common;

StructuredBuffer<LinkRelocation> link_relocation;
RWStructuredBuffer<uint> link_resolved_target;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= gLink.relocation_count) return;
    LinkRelocation row = link_relocation[i];
    if (row.target_kind == 1u)
    {
        link_resolved_target[i] = row.target_index;
        return;
    }
    if (row.target_kind != 2u)
    {
        fail(7u, i);
        return;
    }
    uint representative = lookup_identity_value(row.target_identity);
    if (representative == INVALID)
    {
        fail(4u, i);
        return;
    }
    uint target = link_symbol_definition[representative];
    if (target == INVALID)
    {
        fail(5u, i);
        return;
    }
    link_resolved_target[i] = target;
}
