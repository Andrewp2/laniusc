// Shared contract for GPU symbol finalization of retained x86 objects.
//
// An original object names each deferred generic call by a provisional
// identity (RESERVED_LIB, NS_USE, build-global use ordinal). Discovery publishes
// a dense route table from use ordinal to an admitted final native identity:
// (RESERVED_LIB, NS_INSTANCE, deterministic instance rank) or an ordinary
// DeclNative identity. These kernels rewrite only the symbol and identity
// sections, recompute the rewritten identity hashes and publish the result only
// when every input is valid. Text, rodata and relocations never pass through
// this stage. Rust constants: codegen/x86/symbol_finalization.rs.

__exported import codegen.x86.symbol_finalization.read_retained_symbol_identities;

struct FinalizeParams
{
    uint object_count;
    uint symbol_count;
    uint identity_word_count;
    uint route_capacity;
    uint generation;
    uint symbol_capacity;
    uint identity_word_capacity;
    uint reserved;
};

ConstantBuffer<FinalizeParams> gFinalize;

static const uint INVALID = 0xffffffffu;


// Upstream readiness record (generation, flags, instance count, use count).
static const uint READY_ROUTES_PUBLISHED = 1u;
// Set by the GPU caller/target ABI comparison. This stage only consumes it.
static const uint READY_ABI_CERTIFIED = 2u;

// Status words. A failure code keeps the minimum detail recorded for it, so
// the reported failure does not depend on lane order.
static const uint STATUS_PUBLISHED = 0u;
static const uint STATUS_SYMBOL_DEMAND = 1u;
static const uint STATUS_IDENTITY_DEMAND = 2u;
static const uint STATUS_FAILURE_BASE = 4u;
static const uint STATUS_WORDS = 16u;

static const uint FAIL_READINESS = 0u;
static const uint FAIL_OBJECT_MALFORMED = 1u;
static const uint FAIL_SYMBOL_MALFORMED = 2u;
static const uint FAIL_ROUTE_MISSING = 3u;
static const uint FAIL_ROUTE_USE_CHAIN = 4u;
static const uint FAIL_ROUTE_OUT_OF_RANGE = 5u;
static const uint FAIL_ROUTE_INVALID_IDENTITY = 6u;
static const uint FAIL_USE_OUT_OF_RANGE = 7u;
static const uint FAIL_PROVISIONAL_DEFINITION = 8u;
static const uint FAIL_IDENTITY_OVERLAP = 9u;
static const uint FAIL_CODE_COUNT = 10u;

static const uint READINESS_GENERATION = 0u;
static const uint READINESS_ROUTES_UNPUBLISHED = 1u;
static const uint READINESS_ABI_UNCERTIFIED = 2u;
static const uint READINESS_ROUTE_TABLE_SHORT = 3u;

uint failure_slot(uint code)
{
    return STATUS_FAILURE_BASE + code;
}
