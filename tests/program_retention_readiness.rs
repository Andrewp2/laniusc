//! Readiness of retained non-trait facts (docs/compiler-program-retention.md):
//! receiver parameter terms, pattern syntax, variant constructor callees,
//! unit and never call results and generic match types. One frontend job
//! exports into a store. The test reads the store only and checks that each
//! value row and use carries a term of the caller's binder chain, and that
//! non-value syntax (patterns, bounds, constructor callees) is classified as
//! such instead of being counted as an untyped value.

use std::sync::Arc;

use laniusc_compiler::{
    compiler::{GpuCompiler, GpuCompilerBackends},
    type_checker::program_retention::{PROBE_WORDS, ProgramRetention, ProgramRetentionCapacity, counts},
};

#[allow(unused_imports)]
use crate::common;

// `enter` calls a bound trait member through a caller-scoped `&F`; `read`
// calls inherent methods on `&Counter<T>` (a borrowed receiver, adjustment
// 1); `by_value` auto-references a local `Counter<T>` (adjustment 2); `peek`
// is an impl method calling its own impl's methods. `touch` returns unit,
// `halt` never returns. Patterns name variants with and without payloads.
const SOURCE: &str = r#"module ready::a;
pub trait Mapper<T, U> { pub fn apply(&self, value: T) -> U; }
pub trait Marker {}
pub struct Counter<T> { value: T }
pub impl<T> Counter<T> {
    pub fn get(&self) -> T { return self.value; }
    pub fn touch(&self) { }
    pub fn peek(&self) -> T { self.touch(); return self.get(); }
}
pub enum Choice<A, B> { Left(A), Right(B) }
pub enum Wrap<E> { Value(E), Empty }
fn halt() -> ! { assert(false); }
fn enter<F, T, U>(f: &F, value: T) -> U where F: Mapper<T, U> { return f.apply(value); }
fn read<T>(c: &Counter<T>) -> T { c.touch(); return c.get(); }
fn by_value<T>(c: Counter<T>) -> T { return c.get(); }
fn left_or_halt<A, B>(c: Choice<A, B>) -> A { return match (c) { Left(inner) -> inner, Right(_) -> halt() }; }
fn left_or<A, B>(c: Choice<A, B>, fallback: A) -> A { return match (c) { Left(inner) -> inner, Right(_) -> fallback }; }
fn is_left<A, B>(c: Choice<A, B>) -> bool { return match (c) { Left(_) -> true, Right(_) -> false }; }
fn is_value<E>(w: Wrap<E>) -> bool { return match (w) { Value(_) -> true, Empty -> false }; }
fn wrapped<T, E>(e: E) -> Wrap<E> { return Wrap::Value(e); }
fn empty<E>() -> Wrap<E> { let none: Wrap<E> = Wrap::Empty; return none; }
fn checked<T>(v: T, n: i32) -> T { assert(n >= 0); return v; }
fn by_ref<T, U>(value: T, other: U) -> T where U: Mapper<T, T>, T: Marker { return value; }
fn inline<T: Mapper<T, T>, U>(value: T, other: U) -> T { return value; }
fn plain(c: Counter<i32>) -> i32 {
    c.touch();
    assert(c.get() > 0);
    let w: Wrap<i32> = Wrap::Value(1);
    let x: Choice<i32, bool> = Choice::Left(2);
    let held: bool = match (w) { Value(_) -> true, Empty -> false };
    return match (x) { Left(v) -> v, Right(_) -> halt() };
}
fn main() -> i32 { return plain(Counter { value: 1 }); }
"#;

const TERM_UNIT: u32 = 1;
const TERM_BOOL: u32 = 2;
const TERM_NEVER: u32 = 18;
const RT_NONE: u32 = 0xffff_fffd;
const RT_FIRST_TERM: u32 = 32;
const PARAM_BIT: u32 = 0x8000_0000;
const ID_MASK: u32 = 0x1fff_ffff;
const KIND_REF: u32 = 5;
const FORM_DIRECT: u32 = 1;
const FORM_METHOD: u32 = 2;
const FORM_CONSTRUCTOR: u32 = 4;
const FORM_INTRINSIC: u32 = 5;
const ROLE_VALUE: u32 = 1;
const ROLE_CALLEE: u32 = 3;
const ROLE_BOUND: u32 = 4;
const ROLE_PATTERN: u32 = 5;
const BIND_VARIANT: u32 = 3;
const ROW_MISSING: u32 = 4;
const HIR_TYPE: u32 = 5;
const HIR_CALL: u32 = 19;
const HIR_NAME: u32 = 22;
const HIR_PATH: u32 = 33;
const HIR_MATCH: u32 = 34;

