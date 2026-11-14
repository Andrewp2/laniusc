//! Production substitution over retained terms
//! (docs/compiler-retained-substitution.md).
//!
//! Synthetic programs are built in the store by a single-lane GPU script
//! (`shaders/tests/retention_subst_fixture.slang`): every declaration,
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
            FIXTURE_KERNEL,
            RESULT_WORDS,
            RetainedSubstitution,
            SubstitutionCapacity,
            SubstitutionReport,
            SubstitutionRequests,
            USES_KERNEL,
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
    /// Failure with status, failed node register and failed value register.
    Fail(u32, Option<R>, Option<R>),
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
        self.request(decl, env, term, Expect::Fail(status, node, value));
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
    fn named(&mut self, decl: R, const_mask: u32, args: &[R]) -> R {
        self.mk(NAMED, 0, [W::R(decl), W::I(const_mask), W::I(0)], args)
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
    store.begin_build().unwrap();
    let requests = SubstitutionRequests::new(script.expects.len() as u32);
    let out = run_test_kernel(
        store,
        FIXTURE_KERNEL,
        &requests,
        &script.finish(),
        16 + script.regs as usize,
        1,
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
    let report = engine.run(store, &fixture.requests).expect("substitution");
    let elapsed = started.elapsed();
    let results = engine.read_results(fixture.expects.len()).unwrap();
    eprintln!(
        "substitution: {} requests, {} tasks ({} spare), {} edges, {} expansion rounds, {} eval rounds, \
         max frontier {}, max arity {}, edge lanes {}, eval lanes {}, new store terms {}, attempts {}, batches {}, \
         dispatches {}, growths {}/{}, statuses {:?}, {:.2?} host wall time",
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
        report.status_counts(),
        elapsed,
    );
    assert_eq!(report.counts[words::STATE], words::STATE_PUBLISHED);
    for (k, r) in results.iter().enumerate() {
        assert_eq!(
            r[6],
            report.counts[words::RUN],
            "result {k} belongs to this run"
        );
        assert_eq!(r[5], k as u32, "result {k} keeps its request tag");
    }
    (report, results)
}

fn check(fixture: &Fixture, results: &[[u32; RESULT_WORDS]]) {
    for (k, (expect, r)) in fixture.expects.iter().zip(results).enumerate() {
        match *expect {
            Expect::Ok(expected) => {
                assert_eq!(r[1], status::OK, "request {k}: {r:?}");
                if let Some(e) = expected {
                    assert_eq!(
                        r[0], fixture.regs[e as usize],
                        "request {k} result is the expected term: {r:?}"
                    );
                }
            }
            Expect::Fail(st, node, value) => {
                assert_eq!(r[1], st, "request {k} status: {r:?}");
                assert_eq!(
                    r[0], RT_UNKNOWN,
                    "request {k}: a failure never carries a term"
                );
                if let Some(node) = node {
                    assert_eq!(
                        r[2], fixture.regs[node as usize],
                        "request {k} failed node: {r:?}"
                    );
                }
                if let Some(value) = value {
                    assert_eq!(
                        r[4], fixture.regs[value as usize],
                        "request {k} failed value: {r:?}"
                    );
                }
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
    p.s.bad(
        f,
        env1,
        closed_box,
        status::FIT_FAILED,
        Some(closed_bad),
        Some(w256),
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
    // So does a closed environment binding.
    let i300 = p.s.value(I32, 300);
    let pending = p.s.cast(U8, i300);
    let env3 = p.env_f(i32_, bool_, pending, w5);
    let box_n = p.boxed(n);
    p.s.bad(
        f,
        env3,
        box_n,
        status::FIT_FAILED,
        Some(pending),
        Some(i300),
    );

    // Invalid requests.
    let ptt = p.pair(t, t);
    let env_g = p.s.env(g, 3, 0, &[i32_, bool_]);
    p.s.bad(f, env_g, ptt, status::ENV, None, None);
    let wide_mask = p.s.mk(
        ENV,
        2,
        [W::R(f), W::I(7), W::I(1)],
        &[i32_, bool_, i32_, v5],
    );
    p.s.bad(f, wide_mask, ptt, status::ENV, None, None);
    let short =
        p.s.mk(ENV, 2, [W::R(f), W::I(3), W::I(3)], &[i32_, bool_, v5]);
    p.s.bad(f, short, ptt, status::ENV, None, None);
    let not_env = p.pair(i32_, i32_);
    p.s.bad(f, not_env, ptt, status::ENV, None, None);
    let open = p.env_f(t, bool_, v5, w5);
    p.s.bad(f, open, ptt, status::ENV, None, None);
    let i5 = p.s.value(I32, 5);
    let wrong_scalar = p.env_f(i32_, bool_, i5, w5);
    p.s.bad(f, wrong_scalar, ptt, status::ENV, None, None);
    let const_as_type = p.env_f(w5, bool_, v5, w5);
    p.s.bad(f, const_as_type, ptt, status::ENV, None, None);
    let s_decl = p.s_decl;
    let env_s = p.s.env(s_decl, 0, 0, &[]);
    let pii = p.pair(i32_, i32_);
    p.s.bad(s_decl, env_s, pii, status::DECL, None, None);
    let x = p.x;
    let env_x = p.s.env(x, 0, 0, &[]);
    p.s.bad(x, env_x, pii, status::DECL, None, None);
    let zero = p.s.set(0);
    p.s.bad(zero, env1, ptt, status::DECL, None, None);
    for sentinel in [0, RT_UNKNOWN, RT_NONE, u32::MAX] {
        let s = p.s.set(sentinel);
        p.s.bad(f, env1, s, status::UNRESOLVED, Some(s), None);
    }
    let fit = p.s.set(RT_FIT_FAILED);
    p.s.bad(f, env1, fit, status::PRIOR_FIT, Some(fit), None);
    let foreign = p.pair(t, tg);
    p.s.bad(f, env1, foreign, status::FOREIGN, Some(tg), None);
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
    // round per level, three equal requests share it.
    let fixture = build_fixture(&store, &dag_only(200));
    let (report, results) = run(&mut engine, &store, &fixture);
    check(&fixture, &results);
    assert_eq!(
        report.tasks(),
        40,
        "one task per distinct (environment, term)"
    );
    // Pair<D, D> resolves D once; the repeated argument shares its edge.
    assert_eq!(report.edges(), 40);
    assert!(
        report.counts[words::SPARE_TASKS] <= 2,
        "only the three equal roots can race: {}",
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
fn shapes(store: &ProgramRetention, results: &[[u32; RESULT_WORDS]]) -> Vec<(u32, u32, u32, u32)> {
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
            (r[1], a, b, hash(r[4]).0)
        })
        .collect()
}

#[test]
fn retained_substitution_grows_retries_and_resets_per_build() {
    // Reference: default capacities, expected terms skipped so substitution
    // interns its own results.
    let script = cases(203, false);
    let reference_store = ProgramRetention::new(bigger_store()).unwrap();
    let mut engine = RetainedSubstitution::new(SubstitutionCapacity::default()).unwrap();
    let fixture = build_fixture(&reference_store, &script);
    let (reference_report, reference) = run(&mut engine, &reference_store, &fixture);
    check(&fixture, &reference);
    let expected_shapes = shapes(&reference_store, &reference);
    assert!(
        reference_report.counts[words::STORE_NEW_TERMS] > 0,
        "results are new store terms"
    );

    // Tiny substitution tables and a store with no room for any result:
    // every overflow rolls back, grows and retries from the same requests.
    let status = reference_store.status().unwrap();
    let mut tight = bigger_store();
    let fixture_terms = status[2] - reference_report.counts[words::STORE_NEW_TERMS];
    tight.arenas[2] = fixture_terms;
    tight.arenas[3] = 1 << 19;
    tight.slots[2] = (2 * fixture_terms).next_power_of_two();
    let store = ProgramRetention::new(tight).unwrap();
    let fixture = build_fixture(&store, &script);
    let committed = store.status().unwrap();
    let mut tiny = RetainedSubstitution::new(SubstitutionCapacity::tiny()).unwrap();
    let (report, results) = run(&mut tiny, &store, &fixture);
    assert!(
        report.attempts > 1 && report.growths > 0 && report.store_growths > 0,
        "{report:?}"
    );
    check(&fixture, &results);
    assert_eq!(
        shapes(&store, &results),
        expected_shapes,
        "a retried run publishes the reference results"
    );
    let after = store.status().unwrap();
    assert_eq!(after[counts::READY], 1);
    assert_eq!(
        after[2] - committed[2],
        reference_report.counts[words::STORE_NEW_TERMS],
        "rolled-back attempts leave no terms behind"
    );

    // Same store, same requests: a second run is a full recomputation with
    // identical exact results, and a forced single probe chain changes
    // nothing either.
    let (_, again) = run(&mut tiny, &store, &fixture);
    assert_eq!(
        again.iter().map(|r| r[..5].to_vec()).collect::<Vec<_>>(),
        results.iter().map(|r| r[..5].to_vec()).collect::<Vec<_>>()
    );
    tiny.set_hash_mask(0);
    let (_, collided) = run(&mut tiny, &store, &fixture);
    assert_eq!(
        collided.iter().map(|r| r[..5].to_vec()).collect::<Vec<_>>(),
        results.iter().map(|r| r[..5].to_vec()).collect::<Vec<_>>(),
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
    assert_eq!(fresh_report.tasks(), 40);
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
    let produced =
        run_test_kernel(&store, USES_KERNEL, &requests, &[0], 16 + 4 * 4096, 4096).unwrap();
    let mut engine = RetainedSubstitution::new(SubstitutionCapacity::default()).unwrap();
    let report = engine.run(&store, &requests).unwrap();
    let n = report.counts[words::REQUESTS] as usize;
    assert_eq!(report.counts[words::REQUEST_CLAMPED], 0);
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
}
