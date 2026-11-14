//! Program retention (docs/compiler-program-retention.md): two frontend jobs
//! export into one build store, frontend storage is released and exporter
//! scratch is poisoned, and a GPU probe resolves foreign generic definitions
//! from the store alone.

use std::sync::Arc;

use laniusc_compiler::{
    compiler::{GpuCompiler, GpuCompilerBackends},
    type_checker::program_retention::{
        PROBE_WORDS,
        ProgramRetention,
        ProgramRetentionCapacity,
        counts,
    },
};

#[allow(unused_imports)]
use crate::common;

// Job A, library 10. `pad` makes `identity` start at the same token as job
// B's own `identity` (after B's import), so both jobs' private callables
// and their parameter `U` collide on every local token ordinal. `solo` is a
// private generic called only at i32 from a nongeneric function: without a
// store attached the job instantiates it in place.
const LIBRARY: &str = r#"module lib::a;
fn pad() {}
fn identity<U>(value: U) -> U { return value; }
fn solo<V>(value: V) -> V { let kept: V = value; return kept; }
pub fn seed() -> i32 { return solo(5); }
const LIMIT: i32 = 4;
const OFF: bool = false;
const WIDE: i64 = -4294967297;
fn tick(first: ptr, second: ptr, third: ptr) {}
struct Hidden<T> { inner: T }
pub struct Cell<T> { value: T }
pub enum Slot<T> { Empty, Full(T) }
pub fn wrap<T>(value: T) -> Cell<T> {
    let hidden: Hidden<T> = Hidden { inner: value };
    let result = identity(hidden.inner);
    pad();
    return Cell { value: result };
}
pub fn unwrap<T>(cell: Cell<T>) -> T {
    let entry: ptr = tick;
    let bound: i32 = LIMIT;
    return cell.value;
}
pub fn fill<T>(value: T) -> Slot<T> {
    let empty: Slot<T> = Empty;
    return Full(value);
}
pub fn total<const N: usize>(values: [i32; N]) -> i32 {
    let sum: i32 = 0;
    for value in values { sum = sum + value; }
    return sum;
}
pub impl<T> Cell<T> {
    pub fn shadow<T>(&self, value: T) -> T {
        let inherited: T = value;
        let outer = identity(self.value);
        let value: T = inherited;
        return value;
    }
}
"#;

// Job B, library 11. `PairA` and `PairB` have equal widths and different
// field layouts.
const APP: &str = r#"module app::b;
import lib::a;
fn identity<U>(value: U) -> U { return value; }
fn twice<T>(value: T) -> Cell<T> { return wrap(value); }
struct Local<T> { item: T }
struct PairA { left: i32, right: u32 }
struct PairB { left: u32, right: i32 }
fn main() -> i32 {
    let first = wrap(7);
    let second = wrap(Local { item: true });
    let third = wrap(1);
    let flag = first.shadow(false);
    let same = identity(3);
    let a = unwrap(wrap(PairA { left: 1, right: 2 }));
    let b = unwrap(wrap(PairB { left: 3, right: 4 }));
    let slot = fill(9);
    let sum = total([1, 2, 3]);
    let forwarded = twice(1);
    return 0;
}
"#;

