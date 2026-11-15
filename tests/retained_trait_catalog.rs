//! The program trait catalog built on the GPU from the retention store
//! (docs/compiler-retained-trait-catalog.md). Two frontend jobs export into
//! one store: the traits and generic functions are in unit A, and the impls
//! and private self types are in unit B. The frontend's storage is released
//! and exporter scratch is poisoned. The GPU producer then writes the
//! solver's catalog and batch rows, and the production admission,
//! coherence and proof kernels select implementations. The test reads rows
//! back for assertions only.

use std::sync::{Arc, LazyLock};

use laniusc_compiler::{
    compiler::{
        GpuCompiler, GpuCompilerBackends, RetainedTraitCheck, RetainedTraitOptions, RetainedTraitPublication,
        RetainedTraitStage,
    },
    type_checker::program_retention::{ProgramRetention, ProgramRetentionCapacity, counts},
};

#[allow(unused_imports)]
use crate::common;

/// Members of the wide trait, and the order in which unit B's impl lists
/// their methods (an independent permutation).
const WIDE: u32 = 40;
fn wide_order() -> Vec<u32> {
    (0..WIDE).map(|i| (i * 17 + 5) % WIDE).collect()
}

static LIBRARY: LazyLock<String> = LazyLock::new(|| {
    let members = (0..WIDE).map(|i| format!("    pub fn w{i:02}(&self) -> i32;\n")).collect::<String>();
    format!("{LIBRARY_BASE}pub trait Wide {{\n{members}}}\npub fn wide<T: Wide>(value: T) -> T {{ return value; }}\n")
});
static APP: LazyLock<String> = LazyLock::new(|| {
    let methods = wide_order().into_iter().map(|i| format!("    pub fn w{i:02}(&self) -> i32 {{ return {i}; }}\n")).collect::<String>();
    format!("{APP_BASE}pub impl Wide for Local {{\n{methods}}}\n")
});

const LIBRARY_BASE: &str = r#"module rtc::a;
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
pub fn shown<T: Show>(value: T) -> i32 { return 0; }
pub fn outer<T: Show>(value: T) -> i32 { return shown(value); }
pub impl<T: Show> Show for Cell<T> { pub fn show(&self) -> i32 { return 3; } }
pub struct Grid<T, const N: u32> { value: T }
pub impl<T: Show, const N: u32> Show for Grid<T, N> { pub fn show(&self) -> i32 { return 4; } }
"#;

const APP_BASE: &str = r#"module rtc::b;
import rtc::a;
struct Local { v: i32 }
struct Wrap<T> { inner: T }
struct Other { v: i32 }
pub impl Show for Local { pub fn show(&self) -> i32 { return 1; } }
pub impl<T: Show> Show for Wrap<T> { pub fn show(&self) -> i32 { return 2; } }
pub impl Pair<i32> for Local { pub fn left(&self, value: i32) -> i32 { return value; } }
pub impl Show for Other { pub fn show(&self) -> i32 { return 5; } }
// A Grid value only as a parameter: the export does not complete a struct
// literal of a const-generic struct yet.
fn take(g: Grid<Local, 4>) -> i32 { let h = needs(g); return 0; }
// Stored compound terms that no solver row references.
fn unrelated() -> i32 { let q = Wrap { inner: Wrap { inner: Other { v: 1 } } }; return 0; }
fn main() -> i32 {
    let a = needs(Local { v: 1 });
    let w = needs(Wrap { inner: Local { v: 2 } });
    let plain = cell(3);
    let s = plain.shadow(Local { v: 4 });
    let held = cell(Local { v: 5 });
    let i = held.inherit(6);
    let p = paired(7, Local { v: 8 });
    let o = outer(Local { v: 9 });
    let c = needs(cell(Local { v: 10 }));
    let d = wide(Local { v: 12 });
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
const KIND_REQUIRED_MEMBER: u32 = 3;
const RT_KIND_CC_VALUE: u32 = 8;
const SCALAR_I32: u32 = 3;
const PRIVATE: u32 = 0x8000_0000;
const USE_WORDS: usize = 12;
// producer.slang failure codes.
const E_NOT_READY: u32 = 1;
const E_PARAM_OWNER: u32 = 4;
const E_NOMINAL: u32 = 5;
const E_TRAIT_ARITY: u32 = 7;
const E_REQUIRED_MEMBER: u32 = 8;
const E_BINDING_COVERAGE: u32 = 10;
const E_SLOT: u32 = 12;
// The solver's catalog receipt (state, detail) for an overlapping impl
// pair: TS_COHERENCE_CONFLICT (abi.slang), detail 0.
const E_COHERENCE_STATUS: [u32; 2] = [5, 0];
// TS_INVALID_INPUT detail 84, observed when a generic impl head loses its
// parameter (T no longer appears in the self type).
const E_UNCOVERED_STATUS: [u32; 2] = [2, 84];

fn compiler() -> GpuCompiler<'static> {
    pollster::block_on(GpuCompiler::new_with_backends(GpuCompilerBackends::frontend_only()))
        .expect("frontend compiler")
}

