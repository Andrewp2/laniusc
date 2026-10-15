import type_checker.concrete_type_equality;
// Index complete type structure under a declaration's parameter environment.
// Hashes choose a bucket only; callers must still compare complete references.
import type_checker.scoped_type_equality;

public uint scoped_type_hash_mix(uint hash, uint value)
{
    hash = (hash ^ value) * 16777619u;
    return hash ^ (hash >> 16u);
}

// Local frame storage. The scratch expansion is scoped_type_ref_hash_scratch.
#define SCOPED_TYPE_HASH_WALK scoped_type_ref_hash
#define SCOPED_TYPE_HASH_FRAMES uint3 refs[DEPTH_LIMIT]; uint next[DEPTH_LIMIT]; uint counts[DEPTH_LIMIT];
#define SH_REF(d) refs[d]
#define SH_PUSH(d, r) refs[d] = r; next[d] = INVALID
#define SH_CLASSIFIED(d, r) refs[d] = r; next[d] = 0u; counts[d] = 0u
#define SH_NEXT(d) next[d]
#define SH_SET_NEXT(d, v) next[d] = v
#define SH_COUNT(d) counts[d]
#define SH_SET_COUNT(d, v) counts[d] = v
#include "scoped_type_hash_walk.slang"
#undef SCOPED_TYPE_HASH_WALK
#undef SCOPED_TYPE_HASH_FRAMES
#undef SH_REF
#undef SH_PUSH
#undef SH_CLASSIFIED
#undef SH_NEXT
#undef SH_SET_NEXT
#undef SH_COUNT
#undef SH_SET_COUNT
