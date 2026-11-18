//! Production substitution over retained terms
//! (docs/compiler-retained-substitution.md).
//!
//! Synthetic programs are built in the store by a single-lane GPU script
//! (`shaders/tests/seed_retained_substitution_fixture.slang`): every declaration,
//! parameter, term, environment and expected result is interned by the
//! store itself. The script also writes the requests. The export test makes
//! its requests on the GPU from the uses two frontend jobs retained.

use std::sync::Arc;

use laniusc_compiler::{
    compiler::{GpuCompiler, GpuCompilerBackends},
    type_checker::program_retention::{
        ProgramRetention,
        ProgramRetentionCapacity,
        counts,
        substitution::{
            CONSUMER_KERNEL,
            FIXTURE_KERNEL,
            RESULT_WORDS,
            RetainedSubstitution,
            SubstitutionCapacity,
            SubstitutionReport,
            SubstitutionRequests,
            SubstitutionRun,
            USES_KERNEL,
            env_cause,
            run_test_kernel,
            status,
            words,
        },
    },
};

#[allow(unused_imports)]
use crate::common;

const NAMED: u32 = 2;
const ARRAY: u32 = 3;
const SLICE: u32 = 4;
const REF: u32 = 5;
const CC_VALUE: u32 = 8;
const CC_CAST: u32 = 9;
const CC_COUNT: u32 = 10;
const ENV: u32 = 16;
const NS_CALLABLE: u32 = 1;
const NS_NOMINAL: u32 = 2;
const NS_IMPL: u32 = 4;
const TYPE: u32 = 1;
const CONST: u32 = 2;
const BOOL: u32 = 2;
const I32: u32 = 3;
const U32: u32 = 4;
const U64: u32 = 10;
const I8: u32 = 11;
const U8: u32 = 13;
const U16: u32 = 14;
const USIZE: u32 = 17;
const COMMITTED: u32 = 2;
const STAGED: u32 = 1;
const RT_UNKNOWN: u32 = 0xffff_fffe;
const RT_NONE: u32 = 0xffff_fffd;
const RT_FIT_FAILED: u32 = 0xffff_fffc;
const SLOT_LEAF: u32 = 0x8000_0000 | 0x2000_0000 | 1;

type R = u32;

#[derive(Clone, Copy)]
enum W {
    I(u32),
    R(R),
}

#[derive(Clone, Copy, Debug)]
enum Expect {
    /// Success with this expected term register (None: expected terms skipped).
    Ok(Option<R>),
    /// Failure: every field is checked; absent node/value means RT_NONE.
    Fail(Failure),
}

/// The words of a failed result. Registers, except `env` (a register, or
/// `CLOSED` for the environment 0 of a closed evaluation) and the codes.
#[derive(Clone, Copy, Debug, Default)]
struct Failure {
    status: u32,
    node: Option<R>,
    env: Option<R>,
    value: Option<R>,
    /// ENV cause, inner status, inner ENV cause.
    cause: Option<[u32; 3]>,
}

/// `Failure::env` of a failure inside a closed evaluation.
const CLOSED: R = u32::MAX;

fn failure(status: u32, node: Option<R>, value: Option<R>) -> Failure {
    Failure {
        status,
        node,
        value,
        ..Failure::default()
    }
}

/// A construction script for the GPU fixture interpreter.
struct Script {
    ops: Vec<u32>,
    regs: u32,
    expected: bool,
    expects: Vec<Expect>,
}

impl Script {
    fn new(library: u32, expected: bool) -> Self {
        Self {
            ops: vec![library],
            regs: 0,
            expected,
            expects: Vec::new(),
        }
    }
    fn reg(&mut self) -> R {
        self.regs += 1;
        self.regs - 1
    }
    fn set(&mut self, value: u32) -> R {
        let r = self.reg();
        self.ops.extend([7, r, value]);
        r
    }
    fn decl(&mut self, ns: u32, local: u32) -> R {
        let r = self.reg();
        self.ops.extend([1, r, ns, local]);
        r
    }
    fn param(&mut self, owner: R, domain: u32, ordinal: u32, scalar: u32) -> R {
        let r = self.reg();
        self.ops.extend([2, r, owner, domain, ordinal, scalar]);
        r
    }
    fn leaf(&mut self, param: R) -> R {
        let r = self.reg();
        self.ops.extend([3, r, param]);
        r
    }
    fn mk(&mut self, kind: u32, type_slots: u32, w: [W; 3], args: &[R]) -> R {
        let r = self.reg();
        let mut mask = 0;
        let mut words = [0u32; 3];
        for (i, word) in w.iter().enumerate() {
            match *word {
                W::I(v) => words[i] = v,
                W::R(reg) => {
                    words[i] = reg;
                    mask |= 1 << i;
                }
            }
        }
        self.ops.extend([
            4,
            r,
            kind,
            args.len() as u32,
            type_slots,
            words[0],
            words[1],
            words[2],
            mask,
        ]);
        self.ops.extend(args);
        r
    }
    fn entry(
        &mut self,
        decl: R,
        kind: u32,
        parent: Option<R>,
        types: &[R],
        consts: &[R],
        state: u32,
        incomplete: u32,
    ) {
        self.ops.extend([
            5,
            decl,
            kind,
            parent.unwrap_or(u32::MAX),
            types.len() as u32,
            consts.len() as u32,
            state,
            incomplete,
        ]);
        self.ops.extend(types);
        self.ops.extend(consts);
    }
    /// `dst = src ^ mask` (a malformed reference).
    fn flip(&mut self, src: R, mask: u32) -> R {
        let r = self.reg();
        self.ops.extend([9, r, src, mask]);
        r
    }
    fn clear_ready(&mut self) {
        self.ops.push(8);
    }
    fn request(&mut self, decl: R, env: R, term: R, expect: Expect) {
        self.ops.extend([6, decl, env, term]);
        self.expects.push(expect);
    }
    fn ok(&mut self, decl: R, env: R, term: R, expected: Option<R>) {
        self.request(decl, env, term, Expect::Ok(expected));
    }
    fn bad(&mut self, decl: R, env: R, term: R, status: u32, node: Option<R>, value: Option<R>) {
        let mut f = failure(status, node, value);
        f.env = Some(if status == status::NOT_READY || status == status::DECL { CLOSED } else { env });
        self.request(decl, env, term, Expect::Fail(f));
    }
    fn fails(&mut self, decl: R, env: R, term: R, f: Failure) {
        self.request(decl, env, term, Expect::Fail(f));
    }

    // Term helpers.
    fn value(&mut self, scalar: u32, x: u32) -> R {
        self.mk(CC_VALUE, 0, [W::I(scalar), W::I(x), W::I(0)], &[])
    }
    fn count(&mut self, x: u32) -> R {
        self.mk(CC_COUNT, 0, [W::I(x), W::I(0), W::I(0)], &[])
    }
    fn cast(&mut self, target: u32, child: R) -> R {
        self.mk(CC_CAST, 0, [W::I(target), W::I(0), W::I(0)], &[child])
    }
    fn unary(&mut self, kind: u32, t: R) -> R {
        self.mk(kind, 0, [W::I(0); 3], &[t])
    }
    fn array(&mut self, t: R, n: R) -> R {
        self.mk(ARRAY, 0, [W::I(0); 3], &[t, n])
    }
    /// A NAMED term: its type-slot count is its type-operand count.
    fn named(&mut self, decl: R, const_mask: u32, args: &[R]) -> R {
        let types = args.len() as u32 - const_mask.count_ones();
        self.mk(NAMED, types, [W::R(decl), W::I(const_mask), W::I(0)], args)
    }
    fn env(&mut self, owner: R, type_mask: u32, const_mask: u32, args: &[R]) -> R {
        self.mk(
            ENV,
            type_mask.count_ones(),
            [W::R(owner), W::I(type_mask), W::I(const_mask)],
            args,
        )
    }
    /// An expected term, or None when expected terms are skipped.
    fn ex(&mut self, build: impl FnOnce(&mut Self) -> R) -> Option<R> {
        if self.expected {
            Some(build(self))
        } else {
            None
        }
    }
    fn finish(&self) -> Vec<u32> {
        let mut ops = self.ops.clone();
        ops.push(0);
        ops
    }
}

/// The synthetic program: F<T, U, const N: u8, const M: usize>, an impl
/// I<TI> with a method G<TG> inheriting TI, W with 32 type and 32 constant
/// parameters, a staged S and an incomplete X.
struct Program {
    s: Script,
    f: R,
    g: R,
    i: R,
    w: R,
    s_decl: R,
    x: R,
    big: R,
    pair: R,
    boxed: R,
    wide: R,
    t: R,
    u: R,
    n: R,
    m: R,
    ti: R,
    tg: R,
    wt: Vec<R>,
    wc: Vec<R>,
    scalar: [R; 32],
}

