// Readers of the in-place instantiations (04b_select_inplace.slang).
//
// A generic function with exactly one instance in its unit needs no copy:
// the body-specialization passes of the same job bind its parameters to
// that instance's arguments, and its body is lowered under the
// declaration's own identity. `instance_inplace_owner` holds, per function
// HIR row, the selected instance's index plus one; INPLACE_BLOCKED marks a
// function that is not instantiated in place and INPLACE_FAILED one whose
// bound body did not close (it stays a template for the replays).
//
// Both tables are valid only in a job that recorded the instance closure.
// A replay job never reads them: its packet is not empty.
#ifndef LANIUS_INPLACE_READ
#define LANIUS_INPLACE_READ

#ifdef LANIUS_INPLACE_WRITE_OWNER
RWStructuredBuffer<uint> instance_inplace_owner;
#else
StructuredBuffer<uint> instance_inplace_owner;
#endif
StructuredBuffer<uint> instance_inplace_counts;

static const uint INPLACE_BLOCKED = 0x80000000u;
static const uint INPLACE_FAILED = 0x40000000u;
static const uint INPLACE_NONE = 0xffffffffu;

// Whether this job selected any in-place instantiation.
bool inplace_job()
{
    return instance_inplace_counts[0u] != 0u;
}

// The instance bound in place to function row `owner`, or INPLACE_NONE.
uint inplace_instance(uint owner)
{
    uint rows; uint stride;
    instance_inplace_owner.GetDimensions(rows, stride);
    if (owner >= rows) return INPLACE_NONE;
    uint word = instance_inplace_owner[owner];
    return word == 0u || (word & (INPLACE_BLOCKED | INPLACE_FAILED)) != 0u ? INPLACE_NONE : word - 1u;
}

#ifdef LANIUS_INPLACE_ARGUMENTS
StructuredBuffer<uint4> instance_closure_instances;
StructuredBuffer<uint2> instance_closure_refs;

// The checked operand of argument `slot` of `owner`'s in-place instance:
// a type slot, or a constant slot (kind, payload) after the type slots.
bool inplace_argument(uint owner, uint slot, bool constant, out uint2 operand)
{
    operand = uint2(0u, INPLACE_NONE);
    uint instance = inplace_instance(owner);
    if (instance == INPLACE_NONE) return false;
    uint rows; uint stride;
    instance_closure_instances.GetDimensions(rows, stride);
    if (instance >= rows / 2u) return false;
    uint4 extra = instance_closure_instances[2u * instance + 1u];
    uint types = extra.w >> 16u;
    uint arity = extra.w & 0xffffu;
    if (types > arity || slot >= (constant ? arity - types : types)) return false;
    uint index = constant ? types + slot : slot;
    instance_closure_refs.GetDimensions(rows, stride);
    if (extra.x >= rows || index >= rows - extra.x) return false;
    operand = instance_closure_refs[extra.x + index];
    return operand.x != 0u;
}
#endif

#endif
