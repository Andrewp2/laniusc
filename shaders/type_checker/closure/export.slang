// Export of the instance closure (instance_closure.slang): one lane per
// instance writes each argument of its tagged environment as a checked
// operand (ct_realize) and copies its smallest template call. An argument
// whose row another lane is writing leaves the instance pending for the
// next dispatch (04_export); the final dispatch (04a_export_final) marks
// it failed instead. Included by both entry files.
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_subst;
import type_checker.substitution.ct_rows;
import type_checker.substitution.ct_realize;
import type_checker.closure.instance_closure;

static const uint EXPORT_PENDING = 0u;
static const uint EXPORT_DONE = 1u;
static const uint EXPORT_FAILED = 2u;

void export_instance(uint index, bool final_dispatch)
{
    if (index >= min(instance_closure_counts[IC_COUNT_LENGTH], ic_instance_capacity())) return;
    uint4 extra = instance_closure_instances[2u * index + 1u];
    if (extra.z != EXPORT_PENDING) return;
    uint4 instance = instance_closure_instances[2u * index];
    uint status = extra.x == 0xffffffffu ? EXPORT_FAILED : EXPORT_DONE;
    uint arity = ct_arity(instance.x);
    for (uint arg = 0u; arg < arity && status == EXPORT_DONE; arg++)
    {
        uint failure;
        uint2 operand = ct_realize(ct_arg(instance.x, arg), failure);
        if (failure == CT_REALIZE_BUSY && !final_dispatch) status = EXPORT_PENDING;
        else if (failure != 0u) status = EXPORT_FAILED;
        else instance_closure_refs[extra.x + arg] = uint2(operand.x & ~CT_ROW_CONSTANT_TAG, operand.y);
    }
    if (status == EXPORT_PENDING) return;
    instance_closure_instances[2u * index + 1u] =
        uint4(extra.x, ~instance_closure_set[instance.w].y, status, extra.w);
}
