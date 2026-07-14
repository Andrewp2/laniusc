// Count generic type and const parameters with one lane per canonical member.

import atomics;
import gpu_index;

struct Params
{
    uint type_count;
    uint declaration_count;
    uint member_count;
    uint path_capacity;
    uint token_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> dependency_member_words;
RWStructuredBuffer<uint> declaration_generic_arity;

static const uint MEMBER_WORDS = 10u;
static const uint MEMBER_GENERIC_TYPE_PARAMETER = 2u;
static const uint MEMBER_GENERIC_CONST_PARAMETER = 3u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint member_i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (member_i >= gParams.member_count)
        return;
    uint base = member_i * MEMBER_WORDS;
    uint kind = dependency_member_words[base + 1u];
    if (kind != MEMBER_GENERIC_TYPE_PARAMETER && kind != MEMBER_GENERIC_CONST_PARAMETER)
        return;
    uint owner = dependency_member_words[base];
    if (owner < gParams.declaration_count)
        atomic_u32_add(declaration_generic_arity, owner, 1u);
}
