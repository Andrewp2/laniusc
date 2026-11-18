//! Retained instance projection (docs/compiler-retained-projection.md).

use laniusc_compiler::{
    codegen::lir::input_capture,
    compiler::compile_source_to_x86_64_with_gpu_codegen,
};

#[allow(unused_imports)]
use crate::common;

const ORACLE: &str = r#"struct Hidden { inner: i32 }
pub struct Pair { first: i32, second: u32 }
fn halve(value: i32) -> i32 {
    let cell: Hidden = Hidden { inner: value };
    return cell.inner / 2;
}
fn halveu(value: u32) -> u32 { return value / 2; }
fn mix(p: Pair) -> Pair {
    return Pair { first: halve(p.first), second: halveu(p.second) };
}
fn twice(v: f64) -> f64 { return v + v * 0.5; }
fn main() -> i32 {
    let p = mix(Pair { first: -8, second: 10 });
    if (twice(2.0) > 2.5) { return p.first + 10; }
    return 1;
}
"#;

fn dump(capture: &input_capture::Capture) {
    let n = capture["hir.count"][0] as usize;
    let word = |name: &str, i: usize, stride: usize| -> Vec<u32> {
        capture.get(name).map(|w| w[i * stride..(i * stride + stride).min(w.len())].to_vec()).unwrap_or_default()
    };
    let mut names: Vec<_> = capture.keys().cloned().collect();
    names.sort();
    eprintln!("columns: {names:?}");
    for row in 0..n {
        eprintln!(
            "row {row}: core {:?} links {:?} payload {:?} ret {:?} cv {:?} ep {:?} er {:?} nl {:?}",
            word("hir.core", row, 4), word("hir.links", row, 4), word("hir.payload", row, 4),
            word("hir.fn_return_type", row, 1), word("hir.const_value", row, 1),
            word("hir.expression_parents", row, 1), word("hir.expression_roots", row, 1),
            word("hir.nearest_loop", row, 1)
        );
        let mut sem = String::new();
        for name in &names {
            if name.starts_with("typecheck.semantic_") || name == "semantic.expression_types"
                || name == "typecheck.public_decl_index_by_hir"
            {
                let stride = if name.contains("calls_by_hir") { 22 } else if name.contains("value_consts_by_hir") { 2 } else { 1 };
                let w = word(name, row, stride);
                let short = name.trim_start_matches("typecheck.semantic_");
                if w.iter().any(|&x| x != u32::MAX && x != 0) { sem += &format!(" {short}={w:?}"); }
            }
        }
        eprintln!("      {sem}");
    }
    for (name, stride, count) in [("hir.call_args", 4, "hir.call_arg_count"), ("hir.fields", 4, "hir.field_count"),
        ("hir.params", 4, "hir.param_count"), ("typecheck.struct_init_field_ordinals", 1, "hir.field_count")] {
        let c = capture[count][0] as usize;
        for i in 0..c { eprintln!("{name}[{i}] = {:?}", word(name, i, stride)); }
    }
    for i in 0..n { let r = word("hir.param_ranges", i, 2); if r.len()==2 && r[1] != 0 { eprintln!("param_ranges[{i}]={r:?}"); } }
    for name in ["typecheck.type_instance_kind", "typecheck.type_instance_native_words", "typecheck.type_instance_decl_token",
        "typecheck.external_type_library_id", "typecheck.imported_layout_kind", "typecheck.type_instance_arg_count"] {
        let w = &capture[name];
        let live: Vec<_> = w.iter().enumerate().filter(|(_, x)| **x != u32::MAX && **x != 0).take(40).collect();
        eprintln!("{name}: {live:?}");
    }
}

