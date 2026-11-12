// Compacts the native-runtime references emit recorded per target row into
// object relocation rows. Each targets the object's own runtime copy as a
// Text section offset, so an unlinked object stays self-contained, while a
// link that keeps one runtime can point every object at that copy. The one
// other reference a row records, a C entry's raw-only jump, targets the
// entry's own text.

import codegen.lowering_ir;
import gpu_index;

struct Params { uint target_capacity; uint function_capacity; uint artifact_capacity; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<uint2> x86_runtime_reference;
StructuredBuffer<uint> x86_runtime_relocation_prefix;
StructuredBuffer<X86ArtifactLayout> x86_artifact_layout;
RWStructuredBuffer<X86ObjectRelocationRow> x86_object_runtime_relocations;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint SECTION_TEXT = 1u;
static const uint TARGET_SECTION_OFFSET = 1u;
static const uint RELOCATION_RAW_REL32 = 4u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= min(target_lir_total[0u], gParams.target_capacity)) return;
    uint2 reference = x86_runtime_reference[row];
    if (reference.x == 0u) return;
    X86ArtifactLayout layout = x86_artifact_layout[0u];
    X86ObjectRelocationRow relocation;
    relocation.kind = reference.y >> 16u;
    relocation.site_section = SECTION_TEXT;
    relocation.site_offset = reference.x - 1u;
    relocation.target_kind = TARGET_SECTION_OFFSET;
    relocation.target_index = SECTION_TEXT;
    // A raw-only rel32 jumps `reference.y & 0xffff` bytes past its own end.
    relocation.target_offset = relocation.kind == RELOCATION_RAW_REL32
        ? relocation.site_offset + 4u + (reference.y & 0xffffu)
        : layout.runtime_offset - layout.text_offset + (reference.y & 0xffffu);
    relocation.addend_lo = 0xfffffffcu; // rel32 is relative to the next byte
    relocation.addend_hi = 0xffffffffu;
    x86_object_runtime_relocations[x86_runtime_relocation_prefix[row]] = relocation;
}
