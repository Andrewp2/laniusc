// Build one-workgroup-per-function indirect dispatch arguments.

StructuredBuffer<uint> body_plan;
RWStructuredBuffer<uint> module_type_dispatch_args;

static const uint BODY_PLAN_FUNCTION_COUNT = 31u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    uint count = body_plan[BODY_PLAN_FUNCTION_COUNT];
    uint x = min(max(count, 1u), MAX_GROUPS_X);
    uint y = max(1u, (count + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    module_type_dispatch_args[0u] = x;
    module_type_dispatch_args[1u] = y;
    module_type_dispatch_args[2u] = 1u;
}