impl Program {
    fn new(library: u32, expected: bool) -> Self {
        let mut s = Script::new(library, expected);
        let scalar: [R; 32] = std::array::from_fn(|k| s.set(k as u32));
        let f = s.decl(NS_CALLABLE, 0x4000_0001);
        let i = s.decl(NS_IMPL, 1);
        let g = s.decl(NS_CALLABLE, 0x4000_0002);
        let w = s.decl(NS_CALLABLE, 0x4000_0003);
        let s_decl = s.decl(NS_CALLABLE, 0x4000_0004);
        let x = s.decl(NS_CALLABLE, 0x4000_0005);
        let big = s.decl(NS_CALLABLE, 0x4000_0006);
        let pair = s.decl(NS_NOMINAL, 0x10);
        let boxed = s.decl(NS_NOMINAL, 0x11);
        let wide = s.decl(NS_NOMINAL, 0x12);
        let t = s.param(f, TYPE, 0, 0);
        let u = s.param(f, TYPE, 1, 0);
        let n = s.param(f, CONST, 0, U8);
        let m = s.param(f, CONST, 1, USIZE);
        let ti = s.param(i, TYPE, 0, 0);
        let tg = s.param(g, TYPE, 0, 0);
        let wt: Vec<R> = (0..32).map(|k| s.param(w, TYPE, k, 0)).collect();
        let wc: Vec<R> = (0..32).map(|k| s.param(w, CONST, k, USIZE)).collect();
        s.entry(f, 1, None, &[t, u], &[n, m], COMMITTED, 0);
        s.entry(i, 7, None, &[ti], &[], COMMITTED, 0);
        s.entry(g, 2, Some(i), &[ti, tg], &[], COMMITTED, 0);
        s.entry(w, 1, None, &wt, &wc, COMMITTED, 0);
        s.entry(s_decl, 1, None, &[], &[], STAGED, 0);
        s.entry(x, 1, None, &[], &[], COMMITTED, 1);
        let big_params: Vec<R> = (0..33).map(|k| s.param(big, TYPE, k, 0)).collect();
        s.entry(big, 1, None, &big_params, &[], COMMITTED, 0);
        let [t, u, n, m, ti, tg] = [t, u, n, m, ti, tg].map(|p| s.leaf(p));
        let wt = wt.into_iter().map(|p| s.leaf(p)).collect();
        let wc = wc.into_iter().map(|p| s.leaf(p)).collect();
        Self {
            s,
            f,
            g,
            i,
            w,
            s_decl,
            x,
            big,
            pair,
            boxed,
            wide,
            t,
            u,
            n,
            m,
            ti,
            tg,
            wt,
            wc,
            scalar,
        }
    }

    fn env_f(&mut self, t: R, u: R, n: R, m: R) -> R {
        let f = self.f;
        self.s.env(f, 3, 3, &[t, u, n, m])
    }
    fn pair(&mut self, a: R, b: R) -> R {
        let p = self.pair;
        self.s.named(p, 0, &[a, b])
    }
    fn boxed(&mut self, c: R) -> R {
        let b = self.boxed;
        self.s.named(b, 1, &[c])
    }
    fn sc(&self, k: u32) -> R {
        self.scalar[k as usize]
    }

    /// The shared DAG D(i+1) = Pair<D(i), D(i)> over T, and its expected
    /// image over `base`.
    fn dag(&mut self, depth: u32, base: Option<R>) -> (R, Option<R>) {
        let mut d = self.t;
        let mut e = base;
        for _ in 0..depth {
            d = self.pair(d, d);
            e = match e {
                Some(e) if self.s.expected => Some(self.pair(e, e)),
                _ => None,
            };
        }
        (d, e)
    }
}

fn bigger_store() -> ProgramRetentionCapacity {
    let mut capacity = ProgramRetentionCapacity::default();
    capacity.arenas[2] = 1 << 17;
    capacity.arenas[3] = 1 << 19;
    capacity.slots[2] = 1 << 18;
    capacity
}

struct Fixture {
    expects: Vec<Expect>,
    regs: Vec<u32>,
    requests: SubstitutionRequests,
}

fn build_fixture(store: &ProgramRetention, script: &Script) -> Fixture {
    build_fixture_into(store, script, script.expects.len() as u32)
}

/// A fresh build running `script`, whose requests go into buffers of
/// `capacity` rows (the script writes its full count either way).
fn build_fixture_into(store: &ProgramRetention, script: &Script, capacity: u32) -> Fixture {
    store.begin_build().unwrap();
    produce(store, script, capacity)
}

/// Runs `script` in the store's current build (a producer run).
fn produce(store: &ProgramRetention, script: &Script, capacity: u32) -> Fixture {
    let requests = SubstitutionRequests::new(capacity);
    let out = run_test_kernel(
        store,
        FIXTURE_KERNEL,
        &requests,
        &script.finish(),
        16 + script.regs as usize,
        1,
        &[],
    )
    .expect("fixture kernel");
    assert_eq!(out[0], 0, "fixture overflowed the store: {:?}", &out[..4]);
    assert_eq!(out[3], 0, "fixture script error at op word {}", out[3]);
    assert_eq!(out[1] as usize, script.expects.len());
    Fixture {
        expects: script.expects.clone(),
        regs: out[16..].to_vec(),
        requests,
    }
}

fn run(
    engine: &mut RetainedSubstitution,
    store: &ProgramRetention,
    fixture: &Fixture,
) -> (SubstitutionReport, Vec<[u32; RESULT_WORDS]>) {
    let started = std::time::Instant::now();
    let report = engine
        .run(store, &fixture.requests)
        .expect("substitution")
        .published()
        .expect("published");
    let elapsed = started.elapsed();
    let results = engine.read_results(fixture.expects.len()).unwrap();
    eprintln!(
        "substitution: {} requests, {} tasks ({} spare), {} edges, {} expansion rounds, {} eval rounds, \
         max frontier {}, max arity {}, edge lanes {}, eval lanes {}, new store terms {}, attempts {}, batches {}, \
         dispatches {}, growths {}/{}, rolled back terms {}, statuses {:?}, {:.2?} host wall time",
        fixture.expects.len(),
        report.tasks(),
        report.counts[words::SPARE_TASKS],
        report.edges(),
        report.expansion_rounds(),
        report.eval_rounds(),
        report.max_frontier(),
        report.counts[words::MAX_ARITY],
        report.counts[words::EDGE_LANES],
        report.counts[words::EVAL_LANES],
        report.counts[words::STORE_NEW_TERMS],
        report.attempts,
        report.batches,
        report.dispatches,
        report.growths,
        report.store_growths,
        report.rolled_back_terms,
        &report.status_counts()[..18],
        elapsed,
    );
    assert_eq!(report.counts[words::STATE], words::STATE_PUBLISHED);
    let id = report.publication;
    assert_eq!(id.generation, store.generation());
    assert_eq!(id.requests as usize, fixture.expects.len());
    assert_eq!(engine.publication(store).map(|p| p.id), Some(id));
    for (k, r) in results.iter().enumerate() {
        assert_eq!(r[6], id.run, "result {k} belongs to this run");
        assert_eq!(r[7], id.generation, "result {k} belongs to this build");
        assert_eq!(r[5], k as u32, "result {k} keeps its request tag");
    }
    (report, results)
}

fn reg(fixture: &Fixture, r: R) -> u32 {
    fixture.regs[r as usize]
}

fn check(fixture: &Fixture, results: &[[u32; RESULT_WORDS]]) {
    for (k, (expect, r)) in fixture.expects.iter().zip(results).enumerate() {
        match *expect {
            Expect::Ok(expected) => {
                assert_eq!(r[1], status::OK, "request {k}: {r:?}");
                assert_eq!(
                    (r[2], r[3], r[4], r[8], r[9], r[10]),
                    (RT_NONE, 0, RT_NONE, 0, 0, 0),
                    "request {k}: a success carries no provenance: {r:?}"
                );
                if let Some(e) = expected {
                    assert_eq!(
                        r[0],
                        reg(fixture, e),
                        "request {k} result is the expected term: {r:?}"
                    );
                }
            }
            Expect::Fail(f) => {
                assert_eq!(r[1], f.status, "request {k} status: {r:?}");
                assert_eq!(
                    r[0], RT_UNKNOWN,
                    "request {k}: a failure never carries a term"
                );
                assert_eq!(r[2], f.node.map_or(RT_NONE, |n| reg(fixture, n)), "request {k} failed node: {r:?}");
                let env = f.env.expect("every failure specifies its environment");
                let env = if env == CLOSED { 0 } else { reg(fixture, env) };
                assert_eq!(r[3], env, "request {k} failed environment: {r:?}");
                assert_eq!(r[4], f.value.map_or(RT_NONE, |v| reg(fixture, v)), "request {k} failed value: {r:?}");
                let cause = f.cause.unwrap_or([0, 0, 0]);
                assert_eq!([r[8], r[9], r[10]], cause, "request {k} ENV cause: {r:?}");
            }
        }
    }
}