const NS_CALLABLE: u32 = 1;
const PROBE_ELIGIBLE: usize = 0;
const PROBE_CALLEE: usize = 1;
const PROBE_RESULT: usize = 2;
const PROBE_EXPECTED: usize = 3;
const PROBE_RESULT_STATUS: usize = 4;
const PROBE_ROWS: usize = 5;
const PROBE_TYPED: usize = 6;
const PROBE_FAILED: usize = 7;
const PROBE_FIRST_FAILURE: usize = 8;
const PROBE_BAD_REFS: usize = 9;
const PROBE_USES: usize = 10;
const PROBE_USES_CLOSED: usize = 11;
const PROBE_HASH: usize = 12;
const PROBE_PARAMS_CLOSED: usize = 14;
const PROBE_NESTED_CALLEE: usize = 15;
const PROBE_DIR_FLAGS: usize = 16;
const PROBE_EXPECTED_CLOSED: usize = 17;
const PROBE_PARAM_COUNT: usize = 18;
const PROBE_REJECTION_CHECKS: usize = 19;
const PROBE_MISSING: usize = 20;
const PROBE_BINDINGS: usize = 21;
const PROBE_BINDINGS_BAD: usize = 22;
const PROBE_MEMBERS: usize = 23;
const PROBE_MEMBERS_BAD: usize = 24;
const PROBE_CONSTS: usize = 25;
const PROBE_CONSTS_BAD: usize = 26;
const PROBE_ANNOTATIONS: usize = 27;
const PROBE_TOKENS: usize = 28;
const PROBE_TOKENS_BAD: usize = 29;
const PROBE_TEXT_HASH: usize = 30;
const PROBE_SYMBOLIC: usize = 31;
const PROBE_ARG_ROWS: usize = 32;
const PROBE_FN_REFS: usize = 33;
const PROBE_RECORDS: usize = 34;
const PROBE_VARIANTS: usize = 35;
const PROBE_ITERABLES: usize = 37;
const PROBE_TEXT_BYTES: usize = 38;

// Scalar TermIds are the scalar codes (primitive_types.slang).
const TERM_BOOL: u32 = 2;
const TERM_I32: u32 = 3;

/// Every check of one instance passed.
fn assert_complete_instance(lane: &[u32]) {
    assert_eq!(lane[PROBE_REJECTION_CHECKS], 31, "sentinel and owner checks: {lane:?}");
    assert_eq!(lane[PROBE_RESULT_STATUS], 0, "{lane:?}");
    assert_eq!(lane[PROBE_FAILED], 0, "{lane:?}");
    assert_eq!(lane[PROBE_BAD_REFS], 0, "{lane:?}");
    assert_eq!(lane[PROBE_MISSING], 0, "{lane:?}");
    assert_eq!(lane[PROBE_BINDINGS_BAD], 0, "{lane:?}");
    assert_eq!(lane[PROBE_MEMBERS_BAD], 0, "{lane:?}");
    assert_eq!(lane[PROBE_CONSTS_BAD], 0, "{lane:?}");
    assert_eq!(lane[PROBE_TOKENS_BAD], 0, "{lane:?}");
    assert!(lane[PROBE_TOKENS] > 0 && lane[PROBE_ANNOTATIONS] > 0, "{lane:?}");
    assert_eq!(lane[PROBE_USES], lane[PROBE_USES_CLOSED], "{lane:?}");
}

fn compiler() -> GpuCompiler<'static> {
    pollster::block_on(GpuCompiler::new_with_backends(GpuCompilerBackends::frontend_only()))
        .expect("frontend compiler")
}

/// Runs both jobs of one build into `store`.
fn build(compiler: &GpuCompiler<'static>, store: &Arc<ProgramRetention>) {
    store.begin_build().expect("begin build");
    compiler.attach_program_retention(Some(store.clone()));
    let library = pollster::block_on(compiler.semantic_interface_for_source_pack(10, &[LIBRARY]))
        .expect("library job");
    pollster::block_on(compiler.semantic_interface_for_source_pack_with_dependencies(
        11,
        &[APP],
        &[library],
    ))
    .expect("application job");
    compiler.attach_program_retention(None);
}

fn decl_keys(store: &ProgramRetention, count: usize) -> Vec<[u32; 4]> {
    let words = store.read_store_words("rt_decl_key", count * 4).unwrap();
    words.chunks_exact(4).map(|k| [k[0], k[1], k[2], k[3]]).collect()
}

struct Probe {
    uses: Vec<Vec<u32>>,
}

impl Probe {
    fn eligible(&self) -> impl Iterator<Item = &Vec<u32>> {
        self.uses.iter().filter(|u| u[PROBE_ELIGIBLE] == 1)
    }
}

