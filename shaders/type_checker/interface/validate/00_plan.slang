import type_checker.interface.validate.common;

// One thread. Checks the artifact's framing (magic, version, reserved
// header words and the exact length the counts require), records the
// section layout, lays out the scratch tables and writes every later
// kernel's indirect dispatch arguments. An export that already failed, or a
// malformed frame, dispatches no record kernel.

struct Params
{
    uint version;
    uint scratch_capacity;
    uint word_capacity;
    uint check_export_status;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> validate_export_status;
// Three words per record kernel, in dispatch order. Only this kernel binds
// it, so the record kernels can read it as their indirect arguments.
RWStructuredBuffer<uint> validate_dispatch_args;

static const uint HEADER_WORDS = 18u;

// A section's count in the header: modules, segments, declarations, types,
// edges, members and name bytes, the unit id, then predicates, predicate
// arguments, implementations, implementation arguments and method bindings.
uint header_count(uint section)
{
    if (section == S_NAME)
        return validate_artifact_words[10u];
    return validate_artifact_words[section < S_PRED ? 4u + section : 6u + section];
}
static const uint MAX_WORKGROUPS = 65535u;

void write_args(uint kernel, uint threads, uint group)
{
    uint at = 3u * kernel;
    validate_dispatch_args[at] = (threads + group - 1u) / group;
    validate_dispatch_args[at + 1u] = 1u;
    validate_dispatch_args[at + 2u] = 1u;
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    validate_state[STATE_KEY] = INVALID;
    validate_state[STATE_FRAMED] = 0u;
    for (uint kernel = 0u; kernel < ARGS_COUNT; ++kernel)
        write_args(kernel, 0u, 1u);
    if (gParams.check_export_status != 0u && validate_export_status[0u] != 0u)
        return;
    uint byte_len = validate_artifact_length[0u];
    uint words = (byte_len + 3u) / 4u;
    if (byte_len < HEADER_WORDS * 4u || words > gParams.word_capacity)
    {
        fail(PH_HEADER, 0u, 1u);
        return;
    }
    validate_state[STATE_WORDS] = words;
    // "LNSIFACE", zero reserved words, then the version.
    if (validate_artifact_words[0u] != 0x49534e4cu || validate_artifact_words[1u] != 0x45434146u ||
        validate_artifact_words[17u] != 0u)
    {
        fail(PH_HEADER, 0u, 1u);
        return;
    }
    if (validate_artifact_words[2u] != gParams.version)
    {
        fail(PH_HEADER, 0u, 5u);
        return;
    }
    for (uint section = 0u; section < 12u; ++section)
        validate_state[STATE_COUNTS + section] = header_count(section);
    // Each section must fit in the words left before the end, so no sum
    // wraps; the name bytes then fill the rest exactly.
    uint available = byte_len / 4u;
    uint cursor = HEADER_WORDS;
    for (uint section = 0u; section < 11u; ++section)
    {
        validate_state[STATE_STARTS + section] = cursor;
        if (count_of(section) > (available - cursor) / WIDTHS[section])
        {
            fail(PH_HEADER, 0u, 1u);
            return;
        }
        cursor += count_of(section) * WIDTHS[section];
    }
    if (byte_len - cursor * 4u != count_of(S_NAME))
    {
        fail(PH_HEADER, 0u, 1u);
        return;
    }
    validate_state[STATE_STARTS + S_NAME] = cursor * 4u;
    validate_state[STATE_LIBRARY] = validate_artifact_words[3u];
    validate_state[STATE_UNIT] = validate_artifact_words[11u];
    if (count_of(S_DECL) >= OWNER_TAG)
    {
        fail(PH_HEADER, 0u, 2u);
        return;
    }
    if (count_of(S_IMPL) >= OWNER_TAG)
    {
        fail(PH_HEADER, 0u, 3u);
        return;
    }
    // Scratch: argument and binding owners, then the method symbol table
    // (a power of two at least twice the member count).
    uint capacity = 1u;
    while (capacity < 2u * count_of(S_MEMBER) + 2u)
        capacity <<= 1u;
    uint parg_owners = 0u;
    uint iarg_owners = parg_owners + count_of(S_PARG);
    uint bind_owners = iarg_owners + count_of(S_IARG);
    uint symbols = bind_owners + count_of(S_BIND);
    uint impl_predicates = symbols + 2u * capacity;
    uint member_predicates = impl_predicates + 4u * count_of(S_IMPL);
    uint member_results = member_predicates + count_of(S_MEMBER);
    uint binding_results = member_results + 2u * count_of(S_MEMBER);
    uint scratch = binding_results + count_of(S_BIND);
    if (scratch > gParams.scratch_capacity)
    {
        fail(PH_HEADER, 0u, 4u);
        return;
    }
    validate_state[STATE_PARG_OWNERS] = parg_owners;
    validate_state[STATE_IARG_OWNERS] = iarg_owners;
    validate_state[STATE_BIND_OWNERS] = bind_owners;
    validate_state[STATE_SYMBOLS] = symbols;
    validate_state[STATE_IMPL_PREDICATES] = impl_predicates;
    validate_state[STATE_MEMBER_PREDICATES] = member_predicates;
    validate_state[STATE_MEMBER_RESULTS] = member_results;
    validate_state[STATE_BINDING_RESULTS] = binding_results;
    validate_state[STATE_SCRATCH_WORDS] = scratch;
    validate_state[STATE_SYMBOL_CAPACITY] = capacity;

    uint records = max(max(max(count_of(S_MODULE), count_of(S_SEGMENT)), max(count_of(S_DECL), count_of(S_IMPL))),
        max(max(count_of(S_BIND), count_of(S_TYPE)), count_of(S_MEMBER)));
    uint scopes = max(max(count_of(S_TYPE), count_of(S_DECL)), count_of(S_MEMBER));
    uint owners = max(max(count_of(S_PRED), count_of(S_IMPL)), count_of(S_MEMBER));
    uint predicates = max(max(max(count_of(S_PRED), count_of(S_DECL)), count_of(S_PARG)),
        max(count_of(S_IARG), count_of(S_BIND)));
    uint implementations = max(count_of(S_IMPL), 1u);
    uint implementation_rows = max(count_of(S_MEMBER), count_of(S_BIND));
    if (max(max(scratch, records), owners) > MAX_WORKGROUPS * WG ||
        max(max(scopes, implementation_rows), max(implementations, predicates)) > MAX_WORKGROUPS * WALK_WG)
    {
        fail(PH_HEADER, 0u, 4u);
        return;
    }
    validate_state[STATE_FRAMED] = 1u;
    write_args(ARGS_CLEAR, scratch, WG);
    write_args(ARGS_OWNERS, owners, WG);
    write_args(ARGS_RECORDS, records, WG);
    write_args(ARGS_SCOPES, scopes, WALK_WG);
    write_args(ARGS_IMPLEMENTATION_ROWS, implementation_rows, WALK_WG);
    write_args(ARGS_IMPLEMENTATIONS, implementations, WALK_WG);
    write_args(ARGS_PREDICATES, predicates, WALK_WG);
}
