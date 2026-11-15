// Which items a call inference round recomputes
// (docs/compiler-call-inference-rounds.md).
//
// call_inference_round[0] is the round's number: 0 outside the rounds (the
// direct passes, the lookup sweeps and the final pass) and 1 for the job's
// first round (03z_begin_inference_round counts it up). Word 1 is the last
// round that changed a fact outside every function, or a fact without one
// owning function.
//
// call_inference_fn_stamp[g] is the last round that changed a fact of the
// function whose HIR row is g - 1 (enclosing_fn's value for its tokens). A
// pass counts a change with inference_note_change on a token of the item it
// changed, next to its call_inference_state[1] count.
//
// An item is recomputed in round r when r is the first round, or when its
// function or the global word changed a fact in round r - 1 (a change
// counted on the item's function, or on a lane that named no item). A function
// without a change in round r - 1 starts round r with the facts it started
// round r - 1 with, so round r would write each of its facts again with the
// value it holds: skipping its items leaves the same tables.
module inference_activity;

public RWStructuredBuffer<uint> call_inference_round;
public RWStructuredBuffer<uint> call_inference_fn_stamp;
public StructuredBuffer<uint> enclosing_fn;

static const uint INFERENCE_ACTIVITY_NO_GROUP = 0xffffffffu;

// The stamp row of `token`'s function, or NO_GROUP outside every function
// (an invalid token included).
uint inference_group(uint token)
{
    uint count; uint stride;
    enclosing_fn.GetDimensions(count, stride);
    if (token >= count) return INFERENCE_ACTIVITY_NO_GROUP;
    uint group = enclosing_fn[token];
    call_inference_fn_stamp.GetDimensions(count, stride);
    return group == 0u || group >= count ? INFERENCE_ACTIVITY_NO_GROUP : group;
}

// Whether the current pass recomputes the item that owns `token`. Every
// item outside a round is recomputed.
public bool inference_token_active(uint token)
{
    uint round = call_inference_round[0u];
    if (round <= 1u || call_inference_round[1u] + 1u >= round) return true;
    uint count; uint stride;
    enclosing_fn.GetDimensions(count, stride);
    // An item without a token is recomputed every round.
    if (token >= count) return true;
    uint group = enclosing_fn[token];
    // Outside every function only a global change starts a recomputation.
    if (group == 0u) return false;
    call_inference_fn_stamp.GetDimensions(count, stride);
    return group >= count || call_inference_fn_stamp[group] + 1u >= round;
}

// Records that the current round changed a fact of the item that owns
// `token` (or could not finish it), so the item's function is recomputed
// next round. A token outside every function marks every function.
public void inference_note_change(uint token)
{
    uint round = call_inference_round[0u];
    if (round == 0u) return;
    uint group = inference_group(token);
    uint ignored;
    if (group == INFERENCE_ACTIVITY_NO_GROUP) InterlockedMax(call_inference_round[1u], round, ignored);
    else InterlockedMax(call_inference_fn_stamp[group], round, ignored);
}

// The token of the item this lane computes, set by inference_item_active.
static uint inference_item_token = INFERENCE_ACTIVITY_NO_GROUP;

// Whether the current pass recomputes the item that owns `token`, which the
// lane computes: its later inference_note_item_change calls mark the item's
// function.
public bool inference_item_active(uint token)
{
    inference_item_token = token;
    return inference_token_active(token);
}

// inference_note_change for the lane's item. A lane that named no item marks
// every function.
public void inference_note_item_change()
{
    inference_note_change(inference_item_token);
}

// Records a change no single function owns: every function is recomputed
// next round.
public void inference_note_global_change()
{
    uint round = call_inference_round[0u];
    if (round == 0u) return;
    uint ignored;
    InterlockedMax(call_inference_round[1u], round, ignored);
}
