//! The program trait catalog built on the GPU from the retention store
//! (docs/compiler-retained-trait-catalog.md). Two frontend jobs export into
//! one store: the traits and generic functions are in unit A, and the impls
//! and private self types are in unit B. The frontend's storage is released
//! and exporter scratch is poisoned. The GPU producer then writes the
//! solver's catalog and batch rows, and the production admission,
//! coherence and proof kernels select implementations. The test reads rows
//! back for assertions only.

use std::sync::Arc;

use laniusc_compiler::{
    compiler::{GpuCompiler, GpuCompilerBackends, RetainedTraitCheck, RetainedTraitOptions, RetainedTraitStage},
    type_checker::program_retention::{ProgramRetention, ProgramRetentionCapacity, counts},
};

#[allow(unused_imports)]
use crate::common;

const LIBRARY: &str = r#"module rtc::a;
pub trait Show { pub fn show(&self) -> i32; }
pub trait Pair<X> { pub fn left(&self, value: X) -> X; }
pub struct Cell<T> { value: T }
pub fn cell<T>(value: T) -> Cell<T> { return Cell { value: value }; }
pub impl<T> Cell<T> {
    pub fn shadow<T>(&self, value: T) -> T where T: Show { return value; }
    pub fn inherit<U>(&self, other: U) -> U where T: Show { return other; }
}
pub fn needs<T: Show>(value: T) -> T { return value; }
pub fn paired<T, U>(value: T, other: U) -> U where U: Pair<T> { return other; }
"#;

const APP: &str = r#"module rtc::b;
import rtc::a;
struct Local { v: i32 }
struct Wrap<T> { inner: T }
pub impl Show for Local { pub fn show(&self) -> i32 { return 1; } }
pub impl<T: Show> Show for Wrap<T> { pub fn show(&self) -> i32 { return 2; } }
pub impl Pair<i32> for Local { pub fn left(&self, value: i32) -> i32 { return value; } }
fn main() -> i32 {
    let a = needs(Local { v: 1 });
    let w = needs(Wrap { inner: Local { v: 2 } });
    let plain = cell(3);
    let s = plain.shadow(Local { v: 4 });
    let held = cell(Local { v: 5 });
    let i = held.inherit(6);
    let p = paired(7, Local { v: 8 });
    return 0;
}
"#;

const LIB_A: u32 = 30;
const LIB_B: u32 = 31;
const KIND_FREE_FN: u32 = 1;
const KIND_METHOD: u32 = 2;
const KIND_STRUCT: u32 = 5;
const KIND_IMPL: u32 = 7;
const KIND_TRAIT: u32 = 8;
const SCALAR_I32: u32 = 3;
const PRIVATE: u32 = 0x8000_0000;
const USE_WORDS: usize = 12;
// producer.slang failure codes.
const E_NOT_READY: u32 = 1;
const E_TRAIT_ARITY: u32 = 7;
const E_REQUIRED_MEMBER: u32 = 8;

fn compiler() -> GpuCompiler<'static> {
    pollster::block_on(GpuCompiler::new_with_backends(GpuCompilerBackends::frontend_only()))
        .expect("frontend compiler")
}

fn build(compiler: &GpuCompiler<'static>, store: &Arc<ProgramRetention>) {
    store.begin_build().unwrap();
    compiler.attach_program_retention(Some(store.clone()));
    let result = (|| {
        let library = pollster::block_on(compiler.semantic_interface_for_source_pack(LIB_A, &[LIBRARY]))?;
        pollster::block_on(compiler.semantic_interface_for_source_pack_with_dependencies(LIB_B, &[APP], &[library]))?;
        anyhow::Ok(())
    })();
    compiler.attach_program_retention(None);
    result.expect("two-unit build");
    for report in store.job_reports() {
        assert!(report.ready, "{report:?}");
        assert_eq!(report.counts[counts::INVARIANTS], 0, "{report:?}");
        assert_eq!(report.counts[counts::INCOMPLETE], 0, "{report:?}");
    }
}