#[test]
fn retained_projection_oracle_columns() {
    input_capture::arm(1 << 14);
    let bytes = pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(ORACLE)).expect("oracle compiles");
    let captures = input_capture::take();
    eprintln!("{} lowering jobs, {} bytes", captures.len(), bytes.len());
    for c in &captures { dump(c); }
    if let Ok(path) = std::env::var("LANIUS_PROJECTION_ORACLE_DUMP") {
        let mut out = String::new();
        for (name, words) in &captures[0] {
            out += &format!("{name} {}\n", words.iter().map(|w| w.to_string()).collect::<Vec<_>>().join(" "));
        }
        std::fs::write(path, out).unwrap();
    }
    let out = common::run_x86_64_elf_output("oracle", "oracle", &bytes);
    assert_eq!(out.status.code(), Some(6));
}

// Vertical slice: two units retained, frontend released, projection only.
const SLICE_LIBRARY: &str = r#"module lib::a;
struct Hidden<T> { inner: T }
fn keep<T>(value: T) -> T {
    let cell: Hidden<T> = Hidden { inner: value };
    return cell.inner;
}
pub struct PairA { first: i32, second: u32 }
pub struct PairB { first: u32, second: i32 }
pub fn swap<T>(p: PairA, tag: T) -> PairB {
    return PairB { first: keep(p.second), second: keep(p.first) };
}
pub fn scale<T>(v: f64, tag: T) -> f64 { return v * 1.5; }
"#;

// `main` is nongeneric: its own job lowers it and the store keeps no body
// for it. Its use of `start<u8>` is the discovery root, and the projected
// `start<u8>` is the executable's entry.
const SLICE_APP: &str = r#"module app::b;
import lib::a;
fn start<T>() -> i32 {
    let b: PairB = swap(PairA { first: -3, second: 9 }, true);
    let s: f64 = scale(2.0, 1);
    if (s > 2.5) {
        if (b.first == 9) { return b.second + 10; }
    }
    return 1;
}
fn main() -> i32 { return start<u8>(); }
"#;

fn retain(sources: &[(&str, &str)]) -> std::sync::Arc<laniusc_compiler::type_checker::program_retention::ProgramRetention> {
    use laniusc_compiler::{
        compiler::{GpuCompiler, GpuCompilerBackends},
        type_checker::program_retention::{ProgramRetention, ProgramRetentionCapacity},
    };
    let compiler = pollster::block_on(GpuCompiler::new_with_backends(GpuCompilerBackends::frontend_only()))
        .expect("frontend compiler");
    let store = ProgramRetention::new(ProgramRetentionCapacity::default()).unwrap();
    store.begin_build().unwrap();
    compiler.attach_program_retention(Some(store.clone()));
    let library = pollster::block_on(compiler.semantic_interface_for_source_pack(10, &[sources[0].1]))
        .expect("library job");
    pollster::block_on(compiler.semantic_interface_for_source_pack_with_dependencies(11, &[sources[1].1], &[library]))
        .expect("application job");
    compiler.attach_program_retention(None);
    for report in store.job_reports() {
        assert!(report.ready, "{report:?}");
    }
    pollster::block_on(compiler.release_resident_job_buffers());
    drop(compiler);
    store.poison_scratch();
    store
}

mod slice {
    use laniusc_compiler::{
        compiler::{GpuCompiler, GpuCompilerBackends, frontend_check_count},
        type_checker::program_retention::{
            ProgramRetention,
            projection::{
                PRODUCER_KERNEL,
                ProjectionInputs,
                ProjectionOptions,
                ProjectionOutcome,
                RetainedProjection,
                error,
                read_test_buffer,
                run_producer_kernel,
                test_buffer,
            },
            substitution::{RetainedSubstitution, SubstitutionCapacity, SubstitutionRequests, words},
        },
    };

    use super::common;

    const SLOTS: u32 = 1024;
    const APP_LIBRARY: u32 = 11;

    /// Producer figures: ranks, routes, overflow bits, roots, levels.
    #[derive(Debug)]
    pub struct Produced {
        pub ranks: u32,
        pub routes: u32,
        pub roots: u32,
        pub levels: u32,
    }

