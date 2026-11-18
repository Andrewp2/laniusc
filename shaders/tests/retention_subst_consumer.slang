// Test consumer for retained substitution (tests/retained_substitution.rs):
// applies the publication check of retained_substitution_results.slang.
// fx_config: (run, request). fx_out: (publication current, row current,
// row status, row result).
import type_checker.retention.retention_store;
import type_checker.retention.substitution.retained_substitution_results;

RWStructuredBuffer<uint> fx_config;
RWStructuredBuffer<uint> fx_out;

[shader("compute")]
[numthreads(64, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    uint run = fx_config[0u];
    uint request = fx_config[1u];
    fx_out[0u] = sb_publication_current(run) ? 1u : 0u;
    bool row = sb_result_current(run, request);
    fx_out[1u] = row ? 1u : 0u;
    uint4 r0 = sb_results[request * SB_RESULT_WORDS];
    fx_out[2u] = r0.y;
    fx_out[3u] = row ? r0.x : RT_UNKNOWN;
}
