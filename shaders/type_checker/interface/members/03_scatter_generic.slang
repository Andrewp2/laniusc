// Scatter declaration generic parameters before ordinary members.
import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> generic_param_count_out; StructuredBuffer<uint> generic_param_owner_node;
StructuredBuffer<uint> generic_param_name_id; StructuredBuffer<uint> generic_param_token;
StructuredBuffer<uint> generic_param_kind; StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_const_param_slot_by_token; StructuredBuffer<uint> interface_generic_type_count_by_decl;
StructuredBuffer<uint> public_decl_index_by_hir; StructuredBuffer<uint> interface_member_prefix;
RWStructuredBuffer<uint> interface_member_words; RWStructuredBuffer<uint> interface_member_name_id;
RWStructuredBuffer<uint> interface_member_index_by_generic_row; RWStructuredBuffer<uint> interface_member_written;
RWStructuredBuffer<uint> interface_status;
static const uint INVALID=0xffffffffu,MEMBER_WORDS=10u,GENERIC_TYPE=1u,GENERIC_CONST=2u;
static const uint MEMBER_GENERIC_TYPE=2u,MEMBER_GENERIC_CONST=3u,WG_SIZE=256u,MAX_GROUPS_X=65535u;
uint linear_thread_id(uint3 d){return d.x+d.y*MAX_GROUPS_X*WG_SIZE;}
void fail(uint d){atomic_u32_or(interface_status,0u,8192u);atomic_u32_min(interface_status,1u,d);}
[shader("compute")][numthreads(256,1,1)]
void main(uint3 dtid:SV_DispatchThreadID)
{
 uint row=linear_thread_id(dtid);if(row>=min(generic_param_count_out[0u],gParams.token_capacity))return;
 uint owner_hir=generic_param_owner_node[row];uint owner=owner_hir<gParams.hir_capacity?public_decl_index_by_hir[owner_hir]:INVALID;if(owner>=gParams.decl_capacity)return;
 uint token=generic_param_token[row],kind=generic_param_kind[row],slot=INVALID,member_kind=0u;
 if(kind==GENERIC_TYPE){slot=token<gParams.token_capacity?type_generic_param_slot_by_token[token]:INVALID;member_kind=MEMBER_GENERIC_TYPE;}
 else if(kind==GENERIC_CONST){slot=token<gParams.token_capacity?type_const_param_slot_by_token[token]:INVALID;slot=slot==INVALID?INVALID:interface_generic_type_count_by_decl[owner]+slot;member_kind=MEMBER_GENERIC_CONST;}
 uint name_id=generic_param_name_id[row];if(slot==INVALID||name_id==INVALID){fail(row);return;}
 uint dst=interface_member_prefix[owner]+slot,base=dst*MEMBER_WORDS;
 interface_member_words[base+0u]=owner;interface_member_words[base+1u]=member_kind;interface_member_words[base+2u]=slot;
 interface_member_words[base+3u]=0u;interface_member_words[base+4u]=0u;interface_member_words[base+5u]=0u;interface_member_words[base+6u]=0u;
 interface_member_words[base+7u]=INVALID;interface_member_words[base+8u]=0u;interface_member_words[base+9u]=0u;
 uint prior=atomic_u32_compare_exchange(interface_member_written,dst,0u,1u);if(prior!=0u){fail(dst);return;}
 interface_member_name_id[dst]=name_id;interface_member_index_by_generic_row[row]=dst;
}
