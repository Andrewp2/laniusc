// Word offsets of inference_block_tables (03m0_inference_ranges.slang).
//   [0] functions listed, [1] workgroups of 03m1 that finished the round's
//   list, [2] HIR blocks listed so far, [3] token blocks listed so far,
//   [4] workgroups of 03m1, [5] always-active HIR blocks, [6] always-active
//   token blocks, [7] unused;
//   from 8, four words per stamp row g (inference_activity.slang): the
//   largest ~row and the largest row + 1 of g's HIR rows, then the same for
//   its tokens (0 when g has none);
//   then the function list (stamp rows), the HIR block marks, the token block
//   marks (the last round that listed the block, ~0 for an always-active
//   block), the always-active HIR blocks and the always-active token blocks.
// A row whose item inference_token_active recomputes in every round (one
// without a token, or with a function row past the stamps) makes its block
// always active.
static const uint INFERENCE_BLOCK_HEADER = 8u;
static const uint INFERENCE_BLOCK_FUNCTIONS = 0u;
static const uint INFERENCE_BLOCK_DONE = 1u;
static const uint INFERENCE_BLOCK_LISTED = 2u;
static const uint INFERENCE_BLOCK_GROUPS = 4u;
static const uint INFERENCE_BLOCK_ALWAYS = 5u;

struct InferenceBlockLayout
{
    uint groups;
    uint hir_blocks;
    uint token_blocks;
    uint functions;
    uint hir_marks;
    uint token_marks;
    uint hir_always;
    uint token_always;
};

// From the element counts of call_inference_fn_stamp, inference_hir_blocks
// and inference_token_blocks (two header words, then one word per block).
InferenceBlockLayout inference_block_layout(uint stamps, uint hir_list, uint token_list)
{
    InferenceBlockLayout layout;
    layout.groups = stamps;
    layout.hir_blocks = hir_list - 2u;
    layout.token_blocks = token_list - 2u;
    layout.functions = INFERENCE_BLOCK_HEADER + layout.groups * 4u;
    layout.hir_marks = layout.functions + layout.groups;
    layout.token_marks = layout.hir_marks + layout.hir_blocks;
    layout.hir_always = layout.token_marks + layout.token_blocks;
    layout.token_always = layout.hir_always + layout.hir_blocks;
    return layout;
}