/// Every correctness case of the contract.
fn cases(library: u32, expected: bool) -> Script {
    let mut p = Program::new(library, expected);
    let (i32_, bool_, u8_) = (p.sc(I32), p.sc(BOOL), p.sc(U8));
    let v5 = p.s.value(U8, 5);
    let w5 = p.s.value(USIZE, 5);
    let env1 = p.env_f(i32_, bool_, v5, w5);
    let (f, g, i, w) = (p.f, p.g, p.i, p.w);
    let (t, u, n, m, ti, tg) = (p.t, p.u, p.n, p.m, p.ti, p.tg);

    // Shared DAG, requested three times.
    let (d40, e40) = p.dag(40, Some(i32_));
    for _ in 0..3 {
        p.s.ok(f, env1, d40, e40);
    }

    // Depth: REF^63(T) has height 64.
    let mut r = t;
    let mut r62 = t;
    let mut er = Some(i32_);
    for k in 0..63 {
        if k == 62 {
            r62 = r;
        }
        r = p.s.unary(REF, r);
        er = er.map(|e| p.s.unary(REF, e));
    }
    let ref_i32 = p.s.unary(REF, i32_);
    let env2 = p.env_f(ref_i32, bool_, v5, w5);
    p.s.ok(f, env1, r, er);
    p.s.bad(f, env2, r, status::DEPTH, Some(r), None);
    p.s.ok(f, env2, r62, er);

    // Width: 64 slots.
    let wt = p.wt.clone();
    let wc = p.wc.clone();
    let mut bindings: Vec<R> = (0..32).map(|k| p.sc(k % 16 + 2)).collect();
    let type_bindings = bindings.clone();
    for k in 0..32 {
        let v = p.s.value(USIZE, k);
        bindings.push(v);
    }
    let env_w = p.s.env(w, u32::MAX, u32::MAX, &bindings);
    let leaves: Vec<R> = wt.iter().chain(&wc).copied().collect();
    let nested_w = p.s.env(w, u32::MAX, u32::MAX, &leaves);
    let wide = p.wide;
    let wide_t = p.s.named(wide, 0, &wt);
    let wide_e = p.s.ex(|s| s.named(wide, 0, &type_bindings));
    p.s.ok(w, env_w, nested_w, expected.then_some(env_w));
    p.s.ok(w, env_w, wide_t, wide_e);

    // Count classes: N: u8 = 5 and M: usize = 5 give one array identity.
    let arr5 = p.s.ex(|s| {
        let c = s.count(5);
        s.array(i32_, c)
    });
    let a_n = p.s.array(t, n);
    let a_m = p.s.array(t, m);
    p.s.ok(f, env1, a_n, arr5);
    p.s.ok(f, env1, a_m, arr5);
    let a_um = p.s.array(u, m);
    let sl = p.s.unary(SLICE, a_um);
    let sl_e = p.s.ex(|s| {
        let c = s.count(5);
        let a = s.array(bool_, c);
        s.unary(SLICE, a)
    });
    p.s.ok(f, env1, sl, sl_e);

    // Constant projections.
    let cast8 = p.s.cast(U8, m);
    let casti8 = p.s.cast(I8, m);
    let cast16 = p.s.cast(U16, m);
    let nested = p.s.cast(U8, cast16);
    let box8 = p.boxed(cast8);
    let boxi8 = p.boxed(casti8);
    let box_nested = p.boxed(nested);
    let env_m = |p: &mut Program, x: u32| {
        let v = p.s.value(USIZE, x);
        p.env_f(i32_, bool_, v5, v)
    };
    for (x, ok) in [(5, true), (255, true), (256, false)] {
        let env = env_m(&mut p, x);
        if ok {
            let expected_box = if expected {
                let v = p.s.value(U8, x);
                Some(p.boxed(v))
            } else {
                None
            };
            p.s.ok(f, env, box8, expected_box);
        } else {
            let v = p.s.value(USIZE, x);
            p.s.bad(f, env, box8, status::FIT_FAILED, Some(cast8), Some(v));
        }
    }
    for (x, ok) in [(127, true), (128, false)] {
        let env = env_m(&mut p, x);
        if ok {
            let expected_box = if expected {
                let v = p.s.value(I8, x);
                Some(p.boxed(v))
            } else {
                None
            };
            p.s.ok(f, env, boxi8, expected_box);
        } else {
            let v = p.s.value(USIZE, x);
            p.s.bad(f, env, boxi8, status::FIT_FAILED, Some(casti8), Some(v));
        }
    }
    // Nested projections: the failing level is the result's provenance.
    let env300 = env_m(&mut p, 300);
    let v300 = p.s.value(U16, 300);
    p.s.bad(
        f,
        env300,
        box_nested,
        status::FIT_FAILED,
        Some(nested),
        Some(v300),
    );
    let env70000 = env_m(&mut p, 70000);
    let v70000 = p.s.value(USIZE, 70000);
    p.s.bad(
        f,
        env70000,
        box_nested,
        status::FIT_FAILED,
        Some(cast16),
        Some(v70000),
    );
    // Two failing arguments: the first in argument order.
    let w300 = p.s.value(USIZE, 300);
    let both = p.pair(box8, boxi8);
    p.s.bad(f, env300, both, status::FIT_FAILED, Some(cast8), Some(w300));
    let swapped = p.pair(boxi8, box8);
    p.s.bad(
        f,
        env300,
        swapped,
        status::FIT_FAILED,
        Some(casti8),
        Some(w300),
    );
    // A closed record still carries its pending fit.
    let w256 = p.s.value(USIZE, 256);
    let closed_bad = p.s.cast(U8, w256);
    let closed_box = p.boxed(closed_bad);
    p.s.fails(
        f,
        env1,
        closed_box,
        Failure {
            status: status::FIT_FAILED,
            node: Some(closed_bad),
            env: Some(CLOSED),
            value: Some(w256),
            ..Failure::default()
        },
    );
    let w7 = p.s.value(USIZE, 7);
    let closed_ok = p.s.cast(U8, w7);
    let closed_ok_box = p.boxed(closed_ok);
    let closed_e = if expected {
        let v = p.s.value(U8, 7);
        Some(p.boxed(v))
    } else {
        None
    };
    p.s.ok(f, env1, closed_ok_box, closed_e);
    // A request ENV is normalized: its closed evaluation must be the ENV
    // itself. A pending fit in a binding is evaluated even when the term
    // never reads the binding, and it fails the request as an ENV failure
    // with the fit's own provenance.
    let i300 = p.s.value(I32, 300);
    let pending = p.s.cast(U8, i300);
    let env3 = p.env_f(i32_, bool_, pending, w5);
    let box_n = p.boxed(n);
    let ptt = p.pair(t, t);
    for term in [box_n, ptt] {
        p.s.fails(
            f,
            env3,
            term,
            Failure {
                status: status::ENV,
                node: Some(pending),
                env: Some(env3),
                value: Some(i300),
                cause: Some([env_cause::EVAL, status::FIT_FAILED, 0]),
            },
        );
    }
    // A fitting pending binding is not normalized: the failed value is the
    // normalized ENV, the same TermId as the ENV written with the value.
    let cast5 = p.s.cast(U8, w5);
    let env_cast = p.env_f(i32_, bool_, cast5, w5);
    p.s.fails(
        f,
        env_cast,
        box_n,
        Failure {
            status: status::ENV,
            node: Some(env_cast),
            env: Some(env_cast),
            value: Some(env1),
            cause: Some([env_cause::NONCANONICAL, 0, 0]),
        },
    );
    // So is a pending fit deep inside a type binding.
    let boxed_cast7 = p.boxed(closed_ok);
    let env_deep = p.env_f(boxed_cast7, bool_, v5, w5);
    let boxed_decl = p.boxed;
    // Failure provenance is always checked, including in growth runs
    // that omit the success oracle's pre-interned results.
    let v = p.s.value(U8, 7);
    let b = p.s.named(boxed_decl, 1, &[v]);
    let env_deep_e = p.s.env(f, 3, 3, &[b, bool_, v5, w5]);
    p.s.fails(
        f,
        env_deep,
        ptt,
        Failure {
            status: status::ENV,
            node: Some(env_deep),
            env: Some(env_deep),
            value: Some(env_deep_e),
            cause: Some([env_cause::NONCANONICAL, 0, 0]),
        },
    );

    // ENV depth parity: an ENV is not a type. A type binding of height 64
    // is valid, so the ENV holding it (height 65) is too, and a nested ENV
    // rebuilt over it is not DEPTH. A binding of height 65 is DEPTH.
    let mut ref63 = i32_;
    for _ in 0..63 {
        ref63 = p.s.unary(REF, ref63);
    }
    let env64 = p.env_f(ref63, bool_, v5, w5);
    let nested_f = p.env_f(t, u, n, m);
    p.s.ok(f, env64, t, Some(ref63));
    p.s.ok(f, env64, nested_f, Some(env64));
    let ref64 = p.s.unary(REF, ref63);
    let env65 = p.env_f(ref64, bool_, v5, w5);
    p.s.fails(
        f,
        env65,
        t,
        Failure {
            status: status::ENV,
            node: Some(ref64),
            env: Some(env65),
            cause: Some([env_cause::EVAL, status::DEPTH, 0]),
            ..Failure::default()
        },
    );

    // Term kinds of closed evaluation (failed environment 0).
    let c5 = p.s.count(5);
    let arr_value = p.s.array(v5, c5);
    let slice_value = p.s.unary(SLICE, w5);
    let pair_slots =
        p.s.mk(NAMED, 0, [W::R(p.pair), W::I(0), W::I(0)], &[i32_, i32_]);
    let pair_mask =
        p.s.mk(NAMED, 1, [W::R(p.pair), W::I(4), W::I(0)], &[i32_, i32_]);
    let pair_const =
        p.s.mk(NAMED, 1, [W::R(p.pair), W::I(1), W::I(0)], &[i32_, i32_]);
    let boxed_type = p.s.mk(NAMED, 1, [W::R(p.boxed), W::I(0), W::I(0)], &[v5]);
    for (term, st, value) in [
        (arr_value, status::KIND, Some(v5)),
        (slice_value, status::KIND, Some(w5)),
        (pair_slots, status::INVARIANT, None),
        (pair_mask, status::INVARIANT, None),
        (pair_const, status::KIND, Some(i32_)),
        (boxed_type, status::KIND, Some(v5)),
    ] {
        p.s.fails(
            f,
            env1,
            term,
            Failure {
                status: st,
                node: Some(term),
                env: Some(CLOSED),
                value,
                ..Failure::default()
            },
        );
    }
    // Array lengths and projections of values that are not counts, closed
    // and through a binding: a negative i32, a bool, a u64 above 2^32, and
    // the u32 count word 0xffffffff that the canonical store reserves.
    let neg = p.s.value(I32, u32::MAX);
    let truth = p.s.value(BOOL, 1);
    let wide64 = p.s.mk(CC_VALUE, 0, [W::I(U64), W::I(5), W::I(1)], &[]);
    let max32 = p.s.value(U32, u32::MAX);
    for value in [neg, truth, wide64] {
        let arr = p.s.array(i32_, value);
        p.s.fails(
            f,
            env1,
            arr,
            Failure {
                status: status::COUNT,
                node: Some(arr),
                env: Some(CLOSED),
                value: Some(value),
                ..Failure::default()
            },
        );
    }
    for value in [neg, truth, wide64, max32] {
        let cast = p.s.cast(U64, value);
        let boxed = p.boxed(cast);
        p.s.fails(
            f,
            env1,
            boxed,
            Failure {
                status: status::UNSUPPORTED,
                node: Some(cast),
                env: Some(CLOSED),
                value: Some(value),
                ..Failure::default()
            },
        );
    }
    // Canonical array substitution uses cc_count_class, which preserves
    // this valid u32 count. Only CC_CAST uses the ambiguous cc_count
    // sentinel and rejects it; these two paths deliberately differ.
    let arr_max = p.s.array(i32_, max32);
    let arr_max_e = p.s.ex(|s| {
        let c = s.count(u32::MAX);
        s.array(i32_, c)
    });
    p.s.ok(f, env1, arr_max, arr_max_e);

    // Nested ENVs are checked against their owner's binder after
    // evaluation (failed environment = the task's environment).
    let nested_kind = p.env_f(n, u, n, m);
    let nested_scalar = p.env_f(t, u, m, m);
    let nested_owner0 = p.s.mk(ENV, 2, [W::I(0), W::I(3), W::I(3)], &[t, u, n, m]);
    let pair_decl = p.pair;
    let nested_undefined = p.s.mk(ENV, 1, [W::R(pair_decl), W::I(1), W::I(0)], &[t]);
    for (term, st, node, value, cause) in [
        (nested_kind, status::ENV, v5, Some(p.t), env_cause::BINDING),
        (
            nested_scalar,
            status::ENV,
            w5,
            Some(p.n),
            env_cause::BINDING,
        ),
        (
            nested_owner0,
            status::ENV,
            nested_owner0,
            None,
            env_cause::OWNER,
        ),
        (
            nested_undefined,
            status::DECL,
            nested_undefined,
            None,
            env_cause::NONE,
        ),
    ] {
        p.s.fails(
            f,
            env1,
            term,
            Failure {
                status: st,
                node: Some(node),
                env: Some(env1),
                value,
                cause: Some([cause, 0, 0]),
            },
        );
    }

    // Typed constants and count classes: Boxed<5u8> and Boxed<5usize> are
    // distinct, [i32; 5u8] and [i32; 5usize] are one array.
    let box_m = p.boxed(m);
    let boxed_decl = p.boxed;
    let box_n_e = p.s.ex(|s| s.named(boxed_decl, 1, &[v5]));
    let box_m_e = p.s.ex(|s| s.named(boxed_decl, 1, &[w5]));
    if expected {
        assert_ne!(box_n_e, box_m_e);
    }
    p.s.ok(f, env1, box_n, box_n_e);
    p.s.ok(f, env1, box_m, box_m_e);

    // The first failing argument wins even when a later argument fails at
    // a lower level, which is evaluated earlier.
    let mut deep = box_nested;
    for _ in 0..6 {
        deep = p.s.unary(REF, deep);
    }
    let late_first = p.pair(deep, box8);
    p.s.bad(
        f,
        env300,
        late_first,
        status::FIT_FAILED,
        Some(nested),
        Some(v300),
    );
    let early_first = p.pair(box8, deep);
    p.s.bad(
        f,
        env300,
        early_first,
        status::FIT_FAILED,
        Some(cast8),
        Some(w300),
    );

    // Invalid requests.
    let env_g = p.s.env(g, 3, 0, &[i32_, bool_]);
    let wide_mask = p.s.mk(
        ENV,
        2,
        [W::R(f), W::I(7), W::I(1)],
        &[i32_, bool_, i32_, v5],
    );
    let short =
        p.s.mk(ENV, 2, [W::R(f), W::I(3), W::I(3)], &[i32_, bool_, v5]);
    let slots =
        p.s.mk(ENV, 1, [W::R(f), W::I(3), W::I(3)], &[i32_, bool_, v5, w5]);
    let not_env = p.pair(i32_, i32_);
    let open = p.env_f(t, bool_, v5, w5);
    let i5 = p.s.value(I32, 5);
    let wrong_scalar = p.env_f(i32_, bool_, i5, w5);
    let const_as_type = p.env_f(w5, bool_, v5, w5);
    for (env, cause, node, value) in [
        (env_g, env_cause::OWNER, env_g, None),
        (wide_mask, env_cause::SHAPE, wide_mask, None),
        (short, env_cause::SHAPE, short, None),
        (slots, env_cause::SHAPE, slots, None),
        (not_env, env_cause::NOT_ENV, not_env, None),
        (open, env_cause::NOT_ENV, open, None),
        (wrong_scalar, env_cause::BINDING, i5, Some(p.n)),
        (const_as_type, env_cause::BINDING, w5, Some(p.t)),
    ] {
        p.s.fails(
            f,
            env,
            ptt,
            Failure {
                status: status::ENV,
                node: Some(node),
                env: Some(env),
                value,
                cause: Some([cause, 0, 0]),
            },
        );
    }
    let big = p.big;
    p.s.fails(
        big,
        env1,
        ptt,
        Failure {
            status: status::LIMIT,
            node: Some(env1),
            env: Some(env1),
            ..Failure::default()
        },
    );
    let s_decl = p.s_decl;
    let env_s = p.s.env(s_decl, 0, 0, &[]);
    let pii = p.pair(i32_, i32_);
    let x = p.x;
    let env_x = p.s.env(x, 0, 0, &[]);
    let zero = p.s.set(0);
    for (decl, env, term) in [(s_decl, env_s, pii), (x, env_x, pii), (zero, env1, ptt)] {
        p.s.fails(
            decl,
            env,
            term,
            Failure {
                status: status::DECL,
                node: Some(term),
                env: Some(CLOSED),
                ..Failure::default()
            },
        );
    }
    for sentinel in [0, RT_UNKNOWN, RT_NONE, u32::MAX] {
        let s = p.s.set(sentinel);
        p.s.bad(f, env1, s, status::UNRESOLVED, Some(s), None);
    }
    let fit = p.s.set(RT_FIT_FAILED);
    p.s.bad(f, env1, fit, status::PRIOR_FIT, Some(fit), None);
    let foreign = p.pair(t, tg);
    p.s.fails(
        f,
        env1,
        foreign,
        Failure {
            status: status::FOREIGN,
            node: Some(tg),
            env: Some(env1),
            ..Failure::default()
        },
    );
    // A leaf whose constant bit disagrees with its parameter's domain is a
    // malformed reference, not a parameter of another binder.
    let flipped = p.s.flip(t, 0x4000_0000);
    p.s.bad(f, env1, flipped, status::INVARIANT, Some(flipped), None);
    let partial = p.s.env(f, 1, 3, &[i32_, v5, w5]);
    let ptu = p.pair(t, u);
    p.s.bad(f, partial, ptu, status::UNBOUND, Some(u), None);
    p.s.ok(f, partial, ptt, expected.then_some(pii));
    let slot = p.s.set(SLOT_LEAF);
    let with_slot = p.pair(t, slot);
    p.s.bad(f, env1, with_slot, status::SLOT_PENDING, Some(slot), None);

    // Inherited and shadowing parameters stay distinct.
    let p_ti_tg = p.pair(ti, tg);
    let ib = if expected {
        Some(p.pair(i32_, bool_))
    } else {
        None
    };
    p.s.ok(g, env_g, p_ti_tg, ib);
    let p_tg_ti = p.pair(tg, ti);
    let bi = if expected {
        Some(p.pair(bool_, i32_))
    } else {
        None
    };
    p.s.ok(g, env_g, p_tg_ti, bi);
    let env_i = p.s.env(i, 1, 0, &[u8_]);
    let p_ti_ti = p.pair(ti, ti);
    let uu = if expected {
        Some(p.pair(u8_, u8_))
    } else {
        None
    };
    p.s.ok(i, env_i, p_ti_ti, uu);
    p.s.bad(i, env_i, p_ti_tg, status::FOREIGN, Some(tg), None);
    p.s
}