fn chunks<const N: usize>(words: Vec<u32>) -> Vec<[u32; N]> {
    words.chunks_exact(N).map(|c| c.try_into().unwrap()).collect()
}

/// Store records, read for assertions only.
struct Store {
    status: Vec<u32>,
    keys: Vec<[u32; 4]>,
    params: Vec<[u32; 4]>,
    heads: Vec<[u32; 4]>,
    meta: Vec<[u32; 4]>,
    dir: Vec<[u32; 16]>,
    dir_trait: Vec<[u32; 4]>,
    binders: Vec<u32>,
    sigs: Vec<u32>,
    traits: Vec<[u32; 8]>,
    uses: Vec<[u32; USE_WORDS]>,
}

impl Store {
    fn read(store: &ProgramRetention) -> Self {
        let status = store.status().unwrap();
        let w = |name: &str, n: usize| store.read_store_words(name, n).unwrap();
        Self {
            keys: chunks(w("rt_decl_key", status[0] as usize * 4)),
            params: chunks(w("rt_param_key", status[1] as usize * 4)),
            heads: chunks(w("rt_term_head", status[2] as usize * 4)),
            meta: chunks(w("rt_term_meta", status[2] as usize * 4)),
            dir: chunks(w("rt_dir", status[4] as usize * 16)),
            dir_trait: chunks(w("rt_dir_trait", status[4] as usize * 4)),
            binders: w("rt_binders", status[5] as usize),
            sigs: w("rt_sigs", status[6] as usize),
            traits: chunks(w("rt_traits", status[14] as usize * 8)),
            uses: chunks(w("rt_uses", status[8] as usize * USE_WORDS)),
            status,
        }
    }
    fn entry_index(&self, decl: u32) -> usize {
        self.dir.iter().position(|e| e[0] == decl && e[3] == 2).unwrap_or_else(|| panic!("no entry for {decl}"))
    }
    fn entry(&self, decl: u32) -> &[u32; 16] {
        &self.dir[self.entry_index(decl)]
    }
    fn entries(&self, library: u32, kind: u32) -> Vec<u32> {
        self.dir.iter().filter(|e| e[1] == kind && e[3] == 2 && self.keys[e[0] as usize][0] == library).map(|e| e[0]).collect()
    }
    fn types(&self, decl: u32) -> u32 {
        self.entry(decl)[5] & 0xffff
    }
    fn predicates(&self, decl: u32) -> &[[u32; 8]] {
        let t = self.dir_trait[self.entry_index(decl)];
        &self.traits[t[0] as usize..(t[0] + t[1]) as usize]
    }
    fn arity(&self, term: u32) -> u32 {
        (self.heads[term as usize][0] >> 8) & 0xff
    }
    /// The single declaration of `library` and `kind` with `types` composed
    /// type parameters and `predicates` own predicates.
    fn find(&self, library: u32, kind: u32, types: u32, predicates: usize) -> u32 {
        let found = self
            .entries(library, kind)
            .into_iter()
            .filter(|&d| self.types(d) == types && self.predicates(d).len() == predicates)
            .collect::<Vec<_>>();
        assert_eq!(found.len(), 1, "library {library} kind {kind} types {types} predicates {predicates}: {found:?}");
        found[0]
    }
    fn impl_self(&self, decl: u32) -> u32 {
        self.sigs[self.entry(decl)[6] as usize]
    }
    fn impl_trait(&self, decl: u32) -> u32 {
        self.sigs[self.entry(decl)[6] as usize + 1]
    }
    /// The committed NAMED term of `decl` with no arguments.
    fn named(&self, decl: u32) -> u32 {
        (32..self.heads.len() as u32)
            .find(|&t| self.heads[t as usize][0] & 0xff == 2 && self.heads[t as usize][1] == decl && self.arity(t) == 0)
            .unwrap_or_else(|| panic!("no plain term of {decl}"))
    }
    fn job_of(&self, report: &RetainedTraitCheck, library: u32) -> u32 {
        (0..report.rows[0])
            .find(|&job| report.row(0, job).unwrap()[0] == library)
            .unwrap_or_else(|| panic!("no snapshot of library {library}"))
    }
}

