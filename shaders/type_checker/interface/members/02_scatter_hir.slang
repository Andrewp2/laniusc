// Scatter compact parameters, fields, and enum variants by semantic ordinal.
import hir_records;
import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<HirRange> compact_param_ranges;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirMethodCore> compact_method_cores;
StructuredBuffer<HirMethodSignature> compact_method_signatures;
StructuredBuffer<uint> compact_fn_return_type;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> public_decl_index_by_hir;
StructuredBuffer<uint> public_decl_index_by_local;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> interface_generic_type_count_by_decl;
StructuredBuffer<uint> interface_generic_const_count_by_decl;
StructuredBuffer<uint> interface_member_prefix;
RWStructuredBuffer<uint> interface_member_cursor;
StructuredBuffer<uint> interface_type_index_by_hir;
StructuredBuffer<uint> interface_type_count;
StructuredBuffer<uint> interface_signature_type_by_decl;
RWStructuredBuffer<uint> interface_member_words;
RWStructuredBuffer<uint> interface_member_name_id;
RWStructuredBuffer<uint> interface_member_written;
RWStructuredBuffer<uint> interface_status;
static const uint INVALID=0xffffffffu, MEMBER_WORDS=10u;
static const uint MEMBER_PARAMETER=1u, MEMBER_FIELD=4u, MEMBER_ENUM_VARIANT=5u, MEMBER_ASSOCIATED_METHOD=6u;
static const uint TYPE_REF_INSTANCE=3u, METHOD_VIS_PUBLIC=1u, METHOD_SIGNATURE_INHERENT_IMPL=4u;
static const uint WG_SIZE=256u, MAX_GROUPS_X=65535u;
uint linear_thread_id(uint3 d){return d.x+d.y*MAX_GROUPS_X*WG_SIZE;}
void fail(uint d){atomic_u32_or(interface_status,0u,8192u);atomic_u32_min(interface_status,1u,d);}
void emit(uint owner,uint kind,uint ordinal,uint name_id,uint type_index,uint value_lo,uint value_hi,uint detail)
{
 uint dst=interface_member_prefix[owner]+ordinal; uint base=dst*MEMBER_WORDS;
 interface_member_words[base+0u]=owner;interface_member_words[base+1u]=kind;interface_member_words[base+2u]=ordinal;
 interface_member_words[base+3u]=0u;interface_member_words[base+4u]=0u;interface_member_words[base+5u]=0u;interface_member_words[base+6u]=0u;
 interface_member_words[base+7u]=type_index;interface_member_words[base+8u]=value_lo;interface_member_words[base+9u]=value_hi;
 uint prior=atomic_u32_compare_exchange(interface_member_written,dst,0u,1u);if(prior!=0u){fail(detail);return;}
 interface_member_name_id[dst]=name_id;
}

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
 uint payload=receiver_token<gParams.token_capacity?type_expr_ref_payload[receiver_token]:INVALID;
 uint tag=receiver_token<gParams.token_capacity?type_expr_ref_tag[receiver_token]:0u;
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
 if(row<min(compact_param_count[0u],gParams.hir_capacity))
 {
  HirParam param=compact_params[row];
  uint owner=param.owner<gParams.hir_capacity?public_decl_index_by_hir[param.owner]:INVALID;
  if(owner<gParams.decl_capacity)
  {
   uint generic_count=interface_generic_type_count_by_decl[owner]+interface_generic_const_count_by_decl[owner];
   uint name_id=param.name_token<gParams.token_capacity?name_id_by_token[param.name_token]:INVALID;
   uint type_index=param.type_node<gParams.hir_capacity?interface_type_index_by_hir[param.type_node]:INVALID;
   if(name_id==INVALID||type_index==INVALID)fail(row);else emit(owner,MEMBER_PARAMETER,param.ordinal+generic_count,name_id,type_index,0u,0u,row);
  }
 }
 if(row<min(compact_field_count[0u],gParams.hir_capacity))
 {
  HirField field=compact_fields[row];
  uint owner=field.owner<gParams.hir_capacity?public_decl_index_by_hir[field.owner]:INVALID;
  if(owner<gParams.decl_capacity)
  {
   uint generic_count=interface_generic_type_count_by_decl[owner]+interface_generic_const_count_by_decl[owner];
   uint name_id=field.name_token<gParams.token_capacity?name_id_by_token[field.name_token]:INVALID;
   uint type_index=field.value<gParams.hir_capacity?interface_type_index_by_hir[field.value]:INVALID;
   if(name_id==INVALID||type_index==INVALID)fail(row);else emit(owner,MEMBER_FIELD,field.ordinal+generic_count,name_id,type_index,0u,0u,row);
  }
 }
 if(row<min(compact_variant_count[0u],gParams.hir_capacity))
 {
 HirVariant variant=compact_variants[row];
  uint owner=variant.owner<gParams.hir_capacity?public_decl_index_by_hir[variant.owner]:INVALID;
  uint variant_count=min(compact_variant_count[0u],gParams.hir_capacity);
  uint decl_count=min(decl_count_out[0u],gParams.decl_capacity);
  uint local=decl_count>=variant_count?decl_count-variant_count+row:INVALID;
  uint persisted=local<gParams.decl_capacity?public_decl_index_by_local[local]:INVALID;
  if(owner<gParams.decl_capacity&&persisted<gParams.decl_capacity)
  {
   uint generic_count=interface_generic_type_count_by_decl[owner]+interface_generic_const_count_by_decl[owner];
   uint name_id=variant.name_token<gParams.token_capacity?name_id_by_token[variant.name_token]:INVALID;
   uint type_index=interface_signature_type_by_decl[persisted];
   if(name_id==INVALID||type_index==INVALID)fail(row);else emit(owner,MEMBER_ENUM_VARIANT,variant.ordinal+generic_count,name_id,type_index,0u,0u,row);
 }
 }

 if(row<min(compact_method_count[0u],gParams.hir_capacity))
 {
  HirMethodCore method=compact_method_cores[row];
  HirMethodSignature signature=compact_method_signatures[row];
  uint owner=method_owner(row);
  if(owner<gParams.decl_capacity)
  {
   uint method_token=method.name_token;
   uint name_id=method_token<gParams.token_capacity?name_id_by_token[method_token]:INVALID;
   uint return_hir=method.node<gParams.hir_capacity?compact_fn_return_type[method.node]:INVALID;
   uint type_index=return_hir<gParams.hir_capacity?interface_type_index_by_hir[return_hir]:interface_type_count[0u];
   uint param_count=compact_param_ranges[method.node].count;
   if(signature.receiver_mode!=0u&&param_count!=0u)param_count-=1u;
   uint ordinal=atomic_u32_add(interface_member_cursor,owner,1u);
   uint generic_count=interface_generic_type_count_by_decl[owner]+interface_generic_const_count_by_decl[owner];
   if(ordinal<generic_count) { fail(row); return; }
   ordinal = ordinal;
   if(name_id==INVALID||type_index==INVALID)fail(row);
   // Method symbols occupy a namespace disjoint from declaration indices. The
   // compact method HIR row is stable within the unit and is carried through
   // the persisted member record for dependency calls and object definitions.
   else emit(owner,MEMBER_ASSOCIATED_METHOD,ordinal,name_id,type_index,param_count,0x80000000u|method.node,row);
  }
 }
}
