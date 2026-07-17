// Size one contiguous stable member segment per public declaration.
import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> public_decl_count;
StructuredBuffer<uint> public_decl_local_id;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_hir_node;
struct HirRange { uint start; uint count; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirRange> compact_param_ranges;
StructuredBuffer<uint> interface_field_count_by_hir;
StructuredBuffer<uint> interface_variant_count_by_hir;
StructuredBuffer<uint> interface_generic_type_count_by_decl;
StructuredBuffer<uint> interface_generic_const_count_by_decl;
RWStructuredBuffer<uint> interface_member_count;
RWStructuredBuffer<uint> interface_status;
static const uint HIR_ITEM_KIND_FN=4u, HIR_ITEM_KIND_EXTERN_FN=5u;
static const uint HIR_ITEM_KIND_STRUCT=6u, HIR_ITEM_KIND_ENUM=7u;
static const uint WG_SIZE=256u, MAX_GROUPS_X=65535u;
uint linear_thread_id(uint3 d){return d.x+d.y*MAX_GROUPS_X*WG_SIZE;}
void fail(uint d){atomic_u32_or(interface_status,0u,8192u);atomic_u32_min(interface_status,1u,d);}
[shader("compute")][numthreads(256,1,1)]
void main(uint3 dtid:SV_DispatchThreadID)
{
 uint p=linear_thread_id(dtid); if(p>=gParams.decl_capacity)return;
 interface_member_count[p]=0u;
 if(p>=min(public_decl_count[0u],gParams.decl_capacity))return;
 uint local=public_decl_local_id[p]; uint hir=local<gParams.decl_capacity?decl_hir_node[local]:0xffffffffu;
 if(hir>=min(compact_hir_count[0u],gParams.hir_capacity)){fail(p);return;}
 uint count=interface_generic_type_count_by_decl[p]+interface_generic_const_count_by_decl[p];
 uint kind=decl_kind[local];
 if(kind==HIR_ITEM_KIND_FN||kind==HIR_ITEM_KIND_EXTERN_FN)count+=compact_param_ranges[hir].count;
 else if(kind==HIR_ITEM_KIND_STRUCT)count+=interface_field_count_by_hir[hir];
 else if(kind==HIR_ITEM_KIND_ENUM)count+=interface_variant_count_by_hir[hir];
 interface_member_count[p]=count;
}
