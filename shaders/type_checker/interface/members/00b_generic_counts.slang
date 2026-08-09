// Derive stable per-public-declaration generic counts from the same compacted
// rows and slots consumed by member scatter.
import hir_records;
import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_generic_param_count;
StructuredBuffer<HirGenericParam> compact_generic_params;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_const_param_slot_by_token;
StructuredBuffer<uint> public_decl_index_by_hir;
RWStructuredBuffer<uint> interface_generic_type_count_by_decl;
RWStructuredBuffer<uint> interface_generic_const_count_by_decl;
static const uint GENERIC_TYPE=1u,GENERIC_CONST=2u,WG_SIZE=256u,MAX_GROUPS_X=65535u;
uint linear_thread_id(uint3 d){return d.x+d.y*MAX_GROUPS_X*WG_SIZE;}
[shader("compute")][numthreads(256,1,1)]
void main(uint3 dtid:SV_DispatchThreadID)
{
 uint row=linear_thread_id(dtid);if(row>=min(compact_generic_param_count[0u],gParams.hir_capacity))return;
 HirGenericParam parameter=compact_generic_params[row];
 uint owner=parameter.owner<gParams.hir_capacity?public_decl_index_by_hir[parameter.owner]:0xffffffffu;
 uint token=parameter.name_token;if(owner>=gParams.decl_capacity||token>=gParams.token_capacity)return;
 uint kind=parameter.kind;
 if(kind==GENERIC_TYPE){uint slot=type_generic_param_slot_by_token[token];if(slot<gParams.token_capacity)atomic_u32_max(interface_generic_type_count_by_decl,owner,slot+1u);}
 else if(kind==GENERIC_CONST){uint slot=type_const_param_slot_by_token[token];if(slot<gParams.token_capacity)atomic_u32_max(interface_generic_const_count_by_decl,owner,slot+1u);}
}
