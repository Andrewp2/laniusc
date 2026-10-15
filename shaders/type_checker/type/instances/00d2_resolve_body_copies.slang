import gpu_index;
import hir_records;
import status;

// Instance-copy replay: the host appended a renamed copy of each entry's
// generic body to the unit and named the copy by the source byte of its `fn`
// keyword (it never lexes). This pass, the first of a body replay, finds the
// function row whose first token starts at that byte and rewrites the
// entry's target to the method form 0x80000000 | row, which selects that
// function and its enclosing impl. Every later reader of the packet sees an
// ordinary resolved target.
struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
struct TokenIn { uint kind; uint start; uint len; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> token_count;
RWStructuredBuffer<uint4> body_specialization_inputs;
RWStructuredBuffer<uint> status;

#include "body_specialization_entries.slang"

static const uint INVALID = 0xffffffffu;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, 16776960u);
    uint entries = body_entry_count();
    // Copy entries are all-or-nothing and sorted by copy byte.
    if (entries == 0u || body_entry_copy_byte(0u) == INVALID) return;
    uint hir_rows; uint stride;
    compact_hir_core.GetDimensions(hir_rows, stride);
    uint count = min(min(compact_hir_count[0u], gParams.n_hir_nodes), hir_rows);
    if (row >= count || compact_hir_core[row].kind != 3u) return;
    uint token_rows;
    token_words.GetDimensions(token_rows, stride);
    uint token = compact_hir_core[row].token_start;
    if (token >= min(min(token_count[0u], gParams.n_tokens), token_rows)) return;
    uint byte = token_words[token].start;
    uint low = 0u;
    uint high = entries;
    while (low < high)
    {
        uint middle = (low + high) / 2u;
        if (body_entry_copy_byte(middle) < byte) low = middle + 1u;
        else high = middle;
    }
    if (low >= entries || body_entry_copy_byte(low) != byte) return;
    // Copies follow every template row. A copy that resolves inside the
    // template means the instance unit is not template + suffix.
    if (row < body_copy_first_row())
    { record_min_token_error(status, token, 6u, 0x474e0009u); return; }
    uint header = low == 0u ? 0u : body_extra_entry_row(low);
    body_specialization_inputs[header].y = 0x80000000u | row;
}