fn probe(store: &ProgramRetention) -> Probe {
    probe_with(store, &[])
}

fn probe_with(store: &ProgramRetention, requests: &[[u32; 4]]) -> Probe {
    let words = store.resolve_probe(requests).expect("resolve probe");
    Probe { uses: words.chunks_exact(PROBE_WORDS).map(<[u32]>::to_vec).collect() }
}

fn summary(store: &ProgramRetention) -> Vec<u32> {
    let status = store.status().unwrap();
    // Arena counters and the build's committed/rollback/conflict words.
    // Spare records (lanes that lost an intern race) are not retained data.
    let mut words = (0..15)
        .map(|a| status[a] - if a < 4 { status[counts::SPARE + a] } else { 0 })
        .collect::<Vec<_>>();
    words.extend([status[counts::JOBS], status[counts::CONFLICTS], status[counts::INVARIANT_TOTAL],
        status[counts::INCOMPLETE_TOTAL], status[counts::READY]]);
    words
}

#[test]
fn program_retention_resolves_foreign_generic_bodies_from_the_store_alone() {
    let compiler = compiler();
    let store = ProgramRetention::new(ProgramRetentionCapacity::default()).unwrap();
    build(&compiler, &store);
    let status = store.status().unwrap();
    let reports = store.job_reports();
    eprintln!("program retention status: {:?}", &status[..16]);
    eprintln!("program retention reports: {reports:?}");
    assert_eq!(status[counts::JOBS], 2, "both jobs commit");
    assert_eq!(status[counts::CONFLICTS], 0);
    assert_eq!(status[counts::INVARIANTS], 0, "first invariant code {}", status[counts::FIRST_INVARIANT]);
    for report in &reports {
        assert!(report.ready, "committed export must also be complete: {report:?}");
        assert_eq!(report.counts[counts::INVARIANTS], 0, "{report:?}");
        assert_eq!(report.counts[counts::INCOMPLETE], 0, "{report:?}");
    }

    // Colliding local identities stay distinct: both private `identity`
    // callables carry the same token-based local word, in two libraries.
    let keys = decl_keys(&store, status[0] as usize);
    let identities = keys
        .iter()
        .enumerate()
        .filter(|(_, k)| k[2] == NS_CALLABLE && k[3] & 0xc000_0000 == 0x4000_0000)
        .map(|(id, k)| (id as u32, *k))
        .collect::<Vec<_>>();
    let a_identity = identities.iter().find(|(_, k)| k[0] == 10).expect("job A identity").0;
    let b_identity = identities.iter().find(|(_, k)| k[0] == 11).expect("job B identity").0;
    assert_ne!(a_identity, b_identity);
    assert_eq!(
        keys[a_identity as usize][3], keys[b_identity as usize][3],
        "the two private callables collide on their local token"
    );

    // Remove the frontend's retained buffers and bind-group caches, then
    // destroy the compiler. The probe must need only the build store, even
    // when the exporter's separate scratch no longer contains its job maps.
    pollster::block_on(compiler.release_resident_job_buffers());
    drop(compiler);
    store.poison_scratch();
    assert_constant_schema(&store);
    let probe = probe(&store);
    let eligible = probe.eligible().collect::<Vec<_>>();
    for use_words in &probe.uses {
        eprintln!("probe use: {use_words:?}");
    }
    assert!(eligible.len() >= 4, "three wrap calls and one shadow call resolve foreign definitions");
    for use_words in &eligible {
        let callee = &keys[use_words[PROBE_CALLEE] as usize];
        assert_eq!(callee[0], 10, "the resolved definition is job A's");
        assert_eq!(use_words[PROBE_DIR_FLAGS], 0, "callee export is complete: {use_words:?}");
        assert_eq!(use_words[PROBE_EXPECTED_CLOSED], 1, "an unresolved result cannot match itself");
        assert_eq!(use_words[PROBE_REJECTION_CHECKS], 31, "sentinel and owner checks: {use_words:?}");
        assert_eq!(use_words[PROBE_RESULT_STATUS], 0, "declared result substitutes: {use_words:?}");
        assert_eq!(
            use_words[PROBE_RESULT], use_words[PROBE_EXPECTED],
            "callee result under the caller's closed environment is the caller's checked type: {use_words:?}"
        );
        assert!(use_words[PROBE_ROWS] > 0, "the callee body segment is retained");
        assert!(use_words[PROBE_TYPED] > 0);
        assert_eq!(use_words[PROBE_FAILED], 0, "body terms substitute closed: {use_words:?}");
        assert_eq!(use_words[PROBE_FIRST_FAILURE], 0);
        assert_eq!(use_words[PROBE_BAD_REFS], 0, "body tree links stay inside the segment");
        assert_eq!(use_words[PROBE_USES], use_words[PROBE_USES_CLOSED], "body call environments close");
        assert_eq!(use_words[PROBE_PARAMS_CLOSED], use_words[PROBE_PARAM_COUNT]);
        // Every foreign body that calls a function calls job A's private
        // `identity`, never job B's same-spelled one.
        assert!(use_words[PROBE_NESTED_CALLEE] == 0 || use_words[PROBE_NESTED_CALLEE] == a_identity,
            "callee identity is job A's private callable: {use_words:?}");
        assert_complete_instance(use_words);
    }

    // Name the bodies by their retained source text, which must be the
    // program's own text with a matching hash and token records.
    let texts = body_texts(&store);
    for (_, text) in &texts {
        assert!(LIBRARY.contains(text.as_str()) || APP.contains(text.as_str()), "retained text is source: {text:?}");
    }
    let named = |prefix: &str| decl_named(&texts, prefix);
    let lanes = |decl: u32| eligible.iter().filter(move |u| u[PROBE_CALLEE] == decl).collect::<Vec<_>>();
    for (decl, text) in &texts {
        for use_words in lanes(*decl) {
            assert_eq!(use_words[PROBE_TEXT_BYTES] as usize, text.len());
            assert_eq!(use_words[PROBE_TEXT_HASH], fnv1a(text));
        }
    }
    let wrap = lanes(named("fn wrap<"));
    assert_eq!(wrap.len(), 5, "three direct calls and the two inside `unwrap`");
    for use_words in &wrap {
        assert_eq!(use_words[PROBE_NESTED_CALLEE], a_identity);
        assert_eq!(use_words[PROBE_RECORDS], 2, "`Hidden {{ .. }}` and `Cell {{ .. }}`: {use_words:?}");
        assert!(use_words[PROBE_MEMBERS] >= 1, "`hidden.inner` checks its field");
        assert!(use_words[PROBE_BINDINGS] >= 3, "locals and parameters keep exact bindings");
    }
    let shadow = lanes(named("fn shadow<"));
    assert_eq!(shadow.len(), 1);
    assert_eq!(shadow[0][PROBE_NESTED_CALLEE], a_identity);
    assert!(shadow[0][PROBE_MEMBERS] >= 1, "`self.value` checks its field under the impl's binding");
    assert_shadow_bindings(&store, named("fn shadow<"));
    let imported_call = probe_with(&store, &[[named("fn twice<"), 1, TERM_I32, 0]]);
    let imported_call = imported_call.uses.last().unwrap();
    assert_eq!(imported_call[PROBE_ELIGIBLE], 1);
    assert_complete_instance(imported_call);
    assert_eq!(imported_call[PROBE_NESTED_CALLEE], named("fn wrap<"),
        "the retained generic body keeps its bare imported call target");
    // `unwrap` at `Cell<PairA>` and `Cell<PairB>`: equal widths, different
    // field layouts, two different instance bodies.
    let unwrap = lanes(named("fn unwrap<"));
    assert_eq!(unwrap.len(), 2);
    for use_words in &unwrap {
        assert!(use_words[PROBE_FN_REFS] >= 1, "`tick` is a function-reference use: {use_words:?}");
        assert!(use_words[PROBE_CONSTS] >= 1, "`LIMIT` keeps its constant value: {use_words:?}");
        assert!(use_words[PROBE_MEMBERS] >= 1, "`cell.value` checks its field");
    }
    assert_ne!(unwrap[0][PROBE_HASH..PROBE_HASH + 2], unwrap[1][PROBE_HASH..PROBE_HASH + 2]);
    let fill = lanes(named("fn fill<"));
    assert_eq!(fill.len(), 1);
    assert_eq!(fill[0][PROBE_VARIANTS], 2, "`Empty` and `Full(value)`: {:?}", fill[0]);
    let total = lanes(named("fn total<"));
    assert_eq!(total.len(), 1);
    assert!(total[0][PROBE_ITERABLES] >= 1, "the for loop keeps its iterable kind");
    assert!(total[0][PROBE_SYMBOLIC] >= 1, "`[i32; N]` stays symbolic in the template");

    // A1: `solo` is called only at i32, in its own job. The retained body is
    // still the template, so it instantiates at bool, which no use names.
    let solo = named("fn solo<");
    let requests = probe_with(&store, &[[solo, 1, TERM_BOOL, 0], [solo, 1, TERM_I32, 0]]);
    let solo_lanes = &requests.uses[requests.uses.len() - 2..];
    for (lane, scalar) in solo_lanes.iter().zip([TERM_BOOL, TERM_I32]) {
        assert_eq!(lane[PROBE_ELIGIBLE], 1, "{lane:?}");
        assert_eq!(lane[PROBE_RESULT], scalar, "{lane:?}");
        assert!(lane[PROBE_SYMBOLIC] >= 3, "the template rows are symbolic: {lane:?}");
        assert!(lane[PROBE_ARG_ROWS] >= 3, "the value, the local and the result take the argument: {lane:?}");
        assert_eq!(lane[PROBE_ARG_ROWS], lane[PROBE_SYMBOLIC], "every symbolic row is the argument: {lane:?}");
        assert_complete_instance(lane);
    }
    assert_ne!(solo_lanes[0][PROBE_HASH..PROBE_HASH + 2], solo_lanes[1][PROBE_HASH..PROBE_HASH + 2]);
    // Two distinct closed environments instantiate `wrap` differently;
    // `wrap(7)` and `wrap(1)` share theirs.
    let mut wrap_hashes = eligible
        .iter()
        .filter(|u| u[PROBE_ROWS] > 0 && u[PROBE_PARAMS_CLOSED] == 1)
        .map(|u| (u[PROBE_CALLEE], u[PROBE_HASH], u[PROBE_HASH + 1]))
        .collect::<Vec<_>>();
    wrap_hashes.sort();
    wrap_hashes.dedup();
    assert!(wrap_hashes.len() >= 2, "two closed environments give two instance bodies: {wrap_hashes:?}");

    let bytes = store.retained_bytes().unwrap();
    eprintln!(
        "program retention bytes: live {:?} (discovery {} B, bodies {} B, tables {} B) of capacity {} B",
        bytes.live,
        bytes.resident_discovery,
        bytes.streamable_bodies,
        bytes.tables,
        bytes.capacity.iter().sum::<u64>(),
    );
}

