# Generic owned sets: compiler dependency

Generic owned `HashSet<T>` and `TreeSet<T>` are not available in the production
standard library. On 2026-10-23, compiler HEAD
`8cb1af7b65f098ef3f394e66f1891cf01d30dc22` still rejects a small generic set
owner containing either existing map.

Both minimized programs call insertion through a borrowed `Set<i16>` receiver
whose field is `HashMap<T, Unit>` or `TreeMap<T, Unit>`. Both fail with LNC0047:
“a replay argument has no complete GPU native layout; its defining nominal
payloads or a retained checked width witness are required.” The diagnostic
points at `alloc::allocator` line 3. Direct `HashMap<i16, Unit>` and
`TreeMap<i16, Unit>` programs compile and execute successfully, including
insertion, membership, and destruction.

The [minimized repros and controls](../tests/fixtures/stdlib_compiler_state/owned_sets/README.md)
include exact diagnostics, source and compiler hashes, and bounded reproduction
commands. `tests/stdlib_owned_sets_execution.rs` runs the successful map
controls. Its name identifies the dependency work; it does not claim an
executable owned set API.

The older [hash set prototype](../tests/fixtures/stdlib_foundation/hash_set_dependency/README.md)
remains outside the production stdlib. Its full algebra and allocation fixtures
are unverified. A prior boolean payload experiment failed at `441e66f9`; the
current minimal revalidation uses `Unit` and makes no current claim about that
boolean experiment.

The blocked deliverable is a generic set wrapper over each existing map.
Insertion must distinguish a newly stored value, an equivalent existing value,
and allocation failure while making ownership of every supplied or returned key
explicit. Removal, take, and ordered pops must report absence and return any
removed owner. The remaining required surface includes borrowed lookup,
iteration, ordered endpoints, bounds, ranges and cursors, reserve and clone,
subset and disjointness queries, and union, intersection, difference and
symmetric difference.

All allocating set operations need native tests for atomic failure, aliasing,
and cleanup. Keys must obey the map's equality and hashing or ordering laws.
Those set contracts have not been validated while the minimal wrapper cannot
execute. Existing map execution establishes a successful control only. The next
admission step is to rerun the wrappers after compiler support changes, then
build and verify the full set APIs over the maps.