fn fnv1a(text: &str) -> u32 {
    text.bytes().fold(0x811c_9dc5u32, |h, b| (h ^ b as u32).wrapping_mul(0x0100_0193))
}

struct Store {
    status: Vec<u32>,
    dir: Vec<u32>,
    segs: Vec<u32>,
    rows: Vec<u32>,
    tokens: Vec<u32>,
    bytes: Vec<u32>,
    uses: Vec<u32>,
    head: Vec<u32>,
    meta: Vec<u32>,
    args: Vec<u32>,
    owner: Vec<u32>,
    params: Vec<u32>,
    dir_trait: Vec<u32>,
    traits: Vec<u32>,
}

impl Store {
    fn read(store: &ProgramRetention) -> Self {
        let status = store.status().unwrap();
        let read = |name: &str, words: usize| store.read_store_words(name, words).unwrap();
        Self {
            dir: read("rt_dir", status[4] as usize * 16),
            segs: read("rt_segments", status[9] as usize * 24),
            rows: read("rt_seg_rows", status[10] as usize * 28),
            bytes: read("rt_seg_bytes", status[12] as usize),
            tokens: read("rt_seg_tokens", status[13] as usize * 4),
            uses: read("rt_uses", status[8] as usize * 12),
            head: read("rt_term_head", status[2] as usize * 4),
            meta: read("rt_term_meta", status[2] as usize * 4),
            args: read("rt_term_args", status[3] as usize),
            owner: read("rt_term_owner", status[2] as usize * 2),
            params: read("rt_param_key", status[1] as usize * 4),
            dir_trait: read("rt_dir_trait", status[4] as usize * 4),
            traits: read("rt_traits", status[14] as usize * 8),
            status,
        }
    }

    /// The predicate record a BOUND row names (export step 14e).
    fn bound_record(&self, decl: u32, ordinal: u32) -> &[u32] {
        let entry = self.dir.chunks_exact(16).position(|e| e[0] == decl).unwrap();
        let block = &self.dir_trait[entry * 4..entry * 4 + 4];
        assert!(ordinal < block[1], "ordinal {ordinal} inside the predicate block {block:?}");
        let record = (block[0] + ordinal) as usize;
        &self.traits[record * 8..record * 8 + 8]
    }

    fn entry(&self, decl: u32) -> &[u32] {
        self.dir.chunks_exact(16).find(|e| e[0] == decl).expect("directory entry")
    }

    /// The body text of each entry with a segment.
    fn texts(&self) -> Vec<(u32, String)> {
        self.dir
            .chunks_exact(16)
            .filter(|e| e[8] != u32::MAX)
            .map(|e| {
                let s = self.seg(e[0]);
                let (len, base) = (s[18] as usize, s[20] as usize);
                let text = (0..len).map(|i| (self.bytes[base + i / 4] >> ((i % 4) * 8)) as u8).collect();
                (e[0], String::from_utf8(text).unwrap())
            })
            .collect()
    }

    fn named(&self, prefix: &str) -> u32 {
        let found = self.texts().into_iter().filter(|(_, t)| t.starts_with(prefix)).collect::<Vec<_>>();
        assert_eq!(found.len(), 1, "one body starts with {prefix:?}: {:?}", self.texts());
        found[0].0
    }

    fn seg(&self, decl: u32) -> &[u32] {
        let s = self.entry(decl)[8] as usize;
        &self.segs[s * 24..s * 24 + 24]
    }

    fn body_rows(&self, decl: u32) -> Vec<&[u32]> {
        let s = self.seg(decl);
        self.rows[s[1] as usize * 28..(s[1] + s[2]) as usize * 28].chunks_exact(28).collect()
    }

    fn token_hash(&self, decl: u32, token: u32) -> u32 {
        self.tokens[(self.seg(decl)[19] + token) as usize * 4 + 3]
    }