#[test]
fn program_retention_retries_commits_whole_jobs_and_reuses_allocations() {
    let compiler = compiler();
    let reference = ProgramRetention::new(ProgramRetentionCapacity::default()).unwrap();
    build(&compiler, &reference);
    let expected = summary(&reference);
    let expected_probe = probe(&reference);

    // Tiny capacities: every job overflows, rolls back and is retried.
    let tiny = ProgramRetention::new(ProgramRetentionCapacity::tiny()).unwrap();
    build(&compiler, &tiny);
    let (_, growths) = tiny.capacity();
    let reports = tiny.job_reports();
    assert!(growths >= 1 && reports.iter().any(|r| r.attempts > 1), "{reports:?}");
    let status = tiny.status().unwrap();
    eprintln!(
        "program retention retry: {growths} growths, attempts {:?}, rollbacks {}",
        reports.iter().map(|r| r.attempts).collect::<Vec<_>>(),
        status[counts::ROLLBACKS],
    );
    assert!(status[counts::ROLLBACKS] >= 1);
    assert_eq!(summary(&tiny), expected, "a retried build retains exactly the reference records");
    let tiny_probe = probe(&tiny);
    assert_eq!(tiny_probe.uses.len(), expected_probe.uses.len());
    for (a, b) in tiny_probe.uses.iter().zip(&expected_probe.uses) {
        // TermIds may differ in allocation order; structure may not.
        assert_eq!(a[PROBE_ELIGIBLE], b[PROBE_ELIGIBLE]);
        assert_eq!(a[PROBE_ROWS..PROBE_HASH], b[PROBE_ROWS..PROBE_HASH]);
        assert_eq!(a[PROBE_HASH..PROBE_HASH + 2], b[PROBE_HASH..PROBE_HASH + 2]);
        assert_eq!(a[PROBE_RESULT] == a[PROBE_EXPECTED], b[PROBE_RESULT] == b[PROBE_EXPECTED]);
    }

    // An unrelated build must replace the entire identity namespace, even
    // though its smaller live prefixes leave bytes from the old build behind.
    let (capacity, _) = tiny.capacity();
    tiny.begin_build().unwrap();
    compiler.attach_program_retention(Some(tiny.clone()));
    pollster::block_on(compiler.semantic_interface_for_source_pack(
        99,
        &["module fresh; fn echo<T>(x: T) -> T { return x; } fn main() -> i32 { return echo(42); }"],
    ))
    .expect("unrelated build");
    compiler.attach_program_retention(None);
    let fresh_status = tiny.status().unwrap();
    assert_eq!(fresh_status[counts::JOBS], 1);
    assert_eq!(fresh_status[counts::CONFLICTS], 0);
    assert_eq!(fresh_status[counts::INVARIANTS], 0);
    assert_eq!(fresh_status[counts::READY], 1);
    let fresh_keys = decl_keys(&tiny, fresh_status[0] as usize);
    assert!(fresh_keys.iter().any(|key| key[0] == 99));
    assert!(fresh_keys.iter().filter(|key| key[0] != 0).all(|key| key[0] == 99),
        "only the new build's declarations are live: {fresh_keys:?}");
    let fresh_probe = probe(&tiny);
    assert!(!fresh_probe.uses.is_empty(), "the unrelated build exports its call");
    assert_eq!(fresh_probe.eligible().count(), 0, "old foreign definitions are unreachable");
    assert!(fresh_probe.uses.iter().all(|u| u[PROBE_ELIGIBLE] != 6), "the fresh build is usable");
    let definitions = tiny.read_store_words("rt_decl_def", fresh_status[0] as usize).unwrap();
    for use_words in &fresh_probe.uses {
        let callee = use_words[PROBE_CALLEE] as usize;
        assert_ne!(callee, 0, "fresh call retains its callee");
        assert_eq!(fresh_keys[callee][0], 99, "every callee belongs to the fresh build");
        assert!(definitions[callee] > 0 && definitions[callee] <= fresh_status[4]);
    }
    assert_eq!(tiny.capacity().0, capacity, "the unrelated build needs no growth");

    // Rebuild the original program after the unrelated job. Stable contents
    // with retained allocations must still come from a fresh full export.
    build(&compiler, &tiny);
    assert_eq!(tiny.capacity().0, capacity, "the original rebuild needs no growth");
    assert_eq!(summary(&tiny), expected);

    // One probe chain for every key: equality is decided by full records.
    let collided = ProgramRetention::new(ProgramRetentionCapacity::tiny()).unwrap();
    collided.set_hash_mask(0);
    build(&compiler, &collided);
    assert!(collided.capacity().1 > 0, "forced collisions also exercise growth and rehash");
    assert_eq!(summary(&collided), expected, "forced collisions never merge or split keys");
    let collided_probe = probe(&collided);
    for (a, b) in collided_probe.uses.iter().zip(&expected_probe.uses) {
        assert_eq!(a[PROBE_HASH..PROBE_HASH + 2], b[PROBE_HASH..PROBE_HASH + 2]);
    }

    // A duplicate export is committed for inspection but is never ready.
    // A later clean job must not erase the earlier build-level failure.
    compiler.attach_program_retention(Some(collided.clone()));
    pollster::block_on(compiler.semantic_interface_for_source_pack(10, &[LIBRARY])).unwrap();
    let failed = collided.status().unwrap();
    assert!(failed[counts::CONFLICTS] > 0);
    assert!(failed[counts::INVARIANT_TOTAL] > 0);
    assert!(failed[counts::INCOMPLETE_TOTAL] > 0);
    assert!(!collided.job_reports().last().unwrap().ready);
    let blocked = probe(&collided);
    assert_eq!(blocked.eligible().count(), 0, "conflicting builds cannot supply a probe instance");
    assert!(blocked.uses.iter().any(|u| u[PROBE_ELIGIBLE] == 6));
    for use_words in blocked.uses.iter().filter(|u| u[PROBE_ELIGIBLE] == 6) {
        assert_eq!(use_words[PROBE_RESULT_STATUS], 6, "binding itself rejects the conflicting build");
    }
    pollster::block_on(compiler.semantic_interface_for_source_pack(100, &["module later; fn main() -> i32 { return 0; }"])).unwrap();
    compiler.attach_program_retention(None);
    let later = collided.status().unwrap();
    assert_eq!(later[counts::INVARIANTS], 0, "the latest job itself is clean");
    assert_eq!(later[counts::INVARIANT_TOTAL], failed[counts::INVARIANT_TOTAL]);
    assert_eq!(later[counts::READY], 0, "build readiness cannot recover without begin_build");
    build(&compiler, &collided);
    let recovered = collided.status().unwrap();
    assert_eq!(recovered[counts::READY], 1);
    assert_eq!(recovered[counts::INVARIANT_TOTAL], 0);
    assert_eq!(recovered[counts::INCOMPLETE_TOTAL], 0);
    assert!(collided.job_reports().iter().all(|r| r.ready));

    let bytes = tiny.retained_bytes().unwrap();
    eprintln!(
        "program retention bytes after retry: live {} B of capacity {} B",
        bytes.live.iter().sum::<u64>(),
        bytes.capacity.iter().sum::<u64>(),
    );
}

