//! Retained trait facts (docs/compiler-program-retention.md, "Trait facts"):
//! two frontend jobs export their accepted predicates and impl-method
//! bindings into one build store, the frontend is released and exporter
//! scratch is poisoned, and a GPU probe validates every fact from the store
//! alone. The test then names facts by their retained source spans and
//! checks exact owners and identities.

use std::sync::Arc;

use laniusc_compiler::{
    compiler::{GpuCompiler, GpuCompilerBackends},
    type_checker::program_retention::{
        ProgramRetention,
        ProgramRetentionCapacity,
        TRAIT_PROBE_WORDS,
        counts,
    },
};

#[allow(unused_imports)]
use crate::common;

// Library 20. `Tag` is private in both units and declared at the same
// declaration ordinal, so both private traits share one local word.
const LIBRARY: &str = r#"module traits::a;
trait Tag {}
pub trait Show {
    pub fn show(&self) -> i32;
    pub fn make() -> i32;
    pub fn take(self) -> i32;
}
pub trait Pair<X> { pub fn left(&self, value: X) -> X; }
pub struct Cell<T> { value: T }
pub impl<T> Cell<T> {
    pub fn shadow<T>(&self, value: T) -> T where T: Show { return value; }
    pub fn inherit<U>(&self, other: U) -> U where T: Show { return other; }
}
fn tagged<T>(value: T) -> T where T: Tag { return value; }
pub fn needs<T: Show, U>(value: T, other: U) -> U where U: Pair<T> { return other; }
pub fn sized<T, const N: usize>(value: T) -> T where T: Pair<[i32; N]> { return value; }
pub fn scalar<T>(value: T) -> T where bool: Pair<T> { return value; }
pub trait Comparator<A, B> { pub fn compare(&self, a: A, b: B) -> bool; }
pub struct Natural<T> { value: T }
pub impl<T> Comparator<T, T> for Natural<T> {
    pub fn compare(&self, a: T, b: T) -> bool { return true; }
}
"#;

// Library 21: impls of the imported traits for a private self type and a
// generic impl with a prerequisite.
const APP: &str = r#"module traits::b;
import traits::a;
trait Tag {}
struct Local { v: i32 }
struct Wrap<T> { inner: T }
pub impl Show for Local {
    pub fn show(&self) -> i32 { return 1; }
    pub fn make() -> i32 { return 2; }
    pub fn take(self) -> i32 { return 3; }
}
pub impl<T: Show> Show for Wrap<T> {
    pub fn show(&self) -> i32 { return 4; }
    pub fn make() -> i32 { return 5; }
    pub fn take(self) -> i32 { return 6; }
}
pub impl Pair<i32> for Local { pub fn left(&self, value: i32) -> i32 { return value; } }
impl Tag for Local {}
trait Hidden { fn h(&self) -> i32; }
impl Hidden for Local { fn h(&self) -> i32 { return 7; } }
fn local_tag<T>(value: T) -> T where T: Tag { return value; }
fn main() -> i32 { return 0; }
"#;

const KIND_METHOD: u32 = 2;
const KIND_REQUIRED: u32 = 3;
const KIND_IMPL: u32 = 7;
const KIND_TRAIT: u32 = 8;
const NS_NOMINAL: u32 = 2;
const PARAM_BIT: u32 = 0x8000_0000;
const ID_MASK: u32 = 0x1fff_ffff;
const SCALAR_BOOL: u32 = 2;
const SCALAR_I32: u32 = 3;
const SCALAR_USIZE: u32 = 17;
const TERM_ARRAY: u32 = 3;
const INV_TRAIT_FACT: u32 = 10;
const INV_TRAIT_IDENTITY: u32 = 12;