    fn row_named<'a>(&self, decl: u32, rows: &[&'a [u32]], kind: u32, name: &str) -> Vec<&'a [u32]> {
        rows.iter().copied().filter(|r| r[0] == kind && self.token_hash(decl, r[2]) == fnv1a(name)).collect()
    }

    fn uses_of(&self, decl: u32) -> Vec<&[u32]> {
        self.uses.chunks_exact(12).filter(|u| u[0] == decl).collect()
    }

    fn stored(&self, term: u32) -> bool {
        (RT_FIRST_TERM..PARAM_BIT).contains(&term)
    }

    fn kind(&self, term: u32) -> u32 {
        if self.stored(term) { self.head[term as usize * 4] & 0xff } else { 0 }
    }

    fn arg(&self, term: u32, index: usize) -> u32 {
        self.args[self.meta[term as usize * 4] as usize + index]
    }

    /// The owner DeclIds of a term's parameter leaves.
    fn owners(&self, term: u32) -> [u32; 2] {
        if self.stored(term) {
            [self.owner[term as usize * 2], self.owner[term as usize * 2 + 1]]
        } else if term & PARAM_BIT != 0 && term < 0xffff_fffc {
            [self.params[(term & ID_MASK) as usize * 4], 0]
        } else {
            [0, 0]
        }
    }

    fn leaf_owner(&self, leaf: u32) -> u32 {
        assert!(leaf & PARAM_BIT != 0 && !self.stored(leaf), "{leaf:#x} is a parameter leaf");
        self.params[(leaf & ID_MASK) as usize * 4]
    }
}

fn export() -> (Arc<ProgramRetention>, Store) {
    let compiler =
        pollster::block_on(GpuCompiler::new_with_backends(GpuCompilerBackends::frontend_only())).unwrap();
    let store = ProgramRetention::new(ProgramRetentionCapacity::default()).unwrap();
    store.begin_build().unwrap();
    compiler.attach_program_retention(Some(store.clone()));
    pollster::block_on(compiler.semantic_interface_for_source_pack(30, &[SOURCE])).expect("job");
    compiler.attach_program_retention(None);
    pollster::block_on(compiler.release_resident_job_buffers());
    drop(compiler);
    store.poison_scratch();
    let read = Store::read(&store);
    (store, read)
}

