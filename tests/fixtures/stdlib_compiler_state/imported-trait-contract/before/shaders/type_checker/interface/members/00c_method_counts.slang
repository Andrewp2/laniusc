// Count public inherent methods into their owning public type declaration's
// member segment.  This is separate from ordinary member counting so the
// declaration rows are initialized before parallel method lanes add to them.

import hir_records;
import atomics;

struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirMethodCore> compact_method_cores;
StructuredBuffer<HirMethodSignature> compact_method_signatures;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> type_decl_generic_param_count_by_owner_token;
StructuredBuffer<uint> type_decl_const_param_count_by_owner_token;
RWStructuredBuffer<uint> interface_generic_scope_owner_by_hir;
StructuredBuffer<HirRange> compact_param_ranges;
StructuredBuffer<uint> interface_type_local_decl_by_hir;
StructuredBuffer<uint> public_decl_index_by_local;
RWStructuredBuffer<uint> interface_member_count;
RWStructuredBuffer<uint> interface_status;

static const uint INVALID=0xffffffffu;
static const uint METHOD_VIS_PUBLIC=1u, METHOD_SIGNATURE_INHERENT_IMPL=4u;
static const uint WG_SIZE=256u, MAX_GROUPS_X=65535u;
uint linear_thread_id(uint3 d){return d.x+d.y*MAX_GROUPS_X*WG_SIZE;}

uint method_owner(uint row)
{
 uint count=min(compact_method_count[0u],gParams.hir_capacity);
 if(row>=count)return INVALID;
 HirMethodCore core=compact_method_cores[row];
 HirMethodSignature sig=compact_method_signatures[row];
 if(((sig.metadata>>16u)&METHOD_SIGNATURE_INHERENT_IMPL)==0u ||
    (sig.metadata&0xffffu)!=METHOD_VIS_PUBLIC)return INVALID;
 uint receiver_type=sig.impl_receiver_type;
 uint local=receiver_type<gParams.hir_capacity?interface_type_local_decl_by_hir[receiver_type]:INVALID;
 return local<gParams.decl_capacity?public_decl_index_by_local[local]:INVALID;
}

uint parameter_count(uint node)
{
 if(node>=gParams.hir_capacity)return 0u;
 uint token=compact_hir_payload[node].b;
 if(token>=gParams.token_capacity)token=compact_hir_core[node].token_start;
 return token<gParams.token_capacity ? type_decl_generic_param_count_by_owner_token[token]+
     type_decl_const_param_count_by_owner_token[token] : 0u;
}
[shader("compute")][numthreads(256,1,1)]
void main(uint3 dtid:SV_DispatchThreadID)
{
 uint row=linear_thread_id(dtid);
 uint owner=method_owner(row);
 if(owner==INVALID||owner>=gParams.decl_capacity)return;
 uint method_node=compact_method_cores[row].node;
 if(method_node>=gParams.hir_capacity)return;
 uint params=compact_param_ranges[method_node].count;
 uint mode=compact_method_signatures[row].receiver_mode;
 if((mode==1u||mode==2u)&&params!=0u)params-=1u;
 interface_generic_scope_owner_by_hir[method_node]=owner;
 uint count=1u+params+parameter_count(method_node);
 uint impl_node=compact_method_cores[row].impl_node;
 if(impl_node<gParams.hir_capacity)
 {
  uint prior=atomic_u32_compare_exchange(interface_generic_scope_owner_by_hir,impl_node,INVALID,owner);
  if(prior==INVALID)count+=parameter_count(impl_node);
  else if(prior!=owner)atomic_u32_or(interface_status,0u,8192u);
 }
 atomic_u32_add(interface_member_count,owner,count);
}
