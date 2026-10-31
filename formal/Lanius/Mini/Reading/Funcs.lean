import Lanius.Mini.Reading.Stmts

/-! # The reading, V8e: functions and monomorphization

`ReadInst decls inst mf`: the body of a function instance, read with its
type parameters (the impl's, then its own) standing for the instance's
arguments; a projection `fn(v: t) -> f { return v.f; }` for an instance
numbered past the declared functions; and, for a `-> !` function at a value
type `t`, its instance whose body calls it and then returns a call of
itself (never reached: the call traps).

`MonoR decls table done i r`: the function instances closed under calls,
in first-request order: instance `i` of the table is read, the instances
its body calls that are new are appended, and so on until the table is
done. `TypeTable` and `TypeTableMore`: the type instances, from the seeds,
in the order the types first need them. -/

namespace Lanius.Mini.Reading

open Lanius.Mini Lanius.Mini.Prod

/-! ## Functions -/

/-- Where a function instance's signature and body are read. -/
abbrev fnScope (decls : Decls) (fd : FnDecl) (args : List Ty) (ret : Option Ty) : FrontEnv :=
  { decls := decls, home := fd.home, names := fd.implParams ++ fd.params, subst := args,
    globals := moduleGlobals decls fd.home, ret := ret, base := (kidToken fd.tree 1).start }

/-- `name: T`, `self` or `&self` (`paramToken`: the `self` after the `&`),
each a local named by its spelling, numbered by
its offset from the function's name. -/
inductive ParamsR (env : FrontEnv) (fd : FnDecl) : List Local → List CTree → MParams → Prop
  | nil {scope : List Local} : ParamsR env fd scope [] { params := [], scope := scope }
  | cons {scope : List Local} {p : CTree} {rest : List CTree} {t : CTree} {x : Ty} {r : MParams} :
      (nodeProd p = pParamNamed ∨ nodeProd p = pParamSelf ∨ nodeProd p = pParamSelfRef) → (paramToken p).text ∉ env.globals →
      FreshId scope ((paramToken p).start - env.base) → PatternOf fd p t → TyR env t x →
      ParamsR env fd ({ name := (paramToken p).text, id := (paramToken p).start - env.base, ty := x } :: scope) rest r →
      ParamsR env fd scope (p :: rest)
        { params := { id := (paramToken p).start - env.base, ty := x } :: r.params, scope := r.scope }

theorem paramsOf_sound {fuel : Nat} {env : FrontEnv} {fd : FnDecl} :
    ∀ {scope : List Local} {items : List CTree} {ps : MParams}, paramsOf fuel env fd scope items = some ps →
      ParamsR env fd scope items ps
  | scope, [], ps, h => by
    simp only [paramsOf, Option.some.injEq] at h
    subst h
    exact .nil
  | scope, p :: rest, ps, h => by
    simp only [paramsOf] at h
    split at h
    · rename_i c
      simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at c
      obtain ⟨c, fr⟩ := c
      cases hp : patternOf fd p with
      | none => rw [hp] at h; cases h
      | some t =>
        rw [hp] at h
        simp only at h
        cases ht : tyOf fuel env t with
        | none => rw [ht] at h; cases h
        | some x =>
          rw [ht] at h
          simp only [consParam] at h
          cases hr : paramsOf fuel env fd (⟨(paramToken p).text, (paramToken p).start - env.base, x⟩ :: scope) rest with
          | none => rw [hr] at h; cases h
          | some r =>
            rw [hr] at h
            simp only [Option.some.injEq] at h
            subst h
            refine .cons (c.1.elim (fun h => h.elim .inl (fun h => .inr (.inl h))) (fun h => .inr (.inr h))) (fun mem => ?_) ((freshId_iff _ _).1 fr) (patternOf_sound hp) (tyOf_sound ht)
              (paramsOf_sound hr)
            have := c.2
            rw [(member_iff _ _).2 mem] at this
            cases this
    · cases h

/-- The result type a `return_type_opt` names: unit for none or `-> !`. -/
inductive ResultR (env : FrontEnv) (ret : CTree) : RetTy → Prop
  | void : nodeProd ret = pRetVoid → ResultR env ret .retUnit
  | never : nodeProd ret = pRetType → nodeProd (kid ret 1) = pTypeNever → ResultR env ret .retUnit
  | ty {t : Ty} : nodeProd ret = pRetType → nodeProd (kid ret 1) ≠ pTypeNever → TyR env (kid ret 1) t →
      ResultR env ret (.retOf t)

theorem resultOf_sound {fuel : Nat} {env : FrontEnv} {ret : CTree} {r : RetTy} (h : resultOf fuel env ret = some r) :
    ResultR env ret r := by
  unfold resultOf at h
  split at h
  · rename_i pv
    simp only [Option.some.injEq] at h
    subst h
    exact .void pv
  split at h
  · rename_i _ c
    simp only [Bool.and_eq_true, decide_eq_true_eq] at c
    simp only [Option.some.injEq] at h
    subst h
    exact .never c.1 c.2
  split at h
  · rename_i _ c pt
    simp only [Bool.and_eq_true, decide_eq_true_eq, not_and] at c
    cases ht : tyOf fuel env (kid ret 1) with
    | none => rw [ht] at h; simp [retOfTy] at h
    | some t =>
      rw [ht] at h
      simp only [retOfTy, Option.some.injEq] at h
      subst h
      exact .ty pt (c pt) (tyOf_sound ht)
  cases h

/-- A function's `requires` clauses, each a bool condition asserted in order
before the body. -/
inductive ContractsR (env : FrontEnv) (scope : List Local) : CTree → MStmt → MStmt → Prop
  | none {c : CTree} {b : MStmt} : nodeProd c = pContractsNone → ContractsR env scope c b b
  | more {c : CTree} {b : MStmt} {x : MEff} {r : MStmt} : nodeProd c = pContractsMore →
      nodeProd (kid c 0) = pRequires → EffR env scope (some .tyBool) (kid (kid c 0) 2) x →
      ContractsR env scope (kid c 1) b r → ContractsR env scope c b (.mThen (.mAssert x) r)

theorem contractsOf_sound {env : FrontEnv} {scope : List Local} {b : MStmt} :
    ∀ {fuel : Nat} {c : CTree} {m : MStmt}, contractsOf fuel env scope c (some b) = some m → ContractsR env scope c b m
  | 0, _, _, h => by rw [contractsOf.eq_def] at h; simp at h
  | f + 1, c, m, h => by
    rw [contractsOf.eq_def] at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    split at h
    · rename_i pn
      simp only [Option.some.injEq] at h
      subst h
      exact .none (by simpa using pn)
    split at h
    · rename_i _ c'
      simp only [Bool.and_eq_true, decide_eq_true_eq] at c'
      simp only [contractThen] at h
      cases hx : effOf (f + 1) env scope (some .tyBool) (kid (kid c 0) 2) with
      | none => rw [hx] at h; cases h
      | some x =>
        rw [hx] at h
        simp only at h
        cases hr : contractsOf f env scope (kid c 1) (some b) with
        | none => rw [hr] at h; cases h
        | some r =>
          rw [hr] at h
          simp only [Option.some.injEq] at h
          subst h
          exact .more c'.1 c'.2 (effOf_sound hx) (contractsOf_sound hr)
    cases h

theorem contractsOf_none {env : FrontEnv} {scope : List Local} :
    ∀ {fuel : Nat} {c : CTree}, contractsOf fuel env scope c none = none
  | 0, _ => by rw [contractsOf.eq_def]; simp
  | f + 1, c => by
    rw [contractsOf.eq_def]
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel]
    split
    · rfl
    split
    · simp only [contractThen, contractsOf_none]
      split <;> rfl
    rfl

