// Sizes list_inference_blocks once per job, after list_inference_ranges (one lane): a lane per listed function
// and per always-active block.
#include "../inference_block_layout.slang"

StructuredBuffer<uint> call_inference_fn_stamp;
StructuredBuffer<uint> inference_hir_blocks;
StructuredBuffer<uint> inference_token_blocks;
StructuredBuffer<uint> inference_arg_blocks;
RWStructuredBuffer<uint> inference_block_tables;
RWStructuredBuffer<uint> inference_list_writer_args;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    uint stamps; uint hir_list; uint token_list; uint arg_list; uint stride;
    call_inference_fn_stamp.GetDimensions(stamps, stride);
    inference_hir_blocks.GetDimensions(hir_list, stride);
    inference_token_blocks.GetDimensions(token_list, stride);
    inference_arg_blocks.GetDimensions(arg_list, stride);
    InferenceBlockLayout layout = inference_block_layout(stamps, uint3(hir_list, token_list, arg_list));
    uint lanes = min(inference_block_tables[INFERENCE_BLOCK_FUNCTIONS], layout.groups);
    [unroll]
    for (uint domain = 0u; domain < INFERENCE_BLOCK_DOMAINS; domain++)
        lanes += min(inference_block_tables[INFERENCE_BLOCK_ALWAYS + domain], layout.blocks[domain]);
    uint groups = min(max((lanes + 255u) / 256u, 1u), 65535u);
    inference_block_tables[INFERENCE_BLOCK_GROUPS] = groups;
    inference_list_writer_args[0u] = groups;
    inference_list_writer_args[1u] = 1u;
    inference_list_writer_args[2u] = 1u;
}