fn build(compiler: &GpuCompiler<'static>, store: &Arc<ProgramRetention>) {
    store.begin_build().unwrap();
    compiler.attach_program_retention(Some(store.clone()));
    let result = (|| {
        let library = pollster::block_on(compiler.semantic_interface_for_source_pack(LIB_A, &[LIBRARY.as_str()]))?;
        pollster::block_on(compiler.semantic_interface_for_source_pack_with_dependencies(LIB_B, &[APP.as_str()], &[library]))?;
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
    args: Vec<u32>,
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
            args: w("rt_term_args", status[3] as usize),
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

// retention_store.slang term kinds and flags.
const RT_KIND_NAMED: u32 = 2;
const RT_KIND_ARRAY: u32 = 3;
const RT_KIND_SLICE: u32 = 4;
const RT_KIND_REF: u32 = 5;
const RT_KIND_CC_CAST: u32 = 9;
const RT_KIND_CC_COUNT: u32 = 10;
const RTF_SLOT: u32 = 4;
const SCALAR_U32: u32 = 4;

impl Store {
    fn stored(&self, r: u32) -> bool {
        r >= 32 && (r as usize) < self.heads.len() && r < 0x8000_0000
    }
    fn kind(&self, t: u32) -> u32 {
        self.heads[t as usize][0] & 0xff
    }
    fn term_args(&self, t: u32) -> &[u32] {
        let base = self.meta[t as usize][0] as usize;
        &self.args[base..base + self.arity(t) as usize]
    }
    fn has_node(&self, t: u32) -> bool {
        matches!(self.kind(t), RT_KIND_NAMED | RT_KIND_ARRAY | RT_KIND_SLICE | RT_KIND_REF | RT_KIND_CC_CAST)
            && self.meta[t as usize][1] & RTF_SLOT == 0
    }
    /// The term closure the producer must compute, from store records and
    /// the selected uses (`calls`: the use of each call row). Assertions only.
    fn closure(&self, selected_uses: &[u32]) -> std::collections::BTreeSet<u32> {
        let mut roots = Vec::new();
        for e in &self.dir {
            if e[3] == 2 && e[1] == KIND_IMPL && self.stored(self.sigs[e[6] as usize + 1]) {
                roots.push(self.sigs[e[6] as usize]);
                roots.extend_from_slice(self.term_args(self.sigs[e[6] as usize + 1]));
            }
        }
        for t in &self.traits {
            let owner = self.dir.iter().find(|e| e[0] == t[0] && e[3] == 2).map(|e| e[1]);
            if t[1] & 0xff == 1 && matches!(owner, Some(KIND_FREE_FN | KIND_METHOD | KIND_IMPL)) {
                roots.push(t[2]);
                if self.stored(t[3]) {
                    roots.extend_from_slice(self.term_args(t[3]));
                }
            }
        }
        for &u in selected_uses {
            roots.extend_from_slice(self.term_args(self.uses[u as usize][4]));
        }
        let mut seen = std::collections::BTreeSet::new();
        while let Some(r) = roots.pop() {
            if !self.stored(r) || !seen.insert(r) {
                continue;
            }
            if self.has_node(r) {
                roots.extend_from_slice(self.term_args(r));
            } else if self.kind(r) == RT_KIND_CC_VALUE {
                let h = self.heads[r as usize];
                if h[1] == SCALAR_U32 && h[3] == 0 {
                    roots.extend((32..self.heads.len() as u32).filter(|&c| self.kind(c) == RT_KIND_CC_COUNT && self.heads[c as usize][1] == h[2]));
                }
            }
        }
        seen
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
        && report.calls.iter().all(|c| matches!(c[0], 1 | 2))
        && report.obligations.iter().all(|o| matches!(o[0], 1 | 2))
}

/// The fixture's declarations, identified from store records only.
struct Decls {
    show: u32,
    pair: u32,
    wide: u32,
    needs: u32,
    outer: u32,
    shown: u32,
    paired: u32,
    wide_fn: u32,
    local: u32,
    wrap: u32,
    grid: u32,
    other: u32,
    cell_inherent: u32,
    cell_show: u32,
    grid_show: u32,
    show_local: u32,
    show_wrap: u32,
    show_other: u32,
    pair_local: u32,
    wide_local: u32,
    shadow: u32,
    inherit: u32,
}

impl Store {
    fn members(&self, trait_decl: u32) -> Vec<u32> {
        self.entries(LIB_A, KIND_REQUIRED_MEMBER).into_iter().filter(|&m| self.entry(m)[2] == trait_decl).collect()
    }
    fn trait_of(&self, i: u32) -> u32 {
        self.heads[self.impl_trait(i) as usize][1]
    }
    fn self_of(&self, i: u32) -> u32 {
        self.heads[self.impl_self(i) as usize][1]
    }
    fn bindings(&self, i: u32) -> &[[u32; 8]] {
        let t = self.dir_trait[self.entry_index(i)];
        &self.traits[t[2] as usize..(t[2] + t[3]) as usize]
    }
    /// The method of impl `i` bound to required member `required`.
    fn method_for(&self, i: u32, required: u32) -> u32 {
        self.bindings(i).iter().find(|b| b[0] == i && b[2] == required).map(|b| b[3]).unwrap()
    }
    fn impl_params(&self, i: u32) -> Vec<u32> {
        let e = self.entry(i);
        let k = (e[5] & 0xffff) + (e[5] >> 16);
        self.binders[e[4] as usize..(e[4] + k) as usize].to_vec()
    }
    fn decls(&self) -> Decls {
        let one = |found: Vec<u32>, what: &str| -> u32 {
            assert_eq!(found.len(), 1, "{what}: {found:?}");
            found[0]
        };
        let traits = self.entries(LIB_A, KIND_TRAIT);
        let show = one(traits.iter().copied().filter(|&t| self.types(t) == 1 && self.members(t).len() == 1).collect(), "Show");
        let pair = one(traits.iter().copied().filter(|&t| self.types(t) == 2).collect(), "Pair");
        let wide = one(traits.iter().copied().filter(|&t| self.members(t).len() == WIDE as usize).collect(), "Wide");
        let fns = self.entries(LIB_A, KIND_FREE_FN);
        let bound = |d: u32, t: u32| self.predicates(d).len() == 1 && self.predicates(d)[0][4] == t;
        let leaf = |d: u32| self.predicates(d)[0][2] & 0x8000_0000 != 0;
        let calls = |d: u32| self.uses.iter().any(|u| u[0] == d);
        let paired = one(fns.iter().copied().filter(|&d| bound(d, pair)).collect(), "paired");
        let wide_fn = one(fns.iter().copied().filter(|&d| bound(d, wide)).collect(), "wide");
        let outer = one(fns.iter().copied().filter(|&d| bound(d, show) && leaf(d) && calls(d)).collect(), "outer");
        let called_by_outer = |d: u32| self.uses.iter().any(|u| u[0] == outer && u[3] == d);
        let shown = one(fns.iter().copied().filter(|&d| bound(d, show) && leaf(d) && called_by_outer(d)).collect(), "shown");
        let needs = one(fns.iter().copied().filter(|&d| bound(d, show) && leaf(d) && !calls(d) && d != shown).collect(), "needs");
        let impls_b = self.entries(LIB_B, KIND_IMPL);
        let pair_local = one(impls_b.iter().copied().filter(|&i| self.trait_of(i) == pair).collect(), "Pair for Local");
        let local = self.self_of(pair_local);
        let wrap = self.find(LIB_B, KIND_STRUCT, 1, 0);
        let structs_b = self.entries(LIB_B, KIND_STRUCT);
        let other = one(structs_b.iter().copied().filter(|&d| d != local && d != wrap).collect(), "Other");
        assert!(leaf(paired) && leaf(needs), "parameter subjects");
        let grid = one(self.entries(LIB_A, KIND_STRUCT).into_iter().filter(|&d| self.entry(d)[5] >> 16 == 1).collect(), "Grid");
        let in_b = |t: u32, own: u32| one(impls_b.iter().copied().filter(|&i| self.trait_of(i) == t && self.self_of(i) == own).collect(), "impl in B");
        let impls_a = self.entries(LIB_A, KIND_IMPL);
        let cell_inherent = one(impls_a.iter().copied().filter(|&i| self.dir_trait[self.entry_index(i)][3] == 0).collect(), "impl Cell");
        let cell = self.self_of(cell_inherent);
        let in_a = |own: u32| one(impls_a.iter().copied().filter(|&i| i != cell_inherent && self.self_of(i) == own).collect(), "impl in A");
        let methods = self.entries(LIB_A, KIND_METHOD);
        let shadow = *methods
            .iter()
            .find(|&&m| self.entry(m)[2] == cell_inherent && self.predicates(m).iter().all(|p| self.params[(p[2] & 0x1fff_ffff) as usize][0] == m))
            .unwrap();
        let inherit = *methods.iter().find(|&&m| m != shadow && self.entry(m)[2] == cell_inherent).unwrap();
        Decls {
            show,
            pair,
            wide,
            needs,
            outer,
            shown,
            paired,
            wide_fn,
            local,
            wrap,
            grid,
            other,
            cell_inherent,
            cell_show: in_a(cell),
            grid_show: in_a(grid),
            show_local: in_b(show, local),
            show_wrap: in_b(show, wrap),
            show_other: in_b(show, other),
            pair_local,
            wide_local: in_b(wide, local),
            shadow,
            inherit,
        }
    }
}

/// Expected selections, from the store's declarations. The goal of
/// `needs(Grid<Local, 4>)` is checked separately (`grid_goal`).
fn expected(s: &Store, report: &RetainedTraitCheck) -> Vec<Goal> {
    let d = s.decls();
    let job_b = s.job_of(report, LIB_B);
    let job_a = s.job_of(report, LIB_A);
    let key = |d: u32| s.keys[d as usize];
    let callable = |d: u32| [key(d)[0], key(d)[1], key(d)[3]];
    assert!(key(d.local)[3] & PRIVATE != 0, "Local is private to unit B");
    let impl_id = |i: u32| Some([if key(i)[0] == LIB_A { job_a } else { job_b }, key(i)[3], 7]);
    // Method rows are in increasing required symbol.
    let impl_methods = |i: u32| {
        let mut bindings = s.bindings(i).to_vec();
        bindings.sort_by_key(|b| b[5]);
        bindings.iter().map(|b| callable(b[3])).collect::<Vec<_>>()
    };
    let local_text = format!("n{:?}{:?}", [2, job_b, key(d.local)[3] & !PRIVATE, 0], Vec::<String>::new());
    let wrap_text = format!("n{:?}{:?}", [2, job_b, key(d.wrap)[3] & !PRIVATE, 0], vec![local_text.clone()]);
    let cell = s.self_of(d.cell_inherent);
    let cell_text = format!("n{:?}{:?}", [1, key(cell)[0], key(cell)[1], key(cell)[3]], vec![local_text.clone()]);
    let binder = |o: u32| -> u32 {
        (0..report.rows[1]).find(|&a| atom(report, a)[..4] == [4, job_a, key(o)[2], key(o)[3]]).unwrap()
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
    vec![
        goal(d.needs, d.show_local, vec![(param(d.needs, 0), local_text.clone())]),
        goal(d.needs, d.show_wrap, vec![(param(d.needs, 0), wrap_text)]),
        // `shadow`'s own T shadows the impl's T; the impl's slot comes first.
        goal(d.shadow, d.show_local, vec![(param(d.cell_inherent, 0), i32_text.clone()), (param(d.shadow, 0), local_text.clone())]),
        // `inherit` bounds the impl's T, inherited through its parent.
        goal(d.inherit, d.show_local, vec![(param(d.cell_inherent, 0), local_text.clone()), (param(d.inherit, 0), i32_text.clone())]),
        goal(d.paired, d.pair_local, vec![(param(d.paired, 0), i32_text), (param(d.paired, 1), local_text.clone())]),
        goal(d.outer, d.show_local, vec![(param(d.outer, 0), local_text.clone())]),
        // Inside the generic `outer`, `shown(value)` is proven by outer's own bound.
        Goal {
            callee: callable(d.shown),
            status: 2,
            implementation: None,
            targets: Vec::new(),
            bindings: vec![(param(d.shown, 0), format!("p{}:0", binder(d.outer)))],
        },
        // `impl<T: Show> Show for Cell<T>`, whose own bound needs Local: Show.
        goal(d.needs, d.cell_show, vec![(param(d.needs, 0), cell_text)]),
        goal(d.wide_fn, d.wide_local, vec![(param(d.wide_fn, 0), local_text)]),
    ]
}

/// Whether `goal` is `needs(Grid<Local, 4>)`, with a binding over the
/// public Grid nominal applied to Local and a constant.
fn grid_goal(s: &Store, report: &RetainedTraitCheck, goal: &Goal) -> bool {
    let d = s.decls();
    let key = s.keys[d.grid as usize];
    let job_a = s.job_of(report, LIB_A);
    goal.implementation == Some([job_a, s.keys[d.grid_show as usize][3], 7])
        && goal.bindings.len() == 1
        && goal.bindings[0].1.starts_with(&format!("n{:?}", [1, key[0], key[1], key[3]]))
}

fn sorted(mut goals: Vec<Goal>) -> Vec<Goal> {
    goals.sort_by(|a, b| format!("{a:?}").cmp(&format!("{b:?}")));
    goals
}

/// The goals of a solved check, the Grid goal asserted and removed.
fn checked_goals(s: &Store, report: &RetainedTraitCheck) -> Vec<Goal> {
    let mut all = goals(report);
    let grid = all.iter().position(|g| grid_goal(s, report, g)).unwrap_or_else(|| panic!("no Grid goal: {all:#?}"));
    let g = all.remove(grid);
    assert_eq!(g.status, 1, "{g:?}");
    eprintln!("grid goal binding: {}", g.bindings[0].1);
    sorted(all)
}

// tests/retained_route_query.slang answers.
const RQ_FOUND: u32 = 1;
const RQ_HEADER: u32 = 2;
const RQ_STALE: u32 = 3;
const RQ_NOT_IMPL: u32 = 6;

/// One GPU route query and the answer the store's records require.
struct Query {
    request: [u32; 3],
    status: u32,
    implementation: u32,
    method: u32,
    /// (ParamId, NAMED DeclId) of each type binding; constant bindings are
    /// checked by tag.
    bindings: Vec<(u32, Option<u32>)>,
}

fn use_of(s: &Store, store: &ProgramRetention, callee: u32, arg0: u32) -> u32 {
    let found = (0..s.uses.len() as u32)
        .filter(|&u| {
            let r = s.uses[u as usize];
            r[3] == callee && {
                let base = s.meta[r[4] as usize][0] as usize;
                store.read_store_words("rt_term_args", base + 1).unwrap()[base] == arg0
            }
        })
        .collect::<Vec<_>>();
    assert_eq!(found.len(), 1, "use of {callee} with {arg0}");
    found[0]
}

fn queries(s: &Store, store: &ProgramRetention) -> Vec<Query> {
    let d = s.decls();
    let local_term = s.named(d.local);
    let symbol = |m: u32| s.keys[m as usize][3];
    let show_member = s.members(d.show)[0];
    let found = |use_index: u32, i: u32, member: u32, bindings: Vec<(u32, Option<u32>)>| Query {
        request: [use_index, 0, symbol(member)],
        status: RQ_FOUND,
        implementation: i,
        method: s.method_for(i, member),
        bindings,
    };
    let needs_local = use_of(s, store, d.needs, local_term);
    let wrap_use = s
        .uses
        .iter()
        .position(|u| u[3] == d.needs && {
            let base = s.meta[u[4] as usize][0] as usize;
            let arg = store.read_store_words("rt_term_args", base + 1).unwrap()[base];
            arg >= 32 && arg < 0x8000_0000 && s.heads[arg as usize][1] == d.wrap
        })
        .unwrap() as u32;
    let arg_use = |nominal: u32| {
        s.uses
            .iter()
            .position(|u| u[3] == d.needs && {
                let base = s.meta[u[4] as usize][0] as usize;
                let arg = store.read_store_words("rt_term_args", base + 1).unwrap()[base];
                arg >= 32 && arg < 0x8000_0000 && s.heads[arg as usize][1] == nominal
            })
            .unwrap() as u32
    };
    let grid_use = s
        .uses
        .iter()
        .position(|u| u[3] == d.needs && {
            let base = s.meta[u[4] as usize][0] as usize;
            let arg = store.read_store_words("rt_term_args", base + 1).unwrap()[base];
            arg >= 32 && arg < 0x8000_0000 && s.heads[arg as usize][1] == d.grid
        })
        .unwrap() as u32;
    let inner = s.uses.iter().position(|u| u[0] == d.outer && u[3] == d.shown).unwrap() as u32;
    let mut all = vec![
        found(needs_local, d.show_local, show_member, vec![]),
        found(wrap_use, d.show_wrap, show_member, vec![(s.impl_params(d.show_wrap)[0], Some(d.local))]),
        found(arg_use(s.self_of(d.cell_inherent)), d.cell_show, show_member, vec![(s.impl_params(d.cell_show)[0], Some(d.local))]),
        found(grid_use, d.grid_show, show_member, {
            let p = s.impl_params(d.grid_show);
            vec![(p[0], Some(d.local)), (p[1], None)]
        }),
        found(use_of(s, store, d.outer, local_term), d.show_local, show_member, vec![]),
        found(
            s.uses.iter().position(|u| u[3] == d.paired).unwrap() as u32,
            d.pair_local,
            s.members(d.pair)[0],
            vec![],
        ),
        Query { request: [inner, 0, symbol(show_member)], status: RQ_NOT_IMPL, implementation: 0, method: 0, bindings: vec![] },
    ];
    let wide_use = use_of(s, store, d.wide_fn, local_term);
    for member in s.members(d.wide) {
        all.push(found(wide_use, d.wide_local, member, vec![]));
    }
    all
}

fn assert_answers(queries: &[Query], answers: &[[u32; 16]]) {
    assert_eq!(queries.len(), answers.len());
    for (q, a) in queries.iter().zip(answers) {
        assert_eq!(a[0], q.status, "request {:?}: {a:?}", q.request);
        if q.status != RQ_FOUND {
            continue;
        }
        assert_eq!((a[1], a[2]), (q.implementation, q.method), "selected impl and native target of {:?}", q.request);
        assert_eq!(a[3] as usize, q.bindings.len(), "binding count of {:?}: {a:?}", q.request);
        for (b, &(param, decl)) in q.bindings.iter().enumerate() {
            let (id, tag, value) = (a[4 + b * 3], a[5 + b * 3], a[6 + b * 3]);
            assert_eq!(id, param, "binding {b} parameter of {:?}: {a:?}", q.request);
            match decl {
                Some(decl) => assert_eq!((tag, value), (3, decl), "binding {b} of {:?}: {a:?}", q.request),
                None => assert_ne!(tag, 3, "a constant binding of {:?}: {a:?}", q.request),
            }
        }
    }
}

#[test]
fn retained_trait_catalog_keeps_empty_unit_snapshots() {
    let compiler = compiler();
    let mut capacity = ProgramRetentionCapacity::default();
    capacity.arenas[15] = 1;
    let store = ProgramRetention::new(capacity).unwrap();
    for (build, empty_library) in [32, 33].into_iter().enumerate() {
        store.begin_build().unwrap();
        compiler.attach_program_retention(Some(store.clone()));
        let library = pollster::block_on(compiler.semantic_interface_for_source_pack(LIB_A, &[LIBRARY.as_str()])).unwrap();
        let before = store.status().unwrap()[4];
        pollster::block_on(compiler.semantic_interface_for_source_pack_with_dependencies(
            empty_library, &["module rtc::empty; import rtc::a;"], std::slice::from_ref(&library),
        )).unwrap();
        assert_eq!(store.status().unwrap()[4], before, "the import-only job has no directory entries");
        pollster::block_on(compiler.semantic_interface_for_source_pack_with_dependencies(LIB_B, &[APP.as_str()], &[library])).unwrap();
        compiler.attach_program_retention(None);
        let reports = store.job_reports();
        assert_eq!(reports.len(), 3);
        assert!(reports.iter().all(|r| r.ready));
        assert_eq!(reports[1].attempts, if build == 0 { 2 } else { 1 }, "job-arena overflow retries once; the next build reuses capacity");
        let status = store.status().unwrap();
        assert_eq!((status[15], status[counts::JOBS]), (3, 3), "only committed job rows are retained");
        assert_eq!(status[counts::ROLLBACKS], if build == 0 { 1 } else { 0 });
        pollster::block_on(compiler.release_resident_job_buffers());
        store.poison_scratch();
        let report = check(&compiler, &store, RetainedTraitOptions::default());
        assert!(solved(&report), "{report:#?}");
        assert_eq!(report.rows[0], 3);
        let jobs = chunks::<4>(store.read_store_words("rt_jobs", 12).unwrap());
        for (job, library) in [LIB_A, empty_library, LIB_B].into_iter().enumerate() {
            assert_eq!(jobs[job], [library, 0, store.generation(), 0], "no stale or rolled-back job row");
            assert_eq!(report.row(0, job as u32).unwrap(), [library, 0, job as u32, store.generation()]);
        }
    }
    store.write_store_words("rt_jobs", 6, &[store.generation() - 1]).unwrap();
    let stale = check(&compiler, &store, RetainedTraitOptions::default());
    assert_eq!(stale.stage, RetainedTraitStage::Producer);
    assert_eq!(stale.first_failure.map(|f| f.0), Some(2), "a stale empty-unit record fails SNAPSHOT");
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
    let d = s.decls();
    let generation = store.generation();

    // Every catalog and batch word starts poisoned; admission accepts only
    // complete rows.
    let report = check(&compiler, &store, RetainedTraitOptions { poison_arenas: true, ..Default::default() });
    assert!(solved(&report), "{report:#?}");
    assert_eq!((report.producer_failures, report.fill_faults, report.unsupported_member_bounds), (0, 0, 0));
    assert_eq!(report.publication_status, Some([1, 0, u32::MAX]), "a valid publication");
    assert_eq!(report.generation, generation);
    assert_eq!(report.attempts, 1);
    assert_eq!(report.catalog_status.unwrap()[0], 1);
    assert_eq!(report.rows[0], 2, "one snapshot per committed job");
    for job in 0..2 {
        assert_eq!(report.row(0, job).unwrap()[3], generation, "snapshots carry the build generation");
    }
    // Only calls with an applicable predicate are goals. `grid` and `cell`
    // have none; every use in this fixture calls a store callable.
    assert_eq!(report.rows[15], 10, "goal calls");
    assert!(report.plain_calls >= 2, "{}", report.plain_calls);
    eprintln!("plain calls {} unsupported callees {}", report.plain_calls, report.unsupported_callees);
    let expect = expected(&s, &report);
    assert_eq!(checked_goals(&s, &report), sorted(expect), "selected implementations, native targets and environments");
    let first_goals = goals(&report);

    // Term closure: exactly the terms reachable from the solver's roots, one
    // node per distinct term, no row for unrelated stored terms.
    let selected = (0..report.rows[15]).map(|c| report.row(15, c).unwrap()[1]).collect::<Vec<_>>();
    let closure = s.closure(&selected);
    let nodes = closure.iter().filter(|&&t| s.has_node(t)).count() as u32;
    let edges = closure.iter().filter(|&&t| s.has_node(t) && s.kind(t) == RT_KIND_NAMED).map(|&t| s.arity(t)).sum::<u32>();
    assert_eq!(report.closure_terms, closure.len() as u32, "closure terms");
    assert_eq!((report.rows[5], report.rows[6]), (nodes, edges), "catalog nodes and edges are the closure's");
    let all_nodes = (32..s.heads.len() as u32).filter(|&t| s.has_node(t)).count() as u32;
    let wrap_other = (32..s.heads.len() as u32)
        .find(|&t| s.kind(t) == RT_KIND_NAMED && s.heads[t as usize][1] == d.wrap && s.term_args(t) == [s.named(d.other)])
        .expect("Wrap<Other> is stored");
    let wrap_wrap = (32..s.heads.len() as u32)
        .find(|&t| s.kind(t) == RT_KIND_NAMED && s.heads[t as usize][1] == d.wrap && s.term_args(t) == [wrap_other])
        .expect("Wrap<Wrap<Other>> is stored");
    assert!(!closure.contains(&wrap_other) && !closure.contains(&wrap_wrap), "unrelated terms are outside the closure");
    assert!(nodes < all_nodes, "{nodes} closure nodes of {all_nodes} stored node terms");
    // Local is shared by many roots and has one node.
    let local_atom = (0..report.rows[1]).find(|&a| atom(&report, a)[..2] == [2, s.job_of(&report, LIB_B)] && atom(&report, a)[2] == s.keys[d.local as usize][3] & !PRIVATE).unwrap();
    let local_nodes = (0..report.rows[5]).filter(|&n| { let r = report.row(5, n).unwrap(); r[0] == 1 && r[1] == local_atom && r[3] == 0 }).count();
    assert_eq!(local_nodes, 1, "one node for the shared Local term");
    eprintln!(
        "closure: {} terms ({nodes} nodes, {edges} edges) of {} stored terms ({all_nodes} node terms); {} active of {} waves; dispatches {}",
        report.closure_terms, s.heads.len() - 32, report.closure_active_waves, report.closure_waves, report.dispatches
    );
    assert!(report.closure_active_waves <= report.closure_waves);

    // Binding ranks: the GPU sort covers every trait record in
    // log2(P)(log2(P)+1)/2 steps of P lanes. Each lane does one compare,
    // so the work is P log2(P)^2 / 2 for any impl width; the scan it
    // replaced did B^2 per impl.
    let records = s.traits.len() as u32;
    assert_eq!(report.sort_width, records.next_power_of_two());
    let lg = report.sort_width.trailing_zeros();
    assert_eq!(report.sort_steps, lg * (lg + 1) / 2);
    assert!(report.sort_width < 2 * records.max(1));
    // The wide impl's method rows: contiguous, strictly increasing symbol,
    // although its source lists the methods in another order.
    let wide_row = (0..report.rows[9]).find(|&r| atom(&report, report.row(9, r).unwrap()[0])[2] == s.keys[d.wide_local as usize][3]).unwrap();
    let head = report.row(9, wide_row).unwrap();
    assert_eq!(head[7], WIDE);
    let symbols = (0..WIDE).map(|m| report.row(10, head[6] + m).unwrap()[1]).collect::<Vec<_>>();
    assert!(symbols.windows(2).all(|w| w[0] < w[1]), "{symbols:?}");
    let source_order = s.bindings(d.wide_local).iter().map(|b| b[5]).collect::<Vec<_>>();
    assert_ne!(source_order, symbols, "the impl's source order differs from symbol order");

    // Reused solver storage, unpoisoned: the same rows and selections.
    let again = check(&compiler, &store, RetainedTraitOptions::default());
    assert!(solved(&again));
    assert_eq!(goals(&again), first_goals);
    assert_eq!(again.tables[9..=10], report.tables[9..=10], "deterministic impl and method rows");

    // Too few closure waves: the GPU reports an unexpanded frontier and the
    // host doubles the waves; the same rows and selections.
    let short = check(&compiler, &store, RetainedTraitOptions { closure_waves: Some(1), ..Default::default() });
    assert!(short.attempts >= 2 && short.closure_waves >= 2, "{short:#?}");
    assert!(solved(&short));
    assert_eq!(goals(&short), first_goals);
    assert_eq!(short.tables[1..=10], report.tables[1..=10], "identical catalog rows");

    // A full unit table grows and the producer runs again from the store.
    let grown = check(&compiler, &store, RetainedTraitOptions { unit_slots: Some(1), ..Default::default() });
    assert_eq!(grown.attempts, 2, "{grown:#?}");
    assert!(solved(&grown));
    assert_eq!(goals(&grown), first_goals);

    // The publication: no semantic row readback, a GPU consumer reads the
    // selected impl, native target and binding environment.
    let (plain, publication) = compiler.retained_trait_publish(&store, &RetainedTraitOptions::default()).unwrap();
    let publication: RetainedTraitPublication = publication.expect("a solved publication");
    assert_eq!(plain.stage, RetainedTraitStage::Solved);
    assert!(plain.obligations.is_empty() && plain.evidence.is_empty() && plain.calls.is_empty(), "no semantic readback");
    assert!(plain.publication_status.is_none(), "publish reads no status");
    eprintln!("publish: dispatches {} readbacks {} bytes {}", plain.dispatches, plain.readbacks, plain.producer_readback_bytes);
    assert_eq!(publication.status().unwrap(), [1, 0, u32::MAX]);
    let id = publication.identity();
    assert_eq!(id.generation, generation);
    let view = publication.view(&store).unwrap();
    assert!(view.routes.size > 0 && view.proof.size > 0 && view.catalog.size > 0);
    let queries = queries(&s, &store);
    let requests = queries.iter().map(|q| q.request).collect::<Vec<_>>();
    assert_answers(&queries, &publication.query_for_test(&store, id, &requests).unwrap());

    // A second publication keeps the first alive and valid; identities differ.
    let (_, second) = compiler.retained_trait_publish(&store, &RetainedTraitOptions::default()).unwrap();
    let second = second.unwrap();
    assert_ne!(second.identity(), id);
    assert_answers(&queries, &publication.query_for_test(&store, id, &requests).unwrap());
    assert!(publication.query_for_test(&store, second.identity(), &requests).unwrap().iter().all(|a| a[0] == RQ_HEADER));
    drop(second);
    assert_answers(&queries, &publication.query_for_test(&store, id, &requests).unwrap());

    // Fail closed: another identity, a store that is not READY.
    let stale = |id, expect: u32| {
        let answers = publication.query_for_test(&store, id, &requests).unwrap();
        assert!(answers.iter().all(|a| a[0] == expect && a[1..].iter().all(|&w| w == u32::MAX)), "{answers:?}");
    };
    stale(laniusc_compiler::compiler::RetainedTraitIdentity { serial: id.serial + 1, ..id }, RQ_HEADER);
    store.write_store_words("rt_counts", counts::READY as u64, &[0]).unwrap();
    stale(id, RQ_STALE);
    store.write_store_words("rt_counts", counts::READY as u64, &[1]).unwrap();
    assert_answers(&queries, &publication.query_for_test(&store, id, &requests).unwrap());

    // Faults below rewrite store words and restore them.
    let fault_words = |name: &str, writes: &[(usize, u32)], verify: &dyn Fn(&RetainedTraitCheck)| {
        let originals = writes
            .iter()
            .map(|&(offset, _)| store.read_store_words(name, offset + 1).unwrap()[offset])
            .collect::<Vec<_>>();
        for &(offset, value) in writes {
            store.write_store_words(name, offset as u64, &[value]).unwrap();
        }
        let report = check(&compiler, &store, RetainedTraitOptions::default());
        for (&(offset, _), original) in writes.iter().zip(originals) {
            store.write_store_words(name, offset as u64, &[original]).unwrap();
        }
        verify(&report);
    };
    let fault = |name: &str, offset: usize, value: u32, verify: &dyn Fn(&RetainedTraitCheck)| {
        fault_words(name, &[(offset, value)], verify)
    };
    let producer_code = |code: u32| {
        move |r: &RetainedTraitCheck| {
            assert_eq!(r.stage, RetainedTraitStage::Producer, "{r:#?}");
            assert_eq!(r.first_failure.map(|f| f.0), Some(code), "{r:#?}");
        }
    };

    // Refuted obligation: `needs(Local)` with its environment argument
    // rewritten to i32, which has no Show impl.
    let local_term = s.named(d.local);
    let env = s.uses[use_of(&s, &store, d.needs, local_term) as usize][4];
    fault("rt_term_args", s.meta[env as usize][0] as usize, SCALAR_I32, &|r| {
        assert_eq!(r.stage, RetainedTraitStage::Solved, "{r:#?}");
        assert!(!solved(r), "i32: Show has no evidence: {r:#?}");
        let unproven = r.obligations.iter().filter(|o| !matches!(o[0], 1 | 2)).count();
        assert_eq!(unproven, 1, "only the faulted obligation is unproven: {:?}", r.obligations);
        // A batch with a refuted goal publishes no routes to consume.
        let p = r.publication_status.unwrap();
        assert!(p[0] == 2 && p[1] != 0, "the publication fails closed: {p:?}");
    });

    // Coherence: `impl Show for Other` rewritten to Local overlaps
    // `impl Show for Local`.
    fault("rt_sigs", s.entry(d.show_other)[6] as usize, local_term, &|r| {
        assert_eq!(r.stage, RetainedTraitStage::Admission, "{r:#?}");
        eprintln!("coherence status {:?}", r.catalog_status);
        assert_eq!(r.catalog_status.unwrap()[..2], E_COHERENCE_STATUS, "{:?}", r.catalog_status);
        assert!(r.obligations.is_empty(), "no solve over a rejected catalog");
    });
    // The generic Wrap impl rewritten to Local leaves its T uncovered.
    fault("rt_sigs", s.entry(d.show_wrap)[6] as usize, local_term, &|r| {
        assert_eq!(r.stage, RetainedTraitStage::Admission, "{r:#?}");
        eprintln!("uncovered status {:?}", r.catalog_status);
        assert_ne!(r.catalog_status.unwrap()[0], 1);
        assert_eq!(r.catalog_status.unwrap()[..2], E_UNCOVERED_STATUS, "not reported as overlap: {:?}", r.catalog_status);
    });

    // A structural predicate subject (the parser takes only parameter and
    // scalar subjects): `needs`' bound rewritten to `Local: Show`. Every
    // goal of `needs` then proves Local: Show with `impl Show for Local`.
    let needs_bound = s.dir_trait[s.entry_index(d.needs)][0] as usize;
    fault("rt_traits", needs_bound * 8 + 2, local_term, &|r| {
        assert!(solved(r), "{r:#?}");
        let goals = goals(r);
        let callee = [s.keys[d.needs as usize][0], s.keys[d.needs as usize][1], s.keys[d.needs as usize][3]];
        let needs_goals = goals.iter().filter(|g| g.callee == callee).collect::<Vec<_>>();
        assert_eq!(needs_goals.len(), 4, "needs(Local), needs(Wrap), needs(Cell), needs(Grid): {goals:#?}");
        let show_local = Some([s.job_of(r, LIB_B), s.keys[d.show_local as usize][3], 7]);
        assert!(needs_goals.iter().all(|g| g.status == 1 && g.implementation == show_local), "{needs_goals:#?}");
    });

    // An unrelated stored term is not checked or translated: a malformed
    // arity or a slot flag on Wrap<Wrap<Other>> leaves the check solved and
    // equal. The same slot flag on the referenced Local term rejects.
    let head = s.heads[wrap_wrap as usize][0];
    fault("rt_term_head", wrap_wrap as usize * 4, head & !0xff00, &|r| {
        assert!(solved(r), "{r:#?}");
        assert_eq!(goals(r), first_goals);
    });
    let flags = s.meta[wrap_wrap as usize][1];
    fault("rt_term_meta", wrap_wrap as usize * 4 + 1, flags | RTF_SLOT, &|r| {
        assert!(solved(r), "{r:#?}");
        assert_eq!(goals(r), first_goals);
    });
    let flags = s.meta[local_term as usize][1];
    fault("rt_term_meta", local_term as usize * 4 + 1, flags | RTF_SLOT, &producer_code(E_SLOT));

    // Swapped type slots of `shadow` (impl T, own T).
    let start = s.entry(d.shadow)[4] as usize;
    let (outer_slot, own) = (s.binders[start], s.binders[start + 1]);
    fault_words("rt_binders", &[(start, own), (start + 1, outer_slot)], &|r| {
        eprintln!("swapped: stage {:?} first {:?}", r.stage, r.first_failure);
        assert_eq!(r.first_failure.map(|f| f.0), Some(E_PARAM_OWNER), "{r:#?}");
    });

    // Trait arity against the defining binder: Pair applied to no argument.
    let pair_term = s.impl_trait(d.pair_local);
    let head = s.heads[pair_term as usize][0];
    fault("rt_term_head", pair_term as usize * 4, head & !0xff00, &producer_code(E_TRAIT_ARITY));

    // A constant argument of the wrong scalar: Grid<Local, 4> with 4 as i32.
    let grid_term = (32..s.heads.len() as u32)
        .find(|&t| s.heads[t as usize][0] & 0xff == 2 && s.heads[t as usize][1] == d.grid && s.arity(t) == 2 && {
            let arg = store.read_store_words("rt_term_args", s.meta[t as usize][0] as usize + 2).unwrap()[s.meta[t as usize][0] as usize + 1];
            (32..0x8000_0000).contains(&arg)
        })
        .expect("Grid<Local, 4>");
    let base = s.meta[grid_term as usize][0] as usize;
    let four = store.read_store_words("rt_term_args", base + 2).unwrap()[base + 1];
    assert_eq!(s.heads[four as usize][0] & 0xff, RT_KIND_CC_VALUE);
    let wrong = if s.heads[four as usize][1] == SCALAR_I32 { SCALAR_I32 + 1 } else { SCALAR_I32 };
    fault("rt_term_head", four as usize * 4 + 1, wrong, &producer_code(E_NOMINAL));

    // A binding whose required member is the impl's own method.
    let t = s.dir_trait[s.entry_index(d.pair_local)];
    assert_eq!(t[3], 1, "one binding");
    let binding = t[2] as usize;
    fault("rt_traits", binding * 8 + 2, s.traits[binding][3], &producer_code(E_REQUIRED_MEMBER));

    // The wide impl: two bindings of one required member, and a binding
    // count below the trait's member count.
    let wt = s.dir_trait[s.entry_index(d.wide_local)];
    let (b0, b1) = (wt[2] as usize, wt[2] as usize + 1);
    fault_words("rt_traits", &[(b1 * 8 + 2, s.traits[b0][2]), (b1 * 8 + 5, s.traits[b0][5])], &producer_code(E_BINDING_COVERAGE));
    fault("rt_dir_trait", s.entry_index(d.wide_local) * 4 + 3, wt[3] - 1, &producer_code(E_BINDING_COVERAGE));

    // A store that is not READY, or of another build generation.
    fault("rt_counts", counts::READY, 0, &producer_code(E_NOT_READY));
    fault("rt_counts", counts::GENERATION, generation.wrapping_add(1), &producer_code(E_NOT_READY));

    // A fresh build of the same store: new generation, same selections. The
    // earlier publication is refused on the host and on the GPU.
    let rebuilt_compiler = compiler_for_rebuild();
    build(&rebuilt_compiler, &store);
    pollster::block_on(rebuilt_compiler.release_resident_job_buffers());
    store.poison_scratch();
    assert!(publication.view(&store).is_err(), "a publication of an earlier build");
    stale(id, RQ_STALE);
    drop(publication);
    let fresh = check(&compiler, &store, RetainedTraitOptions { poison_arenas: true, ..Default::default() });
    assert_ne!(fresh.generation, generation);
    assert!(solved(&fresh), "{fresh:#?}");
    let s2 = Store::read(&store);
    assert_eq!(checked_goals(&s2, &fresh), sorted(expected(&s2, &fresh)));
    assert_eq!(s.status[counts::JOBS], s2.status[counts::JOBS]);
}

fn compiler_for_rebuild() -> GpuCompiler<'static> {
    compiler()
}


#[test]
fn retained_trait_catalog_solves_closed_instance_goals() {
    let compiler = compiler();
    let store = ProgramRetention::new(ProgramRetentionCapacity::default()).unwrap();
    build(&compiler, &store);
    pollster::block_on(compiler.release_resident_job_buffers());
    store.poison_scratch();
    let s = Store::read(&store);
    let (_, publication) = compiler.retained_trait_publish(&store, &RetainedTraitOptions::default()).unwrap();
    let mut publication = publication.unwrap();
    let queries: Vec<_> = queries(&s, &store).into_iter().filter(|q| q.status == RQ_FOUND).collect();
    let mut instances = vec![[0; 8]; s.uses.len()];
    for q in &queries {
        let u = s.uses[q.request[0] as usize];
        instances[q.request[0] as usize] = [u[3], u[4], store.generation(), 0, 0, 0, 0, 0];
    }
    let (report, closed) = publication.solve_instances_for_test(&store, &instances).unwrap();
    assert_eq!(report.producer_failures, 0, "{report:?}");
    assert_eq!(report.batch_status.unwrap()[0], 1, "{report:?}");
    assert_eq!(report.rows[14], 0, "concrete instances have no assumptions");
    assert_eq!(report.rows[15], 7, "seven concrete calls, sharing a wide proof");
    let closed = closed.expect("closed publication");
    let requests = queries.iter().map(|q| q.request).collect::<Vec<_>>();
    assert_answers(&queries, &closed.query_for_test(&publication, &store, &requests).unwrap());
    // A second wave owns separate proof storage; the first stays current.
    let (_, second) = publication.solve_instances_for_test(&store, &instances).unwrap();
    assert_answers(&queries, &second.unwrap().query_for_test(&publication, &store, &requests).unwrap());
    assert_answers(&queries, &closed.query_for_test(&publication, &store, &requests).unwrap());
    let first = queries[0].request[0] as usize;
    // The original source proof selected Local. Fault the closed instance's
    // binding to i32, which has no Show impl. Reusing the source proof would
    // incorrectly authorize it; this wave must refute the concrete goal.
    let env = instances[first][1] as usize;
    let argument = s.meta[env][0] as usize;
    let saved = s.args[argument];
    store.write_store_words("rt_term_args", argument as u64, &[SCALAR_I32]).unwrap();
    let (refuted, bad) = publication.solve_instances_for_test(&store, &instances).unwrap();
    assert_eq!(refuted.producer_failures, 0, "{refuted:?}");
    assert_ne!(bad.unwrap().status(&publication).unwrap()[0], 1, "a refuted hard goal cannot publish");
    store.write_store_words("rt_term_args", argument as u64, &[saved]).unwrap();
    instances[first][2] = store.generation() - 1;
    let (stale, result) = publication.solve_instances_for_test(&store, &instances).unwrap();
    assert_ne!(stale.producer_failures, 0);
    assert!(result.is_none());
    store.begin_build().unwrap();
    assert!(closed.view(&publication, &store).is_err());
}
