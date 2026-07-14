// Translate declaration-local generic slots in type records to stable member indices.
import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> interface_type_count; StructuredBuffer<uint> interface_type_hir_order;
StructuredBuffer<uint> interface_type_root_owner; StructuredBuffer<uint> interface_type_seed_owner;
StructuredBuffer<uint> interface_member_prefix; StructuredBuffer<uint> interface_member_total;
StructuredBuffer<uint> interface_generic_type_count_by_decl; RWStructuredBuffer<uint> interface_types; RWStructuredBuffer<uint> interface_status;
static const uint TYPE_WORDS=9u,TYPE_KIND_GENERIC=2u,TYPE_KIND_ARRAY=4u,TYPE_LEN_CONST=2u;
static const uint WG_SIZE=256u,MAX_GROUPS_X=65535u;
uint linear_thread_id(uint3 d){return d.x+d.y*MAX_GROUPS_X*WG_SIZE;}
void fail(uint d){atomic_u32_or(interface_status,0u,8192u);atomic_u32_min(interface_status,1u,d);}
[shader("compute")][numthreads(256,1,1)]
void main(uint3 dtid:SV_DispatchThreadID)
{
 uint index=linear_thread_id(dtid);if(index>=min(interface_type_count[0u],gParams.hir_capacity))return;
 uint node=interface_type_hir_order[index];
 uint root=node<gParams.hir_capacity?interface_type_root_owner[node]:0xffffffffu;
 uint owner=root<gParams.hir_capacity?interface_type_seed_owner[root]:0xffffffffu;if(owner>=gParams.decl_capacity){fail(index);return;}
 uint base=index*TYPE_WORDS,total=interface_member_total[0u];
 if(interface_types[base+0u]==TYPE_KIND_GENERIC){uint member=interface_member_prefix[owner]+interface_types[base+1u];if(member>=total){fail(index);return;}interface_types[base+1u]=member;}
 if(interface_types[base+0u]==TYPE_KIND_ARRAY&&interface_types[base+5u]==TYPE_LEN_CONST){uint member=interface_member_prefix[owner]+interface_generic_type_count_by_decl[owner]+interface_types[base+6u];if(member>=total){fail(index);return;}interface_types[base+6u]=member;}
}