    /// Discovers the closed instances reachable from the app's roots on
    /// the GPU and writes them into `inputs` (test producer).
    pub fn produce(store: &ProgramRetention, inputs: &ProjectionInputs, root_library: u32) -> Produced {
        let out = test_buffer(64 + 2 * SLOTS as usize);
        let requests = SubstitutionRequests::new(4096);
        let mut engine = RetainedSubstitution::new(SubstitutionCapacity::default()).unwrap();
        let mask = SLOTS - 1;
        let dir = store.status().unwrap()[4];
        let (none_results, none_counts) = (test_buffer(16), test_buffer(32));
        let none = [("sb_results", &none_results), ("sb_counts", &none_counts)];
        let kernel = |config: &[u32], lanes: u32, extra: &[(&str, &wgpu::Buffer)]| {
            run_producer_kernel(store, PRODUCER_KERNEL, inputs, &requests, config, &out, lanes, extra).unwrap()
        };
        kernel(&[0, root_library, 1, mask, 0], dir, &none);
        let mut lo = 0;
        let mut levels = 0;
        loop {
            let hi = read_test_buffer(&out, 4).unwrap()[0];
            if hi == lo {
                break;
            }
            levels += 1;
            kernel(&[5, 0, 0, mask, 0], 1, &none);
            kernel(&[1, lo, hi, mask, 0], hi - lo, &none);
            let report = engine.run(store, &requests).unwrap().published().unwrap();
            let n = report.counts[words::REQUESTS];
            let publication = engine.publication(store).expect("discovery publication");
            let run = publication.id.run;
            let extra = publication.buffers();
            kernel(&[2, 0, 0, mask, run], n, &extra);
            kernel(&[3, 0, 0, mask, run], n, &extra);
            lo = hi;
        }
        kernel(&[4, 0, 0, mask, 0], 1, &none);
        let w = read_test_buffer(&out, 4).unwrap();
        assert_eq!(w[2], 0, "producer overflow or unresolved request bits");
        Produced { ranks: w[0], routes: w[1], roots: w[3], levels }
    }