const T_DECL: usize = 0;
const T_KIND: usize = 1;
const T_PREDICATES: usize = 2;
const T_PREDICATES_BAD: usize = 3;
const T_BINDINGS: usize = 4;
const T_BINDINGS_BAD: usize = 5;
const T_FAILED: usize = 6;
const T_DIR_FLAGS: usize = 7;
const T_IMPL_TRAIT: usize = 8;
const T_REQUIRED: usize = 9;
const T_RECEIVERS: usize = 10;

fn compiler() -> GpuCompiler<'static> {
    pollster::block_on(GpuCompiler::new_with_backends(GpuCompilerBackends::frontend_only()))
        .expect("frontend compiler")
}

fn build(compiler: &GpuCompiler<'static>, store: &Arc<ProgramRetention>) -> anyhow::Result<()> {
    store.begin_build()?;
    compiler.attach_program_retention(Some(store.clone()));
    let result = (|| {
        let library = pollster::block_on(compiler.semantic_interface_for_source_pack(20, &[LIBRARY]))?;
        pollster::block_on(compiler.semantic_interface_for_source_pack_with_dependencies(21, &[APP], &[library]))?;
        Ok(())
    })();
    compiler.attach_program_retention(None);
    result
}

fn source(library: u32) -> &'static str {
    match library {
        20 => LIBRARY,
        21 => APP,
        other => panic!("no source for library {other}"),
    }
}

/// The store's records, read back for assertions only.
struct Store {
    status: Vec<u32>,
    keys: Vec<[u32; 4]>,
    params: Vec<[u32; 4]>,
    heads: Vec<[u32; 4]>,
    meta: Vec<[u32; 4]>,
    args: Vec<u32>,
    dir: Vec<[u32; 16]>,
    dir_trait: Vec<[u32; 4]>,
    traits: Vec<[u32; 8]>,
    binders: Vec<u32>,
}

fn chunks<const N: usize>(words: Vec<u32>) -> Vec<[u32; N]> {
    words.chunks_exact(N).map(|c| c.try_into().unwrap()).collect()
}

fn read(store: &ProgramRetention) -> Store {
    let status = store.status().unwrap();
    let w = |name: &str, n: usize| store.read_store_words(name, n).unwrap();
    Store {
        keys: chunks(w("rt_decl_key", status[0] as usize * 4)),
        params: chunks(w("rt_param_key", status[1] as usize * 4)),
        heads: chunks(w("rt_term_head", status[2] as usize * 4)),
        meta: chunks(w("rt_term_meta", status[2] as usize * 4)),
        args: w("rt_term_args", status[3] as usize),
        dir: chunks(w("rt_dir", status[4] as usize * 16)),
        dir_trait: chunks(w("rt_dir_trait", status[4] as usize * 4)),
        binders: w("rt_binders", status[5] as usize),
        traits: chunks(w("rt_traits", status[14] as usize * 8)),
        status,
    }
}

