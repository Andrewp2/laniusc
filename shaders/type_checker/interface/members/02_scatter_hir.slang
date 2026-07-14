// Scatter parameters, fields, and enum variants by parser semantic ordinal.
import atomics;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_status; StructuredBuffer<uint> hir_kind; StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint4> hir_param_record; StructuredBuffer<uint> hir_param_type_node;
StructuredBuffer<uint> hir_struct_field_parent_struct; StructuredBuffer<uint> hir_struct_field_ordinal;
StructuredBuffer<uint> hir_struct_field_type_node; StructuredBuffer<uint> hir_variant_parent_enum;
StructuredBuffer<uint> hir_variant_ordinal; StructuredBuffer<uint> public_decl_index_by_hir;
StructuredBuffer<uint> name_id_by_token; StructuredBuffer<uint> interface_generic_type_count_by_decl;
StructuredBuffer<uint> interface_generic_const_count_by_decl; StructuredBuffer<uint> interface_member_prefix;
StructuredBuffer<uint> interface_type_index_by_hir; StructuredBuffer<uint> interface_signature_type_by_decl;
RWStructuredBuffer<uint> interface_member_words; RWStructuredBuffer<uint> interface_member_name_id;
RWStructuredBuffer<uint> interface_member_index_by_hir; RWStructuredBuffer<uint> interface_member_written;
RWStructuredBuffer<uint> interface_status;
static const uint INVALID=0xffffffffu, MEMBER_WORDS=10u, HIR_PARAM=4u;
static const uint MEMBER_PARAMETER=1u, MEMBER_FIELD=4u, MEMBER_ENUM_VARIANT=5u;
static const uint WG_SIZE=256u, MAX_GROUPS_X=65535u;
uint linear_thread_id(uint3 d){return d.x+d.y*MAX_GROUPS_X*WG_SIZE;}
void fail(uint d){atomic_u32_or(interface_status,0u,8192u);atomic_u32_min(interface_status,1u,d);}
void emit(uint node,uint owner,uint kind,uint ordinal,uint name_id,uint type_index)
{
 uint dst=interface_member_prefix[owner]+ordinal; uint base=dst*MEMBER_WORDS;
 interface_member_words[base+0u]=owner;interface_member_words[base+1u]=kind;interface_member_words[base+2u]=ordinal;
 interface_member_words[base+3u]=0u;interface_member_words[base+4u]=0u;interface_member_words[base+5u]=0u;interface_member_words[base+6u]=0u;
 interface_member_words[base+7u]=type_index;interface_member_words[base+8u]=0u;interface_member_words[base+9u]=0u;
 uint prior=atomic_u32_compare_exchange(interface_member_written,dst,0u,1u);if(prior!=0u){fail(dst);return;}
 interface_member_name_id[dst]=name_id;interface_member_index_by_hir[node]=dst;
}
[shader("compute")][numthreads(256,1,1)]
void main(uint3 dtid:SV_DispatchThreadID)
{
 uint node=linear_thread_id(dtid);if(node>=min(hir_status[5u],gParams.hir_capacity))return;
 uint owner_hir=INVALID,ordinal=INVALID,name_token=INVALID,type_node=INVALID,kind=0u,type_index=INVALID;
 if(hir_kind[node]==HIR_PARAM){uint4 r=hir_param_record[node];owner_hir=r.x;ordinal=r.y;name_token=r.z;type_node=hir_param_type_node[node];kind=MEMBER_PARAMETER;}
 else if(hir_variant_parent_enum[node]<gParams.hir_capacity){owner_hir=hir_variant_parent_enum[node];ordinal=hir_variant_ordinal[node];name_token=hir_token_pos[node];kind=MEMBER_ENUM_VARIANT;}
 else if(hir_struct_field_parent_struct[node]<gParams.hir_capacity){owner_hir=hir_struct_field_parent_struct[node];ordinal=hir_struct_field_ordinal[node];name_token=hir_token_pos[node];type_node=hir_struct_field_type_node[node];kind=MEMBER_FIELD;}
 else return;
 uint owner=public_decl_index_by_hir[owner_hir];if(owner>=gParams.decl_capacity)return;
 uint generic_count=interface_generic_type_count_by_decl[owner]+interface_generic_const_count_by_decl[owner];ordinal+=generic_count;
 uint name_id=name_token<gParams.token_capacity?name_id_by_token[name_token]:INVALID;
 if(kind==MEMBER_ENUM_VARIANT){uint variant=public_decl_index_by_hir[node];type_index=variant<gParams.decl_capacity?interface_signature_type_by_decl[variant]:INVALID;}
 else type_index=type_node<gParams.hir_capacity?interface_type_index_by_hir[type_node]:INVALID;
 if(name_id==INVALID||type_index==INVALID){fail(node);return;} emit(node,owner,kind,ordinal,name_id,type_index);
}