/// `envs` independent environments over two shared templates.
fn many(library: u32, envs: u32, expected: bool) -> Script {
    let mut p = Program::new(library, expected);
    let (i32_, bool_) = (p.sc(I32), p.sc(BOOL));
    let (f, t, u, m) = (p.f, p.t, p.u, p.m);
    let (d8, _) = p.dag(8, None);
    let a_um = p.s.array(u, m);
    let twin = p.pair(t, a_um);
    for k in 1..=envs {
        let c = p.s.count(k);
        let arr = p.s.array(i32_, c);
        let vk = p.s.value(U8, k & 255);
        let wk = p.s.value(USIZE, k);
        let env = p.env_f(arr, bool_, vk, wk);
        let e8 = if expected {
            let mut e = arr;
            for _ in 0..8 {
                e = p.pair(e, e);
            }
            Some(e)
        } else {
            None
        };
        p.s.ok(f, env, d8, e8);
        let et = if expected {
            let a = p.s.array(bool_, c);
            Some(p.pair(arr, a))
        } else {
            None
        };
        p.s.ok(f, env, twin, et);
    }
    p.s
}

/// Only the shared DAG: its task graph is exactly its 40 distinct nodes.
fn dag_only(library: u32) -> Script {
    let mut p = Program::new(library, true);
    let (i32_, bool_) = (p.sc(I32), p.sc(BOOL));
    let v5 = p.s.value(U8, 5);
    let w5 = p.s.value(USIZE, 5);
    let env1 = p.env_f(i32_, bool_, v5, w5);
    let (d40, e40) = p.dag(40, Some(i32_));
    let f = p.f;
    for _ in 0..3 {
        p.s.ok(f, env1, d40, e40);
    }
    p.s
}