/// Each retained body's DeclId and source text, read from the store.
fn body_texts(store: &ProgramRetention) -> Vec<(u32, String)> {
    let status = store.status().unwrap();
    let dir = store.read_store_words("rt_dir", status[4] as usize * 16).unwrap();
    let segs = store.read_store_words("rt_segments", status[9] as usize * 24).unwrap();
    let bytes = store.read_store_words("rt_seg_bytes", status[12] as usize).unwrap();
    dir.chunks_exact(16)
        .filter(|e| e[8] != u32::MAX)
        .map(|e| {
            let s = &segs[e[8] as usize * 24..e[8] as usize * 24 + 24];
            let (len, base) = (s[18] as usize, s[20] as usize);
            let text = (0..len).map(|i| (bytes[base + i / 4] >> ((i % 4) * 8)) as u8).collect::<Vec<_>>();
            (e[0], String::from_utf8(text).expect("retained body text is UTF-8"))
        })
        .collect()
}

fn fnv1a(text: &str) -> u32 {
    text.bytes().fold(0x811c_9dc5u32, |h, b| (h ^ b as u32).wrapping_mul(0x0100_0193))
}

fn assert_constant_schema(store: &ProgramRetention) {
    let status = store.status().unwrap();
    let dir = store.read_store_words("rt_dir", status[4] as usize * 16).unwrap();
    let schema = store.read_store_words("rt_schema", status[7] as usize * 4).unwrap();
    let sigs = store.read_store_words("rt_sigs", status[6] as usize).unwrap();
    let mut values = Vec::new();
    for entry in dir.chunks_exact(16).filter(|e| e[1] == 9) {
        assert_eq!(entry[10], 1, "one constant schema row");
        let record = &schema[entry[9] as usize * 4..entry[9] as usize * 4 + 4];
        assert_eq!(record[0], entry[0]);
        assert_eq!(record[1], 4 | (1 << 8), "the initializer must be concrete");
        values.push((sigs[entry[6] as usize], record[2], record[3]));
    }
    values.sort();
    assert_eq!(values, [(TERM_BOOL, 0, 0), (TERM_I32, 4, 0), (9, 0xffff_ffff, 0xffff_fffe)]);
}