    pub fn codegen() -> GpuCompiler<'static> {
        pollster::block_on(GpuCompiler::new_with_backends(GpuCompilerBackends::x86_only())).expect("x86 compiler")
    }

    pub fn project(
        compiler: &GpuCompiler<'_>,
        projection: &mut RetainedProjection,
        store: &ProgramRetention,
        inputs: &ProjectionInputs,
        options: ProjectionOptions,
    ) -> ProjectionOutcome {
        projection.run(compiler, store, inputs, &options).expect("projection runs")
    }

    #[test]
    fn retained_projection_executes_two_unit_program() {
        common::run_with_timeout("retained projection slice", slice_program);
    }

    fn slice_program() {
        let exported = frontend_check_count();
        let store = super::retain(&[("lib", super::SLICE_LIBRARY), ("app", super::SLICE_APP)]);
        let before = frontend_check_count();
        assert!(before >= exported + 2, "the export ran two frontend checks: {exported:?} -> {before:?}");
        let inputs = ProjectionInputs::new(64, 256);
        let produced = produce(&store, &inputs, APP_LIBRARY);
        eprintln!("producer: {produced:?}");
        assert_eq!(produced.roots, 1, "main is the only root");
        let started = std::time::Instant::now();
        let compiler = codegen();
        eprintln!("codegen compiler ready in {:?}", started.elapsed());
        let mut projection = RetainedProjection::new(SubstitutionCapacity::default()).unwrap();
        let options = ProjectionOptions { batch_rows: 1 << 16, ..ProjectionOptions::default() };
        let outcome = project(&compiler, &mut projection, &store, &inputs, options);
        let (objects, report) = match outcome {
            ProjectionOutcome::Objects { objects, report } => (objects, report),
            ProjectionOutcome::Rejected { error, report } => panic!("{error} ({report:?})"),
        };
        eprintln!(
            "projection: {} instances, {} rows, {} requests, {} batches; {} dispatches, {} readbacks ({} bytes), \
             {} allocations ({} bytes); plan {} us, substitution {} us ({} dispatches), check {} us, lowering {} us; total {:?}",
            report.instances, report.rows, report.requests, report.batches.len(), report.dispatches, report.readbacks,
            report.readback_bytes, report.allocations, report.allocated_bytes, report.plan_us, report.substitution_us,
            report.substitution.as_ref().map_or(0, |s| s.dispatches), report.check_us, report.lowering_us, started.elapsed()
        );
        let elf = compiler.link_x86_objects(&objects).expect("link");
        assert_eq!(frontend_check_count(), before, "projection and link ran no frontend checks");
        let out = common::run_x86_64_elf_output("retained projection", "retained_projection", &elf);
        assert_eq!(out.status.code(), Some(7));
    }

    fn execute(
        compiler: &GpuCompiler<'_>,
        projection: &mut RetainedProjection,
        store: &ProgramRetention,
        inputs: &ProjectionInputs,
        options: ProjectionOptions,
        name: &str,
    ) -> (Option<i32>, laniusc_compiler::type_checker::program_retention::projection::ProjectionReport, usize) {
        let (objects, report) = match project(compiler, projection, store, inputs, options) {
            ProjectionOutcome::Objects { objects, report } => (objects, report),
            ProjectionOutcome::Rejected { error, report } => panic!("{error} ({report:?})"),
        };
        let count = objects.len();
        let elf = compiler.link_x86_objects(&objects).expect("link");
        let out = common::run_x86_64_elf_output(name, name, &elf);
        (out.status.code(), report, count)
    }

    // Small capacities, several batches with cross-batch calls, one engine
    // reused for an unrelated build, and a stale generation.
    #[test]
    fn retained_projection_batches_retries_reuse_and_staleness() {
        common::run_with_timeout("retained projection batches", batches_program);
    }

    #[test]
    fn retained_projection_rejects_truncated_and_unready_inputs() {
        common::run_with_timeout("retained projection input boundary", input_boundary_program);
    }

    fn input_boundary_program() {
        let store = super::retain(&[("lib", super::SLICE_LIBRARY), ("app", super::SLICE_APP)]);
        let inputs = ProjectionInputs::new(5, 64);
        let produced = produce(&store, &inputs, APP_LIBRARY);
        assert_eq!(produced.ranks, inputs.instance_capacity(), "the entire resident prefix is valid");
        let compiler = codegen();
        let mut projection = RetainedProjection::new(SubstitutionCapacity::default()).unwrap();
        let generation = store.generation();
        let requests = SubstitutionRequests::new(1);
        let out = test_buffer(4);
        let (none_results, none_counts) = (test_buffer(16), test_buffer(32));
        let extra = [("sb_results", &none_results), ("sb_counts", &none_counts)];
        let cases = [
            ([generation, 1, inputs.instance_capacity() + 1, produced.routes], error::INPUT_CAPACITY),
            ([generation, 1, produced.ranks, inputs.route_capacity() + 1], error::INPUT_CAPACITY),
            ([generation, 0, produced.ranks, produced.routes], error::READINESS),
            ([generation + 1, 1, 0, 0], error::READINESS),
            ([generation, 0, 0, 0], error::READINESS),
            ([generation, 1, 0, inputs.route_capacity() + 1], error::INPUT_CAPACITY),
        ];
        for (header, expected) in cases {
            run_producer_kernel(&store, PRODUCER_KERNEL, &inputs, &requests,
                &[6, header[0], header[1], header[2], header[3]], &out, 1, &extra).unwrap();
            match project(&compiler, &mut projection, &store, &inputs, ProjectionOptions::default()) {
                ProjectionOutcome::Rejected { error, report } => {
                    assert_eq!(error.code, expected, "header {header:?}: {error}");
                    assert!(report.batches.is_empty());
                    assert!(report.substitution.is_none(), "invalid headers stop before substitution");
                }
                ProjectionOutcome::Objects { .. } => panic!("invalid header {header:?} published a prefix"),
            }
        }
        run_producer_kernel(&store, PRODUCER_KERNEL, &inputs, &requests,
            &[6, generation, 1, 0, 0], &out, 1, &extra).unwrap();
        match project(&compiler, &mut projection, &store, &inputs, ProjectionOptions::default()) {
            ProjectionOutcome::Objects { objects, report } => {
                assert!(objects.is_empty());
                assert!(report.batches.is_empty());
                assert!(report.substitution.is_none());
            }
            ProjectionOutcome::Rejected { error, .. } => panic!("valid empty input: {error}"),
        }
    }

    const OTHER_LIBRARY: &str = r#"module lib::a;