/// Decoded solver rows of one obligation.
#[derive(Debug, PartialEq, Eq)]
struct Goal {
    callee: [u32; 3],
    status: u32,
    implementation: Option<[u32; 3]>,
    targets: Vec<[u32; 3]>,
    bindings: Vec<([u32; 3], String)>,
}

fn atom(report: &RetainedTraitCheck, row: u32) -> [u32; 8] {
    report.row(1, row).unwrap().try_into().unwrap()
}

/// A root reference as text: scalars, private and public nominals and
/// their arguments, parameters by (owner atom, domain, ordinal).
fn root_text(report: &RetainedTraitCheck, tag: u32, payload: u32) -> String {
    match tag {
        1 => format!("s{payload}"),
        2 | 0x8000_0002 => {
            let a = atom(report, payload);
            format!("p{}:{}", a[1], a[3] & 0xffff)
        }
        3 => {
            let node = report.row(5, payload).unwrap();
            assert_eq!(node[0], 1, "only nominal nodes in this fixture: {node:?}");
            let nominal = atom(report, node[1]);
            let args = (0..node[3])
                .map(|i| {
                    let edge = report.row(6, node[2] + i).unwrap();
                    root_text(report, edge[0], edge[1])
                })
                .collect::<Vec<_>>();
            format!("n{:?}{:?}", &nominal[..4], args)
        }
        other => format!("tag{other}:{payload}"),
    }
}

fn goals(report: &RetainedTraitCheck) -> Vec<Goal> {
    (0..report.rows[16])
        .map(|o| {
            let obligation = report.row(16, o).unwrap();
            let call = report.row(15, obligation[0]).unwrap();
            assert_eq!(obligation[2], call[4], "the obligation's environment is its call's");
            let callable = report.row(4, call[3]).unwrap();
            let callee_atom = atom(report, callable[0]);
            let env = report.row(11, call[4]).unwrap();
            let bindings = (0..env[2])
                .map(|b| {
                    let binding = report.row(12, env[1] + b).unwrap();
                    assert_eq!(binding[0], call[4]);
                    let root = report.row(7, binding[2]).unwrap();
                    let p = atom(report, binding[1]);
                    ([p[1], p[2], p[3] & 0xffff], root_text(report, root[0], root[1]))
                })
                .collect();
            let status = report.obligations[o as usize];
            let selected = report.selected_implementation(o as usize);
            let (implementation, targets) = match selected {
                Some(row) => {
                    let head = report.row(9, row).unwrap();
                    let impl_atom = atom(report, head[0]);
                    let targets = (0..head[7])
                        .map(|m| {
                            let method = report.row(10, head[6] + m).unwrap();
                            assert_eq!(method[0], row);
                            let target = atom(report, method[2]);
                            [target[1], target[2], target[3]]
                        })
                        .collect();
                    (Some([impl_atom[1], impl_atom[2], impl_atom[0]]), targets)
                }
                None => (None, Vec::new()),
            };
            Goal { callee: [callee_atom[1], callee_atom[2], callee_atom[3]], status: status[0], implementation, targets, bindings }
        })
        .collect()
}

fn check(compiler: &GpuCompiler<'static>, store: &ProgramRetention, options: RetainedTraitOptions) -> RetainedTraitCheck {
    let report = compiler.retained_trait_check(store, &RetainedTraitOptions { read_rows: true, ..options }).unwrap();
    eprintln!(
        "retained trait check: stage {:?} attempts {} failures {} first {:?} rows {:?} dispatches {} readbacks {} wait {} ns producer bytes {}",
        report.stage, report.attempts, report.producer_failures, report.first_failure, report.rows,
        report.dispatches, report.readbacks, report.readback_wait_ns, report.producer_readback_bytes
    );
    report
}

