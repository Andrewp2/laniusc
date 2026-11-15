use laniusc_compiler::{
    compiler::{GpuCompiler, GpuCompilerBackends, fallback_counters},
    type_checker::program_retention::{
        ProgramRetention,
        ProgramRetentionCapacity,
        discovery::{DiscoveryCapacity, DiscoveryOutcome, DiscoveryPublication, RetainedDiscovery},
        projection::{ProjectionOptions, ProjectionOutcome, RetainedProjection, read_test_buffer},
        substitution::SubstitutionCapacity,
    },
};

use crate::common;
const LIB: &str = r#"module lib::a;
struct Hidden<T> { inner: T }
fn keep<T>(v: T) -> T { let h: Hidden<T> = Hidden { inner: v }; return h.inner; }
pub struct PairA { first: i32, second: u32 }
pub struct PairB { first: u32, second: i32 }
pub fn swap<T>(p: PairA, tag: T) -> PairB {
    return PairB { first: keep(p.second), second: keep(p.first) };
}
pub fn scale<T>(v: f64, tag: T) -> f64 { return v * 1.5; }
"#;
const APP: &str = r#"module app::b;
import lib::a;
fn start<T>() -> i32 {
    let b: PairB = swap(PairA { first: -3, second: 9 }, true);
    let s: f64 = scale(2.0, 1);
    if (s > 2.5) { if (b.first == 9) { return b.second + 10; } }
    return 1;
}
fn another() -> i32 { return start<u8>(); }
fn main() -> i32 { return start<u8>(); }
"#;
fn retain() -> std::sync::Arc<ProgramRetention> {
    let compiler = pollster::block_on(GpuCompiler::new_with_backends(
        GpuCompilerBackends::frontend_only(),
    ))
    .unwrap();
    let store = ProgramRetention::new(ProgramRetentionCapacity::default()).unwrap();
    store.begin_build().unwrap();
    compiler.attach_program_retention(Some(store.clone()));
    let lib = pollster::block_on(compiler.semantic_interface_for_source_pack(10, &[LIB])).unwrap();
    pollster::block_on(
        compiler.semantic_interface_for_source_pack_with_dependencies(11, &[APP], &[lib]),
    )
    .unwrap();
    compiler.attach_program_retention(None);
    for report in store.job_reports() {
        assert!(report.ready, "{report:?}");
    }
    pollster::block_on(compiler.release_resident_job_buffers());
    drop(compiler);
    store.poison_scratch();
    store
}
fn publish(engine: &mut RetainedDiscovery, store: &ProgramRetention) -> DiscoveryPublication {
    match engine.run(store).unwrap() {
        DiscoveryOutcome::Published(p) => p,
        DiscoveryOutcome::Rejected(e) => panic!("{e:?}"),
    }
}
// Full semantic oracle: instance environments come from the retained calls,
// and every direct edge reaches that call's declaration, including duplicates.
fn check(store: &ProgramRetention, p: &DiscoveryPublication) -> Vec<u32> {
    eprintln!("discovery: {:?}", p.report);
    assert_eq!(p.report.instances, 5);
    assert_eq!(p.report.roots, 2);
    assert_eq!(p.report.waves, 3);
    let s = store.status().unwrap();
    let uses = store
        .read_store_words("rt_uses", s[8] as usize * 12)
        .unwrap();
    let defs = store
        .read_store_words("rt_decl_def", s[0] as usize)
        .unwrap();
    let dirs = store
        .read_store_words("rt_dir", s[4] as usize * 16)
        .unwrap();
    let heads = store
        .read_store_words("rt_term_head", s[2] as usize * 4)
        .unwrap();
    let rows = read_test_buffer(p.inputs.buffers()[0].1, p.report.instances as usize * 8).unwrap();
    let routes = read_test_buffer(p.inputs.buffers()[1].1, p.report.edges as usize * 4).unwrap();
    let roots = read_test_buffer(&p.root_routes.buffer, s[8] as usize * 4).unwrap();
    assert_eq!(
        read_test_buffer(&p.root_readiness.buffer, 4).unwrap(),
        [p.generation, 1, 5, s[8]]
    );
    let mut identities = Vec::new();
    let mut seen = std::collections::BTreeSet::new();
    for (rank, i) in rows.chunks_exact(8).enumerate() {
        assert_eq!(i[2], p.generation);
        assert_eq!(i[3], 0, "the original main remains the entry");
        assert!(seen.insert((i[0], i[1])));
        assert_eq!(heads[i[1] as usize * 4] & 255, 16);
        assert_eq!(heads[i[1] as usize * 4 + 1], i[0]);
        identities.extend_from_slice(&i[..2]);
        let d = (defs[i[0] as usize] - 1) as usize * 16;
        assert_eq!(i[5], dirs[d + 12]);
        for ordinal in 0..i[5] as usize {
            let u = (dirs[d + 11] as usize + ordinal) * 12;
            let route = &routes[(i[4] as usize + ordinal) * 4..][..4];
            if uses[u + 2] & 255 == 1 {
                assert_eq!(&route[..2], &[0xffff_fffe, 0xffff_0002]);
                assert_eq!(
                    rows[route[2] as usize * 8],
                    uses[u + 3],
                    "rank {rank}, use {ordinal}"
                );
            } else {
                assert_eq!(route[0], u32::MAX);
            }
        }
    }
    let mut root_count = 0;
    for (u, r) in roots.chunks_exact(4).enumerate() {
        if r[3] == 0 {
            continue;
        }
        root_count += 1;
        assert_eq!(r[3], p.generation);
        assert_eq!(&r[..2], &[0xffff_fffe, 0xffff_0002]);
        assert_eq!(rows[r[2] as usize * 8], uses[u * 12 + 3]);
    }
    assert_eq!(root_count, 2);
    identities
}
#[test]
fn retained_discovery_drives_projection_without_a_test_instance_list() {
    common::run_with_timeout("production retained discovery", || {
        let store = retain();
        let before = fallback_counters();
        let mut engine = RetainedDiscovery::new(
            DiscoveryCapacity::default(),
            SubstitutionCapacity::default(),
        )
        .unwrap();
        let p = publish(&mut engine, &store);
        let reference = check(&store, &p);
        let compiler = pollster::block_on(GpuCompiler::new_with_backends(
            GpuCompilerBackends::x86_only(),
        ))
        .unwrap();
        let mut projection = RetainedProjection::new(SubstitutionCapacity::default()).unwrap();
        match projection
            .run(
                &compiler,
                &store,
                &p.inputs,
                &ProjectionOptions {
                    batch_rows: 16,
                    ..Default::default()
                },
            )
            .unwrap()
        {
            ProjectionOutcome::Objects { objects, report } => {
                assert!(objects.len() >= 3, "{report:?}");
            }
            ProjectionOutcome::Rejected { error, .. } => panic!("{error}"),
        }
        assert_eq!(
            fallback_counters(),
            before,
            "discovery and projection never invoke the frontend or replay"
        );
        let mut tiny =
            RetainedDiscovery::new(DiscoveryCapacity::tiny(), SubstitutionCapacity::tiny())
                .unwrap();
        tiny.set_hash_mask(0);
        let retried = publish(&mut tiny, &store);
        assert!(retried.report.attempts > 1);
        assert_eq!(check(&store, &retried), reference);
        assert_eq!(check(&store, &publish(&mut engine, &store)), reference);
        // A relevant unsupported route cannot disappear from discovery.
        let s = store.status().unwrap();
        let uses = store
            .read_store_words("rt_uses", s[8] as usize * 12)
            .unwrap();
        let root = read_test_buffer(&p.root_routes.buffer, s[8] as usize * 4)
            .unwrap()
            .chunks_exact(4)
            .position(|r| r[3] != 0)
            .unwrap();
        store
            .write_store_words("rt_uses", (root * 12 + 2) as u64, &[2])
            .unwrap();
        match engine.run(&store).unwrap() {
            DiscoveryOutcome::Rejected(e) => {
                assert_eq!(e.code, 3);
                assert_eq!(e.use_index, root as u32);
            }
            DiscoveryOutcome::Published(_) => panic!("method silently skipped"),
        }
        store
            .write_store_words("rt_uses", (root * 12 + 2) as u64, &[uses[root * 12 + 2]])
            .unwrap();
        store.begin_build().unwrap();
        let empty = publish(&mut engine, &store);
        assert_eq!(empty.report.instances, 0);
        assert_eq!(empty.report.roots, 0);
    });
}