fn assert_shadow_bindings(store: &ProgramRetention, decl: u32) {
    let status = store.status().unwrap();
    let dir = store.read_store_words("rt_dir", status[4] as usize * 16).unwrap();
    let entry = dir.chunks_exact(16).find(|e| e[0] == decl).unwrap();
    let binders = store.read_store_words("rt_binders", status[5] as usize).unwrap();
    assert_eq!(entry[5], 2, "impl T then method T");
    let impl_t = 0x8000_0000 | binders[entry[4] as usize];
    let method_t = 0x8000_0000 | binders[entry[4] as usize + 1];
    assert_ne!(impl_t, method_t);
    let segments = store.read_store_words("rt_segments", status[9] as usize * 24).unwrap();
    let segment = &segments[entry[8] as usize * 24..entry[8] as usize * 24 + 24];
    let rows = store.read_store_words("rt_seg_rows", status[10] as usize * 28).unwrap();
    let rows = &rows[segment[1] as usize * 28..(segment[1] + segment[2]) as usize * 28];
    let tokens = store.read_store_words("rt_seg_tokens", status[13] as usize * 4).unwrap();
    let token_hash = |token: u32| tokens[(segment[19] + token) as usize * 4 + 3];
    let local_value = rows.chunks_exact(28).find(|r| r[0] == 8 && token_hash(r[9]) == fnv1a("value")).unwrap()[9];
    let param_value = rows.chunks_exact(28).find(|r| r[0] == 4 && token_hash(r[10]) == fnv1a("value")).unwrap()[10];
    assert_ne!(local_value, param_value);
    let mut checked = [0; 4];
    for row in rows.chunks_exact(28) {
        if row[0] == 8 && token_hash(row[9]) == fnv1a("inherited") {
            assert_eq!(row[12], method_t, "inherited uses the method's T, realized as bool");
            checked[0] += 1;
        }
        if row[0] == 21 && token_hash(row[10]) == fnv1a("value") {
            assert_eq!(row[12], impl_t, "self.value uses the impl's T, realized as i32");
            checked[1] += 1;
        }
        let name = match row[0] { 22 => row[11], 33 => row[2], _ => continue };
        if token_hash(name) == fnv1a("value") {
            let after = name > local_value;
            assert_eq!(row[20], 1, "a value name has a local binding");
            assert_eq!(row[21], if after { local_value } else { param_value },
                "same-spelled values must bind to the correct declaration");
            checked[2 + usize::from(after)] += 1;
        }
    }
    assert!(checked.iter().all(|n| *n > 0), "both type and value shadowing were checked: {checked:?}");
}

fn decl_named(texts: &[(u32, String)], prefix: &str) -> u32 {
    let found = texts.iter().filter(|(_, t)| t.starts_with(prefix)).collect::<Vec<_>>();
    assert_eq!(found.len(), 1, "one retained body starts with {prefix:?}: {texts:?}");
    found[0].0
}
