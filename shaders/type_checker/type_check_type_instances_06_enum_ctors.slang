// Retired legacy enum-constructor validator.
//
// The resident compiler validates enum constructor calls through
// type_check_modules_10l_consume_value_enum_calls.slang, which consumes
// parser-owned HIR call/variant records plus resolver/type-reference tables.
// Keeping the old token-neighborhood implementation alive would preserve the
// wrong architecture and reintroduce long token scans into semantic analysis.

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
}