/-- A function instance's body: its parameters, its result type, its block
read with the result type as `return`'s, after its `requires` checks; a
method taking `&self` (read by value) does not write `self`. -/
def ReadFn (decls : Decls) (fd : FnDecl) (args : List Ty) (mf : MFunc) : Prop :=
  ∃ r items ps body mb, (fd.implParams ++ fd.params).length = args.length ∧
    ResultR (fnScope decls fd args none) (kid fd.tree 6) r ∧ Items (kid fd.tree 4) items ∧
    ParamsR (fnScope decls fd args (retExpected (some r))) fd [] items ps ∧
    BlockR (fnScope decls fd args (retExpected (some r))) ps.scope (kid (kid fd.tree 9) 1) body ∧
    ContractsR (fnScope decls fd args (retExpected (some r))) ps.scope (kid fd.tree 8) body mb ∧
    (∀ i, selfRefId (fnScope decls fd args (retExpected (some r))) items = some i → writesLocal mb i = false) ∧
    mf = { params := ps.params, ret := r, body := mb }

theorem refChecked_some {f : Option MFunc} {sid : Option Nat} {m : MFunc} (h : refChecked f sid = some m) :
    f = some m ∧ ∀ i, sid = some i → writesLocal m.body i = false := by
  cases f with
  | none => simp [refChecked] at h
  | some m' =>
    cases sid with
    | none => simp only [refChecked, Option.some.injEq] at h; subst h; exact ⟨rfl, fun _ e => by cases e⟩
    | some i =>
      simp only [refChecked, ifNotWrites] at h
      cases w : writesLocal m'.body i with
      | true => rw [w] at h; simp at h
      | false =>
        rw [w] at h
        simp only [Bool.false_eq_true, if_false, Option.some.injEq] at h
        subst h
        exact ⟨rfl, fun j e => by cases e; exact w⟩