pub fn twice<T>(v: T, w: T) -> T { return w; }
"#;

    const OTHER_APP: &str = r#"module app::b;
import lib::a;
fn start<T>() -> i32 {
    let x: u32 = twice(1, 4);
    let y: i32 = twice(-3, 5);
    return y + 1;
}
fn main() -> i32 { return start<u8>(); }
"#;

    fn batches_program() {
        let compiler = codegen();
        let mut projection = RetainedProjection::new(SubstitutionCapacity::tiny()).unwrap();
        let store = super::retain(&[("lib", super::SLICE_LIBRARY), ("app", super::SLICE_APP)]);
        // Rank capacity grows from 1 (`ProjectionInputs` is sized by the producer).
        let inputs = ProjectionInputs::new(8, 16);
        produce(&store, &inputs, APP_LIBRARY);
        let options = ProjectionOptions { batch_rows: 16, ..ProjectionOptions::default() };
        let (code, report, objects) = execute(&compiler, &mut projection, &store, &inputs, options, "retained_projection_batches");
        eprintln!("batched: {objects} objects, {report:?}");
        assert_eq!(code, Some(7));
        assert!(report.batches.len() >= 3, "{:?}", report.batches);
        assert_eq!(objects, report.batches.len());
        let substitution = report.substitution.as_ref().unwrap();
        assert!(substitution.attempts > 1 || substitution.growths > 0, "tiny capacity grows: {substitution:?}");
        // One identity chain for every instance.
        let options = ProjectionOptions { batch_rows: 16, identity_mask: 0 };
        let (code, _, _) = execute(&compiler, &mut projection, &store, &inputs, options, "retained_projection_chain");
        assert_eq!(code, Some(7));

        // Stale: a new build of the store invalidates the producer's records.
        store.begin_build().unwrap();
        match project(&compiler, &mut projection, &store, &inputs, ProjectionOptions::default()) {
            ProjectionOutcome::Rejected { error, .. } => assert_eq!(error.code, error::READINESS, "{error}"),
            ProjectionOutcome::Objects { .. } => panic!("stale instance records lowered"),
        }
        drop(store);

        // The same projection and compiler for an unrelated program.
        let store = super::retain(&[("lib", OTHER_LIBRARY), ("app", OTHER_APP)]);
        let inputs = ProjectionInputs::new(8, 16);
        produce(&store, &inputs, APP_LIBRARY);
        let (code, report, _) = execute(&compiler, &mut projection, &store, &inputs, ProjectionOptions::default(), "retained_projection_other");
        eprintln!("unrelated: {report:?}");
        assert_eq!(code, Some(6));
        // Exports of the two stores ran the frontend; nothing else did.

    }

    // An instance that breaks the literal rule fails at the template's
    // location and publishes no object. The frontend checks every instance
    // it compiles, so the test rewrites the retained literal of the
    // symbolic `v + 37` to 300: `bump<u8>` then holds a literal its type
    // cannot represent, which only the projection sees.
    #[test]
    fn retained_projection_rejects_instance_rule_violation() {
        common::run_with_timeout("retained projection rule", rule_program);
    }

    const RULE_APP: &str = r#"module app::b;