impl Store {
    fn entry(&self, decl: u32) -> &[u32; 16] {
        self.dir.iter().find(|e| e[0] == decl).unwrap_or_else(|| panic!("no entry for {decl}"))
    }
    /// The retained source text of a predicate record's bound.
    fn bound_text(&self, record: &[u32; 8]) -> &'static str {
        let library = self.keys[record[0] as usize][0];
        &source(library)[record[6] as usize..(record[6] + record[7]) as usize]
    }
    /// The identifier at a binding record's method-name span.
    fn method_name(&self, record: &[u32; 8]) -> &'static str {
        let library = self.keys[record[0] as usize][0];
        let text = &source(library)[record[7] as usize..];
        let end = text.find(|c: char| !c.is_alphanumeric() && c != '_').unwrap_or(text.len());
        &text[..end]
    }
    fn predicates(&self, decl: u32) -> &[[u32; 8]] {
        let t = self.dir_trait[self.dir.iter().position(|e| e[0] == decl).unwrap()];
        &self.traits[t[0] as usize..(t[0] + t[1]) as usize]
    }
    fn bindings(&self, decl: u32) -> &[[u32; 8]] {
        let t = self.dir_trait[self.dir.iter().position(|e| e[0] == decl).unwrap()];
        &self.traits[t[2] as usize..(t[2] + t[3]) as usize]
    }
    fn term_args(&self, term: u32) -> &[u32] {
        let arity = ((self.heads[term as usize][0] >> 8) & 0xff) as usize;
        let base = self.meta[term as usize][0] as usize;
        &self.args[base..base + arity]
    }
    /// The DeclId of the committed method whose binding names `name`.
    fn methods_named<'a>(&'a self, impl_decl: u32, name: &str) -> Vec<&'a [u32; 8]> {
        self.bindings(impl_decl).iter().filter(|b| self.method_name(b) == name).collect()
    }
    /// Predicates of `library` whose diagnostic names exactly `text`.
    fn predicates_with<'a>(&'a self, library: u32, text: &str) -> Vec<&'a [u32; 8]> {
        self.traits
            .iter()
            .filter(|r| r[1] & 0xff == 1 && self.keys[r[0] as usize][0] == library && bound_is(self.bound_text(r), text))
            .collect()
    }
    fn sigs(&self, store: &ProgramRetention, decl: u32) -> Vec<u32> {
        let entry = self.entry(decl);
        let words = store.read_store_words("rt_sigs", (entry[6] + 1 + entry[7]) as usize).unwrap();
        words[entry[6] as usize..].to_vec()
    }
    fn param_owner(&self, leaf: u32) -> u32 {
        assert_eq!(leaf & PARAM_BIT, PARAM_BIT, "subject is a parameter leaf: {leaf:#x}");
        self.params[(leaf & ID_MASK) as usize][0]
    }
}

fn bound_is(span: &str, expected: &str) -> bool {
    span == expected
}

fn probe(store: &ProgramRetention) -> Vec<Vec<u32>> {
    store.trait_probe().unwrap().chunks_exact(TRAIT_PROBE_WORDS).map(<[u32]>::to_vec).collect()
}

fn assert_probe_clean(lanes: &[Vec<u32>]) {
    for lane in lanes {
        assert_eq!(lane[T_FAILED], 0, "trait facts of entry validate: {lane:?}");
        assert_eq!(lane[T_PREDICATES_BAD] + lane[T_BINDINGS_BAD], 0, "{lane:?}");
        assert_eq!(lane[T_DIR_FLAGS], 2 << 8, "committed and complete: {lane:?}");
    }
}

/// Probe lanes and records without TermIds, ParamIds or DeclIds, which
/// depend on allocation order: what a retried build must reproduce.
fn shape(store: &ProgramRetention) -> Vec<Vec<u32>> {
    let s = read(store);
    let mut out = probe(store)
        .into_iter()
        .map(|lane| vec![lane[T_KIND], lane[T_PREDICATES], lane[T_BINDINGS], lane[T_FAILED], lane[T_REQUIRED], lane[T_RECEIVERS]])
        .collect::<Vec<_>>();
    out.extend(s.traits.iter().map(|r| vec![r[1], r[5], r[6], r[7]]));
    out.sort();
    out
}

