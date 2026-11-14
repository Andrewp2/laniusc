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
// and their parameter `U` collide on every local token ordinal.
const LIBRARY: &str = r#"module lib::a;
fn pad() {}
fn identity<U>(value: U) -> U { return value; }
struct Hidden<T> { inner: T }
pub struct Cell<T> { value: T }
pub fn wrap<T>(value: T) -> Cell<T> {
    let hidden: Hidden<T> = Hidden { inner: value };
    let result = identity(hidden.inner);
    pad();
    return Cell { value: result };
}
pub impl<T> Cell<T> {
    pub fn shadow<T>(&self, value: T) -> T {
        let inherited: T = value;
        let outer = identity(self.value);
        return inherited;
    }
}
"#;

// Job B, library 11.
const APP: &str = r#"module app::b;
import lib::a;
fn identity<U>(value: U) -> U { return value; }
struct Local<T> { item: T }
fn main() -> i32 {
    let first = wrap(7);
    let second = wrap(Local { item: true });
    let third = wrap(1);
    let flag = first.shadow(false);
    let same = identity(3);
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
    let words = store.resolve_probe().expect("resolve probe");
    Probe { uses: words.chunks_exact(PROBE_WORDS).map(<[u32]>::to_vec).collect() }
}

fn summary(store: &ProgramRetention) -> Vec<u32> {
    let status = store.status().unwrap();
    // Arena counters and the build's committed/rollback/conflict words.
    // Spare records (lanes that lost an intern race) are not retained data.
    let mut words = (0..13)
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
        // Every foreign body here calls job A's private `identity`, never
        // job B's same-spelled one.
        assert_eq!(use_words[PROBE_NESTED_CALLEE], a_identity, "callee identity is job A's private callable");
    }
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