fn solved(report: &RetainedTraitCheck) -> bool {
    report.stage == RetainedTraitStage::Solved
        && report.batch_status.is_some_and(|s| s[0] == 1 && s[7] == 0)
        && report.calls.iter().all(|c| c[0] == 1)
        && report.obligations.iter().all(|o| o[0] == 1)
}

/// Expected selections, from the store's declarations.
struct Expect {
    goals: Vec<Goal>,
}

fn expected(s: &Store, report: &RetainedTraitCheck) -> Expect {
    let job_b = s.job_of(report, LIB_B);
    let job_a = s.job_of(report, LIB_A);
    let key = |d: u32| s.keys[d as usize];
    let callable = |d: u32| [key(d)[0], key(d)[1], key(d)[3]];
    let show = s.find(LIB_A, KIND_TRAIT, 1, 0);
    let pair = s.find(LIB_A, KIND_TRAIT, 2, 0);
    let needs = s.find(LIB_A, KIND_FREE_FN, 1, 1);
    let paired = s.find(LIB_A, KIND_FREE_FN, 2, 1);
    let local = s.find(LIB_B, KIND_STRUCT, 0, 0);
    let wrap = s.find(LIB_B, KIND_STRUCT, 1, 0);
    let cell_impl = s.entries(LIB_A, KIND_IMPL)[0];
    let methods = s.entries(LIB_A, KIND_METHOD);
    let shadow = *methods.iter().find(|&&m| {
        s.entry(m)[2] == cell_impl && s.predicates(m).iter().all(|p| s.params[(p[2] & 0x1fff_ffff) as usize][0] == m)
    }).unwrap();
    let inherit = *methods.iter().find(|&&m| m != shadow && s.entry(m)[2] == cell_impl).unwrap();
    let impls = s.entries(LIB_B, KIND_IMPL);
    let trait_of = |i: u32| s.heads[s.impl_trait(i) as usize][1];
    let self_of = |i: u32| s.heads[s.impl_self(i) as usize][1];
    let show_local = *impls.iter().find(|&&i| trait_of(i) == show && self_of(i) == local).unwrap();
    let show_wrap = *impls.iter().find(|&&i| trait_of(i) == show && self_of(i) == wrap).unwrap();
    let pair_local = *impls.iter().find(|&&i| trait_of(i) == pair).unwrap();
    assert!(key(local)[3] & PRIVATE != 0, "Local is private to unit B");
    let impl_id = |i: u32| Some([job_b, key(i)[3], 7]);
    let impl_methods = |i: u32| {
        s.entries(LIB_B, KIND_METHOD).into_iter().filter(|&m| s.entry(m)[2] == i).map(callable).collect::<Vec<_>>()
    };
    let local_text = format!("n{:?}{:?}", [2, job_b, key(local)[3] & !PRIVATE, 0], Vec::<String>::new());
    let wrap_text = format!("n{:?}{:?}", [2, job_b, key(wrap)[3] & !PRIVATE, 0], vec![local_text.clone()]);
    let binder = |d: u32| -> u32 {
        (0..report.rows[1]).find(|&a| atom(report, a)[..4] == [4, job_a, key(d)[2], key(d)[3]]).unwrap()
    };
    let param = |owner: u32, ordinal: u32| [binder(owner), 0, ordinal];
    let goal = |callee: u32, i: u32, bindings: Vec<([u32; 3], String)>| Goal {
        callee: callable(callee),
        status: 1,
        implementation: impl_id(i),
        targets: impl_methods(i),
        bindings,
    };
    let i32_text = format!("s{SCALAR_I32}");
    Expect {
        goals: vec![
            goal(needs, show_local, vec![(param(needs, 0), local_text.clone())]),
            goal(needs, show_wrap, vec![(param(needs, 0), wrap_text)]),
            // `shadow`'s own T shadows the impl's T; the impl's slot comes first.
            goal(shadow, show_local, vec![(param(cell_impl, 0), i32_text.clone()), (param(shadow, 0), local_text.clone())]),
            // `inherit` bounds the impl's T, inherited through its parent.
            goal(inherit, show_local, vec![(param(cell_impl, 0), local_text.clone()), (param(inherit, 0), i32_text.clone())]),
            goal(paired, pair_local, vec![(param(paired, 0), i32_text), (param(paired, 1), local_text)]),
        ],
    }
}