#[test]
fn retained_substitution_is_memoized_parallel_and_exact() {
    let store = ProgramRetention::new(bigger_store()).unwrap();
    let mut engine = RetainedSubstitution::new(SubstitutionCapacity::default()).unwrap();

    // A 2^40-leaf tree as a 40-node DAG: one task per distinct node, one
    // round per level, three equal requests share it. The request ENV's
    // closed evaluation is one more task (4 edges) at level 2, which the
    // first DAG level also uses.
    let fixture = build_fixture(&store, &dag_only(200));
    let (report, results) = run(&mut engine, &store, &fixture);
    check(&fixture, &results);
    assert_eq!(
        report.tasks(),
        41,
        "one task per distinct (environment, term)"
    );
    // Pair<D, D> resolves D once; the repeated argument shares its edge.
    assert_eq!(report.edges(), 44);
    assert!(
        report.counts[words::SPARE_TASKS] <= 4,
        "only the three equal roots and their equal ENVs can race: {}",
        report.counts[words::SPARE_TASKS]
    );
    assert_eq!(report.expansion_rounds(), 40);
    assert_eq!(report.eval_rounds(), 40);
    assert!(
        results.iter().all(|r| r[0] == results[0][0]),
        "equal keys give one result"
    );

    // Independent environments run side by side: the span is the template
    // height, not the number of environments.
    let envs = 4096;
    let fixture = build_fixture(&store, &many(201, envs, true));
    let (report, results) = run(&mut engine, &store, &fixture);
    check(&fixture, &results);
    assert!(
        report.expansion_rounds() <= 10,
        "span independent of environments: {}",
        report.expansion_rounds()
    );
    assert!(report.eval_rounds() <= 11, "{}", report.eval_rounds());
    assert!(
        report.max_frontier() >= 2 * envs,
        "frontier width {}",
        report.max_frontier()
    );
    assert!(report.tasks() <= 12 * envs, "{} tasks", report.tasks());
    eprintln!("many-environment frontier log: {:?}", report.frontier_log());

    // Every correctness case.
    let fixture = build_fixture(&store, &cases(202, true));
    let (_, results) = run(&mut engine, &store, &fixture);
    check(&fixture, &results);
}

/// Structural hashes of results (or their failure nodes), comparable across stores.
/// Structural hashes of results (or their failure nodes, environments and
/// values) with their status and causes, comparable across stores.
fn shapes(store: &ProgramRetention, results: &[[u32; RESULT_WORDS]]) -> Vec<[u32; 10]> {
    let terms = store.status().unwrap()[2] as usize;
    let meta = store.read_store_words("rt_term_meta", terms * 4).unwrap();
    let hash = |id: u32| -> (u32, u32) {
        let id = id as usize;
        if (32..terms).contains(&id) {
            (meta[id * 4 + 2], meta[id * 4 + 3])
        } else {
            (id as u32, 0)
        }
    };
    results
        .iter()
        .map(|r| {
            let (a, b) = hash(if r[1] == status::OK { r[0] } else { r[2] });
            let (e, _) = hash(r[3]);
            let (v, _) = hash(r[4]);
            [r[1], a, b, e, v, r[5], r[8], r[9], r[10], r[11]]
        })
        .collect()
}

/// Every result word except the run number.
fn stable(results: &[[u32; RESULT_WORDS]]) -> Vec<Vec<u32>> {
    results
        .iter()
        .map(|r| {
            r.iter()
                .enumerate()
                .filter(|(k, _)| *k != 6)
                .map(|(_, w)| *w)
                .collect()
        })
        .collect()
}

