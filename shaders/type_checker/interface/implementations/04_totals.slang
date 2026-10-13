import atomics;
StructuredBuffer<uint> interface_declaration_member_total;
StructuredBuffer<uint> interface_implementation_member_total;
RWStructuredBuffer<uint> interface_member_total;
RWStructuredBuffer<uint> interface_status;
[shader("compute")][numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint declarations = interface_declaration_member_total[0u];
    uint implementations = interface_implementation_member_total[0u];
    if (implementations > 0xffffffffu - declarations)
    { atomic_u32_or(interface_status, 0u, 131072u); interface_member_total[0u] = 0u; return; }
    interface_member_total[0u] = declarations + implementations;
}
