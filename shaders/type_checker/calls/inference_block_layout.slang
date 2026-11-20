// Word offsets of inference_block_tables (type_checker/calls/inference/list_inference_ranges.slang).
//   [0] functions listed, [1] workgroups of list_inference_blocks that finished the round's
//   list, [2..5) numbers of HIR, token and argument blocks listed so far,
//   [5] workgroups of list_inference_blocks, [6..9) numbers of always-active
//   blocks in the same order, [9] unused;
//   from 10, six words per stamp row g (inference_activity.slang): the
//   largest ~row and the largest row + 1 of g's HIR rows, then the same for
//   its tokens and call arguments (0 when g has none);
//   then the function list (stamp rows), the HIR, token and argument block
//   marks (the last round that listed the block, ~0 for an always-active
//   block), the always-active block lists in the same order.
// A row whose item inference_token_active recomputes in every round (one
// without a token, or with a function row past the stamps) makes its block
// always active.
static const uint INFERENCE_BLOCK_HEADER = 10u;
static const uint INFERENCE_BLOCK_DOMAINS = 3u;
static const uint INFERENCE_ARGUMENT_TILE = 32u;
static const uint INFERENCE_BLOCK_FUNCTIONS = 0u;
static const uint INFERENCE_BLOCK_DONE = 1u;
static const uint INFERENCE_BLOCK_LISTED = 2u;
static const uint INFERENCE_BLOCK_GROUPS = 5u;
static const uint INFERENCE_BLOCK_ALWAYS = 6u;

struct InferenceBlockLayout
{
    uint groups;
    uint3 blocks;
    uint functions;
    uint3 marks;
    uint3 always;
};

// From the element counts of call_inference_fn_stamp, inference_hir_blocks
// and the other block lists (two header words, then one word per block).
InferenceBlockLayout inference_block_layout(uint stamps, uint3 list_sizes)
{
    InferenceBlockLayout layout;
    layout.groups = stamps;
    layout.blocks = list_sizes - 2u;
    layout.functions = INFERENCE_BLOCK_HEADER + layout.groups * (INFERENCE_BLOCK_DOMAINS * 2u);
    uint marks = layout.functions + layout.groups;
    uint always = marks + layout.blocks.x + layout.blocks.y + layout.blocks.z;
    uint3 offsets = uint3(0u, layout.blocks.x, layout.blocks.x + layout.blocks.y);
    layout.marks = marks + offsets;
    layout.always = always + offsets;
    return layout;
}