theorem readFn_sound {fuel : Nat} {decls : Decls} {fd : FnDecl} {args : List Ty} {mf : MFunc}
    (h : readFn fuel decls fd args = some mf) : ReadFn decls fd args mf := by
  unfold readFn at h
  simp only at h
  split at h
  · rename_i c
    try simp only [decide_eq_true_eq] at c
    cases hr : resultOf fuel (fnScope decls fd args none) (kid fd.tree 6) with
    | none =>
      rw [hr] at h
      cases hi : listItems fuel (kid fd.tree 4) with
      | none => rw [hi] at h; cases h
      | some items =>
        rw [hi] at h
        obtain ⟨h, -⟩ := refChecked_some h
        simp only [funcParams] at h
        split at h
        · cases h
        · simp [funcRet] at h
    | some r =>
      rw [hr] at h
      cases hi : listItems fuel (kid fd.tree 4) with
      | none => rw [hi] at h; cases h
      | some items =>
        rw [hi] at h
        obtain ⟨h, nw⟩ := refChecked_some h
        simp only [funcParams] at h
        cases hp : paramsOf fuel (fnScope decls fd args (retExpected (some r))) fd [] items with
        | none => rw [hp] at h; cases h
        | some ps =>
          rw [hp] at h
          simp only [funcRet, funcBody] at h
          cases hb : blockOf fuel (fnScope decls fd args (retExpected (some r))) ps.scope (kid (kid fd.tree 9) 1) with
          | none => rw [hb, contractsOf_none] at h; cases h
          | some body =>
            rw [hb] at h
            cases hc : contractsOf fuel (fnScope decls fd args (retExpected (some r))) ps.scope (kid fd.tree 8)
                (some body) with
            | none => rw [hc] at h; cases h
            | some mb =>
              rw [hc] at h
              simp only [Option.some.injEq] at h
              subst h
              exact ⟨r, items, ps, body, mb, c, resultOf_sound hr, listItems_sound hi, paramsOf_sound hp,
                blockOf_sound hb, contractsOf_sound hc, nw, rfl⟩
  · cases h

/-- An extern function's instance (its tree is `externTree`'s): no type
parameters or arguments, its parameters and result type, and the body
returning the call of its host service on its parameters. -/
def ReadExtern (decls : Decls) (fd : FnDecl) (args : List Ty) (mf : MFunc) : Prop :=
  ∃ r items ps, (fd.implParams ++ fd.params).length = 0 ∧ args.length = 0 ∧
    ResultR (fnScope decls fd args none) (kid fd.tree 6) r ∧ Items (kid fd.tree 4) items ∧
    ParamsR (fnScope decls fd args none) fd [] items ps ∧
    mf = { params := ps.params, ret := r, body := .mReturnEval (.xHost (hostId fd.name) (paramEffs ps.params)) }

