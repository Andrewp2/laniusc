// Per-node dependency records shared by GPU dependency discovery and liveness.
// The declaration-order layout is nine uint words; lowering_ir.rs allocates it.

static const uint VARIABLE_NONE = 0u;
static const uint VARIABLE_CALL_ARGUMENTS = 1u;
static const uint VARIABLE_AGGREGATE_ELEMENTS = 2u;

// The values one live node reads: up to three operands, then the rows of its
// call arguments or aggregate elements.
struct X86LivenessDependencies
{
    uint position;
    uint function_id;
    uint fixed0;
    uint fixed1;
    uint fixed2;
    uint fixed_count;
    uint variable_kind;
    uint variable_start;
    uint variable_count;
};

