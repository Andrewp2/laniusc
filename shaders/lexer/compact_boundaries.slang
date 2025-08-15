// shaders/lexer/compact_boundaries.slang
// Compact boundaries and write per-token data.
// This file provides two entry points:
//   - compact_boundaries_all   : uses ANY-end predicate (emit || eof)
//   - compact_boundaries_kept  : uses KEPT-end predicate ((emit&keep_emit)||(eof&keep_eof))

import utils;

struct LexParams
{
    uint n;
    uint m;
    uint identity_id;
};
ConstantBuffer<LexParams> gParams;

// Inputs
StructuredBuffer<uint> s_final;       // inclusive sums of CURRENT stream (all or kept)
StructuredBuffer<uint> s_final_all;   // inclusive sums of ALL boundaries
StructuredBuffer<uint> flags_packed;  // per-i packed flags (EMIT/EOF/KEEP_EMIT/KEEP_EOF)
StructuredBuffer<uint> tok_types;     // PACKED kinds per i for KEPT stream (EMIT|EOF)
StructuredBuffer<uint> end_excl_by_i; // exclusive end for single-kept boundary at i

// Outputs
RWStructuredBuffer<uint> end_positions;     // compacted exclusive ends (CURRENT stream)
RWStructuredBuffer<uint> types_compact;     // compacted kinds         (CURRENT stream)
RWStructuredBuffer<uint> all_index_compact; // for each *kept* token: 1-based index in ALL stream
RWStructuredBuffer<uint> token_count;       // [0] = total compacted (CURRENT)

// -------- shared implementation (predicate parameterized) --------
inline void compact_impl(bool use_kept_pred, uint3 tid)
{
    uint i = tid.x;
    if (i >= gParams.n)
        return;

    uint pref = s_final[i];

    if (i + 1u == gParams.n)
    {
        token_count[0] = pref;
    }

    uint f = flags_packed[i];
    uint selected = use_kept_pred ? kept_any_from_flags(f) : any_end_from_flags(f);
    if (selected == 0u)
        return;

    uint prev = (i == 0u) ? 0u : s_final[i - 1u];
    uint delta = pref - prev;

    uint all_idx_1based = s_final_all[i];

    uint emit_kind16 = (tok_types[i]) & 0xFFFFu;
    uint eof_kind16 = (tok_types[i] >> 16) & 0xFFFFu;

    if (delta == 2u)
    {
        uint k0 = pref - 2u;
        end_positions[k0] = i;

        // ▼ Only KEPT stream writes kinds / ALL-index bookkeeping
        if (use_kept_pred)
        {
            uint kind0 = (emit_kind16 != 0xFFFFu) ? emit_kind16 : eof_kind16;
            types_compact[k0] = kind0;
            all_index_compact[k0] = all_idx_1based - 1u;
        }

        uint k1 = pref - 1u;
        end_positions[k1] = gParams.n;

        if (use_kept_pred)
        {
            uint kind1 = (eof_kind16 != 0xFFFFu) ? eof_kind16 : emit_kind16;
            types_compact[k1] = kind1;
            all_index_compact[k1] = all_idx_1based;
        }
        return;
    }

    uint k = pref - 1u;

    uint end_excl = end_excl_by_i[i];
    end_positions[k] = end_excl;

    uint is_last = (i + 1u == gParams.n) ? 1u : 0u;

    // ▼ Only KEPT stream needs token kinds
    if (use_kept_pred)
    {
        uint kind = 0u;
        if (is_last != 0u)
        {
            kind = (eof_kind16 != 0xFFFFu) ? eof_kind16 : emit_kind16;
        }
        else
        {
            kind = (emit_kind16 != 0xFFFFu) ? emit_kind16 : eof_kind16;
        }
        types_compact[k] = kind;

        uint prev_all = (i == 0u) ? 0u : s_final_all[i - 1u];
        uint delta_all = all_idx_1based - prev_all;

        uint all_idx_for_kept = all_idx_1based;
        if (is_last != 0u && delta_all == 2u)
        {
            all_idx_for_kept = (end_excl == i) ? (all_idx_1based - 1u) : all_idx_1based;
        }
        all_index_compact[k] = all_idx_for_kept;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void compact_boundaries_all(uint3 tid: SV_DispatchThreadID)
{
    compact_impl(false, tid);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void compact_boundaries_kept(uint3 tid: SV_DispatchThreadID)
{
    compact_impl(true, tid);
}