theorem externFunc_sound {fuel : Nat} {decls : Decls} {fd : FnDecl} {args : List Ty} {mf : MFunc}
    (h : externFunc fuel decls fd args = some mf) : ReadExtern decls fd args mf := by
  unfold externFunc at h
  simp only at h
  split at h
  · rename_i c
    simp only [Bool.and_eq_true, decide_eq_true_eq] at c
    cases hi : listItems fuel (kid fd.tree 4) with
    | none => rw [hi] at h; cases h
    | some items =>
      rw [hi] at h
      simp only [externBody] at h
      cases hp : paramsOf fuel (fnScope decls fd args none) fd [] items with
      | none => rw [hp] at h; cases h
      | some ps =>
        rw [hp] at h
        simp only at h
        cases hr : resultOf fuel (fnScope decls fd args none) (kid fd.tree 6) with
        | none => rw [hr] at h; cases h
        | some r =>
          rw [hr, Option.some.injEq] at h
          subst h
          exact ⟨r, items, ps, c.1, c.2, resultOf_sound hr, listItems_sound hi, paramsOf_sound hp, rfl⟩
  · cases h

/-- A function instance: a projection (numbered past the declared
functions), an extern function's instance, a declared function's instance,
or a `-> !` function's instance at a value type. -/
inductive ReadInst (decls : Decls) (inst : Inst) : MFunc → Prop
  | projection {t : Ty} {rest : List Ty} {r : Ty} : decls.fns[inst.decl]? = none → inst.args = t :: rest →
      FieldTyAt decls t (inst.decl - decls.fns.length) r →
      ReadInst decls inst
        { params := [{ id := 0, ty := t }], ret := .retOf r,
          body := .mReturn (.field 0 (inst.decl - decls.fns.length)) }
  | host {fd : FnDecl} {mf : MFunc} : decls.fns[inst.decl]? = some fd → nodeProd fd.tree = pExternFn →
      ReadExtern decls fd inst.args mf → ReadInst decls inst mf
  | plain {fd : FnDecl} {mf : MFunc} : decls.fns[inst.decl]? = some fd → diverges fd inst = false →
      ReadFn decls fd inst.args mf → nodeProd fd.tree ≠ pExternFn → ReadInst decls inst mf
  | diverge {fd : FnDecl} {g : MFunc} {t : Ty} : decls.fns[inst.decl]? = some fd → diverges fd inst = true →
      ReadFn decls fd (initTys inst.args) g → lastTy inst.args = some t → nodeProd fd.tree ≠ pExternFn →
      ReadInst decls inst
        { params := g.params, ret := .retOf t,
          body := .mThen (.mDiscard (.xCall ⟨inst.decl, initTys inst.args⟩ (paramEffs g.params)))
            (.mReturnEval (.xCall inst (paramEffs g.params))) }

theorem readInst_sound {fuel : Nat} {decls : Decls} {inst : Inst} {mf : MFunc} (h : readInst fuel decls inst = some mf) :
    ReadInst decls inst mf := by
  unfold readInst at h
  cases hf : decls.fns[inst.decl]? with
  | none =>
    rw [hf] at h
    simp only [projectionFunc] at h
    cases hr : projectionRet fuel decls inst with
    | none => rw [hr] at h; cases h
    | some r =>
      rw [hr] at h
      simp only at h
      unfold projectionRet at hr
      cases ha : inst.args with
      | nil => rw [ha] at hr; cases hr
      | cons t rest =>
        rw [ha] at hr h
        simp only [Option.some.injEq] at h
        subst h
        have e : fieldTyAt fuel decls t (inst.decl - decls.fns.length) = some r := by
          unfold fieldTyAt; exact hr
        exact .projection hf ha (fieldTyAt_sound _ e)
  | some fd =>
    rw [hf] at h
    simp only [readDeclInst] at h
    split at h
    · rename_i ex
      exact .host hf ex (externFunc_sound h)
    rename_i ex
    split at h
    · rename_i dv
      simp only [divergeFunc] at h
      cases hg : readFn fuel decls fd (initTys inst.args) with
      | none => rw [hg] at h; cases h
      | some g =>
        rw [hg] at h
        simp only at h
        cases hl : lastTy inst.args with
        | none => rw [hl] at h; cases h
        | some t =>
          rw [hl] at h
          simp only [Option.some.injEq] at h
          subst h
          exact .diverge hf dv (readFn_sound hg) hl ex
    · rename_i dv
      exact .plain hf (by simpa using dv) (readFn_sound h) ex

/-! ## Monomorphization -/