import lib::a;
fn bump<T>(v: T) -> T { return v + 37; }
fn start<T>() -> i32 {
    let x: u8 = bump(1);
    return 0;
}
fn main() -> i32 { return start<u8>(); }
"#;

    fn rule_program() {
        let store = super::retain(&[("lib", OTHER_LIBRARY), ("app", RULE_APP)]);
        let rows = store.status().unwrap()[10] as usize;
        let words = store.read_store_words("rt_seg_rows", rows * 28).unwrap();
        let literal = (0..rows)
            .filter(|&r| words[r * 28] == 23 && words[r * 28 + 9] == 37 && words[r * 28 + 10] == 0)
            .collect::<Vec<_>>();
        assert_eq!(literal.len(), 1, "one retained literal 37");
        store.write_store_words("rt_seg_rows", (literal[0] * 28 + 9) as u64, &[300]).unwrap();
        let inputs = ProjectionInputs::new(8, 16);
        produce(&store, &inputs, APP_LIBRARY);
        let compiler = codegen();
        let mut projection = RetainedProjection::new(SubstitutionCapacity::default()).unwrap();
        match project(&compiler, &mut projection, &store, &inputs, ProjectionOptions::default()) {
            ProjectionOutcome::Rejected { error, report } => {
                eprintln!("rejected: {error} ({report:?})");
                assert_eq!(error.code, error::RULE);
                assert_eq!(error.detail >> 24, error::RULE_INTEGER_RANGE);
                assert_eq!(error.byte as usize, RULE_APP.find("37").unwrap());
                assert!(report.batches.is_empty(), "nothing was lowered");
            }
            ProjectionOutcome::Objects { .. } => panic!("bump<u8> with 300 lowered"),
        }
    }
}

#[test]
fn retained_projection_selects_float_status_at_the_instance_width() {
    use laniusc_compiler::type_checker::program_retention::{
        discovery::{DiscoveryCapacity, DiscoveryOutcome, RetainedDiscovery},
        projection::{ProjectionOptions, ProjectionOutcome, RetainedProjection, error},
        substitution::SubstitutionCapacity,
    };
    common::run_with_timeout("retained float status", || {
        let lib = "module lib::a; pub fn number<T>(v:T)->T { return v + 1e39; }";
        let app = "module app::b; import lib::a; fn main()->i32 { let n:f64 = number<f64>(1.0); return 0; }";
        let store = retain(&[("lib", lib), ("app", app)]);
        let count = store.status().unwrap()[10] as usize;
        let rows = store.read_store_words("rt_seg_rows", count * 28).unwrap();
        let literals: Vec<_> = (0..count).filter(|&r| rows[r*28] == 23 && rows[r*28+8] == 27).collect();
        assert_eq!(literals.len(), 1);
        let word = literals[0] * 28 + 24;
        assert_eq!(rows[word] >> 16, 2, "1e39 overflows f32 but is valid f64");
        let mut discovery = RetainedDiscovery::new(DiscoveryCapacity::tiny(), SubstitutionCapacity::tiny()).unwrap();
        let publication = match discovery.run(&store).unwrap() {
            DiscoveryOutcome::Published(p) => p,
            DiscoveryOutcome::Rejected(e) => panic!("{e:?}"),
        };
        let compiler = pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new()).unwrap();
        let mut projection = RetainedProjection::new(SubstitutionCapacity::tiny()).unwrap();
        let options = ProjectionOptions::default();
        assert!(matches!(projection.run(&compiler, &store, &publication.inputs, &options).unwrap(), ProjectionOutcome::Objects { .. }));
        // A failed parser status for the selected width must stop publication,
        // even when the retained rounded bits still describe a finite value.
        for status in [1, 2, 5] {
            store.write_store_words("rt_seg_rows", word as u64, &[rows[word] | (status << 24)]).unwrap();
            match projection.run(&compiler, &store, &publication.inputs, &options).unwrap() {
                ProjectionOutcome::Rejected { error, report } => {
                    assert_eq!(error.code, error::RULE, "{error}");
                    assert_eq!(error.detail >> 24, error::RULE_FLOAT_LITERAL);
                    assert_eq!(error.detail & 0xff, status);
                    assert_eq!(error.byte as usize, lib.find("1e39").unwrap());
                    assert!(report.batches.is_empty());
                }
                ProjectionOutcome::Objects { .. } => panic!("failed f64 literal was published"),
            }
        }
        store.write_store_words("rt_seg_rows", word as u64, &[rows[word]]).unwrap();
        assert!(matches!(projection.run(&compiler, &store, &publication.inputs, &options).unwrap(), ProjectionOutcome::Objects { .. }));
    });
}

