// Scatter compact parameters, fields, and enum variants by semantic ordinal.
import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
struct HirParam { uint owner; uint name_token; uint type_node; uint ordinal; };
struct HirField { uint owner; uint name_token; uint value; uint ordinal; };
struct HirVariant { uint owner; uint name_token; uint ordinal; uint file_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> public_decl_index_by_hir;
StructuredBuffer<uint> public_decl_index_by_local;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> interface_generic_type_count_by_decl;
StructuredBuffer<uint> interface_generic_const_count_by_decl;
StructuredBuffer<uint> interface_member_prefix;
StructuredBuffer<uint> interface_type_index_by_hir;
StructuredBuffer<uint> interface_signature_type_by_decl;
RWStructuredBuffer<uint> interface_member_words;
RWStructuredBuffer<uint> interface_member_name_id;
RWStructuredBuffer<uint> interface_member_written;
RWStructuredBuffer<uint> interface_status;
static const uint INVALID=0xffffffffu, MEMBER_WORDS=10u;
static const uint MEMBER_PARAMETER=1u, MEMBER_FIELD=4u, MEMBER_ENUM_VARIANT=5u;
static const uint WG_SIZE=256u, MAX_GROUPS_X=65535u;
uint linear_thread_id(uint3 d){return d.x+d.y*MAX_GROUPS_X*WG_SIZE;}
void fail(uint d){atomic_u32_or(interface_status,0u,8192u);atomic_u32_min(interface_status,1u,d);}
void emit(uint owner,uint kind,uint ordinal,uint name_id,uint type_index,uint detail)
{
 uint dst=interface_member_prefix[owner]+ordinal; uint base=dst*MEMBER_WORDS;
 interface_member_words[base+0u]=owner;interface_member_words[base+1u]=kind;interface_member_words[base+2u]=ordinal;
 interface_member_words[base+3u]=0u;interface_member_words[base+4u]=0u;interface_member_words[base+5u]=0u;interface_member_words[base+6u]=0u;
 interface_member_words[base+7u]=type_index;interface_member_words[base+8u]=0u;interface_member_words[base+9u]=0u;
 uint prior=atomic_u32_compare_exchange(interface_member_written,dst,0u,1u);if(prior!=0u){fail(detail);return;}
 interface_member_name_id[dst]=name_id;
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
   if(name_id==INVALID||type_index==INVALID)fail(row);else emit(owner,MEMBER_PARAMETER,param.ordinal+generic_count,name_id,type_index,row);
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
   if(name_id==INVALID||type_index==INVALID)fail(row);else emit(owner,MEMBER_FIELD,field.ordinal+generic_count,name_id,type_index,row);
  }
 }
 if(row<min(compact_variant_count[0u],gParams.hir_capacity))
 {
  HirVariant variant=compact_variants[row];
  uint owner=variant.owner<gParams.hir_capacity?public_decl_index_by_hir[variant.owner]:INVALID;
  uint local=variant.name_token<gParams.token_capacity?decl_id_by_name_token[variant.name_token]:INVALID;
  uint persisted=local<gParams.decl_capacity?public_decl_index_by_local[local]:INVALID;
  if(owner<gParams.decl_capacity&&persisted<gParams.decl_capacity)
  {
   uint generic_count=interface_generic_type_count_by_decl[owner]+interface_generic_const_count_by_decl[owner];
   uint name_id=variant.name_token<gParams.token_capacity?name_id_by_token[variant.name_token]:INVALID;
   uint type_index=interface_signature_type_by_decl[persisted];
   if(name_id==INVALID||type_index==INVALID)fail(row);else emit(owner,MEMBER_ENUM_VARIANT,variant.ordinal+generic_count,name_id,type_index,row);
  }
 }
}