/// The store's term records: every hash slot points below the term
/// counter at a live record, every live record has exactly one slot, no
/// two published records are key-equal, and `old` (heads and metadata
/// of the terms committed before) is unchanged.
fn check_store_terms(store: &ProgramRetention, old: &(usize, Vec<u32>)) {
    let status = store.status().unwrap();
    let terms = status[2] as usize;
    let (capacity, _) = store.capacity();
    let slots = store
        .read_store_words("rt_term_slot", capacity.slots[2] as usize)
        .unwrap();
    let heads = store.read_store_words("rt_term_head", terms * 4).unwrap();
    let meta = store.read_store_words("rt_term_meta", terms * 4).unwrap();
    let args = store
        .read_store_words("rt_term_args", status[3] as usize)
        .unwrap();
    let mut published = std::collections::BTreeSet::new();
    for &slot in &slots {
        if slot == 0 {
            continue;
        }
        assert!(
            (32..terms as u32).contains(&slot),
            "slot points at {slot}, past the term counter {terms}"
        );
        assert!(published.insert(slot), "two slots publish term {slot}");
        assert_ne!(
            heads[slot as usize * 4],
            0,
            "slot publishes a tombstone {slot}"
        );
    }
    let live = (32..terms as u32)
        .filter(|&id| heads[id as usize * 4] != 0)
        .collect::<std::collections::BTreeSet<_>>();
    assert_eq!(published, live, "every live term retains its hash slot");
    let mut keys = std::collections::BTreeMap::new();
    for &id in &published {
        let id = id as usize;
        let head = &heads[id * 4..id * 4 + 4];
        let arity = ((head[0] >> 8) & 0xff) as usize;
        let base = meta[id * 4] as usize;
        let key: Vec<u32> = head
            .iter()
            .copied()
            .chain(args[base..base + arity].iter().copied())
            .collect();
        if let Some(other) = keys.insert(key, id) {
            panic!("terms {other} and {id} have one key");
        }
    }
    let (count, words) = old;
    assert_eq!(
        &heads[..count * 4],
        &words[..count * 4],
        "committed term heads are unchanged"
    );
    assert_eq!(
        &meta[..count * 4],
        &words[count * 4..],
        "committed term metadata is unchanged"
    );
}

fn term_snapshot(store: &ProgramRetention) -> (usize, Vec<u32>) {
    let terms = store.status().unwrap()[2] as usize;
    let mut words = store.read_store_words("rt_term_head", terms * 4).unwrap();
    words.extend(store.read_store_words("rt_term_meta", terms * 4).unwrap());
    (terms, words)
}

#[test]
fn retained_substitution_grows_retries_and_resets_per_build() {
    // Reference: default capacities, expected terms skipped so substitution
    // interns its own results.
    let script = cases(203, false);
    let reference_store = ProgramRetention::new(bigger_store()).unwrap();
    let mut engine = RetainedSubstitution::new(SubstitutionCapacity::default()).unwrap();
    let fixture = build_fixture(&reference_store, &script);
    let reference_before = reference_store.status().unwrap();
    let (reference_report, reference) = run(&mut engine, &reference_store, &fixture);
    check(&fixture, &reference);
    let expected_shapes = shapes(&reference_store, &reference);
    assert!(
        reference_report.counts[words::STORE_NEW_TERMS] > 0,
        "results are new store terms"
    );

    // Tiny substitution tables and a store with room for half the results:
    // the attempt that first reaches evaluation interns that half, overflows
    // the store at a later level and rolls back. Every overflow grows and
    // retries from the same requests, with the full hash and with every
    // store key on one probe chain.
    let status = reference_store.status().unwrap();
    // Published terms and argument words: a lane that loses a slot to an
    // equal key keeps its record as a counted spare, and how many lanes
    // race depends on timing, so allocations alone are not deterministic.
    let published = |status: &[u32], arena: usize| status[arena] - status[counts::SPARE + arena];
    let new_args = published(&status, 3) - published(&reference_before, 3);
    let new_published_terms = published(&status, 2) - published(&reference_before, 2);
    let new_terms = reference_report.counts[words::STORE_NEW_TERMS];
    let fixture_terms = status[2] - new_terms;
    let mut tight = bigger_store();
    tight.arenas[2] = fixture_terms + new_terms / 2;
    tight.arenas[3] = 1 << 19;
    tight.slots[2] = (2 * tight.arenas[2]).next_power_of_two();
    let mut kept = None;
    for mask in [0, u32::MAX] {
        let store = ProgramRetention::new(tight).unwrap();
        store.set_hash_mask(mask);
        let fixture = build_fixture(&store, &script);
        let committed = store.status().unwrap();
        let old = term_snapshot(&store);
        let mut tiny = RetainedSubstitution::new(SubstitutionCapacity::tiny()).unwrap();
        let (report, results) = run(&mut tiny, &store, &fixture);
        assert!(
            report.attempts > 2 && report.growths > 0 && report.store_growths > 0,
            "{report:?}"
        );
        assert!(
            report.rolled_back_terms > 0,
            "an attempt interned store terms and rolled them back: {report:?}"
        );
        check(&fixture, &results);
        assert_eq!(
            shapes(&store, &results),
            expected_shapes,
            "a retried run publishes the reference results (store hash mask {mask:#x})"
        );
        let after = store.status().unwrap();
        assert_eq!(after[counts::READY], 1);
        assert_eq!(after[counts::OVERFLOW], committed[counts::OVERFLOW]);
        assert_eq!(after[counts::DEMAND + 2], committed[counts::DEMAND + 2]);
        assert_eq!(after[counts::DEMAND + 3], committed[counts::DEMAND + 3]);
        assert_eq!(
            published(&after, 2) - published(&committed, 2),
            new_published_terms,
            "rolled-back attempts leave no terms behind"
        );
        assert_eq!(published(&after, 3) - published(&committed, 3), new_args, "rolled-back attempts leave no argument words behind");
        check_store_terms(&store, &old);
        kept = Some((store, fixture, tiny, results));
    }
    let (store, fixture, mut tiny, results) = kept.unwrap();
    store.set_hash_mask(u32::MAX);

    // Same store, same requests: a second run is a full recomputation with
    // identical exact results, and a forced single probe chain changes
    // nothing either.
    let (_, again) = run(&mut tiny, &store, &fixture);
    assert_eq!(stable(&again), stable(&results));
    tiny.set_hash_mask(0);
    let (_, collided) = run(&mut tiny, &store, &fixture);
    assert_eq!(
        stable(&collided),
        stable(&results),
        "forced memo collisions never merge keys"
    );
    // Forced store collisions too: a store hash mask holds for whole builds.
    let collided_store = ProgramRetention::new(bigger_store()).unwrap();
    collided_store.set_hash_mask(0);
    let collided_fixture = build_fixture(&collided_store, &script);
    let (_, collided) = run(&mut tiny, &collided_store, &collided_fixture);
    check(&collided_fixture, &collided);
    assert_eq!(
        shapes(&collided_store, &collided),
        expected_shapes,
        "forced store collisions never merge keys"
    );
    tiny.set_hash_mask(u32::MAX);

    // A fresh build in the same allocations: the stale requests, memo and
    // results of the earlier build are unreachable.
    let fresh = build_fixture(&store, &dag_only(204));
    assert!(fresh.expects.len() < fixture.expects.len());
    let (fresh_report, fresh_results) = run(&mut tiny, &store, &fresh);
    check(&fresh, &fresh_results);
    assert_eq!(fresh_report.tasks(), 41);
    let keys = store
        .read_store_words("rt_decl_key", 4 * store.status().unwrap()[0] as usize)
        .unwrap();
    assert!(
        keys.chunks_exact(4).skip(1).all(|k| k[0] == 204),
        "only the fresh build's declarations are live"
    );

    // A build whose store is not READY publishes NOT_READY for every request.
    let mut script = dag_only(205);
    script.clear_ready();
    let blocked = build_fixture(&store, &script);
    let (_, blocked_results) = run(&mut tiny, &store, &blocked);
    assert!(
        blocked_results
            .iter()
            .all(|r| r[1] == status::NOT_READY && r[0] == RT_UNKNOWN)
    );
}

/// The GPU consumer's check (`sb_consumer.slang`) of one publication's
/// buffers against `store`: (publication current, row current, row
/// status, row result if current).
fn consume(
    store: &ProgramRetention,
    buffers: &(wgpu::Buffer, wgpu::Buffer),
    run: u32,
    request: u32,
) -> [u32; 4] {
    consume_with_store_bindings(store, buffers, run, request, &[])
}

fn consume_with_store_bindings(
    store: &ProgramRetention,
    buffers: &(wgpu::Buffer, wgpu::Buffer),
    run: u32,
    request: u32,
    store_bindings: &[(&str, &wgpu::Buffer)],
) -> [u32; 4] {
    let requests = SubstitutionRequests::new(1);
    let mut bindings = vec![("sb_results", &buffers.0), ("sb_counts", &buffers.1)];
    bindings.extend_from_slice(store_bindings);
    let out = run_test_kernel(
        store,
        CONSUMER_KERNEL,
        &requests,
        &[run, request],
        4,
        1,
        &bindings,
    )
    .unwrap();
    [out[0], out[1], out[2], out[3]]
}

fn published_buffers(
    engine: &RetainedSubstitution,
    store: &ProgramRetention,
) -> (wgpu::Buffer, wgpu::Buffer) {
    let publication = engine.publication(store).expect("a current publication");
    (publication.results.clone(), publication.counts.clone())
}

