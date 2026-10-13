// Predicate scatter appends exact impl-owned bounds; close empty ranges and
// prove every nonempty range contains only that lexical implementation's rows.
import hir_records;
import atomics;
import semantic_interface_layout;
struct Params { uint hir_capacity; uint decl_capacity; uint token_capacity; uint library_id; uint unit_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> interface_implementation_flag;
StructuredBuffer<uint> interface_implementation_prefix;
StructuredBuffer<uint> interface_implementation_total;
StructuredBuffer<uint> interface_predicate_total;
StructuredBuffer<uint> interface_predicate_words;
RWStructuredBuffer<uint> interface_implementation_words;
RWStructuredBuffer<uint> interface_status;
void fail(uint row)
{
 atomic_u32_or(interface_status, 0u, 131072u);
 atomic_u32_min(interface_status, 1u, row);
 atomic_u32_min(interface_status, 2u, 51u);
}
[shader("compute")][numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
 uint row=dtid.x+dtid.y*16776960u; uint rows;uint stride;
 interface_implementation_flag.GetDimensions(rows,stride);
 if(row>=min(compact_hir_count[0u],rows)||interface_implementation_flag[row]!=1u)return;
 uint index=interface_implementation_prefix[row];
 if(index>=interface_implementation_total[0u]){fail(row);return;}
 uint base=index*SEMANTIC_INTERFACE_IMPLEMENTATION_WORDS;
 uint count=interface_implementation_words[base+11u];
 if(count==0u){interface_implementation_words[base+10u]=0u;return;}
 uint first=interface_implementation_words[base+10u];uint total=interface_predicate_total[0u];
 if(first>total||count>total-first){fail(row);return;}
 for(uint n=0u;n<count;n++)
 {
  uint predicate=(first+n)*SEMANTIC_INTERFACE_PREDICATE_WORDS;
  if(interface_predicate_words[predicate]!=(SEMANTIC_INTERFACE_IMPLEMENTATION_OWNER|index)||
     interface_predicate_words[predicate+1u]!=(0xc0000000u|row)){fail(row);return;}
 }
}