#[test]
fn program_retention_exports_ready_receivers_patterns_and_call_results() {
    let (store, s) = export();
    let report = store.job_reports().last().cloned().unwrap();
    for entry in s.dir.chunks_exact(16).filter(|e| e[15] != 0 || e[8] != u32::MAX) {
        let stats = if entry[8] != u32::MAX { s.seg(entry[0])[12..16].to_vec() } else { vec![] };
        eprintln!("entry {:?} stats {stats:?}", &entry[..16]);
    }
    for decl in s.texts().iter().map(|(d, _)| *d) {
        for row in s.body_rows(decl).iter().filter(|r| r[15] & ROW_MISSING != 0) {
            eprintln!("missing row in {decl}: {row:?}");
        }
    }
    for u in s.uses.chunks_exact(12) {
        eprintln!("use {u:?}");
    }
    assert_eq!(report.counts[counts::INVARIANTS], 0, "first invariant {}: {report:?}",
        report.counts[counts::FIRST_INVARIANT]);
    assert_eq!(report.counts[counts::INCOMPLETE], 0, "{report:?}");
    assert!(report.ready, "{report:?}");
    assert_eq!(s.status[counts::READY], 1);

    // Receivers: the accepted receiver parameter is a term of the caller's
    // scope, and it is the matched receiver (adjustment 1) or a reference
    // to it (adjustment 2).
    let mut receivers = [0usize; 3];
    for (caller, expect) in [("fn enter<", 0), ("fn read<", 1), ("fn by_value<", 2), ("fn peek(", 1)] {
        let decl = s.named(caller);
        let parent = s.entry(decl)[2];
        let methods = s.uses_of(decl).into_iter().filter(|u| u[2] & 0xff == FORM_METHOD).collect::<Vec<_>>();
        assert!(!methods.is_empty(), "{caller} has method uses");
        for u in methods {
            let (matched, receiver, adjust) = (u[6], u[7], (u[2] >> 8) & 0xff);
            for owner in s.owners(receiver).into_iter().chain(s.owners(matched)) {
                assert!(owner == 0 || owner == decl || owner == parent,
                    "{caller}: receiver terms are caller-scoped: {u:?}");
            }
            assert_ne!(s.owners(receiver), [0, 0], "{caller}: the receiver is symbolic in the template");
            match adjust {
                1 => assert_eq!(receiver, matched, "{caller}: a borrowed receiver is passed as matched"),
                2 => {
                    assert_eq!(s.kind(receiver), KIND_REF, "{caller}: auto-reference: {u:?}");
                    assert_eq!(s.arg(receiver, 0), matched, "{caller}: &matched");
                }
                _ => panic!("{caller}: unexpected receiver adjustment {u:?}"),
            }
            receivers[expect.min(2)] += 1;
        }
    }
    assert!(receivers.iter().all(|n| *n > 0), "bound, borrowed and auto-referenced receivers: {receivers:?}");

    // Call results: unit statements, the never-returning call and the
    // assert intrinsic carry the checker's authoritative result.
    let read = s.named("fn read<");
    let touch = s.uses_of(read).into_iter().filter(|u| u[5] == TERM_UNIT).count();
    assert_eq!(touch, 1, "`c.touch()` returns unit");
    let checked = s.named("fn checked<");
    let asserts = s.uses_of(checked);
    assert_eq!(asserts.len(), 1);
    assert_eq!((asserts[0][2] & 0xff, asserts[0][5]), (FORM_INTRINSIC, TERM_UNIT), "assert returns unit");
    let halt = s.uses_of(s.named("fn left_or_halt<"));
    assert_eq!(halt.len(), 1, "only `halt()` is a use; the patterns are not");
    assert_eq!((halt[0][2] & 0xff, halt[0][5]), (FORM_DIRECT, TERM_NEVER), "halt never returns");
    for u in s.uses.chunks_exact(12) {
        assert!(u[5] != RT_NONE && u[5] < 0xffff_fffc, "every use has a result term: {u:?}");
        assert!(matches!(u[2] & 0xff, 1..=6 | 8), "every use resolves: {u:?}");
    }
    // `plain` is nongeneric: no segment, but its uses are discovery roots.
    // Its patterns (`Value(_)`, `Empty`, `Left(v)`, `Right(_)`) are not.
    let plain = s.uses.chunks_exact(12)
        .find(|u| s.entry(u[0])[8] == u32::MAX && u[2] & 0xff == FORM_METHOD)
        .expect("`plain` calls `c.touch()`")[0];
    let plain_uses = s.uses_of(plain);
    let forms = |form: u32| plain_uses.iter().filter(|u| u[2] & 0xff == form).count();
    assert_eq!(forms(FORM_CONSTRUCTOR), 2, "`Wrap::Value(1)` and `Choice::Left(2)`: {plain_uses:?}");
    assert_eq!(forms(FORM_INTRINSIC), 1);
    assert!(plain_uses.iter().any(|u| u[2] & 0xff == FORM_METHOD && u[5] == TERM_UNIT));
    assert!(plain_uses.iter().any(|u| u[2] & 0xff == FORM_DIRECT && u[5] == TERM_NEVER));

    // Patterns: role PATTERN with the variant binding, never a use.
    let is_left = s.named("fn is_left<");
    let rows = s.body_rows(is_left);
    for name in ["Left", "Right"] {
        let pattern = s.row_named(is_left, &rows, HIR_PATH, name);
        assert_eq!(pattern.len(), 1, "{name}");
        let r = pattern[0];
        assert_eq!((r[14], r[13], r[20]), (ROLE_PATTERN, RT_NONE, BIND_VARIANT), "{name}: {r:?}");
        assert_eq!(r[15] & ROW_MISSING, 0);
    }
    let is_value = s.named("fn is_value<");
    let rows = s.body_rows(is_value);
    let unit_pattern = rows.iter().find(|r| r[14] == ROLE_PATTERN && r[22] == 1).expect("`Empty` pattern");
    assert_eq!((unit_pattern[13], unit_pattern[20]), (RT_NONE, BIND_VARIANT), "{unit_pattern:?}");
    assert!(s.uses_of(is_value).is_empty(), "patterns are not uses");
    // Runtime variant values stay uses with caller-scoped results.
    let empty = s.named("fn empty<");
    let value = s.uses_of(empty);
    assert_eq!(value.len(), 1);
    assert_eq!(value[0][2] & 0xff, FORM_CONSTRUCTOR);
    let rows = s.body_rows(empty);
    let path = rows.iter().find(|r| r[0] == HIR_PATH && r[14] == ROLE_VALUE).expect("`Wrap::Empty` value");
    assert_eq!(path[12], value[0][5]);
    assert_eq!(s.owners(path[12]), [empty, 0], "`Wrap<E>` over the function's E");

    // Constructor callee: callable syntax with the variant binding; the
    // caller-scoped instance is the call's result.
    let wrapped = s.named("fn wrapped<");
    let rows = s.body_rows(wrapped);
    let callee = rows.iter().find(|r| r[14] == ROLE_CALLEE).expect("`Wrap::Value` callee");
    assert_eq!((callee[0], callee[12], callee[20]), (HIR_PATH, RT_NONE, BIND_VARIANT), "{callee:?}");
    let call = rows.iter().find(|r| r[0] == HIR_CALL).unwrap();
    assert_eq!(s.owners(call[12]), [wrapped, 0], "`Wrap<E>` over the function's E");
    assert_eq!(s.uses_of(wrapped)[0][5], call[12]);

    // Match results: a closed symbolic type in the enclosing binder, with
    // a never arm or a value arm.
    for name in ["fn left_or_halt<", "fn left_or<"] {
        let decl = s.named(name);
        let rows = s.body_rows(decl);
        let matched = rows.iter().find(|r| r[0] == HIR_MATCH).unwrap();
        assert_eq!(matched[14], ROLE_VALUE);
        assert_eq!(s.leaf_owner(matched[12]), decl, "{name}: the match is the function's A: {matched:?}");
        let inner = s.row_named(decl, &rows, HIR_NAME, "inner");
        assert!(inner.iter().all(|r| r[12] == matched[12]), "{name}: the arm value is A");
    }
    let rows = s.body_rows(is_left);
    assert_eq!(rows.iter().find(|r| r[0] == HIR_MATCH).unwrap()[12], TERM_BOOL);

    // Bounds are not value types. Each BOUND row names its predicate record
    // by ordinal: the record's owner is the function and its ordinal is the
    // row's. (`T: &Marker` heads are rejected by the frontend, LNC0008.)
    for (name, predicates, rows_expected) in [("fn enter<", 1, 1), ("fn by_ref<", 2, 2), ("fn inline<", 1, 1)] {
        let decl = s.named(name);
        let rows = s.body_rows(decl);
        let bounds = rows.iter().filter(|r| r[14] == ROLE_BOUND).collect::<Vec<_>>();
        assert_eq!(bounds.len(), rows_expected, "{name}: {bounds:?}");
        let mut ordinals = Vec::new();
        for r in &bounds {
            assert_eq!(r[0], HIR_TYPE);
            assert_eq!((r[12], r[15] & ROW_MISSING), (RT_NONE, 0), "{name}: {r:?}");
            let record = s.bound_record(decl, r[13]);
            assert_eq!((record[0], record[1]), (decl, 1 | (r[13] << 8)), "{name}: {record:?}");
            ordinals.push(r[13]);
        }
        ordinals.sort();
        ordinals.dedup();
        assert_eq!(ordinals.len(), predicates, "{name}: every predicate is named: {ordinals:?}");
    }
    // The acceptance probe instantiates the bounded templates from the
    // store and checks every row reference, including the BOUND links.
    let requests = [("fn by_ref<", [2, 3, TERM_BOOL]), ("fn inline<", [2, 3, TERM_BOOL]),
        ("fn left_or_halt<", [2, 3, TERM_BOOL]), ("fn is_value<", [1, 3, 0])];
    let requests = requests.map(|(name, [n, a, b])| [s.named(name), n, a, b]);
    let words = store.resolve_probe(&requests).unwrap();
    let lanes = words.chunks_exact(PROBE_WORDS).collect::<Vec<_>>();
    for (lane, request) in lanes[lanes.len() - requests.len()..].iter().zip(&requests) {
        assert_eq!(lane[0], 1, "eligible: {request:?} {lane:?}");
        assert_eq!((lane[7], lane[9], lane[20]), (0, 0, 0), "failed, bad references, missing: {lane:?}");
    }
    for decl in s.texts().iter().map(|(d, _)| *d) {
        assert_eq!(s.seg(decl)[12..16], [0, 0, 0, 0], "segment statistics of {decl}");
    }
}
