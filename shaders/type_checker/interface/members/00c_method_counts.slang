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
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> public_decl_index_by_local;
RWStructuredBuffer<uint> interface_member_count;
RWStructuredBuffer<uint> interface_status;

static const uint INVALID=0xffffffffu, TYPE_REF_INSTANCE=3u;
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
 uint receiver_token=receiver_type<gParams.hir_capacity?compact_hir_core[receiver_type].token_start:INVALID;
 uint tag=receiver_token<gParams.token_capacity?type_expr_ref_tag[receiver_token]:0u;
 uint payload=receiver_token<gParams.token_capacity?type_expr_ref_payload[receiver_token]:INVALID;
 if(tag!=TYPE_REF_INSTANCE||payload>=gParams.token_capacity)return INVALID;
 uint decl_token=type_instance_decl_token[payload];
 if(decl_token>=gParams.token_capacity)return INVALID;
 uint local=decl_id_by_name_token[decl_token];
 return local<gParams.decl_capacity?public_decl_index_by_local[local]:INVALID;
}

[shader("compute")][numthreads(256,1,1)]
void main(uint3 dtid:SV_DispatchThreadID)
{
 uint row=linear_thread_id(dtid);
 uint owner=method_owner(row);
 if(owner==INVALID||owner>=gParams.decl_capacity)return;
 atomic_u32_add(interface_member_count,owner,1u);
}