fn sorted(mut goals: Vec<Goal>) -> Vec<Goal> {
    goals.sort_by(|a, b| format!("{a:?}").cmp(&format!("{b:?}")));
    goals
}

#[test]
fn retained_trait_catalog_selects_cross_unit_implementations_on_gpu() {
    let compiler = compiler();
    let store = ProgramRetention::new(ProgramRetentionCapacity::default()).unwrap();
    build(&compiler, &store);

    // Only the store remains: frontend storage released, scratch poisoned.
    pollster::block_on(compiler.release_resident_job_buffers());
    store.poison_scratch();
    let s = Store::read(&store);
    let generation = store.generation();

    // Every catalog and batch word starts poisoned; admission accepts only
    // complete rows.
    let report = check(&compiler, &store, RetainedTraitOptions { poison_arenas: true, ..Default::default() });
    assert!(solved(&report), "{report:#?}");
    assert_eq!((report.producer_failures, report.fill_faults, report.unsupported_member_bounds), (0, 0, 0));
    assert_eq!(report.generation, generation);
    assert_eq!(report.attempts, 1);
    assert_eq!(report.catalog_status.unwrap()[0], 1);
    assert_eq!(report.rows[0], 2, "one snapshot per committed job");
    for job in 0..2 {
        assert_eq!(report.row(0, job).unwrap()[3], generation, "snapshots carry the build generation");
    }
    let expect = expected(&s, &report);
    assert_eq!(sorted(goals(&report)), sorted(expect.goals), "selected implementations, native targets and environments");
    let first_goals = goals(&report);

    // Reused solver storage, unpoisoned: the same rows and selections.
    let again = check(&compiler, &store, RetainedTraitOptions::default());
    assert!(solved(&again));
    assert_eq!(goals(&again), first_goals);

    // A full unit table grows and the producer runs again from the store.
    let grown = check(&compiler, &store, RetainedTraitOptions { unit_slots: Some(1), ..Default::default() });
    assert_eq!(grown.attempts, 2, "{grown:#?}");
    assert!(solved(&grown));
    assert_eq!(goals(&grown), first_goals);

    // Faults below rewrite one store word and restore it.
    let fault = |name: &str, offset: usize, value: u32, verify: &dyn Fn(&RetainedTraitCheck)| {
        let original = store.read_store_words(name, offset + 1).unwrap()[offset];
        store.write_store_words(name, offset as u64, &[value]).unwrap();
        let report = check(&compiler, &store, RetainedTraitOptions::default());
        store.write_store_words(name, offset as u64, &[original]).unwrap();
        verify(&report);
    };

    // Refuted obligation: `needs(Local)` with its environment argument
    // rewritten to i32, which has no Show impl.
    let needs = s.find(LIB_A, KIND_FREE_FN, 1, 1);
    let local = s.find(LIB_B, KIND_STRUCT, 0, 0);
    let local_term = s.named(local);
    let env = s
        .uses
        .iter()
        .filter(|u| u[3] == needs)
        .map(|u| u[4])
        .find(|&env| {
            let base = s.meta[env as usize][0] as usize;
            store.read_store_words("rt_term_args", base + 1).unwrap()[base] == local_term
        })
        .expect("the use of needs(Local)");
    fault("rt_term_args", s.meta[env as usize][0] as usize, SCALAR_I32, &|r| {
        assert_eq!(r.stage, RetainedTraitStage::Solved, "{r:#?}");
        assert!(!solved(r), "i32: Show has no evidence: {r:#?}");
        let unproven = r.obligations.iter().filter(|o| !matches!(o[0], 1 | 2)).count();
        assert_eq!(unproven, 1, "only the faulted obligation is unproven: {:?}", r.obligations);
    });

    // Coherence: the generic Wrap impl's self type rewritten to Local
    // overlaps `impl Show for Local`.
    let wrap = s.find(LIB_B, KIND_STRUCT, 1, 0);
    let impls = s.entries(LIB_B, KIND_IMPL);
    let show_wrap = *impls.iter().find(|&&i| s.heads[s.impl_self(i) as usize][1] == wrap).unwrap();
    fault("rt_sigs", s.entry(show_wrap)[6] as usize, local_term, &|r| {
        assert_eq!(r.stage, RetainedTraitStage::Admission, "{r:#?}");
        assert_ne!(r.catalog_status.unwrap()[0], 1);
        assert!(r.obligations.is_empty(), "no solve over a rejected catalog");
    });

    // Swapped type slots of `shadow` (impl T, own T): never a solved check.
    let cell_impl = s.entries(LIB_A, KIND_IMPL)[0];
    let shadow = *s
        .entries(LIB_A, KIND_METHOD)
        .iter()
        .find(|&&m| s.entry(m)[2] == cell_impl && s.predicates(m).iter().all(|p| s.params[(p[2] & 0x1fff_ffff) as usize][0] == m))
        .unwrap();
    let start = s.entry(shadow)[4] as usize;
    let (outer, own) = (s.binders[start], s.binders[start + 1]);
    store.write_store_words("rt_binders", start as u64, &[own, outer]).unwrap();
    let swapped = check(&compiler, &store, RetainedTraitOptions::default());
    store.write_store_words("rt_binders", start as u64, &[outer, own]).unwrap();
    assert!(!solved(&swapped), "swapped slots are rejected or refuted: {swapped:#?}");

    // Trait arity against the defining binder: Pair applied to no argument.
    let pair_local = *impls.iter().find(|&&i| s.arity(s.impl_trait(i)) == 1).unwrap();
    let pair_term = s.impl_trait(pair_local);
    let head = s.heads[pair_term as usize][0];
    fault("rt_term_head", pair_term as usize * 4, head & !0xff00, &|r| {
        assert_eq!(r.stage, RetainedTraitStage::Producer);
        assert_eq!(r.first_failure.map(|f| f.0), Some(E_TRAIT_ARITY), "{r:#?}");
    });

    // A binding whose required member is the impl's own method.
    let t = s.dir_trait[s.entry_index(pair_local)];
    assert_eq!(t[3], 1, "one binding");
    let binding = t[2] as usize;
    fault("rt_traits", binding * 8 + 2, s.traits[binding][3], &|r| {
        assert_eq!(r.stage, RetainedTraitStage::Producer);
        assert_eq!(r.first_failure.map(|f| f.0), Some(E_REQUIRED_MEMBER), "{r:#?}");
    });

    // A store that is not READY, or of another build generation.
    fault("rt_counts", counts::READY, 0, &|r| {
        assert_eq!(r.first_failure.map(|f| f.0), Some(E_NOT_READY), "{r:#?}");
    });
    fault("rt_counts", counts::GENERATION, generation.wrapping_add(1), &|r| {
        assert_eq!(r.first_failure.map(|f| f.0), Some(E_NOT_READY), "{r:#?}");
    });

    // A fresh build of the same store: new generation, same selections.
    let rebuilt_compiler = compiler_for_rebuild();
    build(&rebuilt_compiler, &store);
    pollster::block_on(rebuilt_compiler.release_resident_job_buffers());
    store.poison_scratch();
    let fresh = check(&compiler, &store, RetainedTraitOptions { poison_arenas: true, ..Default::default() });
    assert_ne!(fresh.generation, generation);
    assert!(solved(&fresh), "{fresh:#?}");
    let s2 = Store::read(&store);
    assert_eq!(sorted(goals(&fresh)), sorted(expected(&s2, &fresh).goals));
    assert_eq!(s.status[counts::JOBS], s2.status[counts::JOBS]);
}

fn compiler_for_rebuild() -> GpuCompiler<'static> {
    compiler()
}
