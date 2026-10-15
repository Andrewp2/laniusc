// Call environments as canonical IDs. call_env_ct[token] holds the CT_ENV
// records of the call whose callee is spelled at `token`: x the value
// environment (03e: explicit, argument claims, then result context), y the
// expected environment (03k: explicit, result context, then claims ranked by
// literal context). 03_publish_call_envs republishes them whenever their
// bindings change; CT_NONE until the first publication.
import type_checker.canonical.canonical_api;

public globallycoherent RWStructuredBuffer<uint2> call_env_ct;

public uint2 ct_call_env(uint token)
{
    uint count; uint stride;
    call_env_ct.GetDimensions(count, stride);
    return token < count ? call_env_ct[token] : uint2(CT_NONE, CT_NONE);
}