/-- Instance `i` of the table onward: each is read, and the instances its
body calls that are new are appended to the table. -/
inductive MonoR (decls : Decls) : List Inst → List MFunc → Nat → Mono → Prop
  | done {table : List Inst} {done : List MFunc} {i : Nat} : table[i]? = none →
      MonoR decls table done i { table := table, funcs := done }
  | step {table : List Inst} {done : List MFunc} {i : Nat} {inst : Inst} {mf : MFunc} {r : Mono} :
      table[i]? = some inst → ReadInst decls inst mf →
      MonoR decls (addInsts table (stmtCalls mf.body)) (done ++ [mf]) (i + 1) r → MonoR decls table done i r

theorem monoLoop_sound {rfuel : Nat} {decls : Decls} : ∀ {fuel : Nat} {table : List Inst} {done : List MFunc} {i : Nat}
    {r : Mono}, monoLoop fuel rfuel decls table done i = some r → MonoR decls table done i r
  | 0, _, _, _, _, h => by unfold monoLoop at h; simp at h
  | f + 1, table, done, i, r, h => by
    unfold monoLoop at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    cases hi : table[i]? with
    | none =>
      rw [hi] at h
      simp only [Option.some.injEq] at h
      subst h
      exact .done hi
    | some inst =>
      rw [hi] at h
      simp only at h
      cases hm : readInst rfuel decls inst with
      | none => rw [hm] at h; cases h
      | some mf =>
        rw [hm] at h
        simp only at h
        exact .step hi (readInst_sound hm) (monoLoop_sound h)

/-- The type instances the types `ts` need, appended to `table` in the
order they are first needed. -/
inductive TypeTable (decls : Decls) : List Inst → List Ty → List Inst → Prop
  | nil {table : List Inst} : TypeTable decls table [] table
  | cons {table : List Inst} {t : Ty} {rest : List Ty} {xs r : List Inst} : TyInsts decls t xs →
      TypeTable decls (addInsts table xs) rest r → TypeTable decls table (t :: rest) r

theorem typeTable_sound {fuel : Nat} {decls : Decls} :
    ∀ {table : List Inst} {ts : List Ty} {r : List Inst}, typeTable fuel decls table ts = some r →
      TypeTable decls table ts r
  | table, [], r, h => by
    simp only [typeTable, Option.some.injEq] at h
    subst h
    exact .nil
  | table, t :: rest, r, h => by
    simp only [typeTable] at h
    cases hx : tyInsts fuel decls t with
    | none => rw [hx] at h; cases h
    | some xs =>
      rw [hx] at h
      exact .cons (tyInsts_sound hx) (typeTable_sound h)

/-- `TypeTable` over more types, passing over a type whose instance the
table already holds. -/
inductive TypeTableMore (decls : Decls) : List Inst → List Ty → List Inst → Prop
  | nil {table : List Inst} : TypeTableMore decls table [] table
  | known {table : List Inst} {t : Ty} {rest : List Ty} {r : List Inst} : tyKnown table t = true →
      TypeTableMore decls table rest r → TypeTableMore decls table (t :: rest) r
  | new {table : List Inst} {t : Ty} {rest : List Ty} {r1 r : List Inst} : tyKnown table t = false →
      TypeTable decls table [t] r1 → TypeTableMore decls r1 rest r → TypeTableMore decls table (t :: rest) r

theorem typeTableMore_none {fuel : Nat} {decls : Decls} (ts : List Ty) : typeTableMore fuel decls none ts = none := by
  cases ts <;> rfl

theorem typeTableMore_sound {fuel : Nat} {decls : Decls} :
    ∀ {table : List Inst} {ts : List Ty} {r : List Inst}, typeTableMore fuel decls (some table) ts = some r →
      TypeTableMore decls table ts r
  | table, [], r, h => by
    simp only [typeTableMore, Option.some.injEq] at h
    subst h
    exact .nil
  | table, t :: rest, r, h => by
    simp only [typeTableMore] at h
    split at h
    · rename_i k
      exact .known k (typeTableMore_sound h)
    · rename_i k
      cases ht : typeTable fuel decls table [t] with
      | none => rw [ht, typeTableMore_none] at h; cases h
      | some r1 =>
        rw [ht] at h
        exact .new (by simpa using k) (typeTable_sound ht) (typeTableMore_sound h)

end Lanius.Mini.Reading