#[test]
fn retained_substitution_publications_are_identified_and_fail_closed() {
    let store = ProgramRetention::new(bigger_store()).unwrap();
    let mut engine = RetainedSubstitution::new(SubstitutionCapacity::default()).unwrap();
    let script = dag_only(210);
    let n = script.expects.len() as u32;

    // A committed run: the consumer accepts its rows.
    let full = build_fixture_into(&store, &script, n);
    let (first, results) = run(&mut engine, &store, &full);
    check(&full, &results);
    let id1 = first.publication;
    let buffers = published_buffers(&engine, &store);
    assert_eq!(
        consume(&store, &buffers, id1.run, 0),
        [1, 1, status::OK, results[0][0]]
    );
    assert_eq!(
        consume(&store, &buffers, id1.run, n)[..2],
        [1, 0],
        "rows past the count are not results"
    );

    // More requests than rows: nothing runs, nothing is published, the
    // store is untouched, and the earlier publication in these buffers is
    // withdrawn.
    let short = produce(&store, &script, n - 1);
    let before = store.status().unwrap();
    match engine.run(&store, &short.requests).unwrap() {
        SubstitutionRun::RequestCapacity {
            requested,
            capacity,
        } => {
            assert_eq!((requested, capacity), (n, n - 1));
        }
        other => panic!("a short request buffer published: {other:?}"),
    }
    assert!(engine.publication(&store).is_none());
    assert_eq!(
        store.status().unwrap(),
        before,
        "a request-capacity run leaves the store untouched"
    );
    let counts = engine.read_counts().unwrap();
    assert_eq!(counts[words::STATE], words::STATE_REQUEST_CAPACITY);
    assert_eq!(counts[words::REQUEST_DEMAND], n);
    assert!(
        counts[words::STATUS..words::STATUS + words::STATUSES]
            .iter()
            .all(|&c| c == 0)
    );
    assert_eq!(consume(&store, &buffers, id1.run, 0)[..2], [0, 0]);

    // The producer reruns its production into grown storage.
    let grown = produce(&store, &script, n);
    let (second, again) = run(&mut engine, &store, &grown);
    check(&grown, &again);
    let id2 = second.publication;
    assert_ne!(id2.run, id1.run);
    assert_eq!(id2.generation, id1.generation);
    assert_eq!(
        consume(&store, &buffers, id1.run, 0)[..2],
        [0, 0],
        "an older run of reused buffers"
    );
    assert_eq!(consume(&store, &buffers, id2.run, 0)[..2], [1, 1]);

    // A larger request buffer replaces the result buffer. The old result
    // buffer with the new counts fails the row check; new buffers with the
    // old run fail the publication check.
    let wide = produce(&store, &script, 1024);
    let (third, _) = run(&mut engine, &store, &wide);
    let id3 = third.publication;
    let current = published_buffers(&engine, &store);
    assert_eq!(consume(&store, &current, id3.run, 0)[..2], [1, 1]);
    assert_eq!(consume(&store, &current, id2.run, 0)[..2], [0, 0]);
    let mixed = (buffers.0.clone(), current.1.clone());
    assert_eq!(consume(&store, &mixed, id3.run, 0)[..2], [1, 0]);

    // Another engine's run (whose tables grow) never matches this engine's
    // run numbers.
    let mut tiny = RetainedSubstitution::new(SubstitutionCapacity::tiny()).unwrap();
    let (other, _) = run(&mut tiny, &store, &wide);
    assert!(other.growths > 0);
    let other_buffers = published_buffers(&tiny, &store);
    assert_ne!(other.publication.run, id3.run);
    assert_eq!(consume(&store, &other_buffers, id3.run, 0)[..2], [0, 0]);
    assert_eq!(
        consume(&store, &current, other.publication.run, 0)[..2],
        [0, 0]
    );
    assert_eq!(
        consume(&store, &other_buffers, other.publication.run, 0)[..2],
        [1, 1]
    );

    // Another store never matches, and neither does this store's next build.
    let elsewhere = ProgramRetention::new(bigger_store()).unwrap();
    assert!(engine.publication(&elsewhere).is_none());
    assert_ne!(elsewhere.generation(), id3.generation);
    assert_eq!(consume(&elsewhere, &current, id3.run, 0)[..2], [0, 0]);
    store.begin_build().unwrap();
    assert!(engine.publication(&store).is_none());
    assert!(tiny.publication(&store).is_none());
    assert_ne!(store.generation(), id3.generation);
    assert_eq!(consume(&store, &current, id3.run, 0)[..2], [0, 0]);

    // A host error fails closed: the store is no longer READY, nothing is
    // published, and the consumer rejects the buffers.
    let rebuilt = build_fixture_into(&store, &script, n);
    let (_, _) = run(&mut engine, &store, &rebuilt);
    let id5 = engine.publication(&store).unwrap().id;
    let mut oversized = RetainedSubstitution::new(SubstitutionCapacity {
        tasks: 1 << 30,
        edges: 1 << 30,
        memo_slots: 1 << 31,
    })
    .unwrap();
    assert!(oversized.run(&store, &rebuilt.requests).is_err());
    assert!(oversized.publication(&store).is_none());
    assert_eq!(store.status().unwrap()[counts::READY], 0);
    let still = published_buffers(&engine, &store);
    assert_eq!(
        consume(&store, &still, id5.run, 0)[..2],
        [0, 0],
        "a build that is not READY"
    );
}

#[test]
fn retained_substitution_old_bindings_observe_store_growth_invalidations() {
    let compiler = pollster::block_on(GpuCompiler::new_with_backends(
        GpuCompilerBackends::frontend_only(),
    )).unwrap();
    let mut capacity = bigger_store();
    // The synthetic requests use no body rows. A later frontend export
    // must grow these arenas without rerunning the substitution engine.
    capacity.arenas[10] = 1;
    capacity.arenas[13] = 1;
    let store = ProgramRetention::new(capacity).unwrap();
    let mut engine = RetainedSubstitution::new(SubstitutionCapacity::default()).unwrap();
    let fixture = build_fixture(&store, &dag_only(211));
    let (report, results) = run(&mut engine, &store, &fixture);
    check(&fixture, &results);
    let buffers = published_buffers(&engine, &store);
    let old_counts = store.clone_store_buffer_for_test("rt_counts").unwrap();
    let bindings = [("rt_counts", &old_counts)];
    let consume_old = || consume_with_store_bindings(
        &store, &buffers, report.publication.run, 0, &bindings,
    );
    assert_eq!(consume_old()[..2], [1, 1]);
    let growths = store.capacity().1;
    compiler.attach_program_retention(Some(store.clone()));
    pollster::block_on(compiler.semantic_interface_for_source_pack(10, &[LIBRARY]))
        .expect("export that grows the store after publication");
    assert!(store.capacity().1 > growths);
    assert_eq!(store.job_reports().len(), 1);
    assert!(store.job_reports().iter().all(|r| r.ready));
    assert_eq!(consume_old()[..2], [1, 1], "committed terms survive growth");

    // READY invalidation and a fresh build must both reach bindings held
    // before growth, not just bindings made from the current store map.
    store.write_store_words("rt_counts", counts::READY as u64, &[0]).unwrap();
    assert_eq!(consume_old()[..2], [0, 0], "old bindings observe failure");
    store.begin_build().unwrap();
    assert_eq!(store.status().unwrap()[counts::READY], 1);
    assert_eq!(consume_old()[..2], [0, 0], "old bindings observe the new generation");
}

// Export path: two frontend jobs, store only.
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