#[test]
fn retained_projection_rejects_wrong_pattern_schema_and_payload_type() {
    use laniusc_compiler::type_checker::program_retention::{
        discovery::{DiscoveryCapacity,DiscoveryOutcome,RetainedDiscovery},
        projection::{ProjectionOptions,ProjectionOutcome,RetainedProjection,error},
        substitution::SubstitutionCapacity,
    };
    common::run_with_timeout("retained pattern rejection",|| {
        let lib=r#"module lib::a;
pub enum Choice<T> { One(T), Pair(T,T) }
pub fn unwrap<T>(value:Choice<T>, fallback:T)->T {
    return match (value) { One(inner) -> inner, _ -> fallback };
}
"#;
        let app=r#"module app::b;
import lib::a;
fn main()->i32 { return unwrap<i32>(One(3),4); }
"#;
        let store=retain(&[("lib",lib),("app",app)]);
        let mut discovery=RetainedDiscovery::new(DiscoveryCapacity::tiny(),SubstitutionCapacity::tiny()).unwrap();
        let publication=match discovery.run(&store).unwrap() {
            DiscoveryOutcome::Published(p)=>p,
            DiscoveryOutcome::Rejected(e)=>panic!("{e:?}"),
        };
        let count=store.status().unwrap()[10] as usize;
        let rows=store.read_store_words("rt_seg_rows",count*28).unwrap();
        let pattern=(0..count).filter(|&r|rows[r*28+14]==5 && rows[r*28+20]==3).collect::<Vec<_>>();
        assert_eq!(pattern.len(),1);
        let root=pattern[0];
        let payload=root+1;
        assert_eq!(rows[payload*28+20],1,"the inner payload binds a local");
        let compiler=pollster::block_on(laniusc_compiler::compiler::GpuCompiler::new()).unwrap();
        let mut projection=RetainedProjection::new(SubstitutionCapacity::tiny()).unwrap();
        for (word,value,code) in [(root*28+22,1,error::FIELD),(payload*28+12,2,error::SIGNATURE)] {
            store.write_store_words("rt_seg_rows",word as u64,&[value]).unwrap();
            match projection.run(&compiler,&store,&publication.inputs,&ProjectionOptions::default()).unwrap() {
                ProjectionOutcome::Rejected{error,report}=>{
                    assert_eq!(error.code,code,"{error}");
                    assert!(report.batches.is_empty(),"a bad pattern lowers no object");
                }
                ProjectionOutcome::Objects{..}=>panic!("malformed pattern was published"),
            }
            store.write_store_words("rt_seg_rows",word as u64,&[rows[word]]).unwrap();
        }
        assert!(matches!(projection.run(&compiler,&store,&publication.inputs,&ProjectionOptions::default()).unwrap(),ProjectionOutcome::Objects{..}));
    });
}