#[test]
fn program_retention_exports_trait_predicates_and_method_bindings() {
    let compiler = compiler();
    let store = ProgramRetention::new(ProgramRetentionCapacity::default()).unwrap();
    if let Err(err) = build(&compiler, &store) { panic!("build: {err:?}"); }
    let reports = store.job_reports();
    for report in &reports {
        assert!(report.ready, "{report:?}");
        assert_eq!(report.counts[counts::INVARIANTS], 0, "first invariant {}", report.counts[counts::FIRST_INVARIANT]);
        assert_eq!(report.counts[counts::INCOMPLETE], 0, "{report:?}");
    }

    // Only the store remains: frontend storage released, scratch poisoned.
    pollster::block_on(compiler.release_resident_job_buffers());
    drop(compiler);
    store.poison_scratch();
    let lanes = probe(&store);
    assert_probe_clean(&lanes);
    let s = read(&store);
    for record in &s.traits {
        eprintln!("trait record {record:?}");
    }

    // Traits by their declaration entries and keys.
    let traits = s.dir.iter().filter(|e| e[1] == KIND_TRAIT).map(|e| (e[0], s.keys[e[0] as usize])).collect::<Vec<_>>();
    assert_eq!(traits.len(), 6, "Tag, Show, Pair, Comparator in A; Tag and Hidden in B: {traits:?}");
    let a_traits = traits.iter().filter(|(_, k)| k[0] == 20).collect::<Vec<_>>();
    assert!(traits.iter().all(|(_, k)| k[2] == NS_NOMINAL));

    // Predicates name their bound text; owners and subjects are exact.
    let show = s.predicates_with(20, "Show");
    assert_eq!(show.len(), 3, "needs, shadow and inherit bound Show: {show:?}");
    let show_trait = show[0][4];
    assert!(show.iter().all(|r| r[4] == show_trait));
    assert!(a_traits.iter().any(|(decl, _)| *decl == show_trait));
    for record in &show {
        let owner = record[0];
        let owner_entry = s.entry(owner);
        let subject_owner = s.param_owner(record[2]);
        let (_, owner_key) = (owner, s.keys[owner as usize]);
        assert_eq!(owner_key[0], 20);
        if subject_owner != owner {
            // `inherit`: the impl's T, inherited through the method's parent.
            assert_eq!(subject_owner, owner_entry[2], "inherited subject belongs to the parent impl");
            assert_eq!(s.keys[subject_owner as usize][2], 4, "the parent is an impl");
        }
    }
    let inherited = show.iter().filter(|r| s.param_owner(r[2]) != r[0]).count();
    assert_eq!(inherited, 1, "only `inherit` bounds the impl's T; `shadow` bounds its own T");

    let pair_bounds = s.predicates_with(20, "Pair");
    assert_eq!(pair_bounds.len(), 3, "exact trait-name spans exclude arguments and following syntax");
    let pair_generic = pair_bounds.iter().copied()
        .filter(|r| s.term_args(r[3])[0] & PARAM_BIT != 0).collect::<Vec<_>>();
    assert_eq!(pair_generic.len(), 2, "needs and scalar: {pair_generic:?}");
    let pair_trait = pair_generic[0][4];
    assert_ne!(pair_trait, show_trait);
    let scalar_subject = pair_generic.iter().filter(|r| r[2] == SCALAR_BOOL).count();
    assert_eq!(scalar_subject, 1, "`where bool: Pair<T>` keeps its scalar subject");
    for record in &pair_generic {
        let args = s.term_args(record[3]);
        assert_eq!(args.len(), 1);
        assert_eq!(s.param_owner(args[0]), record[0], "the argument is the owner's own T");
    }

    // A type argument containing a constant: `[i32; N]` keeps N's scalar.
    let sized = pair_bounds.iter().copied()
        .filter(|r| s.term_args(r[3])[0] & PARAM_BIT == 0).collect::<Vec<_>>();
    assert_eq!(sized.len(), 1);
    let array = s.term_args(sized[0][3])[0];
    assert_eq!(s.heads[array as usize][0] & 0xff, TERM_ARRAY);
    let [element, length] = s.term_args(array).try_into().unwrap();
    assert_eq!(element, SCALAR_I32);
    assert_eq!(length & 0x4000_0000, 0x4000_0000, "the length is a constant parameter leaf");
    let n = s.params[(length & ID_MASK) as usize];
    assert_eq!(n[0], sized[0][0], "N belongs to `sized`");
    assert_eq!(n[3], SCALAR_USIZE, "N keeps its declared scalar");

    // Private traits with one local word in two units stay distinct.
    let tags_a = s.predicates_with(20, "Tag");
    let tags_b = s.predicates_with(21, "Tag");
    assert_eq!((tags_a.len(), tags_b.len()), (1, 1));
    assert_ne!(tags_a[0][4], tags_b[0][4]);
    assert_eq!(s.keys[tags_a[0][4] as usize][0], 20);
    assert_eq!(s.keys[tags_b[0][4] as usize][0], 21);
    assert_eq!(s.keys[tags_a[0][4] as usize][3], s.keys[tags_b[0][4] as usize][3],
        "both private traits share their local word");

    // Impls in B: imported trait identities meet A's declarations.
    let impls = lanes.iter().filter(|l| l[T_KIND] == KIND_IMPL && s.keys[l[T_DECL] as usize][0] == 21).collect::<Vec<_>>();
    assert_eq!(impls.len(), 5, "{impls:?}");
    let show_impls = impls.iter().filter(|l| l[T_IMPL_TRAIT] == show_trait).collect::<Vec<_>>();
    assert_eq!(show_impls.len(), 2);
    for lane in &show_impls {
        assert_eq!(lane[T_BINDINGS], 3);
        assert_eq!(lane[T_REQUIRED], 3, "the trait's committed required members");
        assert_eq!(lane[T_RECEIVERS], 0b111, "none, self and &self receivers");
        let impl_decl = lane[T_DECL];
        for (name, mode) in [("make", 0), ("take", 1), ("show", 2)] {
            let found = s.methods_named(impl_decl, name);
            assert_eq!(found.len(), 1, "{name}");
            let binding = found[0];
            assert_eq!((binding[1] >> 8) & 0xff, mode, "{name} receiver mode");
            let required = s.keys[binding[2] as usize];
            assert_eq!(required[0], 20, "the required member is the trait unit's");
            assert_eq!(s.entry(binding[2])[1], KIND_REQUIRED);
            assert_eq!(s.entry(binding[3])[1], KIND_METHOD);
            assert_eq!(s.keys[binding[3] as usize][0], 21, "the native target is the impl unit's");
        }
    }
    let generic = show_impls.iter().find(|l| s.predicates(l[T_DECL]).len() == 1).expect("the generic impl");
    let prerequisite = s.predicates(generic[T_DECL])[0];
    assert!(bound_is(s.bound_text(&prerequisite), "Show"));
    assert_eq!(prerequisite[4], show_trait, "the prerequisite names the imported trait");
    assert_eq!(s.param_owner(prerequisite[2]), generic[T_DECL], "its subject is the impl's own T");
    let concrete = show_impls.iter().find(|l| l[T_DECL] != generic[T_DECL]).unwrap();
    assert!(s.predicates(concrete[T_DECL]).is_empty());
    let pair_impl = impls.iter().find(|l| l[T_IMPL_TRAIT] == pair_trait).expect("Pair<i32> impl");
    assert_eq!(pair_impl[T_BINDINGS], 1);
    let sigs = s.sigs(&store, pair_impl[T_DECL]);
    assert_eq!(s.term_args(sigs[1]), [SCALAR_I32], "`Pair<i32>` keeps its argument");
    assert_eq!(s.heads[sigs[1] as usize][1], pair_trait);
    let tag_impl = impls.iter().find(|l| l[T_IMPL_TRAIT] == tags_b[0][4]).expect("B's own Tag impl");
    assert_eq!((tag_impl[T_BINDINGS], tag_impl[T_REQUIRED]), (0, 0));

    let private_impl = impls.iter().find(|l| s.methods_named(l[T_DECL], "h").len() == 1)
        .expect("the private Hidden impl");
    let binding = s.methods_named(private_impl[T_DECL], "h")[0];
    let target = s.keys[binding[3] as usize];
    assert_eq!(target[0], 21);
    assert_eq!(target[3] & 0xc000_0000, 0x4000_0000, "private native symbol, not a public alias");
    assert_eq!(s.entry(binding[3])[1], KIND_METHOD);
    assert_eq!(s.entry(binding[3])[2], private_impl[T_DECL]);
    assert_eq!(s.entry(binding[2])[1], KIND_REQUIRED);
    assert_eq!(s.entry(binding[2])[2], private_impl[T_IMPL_TRAIT]);

    // A generic impl head in A: `Comparator<T, T> for Natural<T>` over the
    // impl's own T, with its one method bound.
    let comparator = lanes.iter()
        .find(|l| l[T_KIND] == KIND_IMPL && s.keys[l[T_DECL] as usize][0] == 20 && l[T_BINDINGS] == 1)
        .expect("the Comparator impl");
    let head = s.sigs(&store, comparator[T_DECL]);
    let t = s.term_args(head[0]);
    assert_eq!(t.len(), 1, "Natural<T>");
    assert_eq!(s.param_owner(t[0]), comparator[T_DECL]);
    assert_eq!(s.term_args(head[1]), [t[0], t[0]], "Comparator<T, T> names the impl's T twice");
    assert_eq!(comparator[T_REQUIRED], 1);
    assert_eq!(comparator[T_RECEIVERS], 1 << 2, "&self");

    // Required members keep their receivers: `&self` is REF(Self) and
    // `self` is Self, with Self the trait's implicit parameter.
    let local_show = show_impls.iter().find(|l| l[T_DECL] == concrete[T_DECL]).unwrap();
    for (name, reference) in [("show", true), ("take", false), ("make", false)] {
        let binding = s.methods_named(local_show[T_DECL], name)[0];
        let required = binding[2];
        let sigs = s.sigs(&store, required);
        if name == "make" {
            assert_eq!(sigs.len(), 1, "make() has only its result");
            continue;
        }
        let receiver = sigs[1];
        let leaf = if reference {
            assert_eq!(s.heads[receiver as usize][0] & 0xff, 5, "{name}: REF");
            s.term_args(receiver)[0]
        } else {
            receiver
        };
        let param = s.params[(leaf & ID_MASK) as usize];
        assert_eq!((param[0], param[1], param[2]), (show_trait, 1, 0xffff), "{name}: the trait's Self");
        assert!(s.binders.contains(&(leaf & ID_MASK)));
    }
    assert_eq!(s.status[counts::READY], 1);
}

