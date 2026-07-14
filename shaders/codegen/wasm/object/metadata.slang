// Publish compact object counts/status after projection.

import prefix_scan;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> body_plan;
StructuredBuffer<uint> interface_public_decl_count;
StructuredBuffer<uint> wasm_type_scan_block_prefix;
StructuredBuffer<uint> call_reloc_status;
RWStructuredBuffer<uint> object_metadata;

static const uint BODY_PLAN_BODY_LEN = 3u;
static const uint BODY_PLAN_FUNCTION_COUNT = 31u;
static const uint BODY_PLAN_MAIN_SLOT = 34u;

[shader("compute")]
[numthreads(8, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint slot = tid.x;
    if (slot == 0u) object_metadata[0u] = body_plan[BODY_PLAN_FUNCTION_COUNT];
    else if (slot == 1u) object_metadata[1u] = body_plan[BODY_PLAN_BODY_LEN];
    else if (slot == 2u) object_metadata[2u] = inclusive_scan_total(gScan.n_blocks, wasm_type_scan_block_prefix);
    else if (slot == 3u) object_metadata[3u] = interface_public_decl_count[0u];
    else if (slot == 4u) object_metadata[4u] = body_plan[BODY_PLAN_MAIN_SLOT];
    else if (slot == 5u) object_metadata[5u] = call_reloc_status[0u];
    else if (slot == 6u) object_metadata[6u] = call_reloc_status[1u];
    else if (slot == 7u) object_metadata[7u] = call_reloc_status[2u];
}