#[test]
fn retained_substitution_instantiates_exported_foreign_templates() {
    let compiler = pollster::block_on(GpuCompiler::new_with_backends(
        GpuCompilerBackends::frontend_only(),
    ))
    .expect("frontend compiler");
    let store: Arc<ProgramRetention> =
        ProgramRetention::new(ProgramRetentionCapacity::default()).unwrap();
    store.begin_build().unwrap();
    compiler.attach_program_retention(Some(store.clone()));
    let library = pollster::block_on(compiler.semantic_interface_for_source_pack(10, &[LIBRARY]))
        .expect("library job");
    pollster::block_on(
        compiler.semantic_interface_for_source_pack_with_dependencies(11, &[APP], &[library]),
    )
    .expect("application job");
    compiler.attach_program_retention(None);
    for report in store.job_reports() {
        assert!(report.ready, "{report:?}");
    }
    pollster::block_on(compiler.release_resident_job_buffers());
    drop(compiler);
    store.poison_scratch();

    let requests = SubstitutionRequests::new(4096);
    let produced = run_test_kernel(
        &store,
        USES_KERNEL,
        &requests,
        &[0],
        16 + 4 * 4096,
        4096,
        &[],
    )
    .unwrap();
    let mut engine = RetainedSubstitution::new(SubstitutionCapacity::default()).unwrap();
    let report = engine.run(&store, &requests).unwrap().published().unwrap();
    let n = report.counts[words::REQUESTS] as usize;
    let results = engine.read_results(n).unwrap();
    eprintln!(
        "export substitution: {n} requests, {} tasks, {} edges, {} + {} rounds, statuses {:?}",
        report.tasks(),
        report.edges(),
        report.expansion_rounds(),
        report.eval_rounds(),
        report.status_counts()
    );
    let terms = store.status().unwrap()[2] as usize;
    let heads = store.read_store_words("rt_term_head", terms * 4).unwrap();
    let mut uses = std::collections::BTreeSet::new();
    let mut by_kind = [0usize; 5];
    for (k, r) in results.iter().enumerate() {
        let tag = &produced[16 + 4 * k..20 + 4 * k];
        let (use_index, kind, expected) = (tag[0], tag[1] as usize, tag[3]);
        uses.insert(use_index);
        by_kind[kind] += 1;
        assert_eq!(
            r[1],
            status::OK,
            "request {k} (use {use_index}, kind {kind}, index {}): {r:?}",
            tag[2]
        );
        if kind == 0 {
            assert_eq!(
                r[0], expected,
                "the callee result under the caller's environment is the caller's type"
            );
        }
        if kind == 3 {
            assert_eq!(
                heads[r[0] as usize * 4] & 0xff,
                ENV,
                "an inner call environment closes to an ENV"
            );
        }
    }
    eprintln!(
        "export substitution requests per kind: {by_kind:?} over {} uses",
        uses.len()
    );
    assert!(uses.len() >= 4, "three wrap calls and one shadow call");
    assert!(
        by_kind[2] > 0 && by_kind[3] > 0,
        "body rows and inner call environments are substituted"
    );

    // Inner call environments, by outer use and inner callee (test oracle).
    let status_words = store.status().unwrap();
    let rt_uses = store
        .read_store_words("rt_uses", 12 * status_words[8] as usize)
        .unwrap();
    let decl_def = store
        .read_store_words("rt_decl_def", status_words[0] as usize)
        .unwrap();
    let dir = store
        .read_store_words("rt_dir", 16 * status_words[4] as usize)
        .unwrap();
    let meta = store.read_store_words("rt_term_meta", terms * 4).unwrap();
    let args = store
        .read_store_words("rt_term_args", status_words[3] as usize)
        .unwrap();
    let use_word = |u: u32, w: usize| rt_uses[u as usize * 12 + w];
    let mut inner_envs = std::collections::BTreeMap::new();
    let mut outer_by_callee: std::collections::BTreeMap<
        u32,
        std::collections::BTreeSet<(u32, u32)>,
    > = Default::default();
    for (k, r) in results.iter().enumerate() {
        let tag = &produced[16 + 4 * k..20 + 4 * k];
        let (outer, kind, index) = (tag[0], tag[1], tag[2]);
        let callee = use_word(outer, 3);
        outer_by_callee
            .entry(callee)
            .or_default()
            .insert((use_word(outer, 1), outer));
        if kind != 3 {
            continue;
        }
        let entry = decl_def[callee as usize] as usize - 1;
        let inner = dir[entry * 16 + 11] + index;
        let inner_callee = use_word(inner, 3);
        assert!(
            inner_envs.insert((outer, inner_callee), r[0]).is_none(),
            "one environment per inner use"
        );
    }
    let mut callees: Vec<_> = outer_by_callee.into_iter().collect();
    callees.sort_by_key(|(_, uses)| uses.len());
    let (shadow, shadow_uses) = &callees[0];
    let (_, wrap_uses) = &callees[1];
    assert_eq!((shadow_uses.len(), wrap_uses.len()), (1, 3), "{callees:?}");
    let shadow_use = shadow_uses.iter().next().unwrap().1;
    let wraps: Vec<u32> = wrap_uses.iter().map(|(_, u)| *u).collect();
    let shadow_inner: Vec<_> = inner_envs
        .iter()
        .filter(|((outer, _), _)| *outer == shadow_use)
        .collect();
    assert_eq!(shadow_inner.len(), 1, "shadow's body calls identity once");
    let identity = (shadow_inner[0].0).1;
    assert_ne!(identity, *shadow);
    let env_of = |outer: u32| inner_envs[&(outer, identity)];
    let (wrap7, wrap_local, wrap1) = (env_of(wraps[0]), env_of(wraps[1]), env_of(wraps[2]));
    let in_shadow = env_of(shadow_use);
    assert_eq!(
        wrap7, wrap1,
        "wrap(7) and wrap(1) call identity in one environment"
    );
    assert_ne!(
        wrap7, wrap_local,
        "wrap(Local {{ .. }}) is another instance"
    );
    assert_eq!(
        in_shadow, wrap7,
        "identity(self.value) in shadow binds the impl's T (i32), not the method's T (bool)"
    );
    let head = |t: u32| &heads[t as usize * 4..t as usize * 4 + 4];
    let arg = |t: u32, i: usize| args[meta[t as usize * 4] as usize + i];
    assert_eq!(
        head(wrap7),
        &[ENV | 1 << 8 | 1 << 16, identity, 1, 0],
        "ENV(identity; U = i32): owner, masks and arity"
    );
    assert_eq!(arg(wrap7, 0), I32);
    assert_eq!(head(wrap_local)[..2], [ENV | 1 << 8 | 1 << 16, identity]);
    let local = arg(wrap_local, 0);
    assert_eq!(head(local)[0] & 0xff, NAMED);
    assert_eq!(arg(local, 0), BOOL, "Local<bool>");
}

#[test]
fn retained_substitution_binds_nominal_schemas_by_exact_parameter() {
    let store = ProgramRetention::new(bigger_store()).unwrap();
    let mut engine = RetainedSubstitution::new(SubstitutionCapacity::default()).unwrap();
    let mut s = Script::new(220, true);
    let decl = s.decl(NS_NOMINAL, 1);
    let other = s.decl(NS_NOMINAL, 2);
    let t = s.param(decl, TYPE, 0, 0);
    let u = s.param(decl, TYPE, 1, 0);
    let n = s.param(decl, CONST, 0, U8);
    let m = s.param(decl, CONST, 1, USIZE);
    s.entry(decl, 5, None, &[t,u], &[n,m], COMMITTED, 0);
    s.entry(other, 6, None, &[t,u], &[n,m], COMMITTED, 0);
    let t = s.leaf(t); let u = s.leaf(u); let n = s.leaf(n); let m = s.leaf(m);
    let int = s.set(I32); let boolean = s.set(BOOL);
    let three = s.value(U8,3); let five = s.value(USIZE,5);
    let three_count = s.count(3); let five_count = s.count(5);
    // Source operand order can interleave domains; the binder groups them.
    let named = s.named(decl,0b0101,&[three,int,five,boolean]);
    let field = s.array(t,n);
    let expected = s.array(int,three_count);
    s.ok(decl,named,field,Some(expected));
    let inner = s.array(u,m);
    let field = s.unary(SLICE,inner);
    let expected_inner = s.array(boolean,five_count);
    let expected = s.unary(SLICE,expected_inner);
    s.ok(decl,named,field,Some(expected));
    s.ok(decl,named,n,Some(three));
    s.ok(decl,named,m,Some(five));
    // Reordering the type arguments must change each exact parameter's binding.
    let swapped = s.named(decl,0b0101,&[three,boolean,five,int]);
    s.ok(decl,swapped,t,Some(boolean));
    s.ok(decl,swapped,u,Some(int));
    let wrong_owner = s.named(other,0b0101,&[three,int,five,boolean]);
    s.fails(decl,wrong_owner,t,Failure {
        status:status::ENV,node:Some(wrong_owner),env:Some(wrong_owner),
        cause:Some([env_cause::OWNER,0,0]),..Default::default()
    });
    let wrong_scalar = s.named(decl,0b0101,&[five,int,five,boolean]);
    s.fails(decl,wrong_scalar,t,Failure {
        status:status::ENV,node:Some(five),env:Some(wrong_scalar),value:Some(n),
        cause:Some([env_cause::BINDING,0,0]),..Default::default()
    });
    let missing = s.named(decl,0b0001,&[three,int,boolean]);
    s.fails(decl,missing,t,Failure {
        status:status::ENV,node:Some(missing),env:Some(missing),
        cause:Some([env_cause::SHAPE,0,0]),..Default::default()
    });
    let fixture=build_fixture(&store,&s);
    let (_,results)=run(&mut engine,&store,&fixture);
    check(&fixture,&results);
}