#[test]
fn program_retention_trait_facts_reject_faults_retry_and_rebuild() {
    let compiler = compiler();
    let reference = ProgramRetention::new(ProgramRetentionCapacity::default()).unwrap();
    build(&compiler, &reference).unwrap();
    let expected = shape(&reference);
    assert_probe_clean(&probe(&reference));

    // The consumer checks exact owners: a predicate moved to another owner
    // and a binding naming a non-required member are rejected.
    let s = read(&reference);
    let predicates = (0..s.traits.len()).filter(|&r| s.traits[r][1] & 0xff == 1).collect::<Vec<_>>();
    let (moved, other) = predicates.iter().flat_map(|&a| predicates.iter().map(move |&b| (a, b)))
        .find(|&(a, b)| s.traits[a][0] != s.traits[b][0]).unwrap();
    reference.write_store_words("rt_traits", moved as u64 * 8, &[s.traits[other][0]]).unwrap();
    let binding = (0..s.traits.len()).find(|&r| s.traits[r][1] & 0xff == 2).unwrap();
    reference.write_store_words("rt_traits", binding as u64 * 8 + 2, &[s.traits[binding][3]]).unwrap();
    let lanes = probe(&reference);
    let bad = lanes.iter().filter(|l| l[T_FAILED] != 0).collect::<Vec<_>>();
    assert!(bad.iter().any(|l| l[T_FAILED] & 1 != 0 && l[T_PREDICATES_BAD] == 1), "moved owner: {bad:?}");
    assert!(bad.iter().any(|l| l[T_FAILED] & (1 << 9) != 0 && l[T_BINDINGS_BAD] == 1), "wrong member: {bad:?}");

    // Producer faults injected into the export snapshot (never into the
    // frontend) are missing facts: the build is never ready.
    for (table, word, code) in [
        ("predicate_owner_node", 0, INV_TRAIT_FACT),
        ("predicate_method_validation_required_symbol", u32::MAX, INV_TRAIT_FACT),
        ("semantic_function_native_symbol_by_hir", 0x4000_0001, INV_TRAIT_IDENTITY),
        ("predicate_bound_reference", u32::MAX, INV_TRAIT_FACT),
        ("predicate_bound_arg_count", 0, INV_TRAIT_FACT),
        ("predicate_bound_token", u32::MAX, INV_TRAIT_FACT),
    ] {
        let faulted = ProgramRetention::new(ProgramRetentionCapacity::default()).unwrap();
        faulted.set_export_fault(Some((table, word)));
        build(&compiler, &faulted).unwrap();
        let status = faulted.status().unwrap();
        eprintln!("fault {table}: invariants {} first {} incomplete {}",
            status[counts::INVARIANT_TOTAL], status[counts::FIRST_INVARIANT], status[counts::INCOMPLETE_TOTAL]);
        assert_eq!(status[counts::READY], 0, "{table}");
        assert!(status[counts::INVARIANT_TOTAL] > 0 && status[counts::INCOMPLETE_TOTAL] > 0, "{table}");
        assert!(faulted.job_reports().iter().any(|r| !r.ready && r.counts[counts::FIRST_INVARIANT] <= code
            && r.counts[counts::FIRST_INVARIANT] >= INV_TRAIT_FACT), "{table}: {:?}",
            faulted.job_reports().iter().map(|r| r.counts[counts::FIRST_INVARIANT]).collect::<Vec<_>>());
        let lanes = probe(&faulted);
        assert!(lanes.iter().any(|l| l[T_DIR_FLAGS] & 1 != 0), "{table}: the faulted owner is incomplete");
    }

    // Tiny capacities: the trait arena overflows, the job rolls back, the
    // store grows and the retried export retains the same facts.
    let tiny = ProgramRetention::new(ProgramRetentionCapacity::tiny()).unwrap();
    build(&compiler, &tiny).unwrap();
    let (capacity, growths) = tiny.capacity();
    assert!(growths >= 1 && capacity.arenas[14] > ProgramRetentionCapacity::tiny().arenas[14]);
    assert!(tiny.status().unwrap()[counts::ROLLBACKS] >= 1);
    assert!(tiny.job_reports().iter().all(|r| r.ready));
    assert_eq!(shape(&tiny), expected, "a retried build retains the reference trait facts");
    assert_probe_clean(&probe(&tiny));

    // A fresh build in the same allocations: an unrelated job leaves no
    // trait facts of the earlier build, and the rebuild reproduces them.
    tiny.begin_build().unwrap();
    compiler.attach_program_retention(Some(tiny.clone()));
    pollster::block_on(compiler.semantic_interface_for_source_pack(
        99,
        &["module fresh; trait Only {} fn keep<T>(x: T) -> T where T: Only { return x; } fn main() -> i32 { return 0; }"],
    ))
    .unwrap();
    compiler.attach_program_retention(None);
    let fresh = read(&tiny);
    assert_eq!(fresh.status[14], 1, "one predicate record");
    assert_eq!(fresh.keys[fresh.traits[0][0] as usize][0], 99);
    assert_eq!(fresh.keys[fresh.traits[0][4] as usize][0], 99);
    assert_probe_clean(&probe(&tiny));
    build(&compiler, &tiny).unwrap();
    assert_eq!(tiny.capacity().0, capacity, "the rebuild needs no growth");
    assert_eq!(shape(&tiny), expected);
}
