module

public import Lanius.Mini.Refs.Lemmas
public import Lanius.Mini.Refs.CoreLemmas

@[expose] public section

/-! # References: a place's address (F5)

The run of a place's code (`RPlace.code`): it puts the sub-place's lowest
byte in its target slot when Core resolves the place and can read it
(`RPlace.addr_exec`), and it stops when Core's resolution traps with a
checked trap (`RPlace.traps_stop`). For `PlaceAddr` and `PlaceAddrTraps`.
-/

namespace Lanius.Mini

open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-! ## Words -/

theorem bv_self (w : BitVec 64) : w = BitVec.ofNat 64 w.toNat := by
  apply BitVec.eq_of_toNat_eq
  simp

theorem bv_add (a b : Nat) : BitVec.ofNat 64 a + BitVec.ofNat 64 b = BitVec.ofNat 64 (a + b) := by
  apply BitVec.eq_of_toNat_eq
  simp [BitVec.toNat_add, Nat.add_mod]

theorem bv_mul (a b : Nat) : BitVec.ofNat 64 a * BitVec.ofNat 64 b = BitVec.ofNat 64 (a * b) := by
  apply BitVec.eq_of_toNat_eq
  simp [BitVec.toNat_mul, Nat.mul_mod]

theorem bv_sub {a b : Nat} (le : b ≤ a) : BitVec.ofNat 64 a - BitVec.ofNat 64 b = BitVec.ofNat 64 (a - b) := by
  have : BitVec.ofNat 64 a = BitVec.ofNat 64 (a - b) + BitVec.ofNat 64 b := by
    rw [bv_add, Nat.sub_add_cancel le]
  rw [this, BitVec.add_sub_cancel]

theorem addOff_eval_ofNat {env : Env} {r a : Nat} (off : Nat) (hr : env r = BitVec.ofNat 64 a) :
    (addOff r off).eval env = BitVec.ofNat 64 (a + off) := by
  simp only [addOff, Expr.eval, Word.apply, BinOp.apply, hr, bv_add]

theorem lt_eval {env : Env} {slot length : Nat} (small : length < 2 ^ 64) :
    (Expr.compare .u64 .lt (.var slot) (.lit (BitVec.ofNat 64 length))).eval env =
      if (env slot).toNat < length then 1 else 0 := by
  simp [Expr.eval, Word.holds, CmpOp.holdsU, BitVec.ult, Nat.mod_eq_of_lt small]

theorem refTrap_stops {prog : Program} {depth : Nat} {env : Env} {hp : Heap} (t n : Nat) :
    Stops prog depth env hp (refTrap t) n :=
  .divide (by simp [Expr.eval, Word.divides, DivOp.defined])

theorem Env.set_same (env : Env) (t : Nat) (w : BitVec 64) : env.set t w t = w := by
  simp [Env.set]

theorem Env.set_other (env : Env) {t k : Nat} (w : BitVec 64) (ne : k ≠ t) : env.set t w k = env k := by
  simp [Env.set, ne]

/-! ## Sub-places -/

theorem SrcType.sub_snoc : ∀ (path : List ValueProjection) {ty t c : SrcType} {off o : Nat} {p : ValueProjection},
    ty.sub path = some (off, t) → t.subStep p = some (o, c) → ty.sub (path ++ [p]) = some (off + o, c)
  | [], ty, t, c, off, o, p, h, hs => by
    simp only [SrcType.sub, Option.some.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    simp [SrcType.sub, hs]
  | q :: rest, ty, t, c, off, o, p, h, hs => by
    obtain ⟨o', child, inner, hstep, hrest, rfl⟩ := SrcType.sub_cons h
    have ih := SrcType.sub_snoc rest hrest hs
    simp only [List.cons_append, SrcType.sub, hstep, ih, Nat.add_assoc]

theorem Addressed.sub_snoc {x : Addressed} {path : List ValueProjection} {t c : SrcType} {a o : Nat}
    {p : ValueProjection} (h : x.sub path = some (a, t)) (hs : t.subStep p = some (o, c)) :
    x.sub (path ++ [p]) = some (a + o, c) := by
  simp only [Addressed.sub] at h ⊢
  split at h
  · cases h
  rename_i off t' hsub
  simp only [Option.some.injEq, Prod.mk.injEq] at h
  obtain ⟨rfl, rfl⟩ := h
  simp [SrcType.sub_snoc path hsub hs, Nat.add_assoc]

theorem SrcType.indexInfo_some {ty : SrcType} {length : Nat} {element : SrcType}
    (h : ty.indexInfo = some (length, element)) : ty = .array element length := by
  cases ty <;> simp_all [SrcType.indexInfo]

/-- An array sub-place of a home holds `length` elements in Core. -/
theorem Homes.array_length {sx : Statics} {bud : Budget} {places : List Addressed} {st : State} {hp : Heap}
    (homes : Homes sx bud places st hp) {x : Addressed} (mem : x ∈ places) {path : List ValueProjection}
    {a length : Nat} {element : SrcType} {elements : List Value}
    (hsub : x.sub path = some (a, .array element length))
    (hread : Semantics.readCellProjection st x.cell path = .ok (.array elements)) :
    elements.length = length := by
  obtain ⟨i, hi⟩ := List.mem_iff_getElem?.mp mem
  obtain ⟨root, hroot, hold⟩ := homes.holds i x hi
  rw [readCell_path hroot] at hread
  simp only [Addressed.sub] at hsub
  split at hsub
  · cases hsub
  rename_i off t hs
  simp only [Option.some.injEq, Prod.mk.injEq] at hsub
  obtain ⟨-, rfl⟩ := hsub
  obtain ⟨j, -, held, -⟩ := SrcType.sub_holds path hs hold hread
  cases held with
  | array hfields =>
    have len := hfields.length
    simpa using len

/-! ## The run -/

/-- A resolved place's code puts the sub-place's lowest byte in `t`. -/
theorem RPlace.addr_exec {sx : Statics} {bud : Budget} {places : List Addressed} {st : State} {hp : Heap}
    {c : RCtx} {t : Nat} {cprog : Lanius.Core.Program} {prog : Program} {depth : Nat} {env : Env}
    {scratch : List Nat} (homes : Homes sx bud places st hp) (agree : RefsAgree c places st env)
    (tout : t ∉ scratch) :
    ∀ (p : RPlace) {code : Stmt} {ty : SrcType} {cell : Lanius.CellId} {path : List ValueProjection} {v : Value},
      p.code c t = some (code, ty) → p.Resolves cprog st cell path →
      p.IndexRuns cprog st prog depth hp env t scratch →
      Semantics.readCellProjection st cell path = .ok v →
      ∃ x ∈ places, ∃ (address : Nat) (env' : Env), x.cell = cell ∧ x.sub path = some (address, ty) ∧
        Exec prog depth env hp code (.normal env' hp) ∧ env' t = BitVec.ofNat 64 address ∧
        ∀ k, k ∉ scratch → k ≠ t → env' k = env k
  | .home id, code, ty, cell, path, v, hcode, hres, _, _ => by
    simp only [RPlace.code] at hcode
    split at hcode
    · cases hcode
    rename_i offset hty hl
    simp only [Option.some.injEq, Prod.mk.injEq] at hcode
    obtain ⟨rfl, rfl⟩ := hcode
    cases hres with
    | home hid =>
      obtain ⟨x, mem, cell', hid', xcell, xty, xaddr⟩ := agree.homes id offset hty hl
      rw [hid] at hid'
      cases hid'
      refine ⟨x, mem, x.address, _, xcell, by simp [Addressed.sub, SrcType.sub, xty], .assign, ?_,
        fun k _ ne => Env.set_other _ _ ne⟩
      rw [Env.set_same, addOff_eval_ofNat offset (bv_self _), xaddr]
  | .deref id, code, ty, cell, path, v, hcode, hres, _, _ => by
    simp only [RPlace.code] at hcode
    split at hcode
    · cases hcode
    rename_i hl
    simp only [Option.some.injEq, Prod.mk.injEq] at hcode
    obtain ⟨rfl, rfl⟩ := hcode
    cases hres with
    | deref hloc =>
      obtain ⟨x, mem, xcell, xsub⟩ := agree.refs id _ cell path hl hloc
      refine ⟨x, mem, _, _, xcell, xsub, .assign, ?_, fun k _ ne => Env.set_other _ _ ne⟩
      rw [Env.set_same]
      exact bv_self _
  | .field base f, code, ty, cell, path, v, hcode, hres, hruns, hread => by
    simp only [RPlace.code] at hcode
    split at hcode
    · cases hcode
    rename_i codeB tyB hb
    split at hcode
    · cases hcode
    rename_i offset child hstep
    simp only [Option.some.injEq, Prod.mk.injEq] at hcode
    obtain ⟨rfl, rfl⟩ := hcode
    cases hres with
    | field hresB =>
      rename_i pathB
      cases hruns with
      | field hrunsB =>
        obtain ⟨u, hu, -⟩ := CoreRefs.readCell_snoc hread
        obtain ⟨x, mem, a, envB, xcell, xsub, run, envT, same⟩ :=
          RPlace.addr_exec homes agree tout base hb hresB hrunsB hu
        refine ⟨x, mem, a + offset, _, xcell, Addressed.sub_snoc xsub hstep, .seq run .assign, ?_,
          fun k out ne => by rw [Env.set_other _ _ ne]; exact same k out ne⟩
        rw [Env.set_same, addOff_eval_ofNat offset envT]
  | .index base ie indexCode slot, code, ty, cell, path, v, hcode, hres, hruns, hread => by
    simp only [RPlace.code] at hcode
    split at hcode
    · cases hcode
    rename_i codeB tyB hb
    split at hcode
    · cases hcode
    rename_i length element hinfo
    split at hcode
    · cases hcode
    rename_i small
    simp only [Option.some.injEq, Prod.mk.injEq] at hcode
    obtain ⟨rfl, rfl⟩ := hcode
    obtain rfl := SrcType.indexInfo_some hinfo
    cases hres with
    | index hresB hev hiv =>
      rename_i pathB iv i
      cases hruns with
      | index hrunsB _ hrun _ =>
        obtain ⟨u, hu, hq⟩ := CoreRefs.readCell_snoc hread
        obtain ⟨elements, rfl, hel⟩ := CoreRefs.projectedValue_index hq
        obtain ⟨x, mem, a, envB, xcell, xsub, run, envT, same⟩ :=
          RPlace.addr_exec homes agree tout base hb hresB hrunsB hu
        have len := homes.array_length mem xsub (by rw [xcell]; exact hu)
        have lt : i < length := by
          rw [← len]
          exact (List.getElem?_eq_some_iff.mp hel).1
        obtain ⟨env₁, runI, idx, keep⟩ := hrun iv hev envB same
        have slotI : (env₁ slot).toNat = i := idx.1 i hiv
        have t₁ : env₁ t = BitVec.ofNat 64 a := by rw [keep t tout, envT]
        have cmp := lt_eval (env := env₁) (slot := slot) (length := length) (by omega)
        rw [slotI, if_pos lt] at cmp
        have hstep : (SrcType.array element length).subStep (.index i) =
            some (if element.accessKind.narrow then element.accessKind.bytes * i
              else 8 * (length * element.words - (i + 1) * element.words), element) := by
          simp only [SrcType.subStep, if_pos lt]
          split <;> rfl
        have slotW : env₁ slot = BitVec.ofNat 64 i := by rw [bv_self (env₁ slot), slotI]
        have addrRun : Exec prog depth env₁ hp (elementAddr t slot length element)
            (.normal (env₁.set t (BitVec.ofNat 64 (a + if element.accessKind.narrow then element.accessKind.bytes * i
              else 8 * (length * element.words - (i + 1) * element.words)))) hp) := by
          cases hn : element.accessKind.narrow with
          | true =>
            simp only [elementAddr, hn, if_true]
            rw [show BitVec.ofNat 64 (a + element.accessKind.bytes * i) =
                (Expr.binary .u64 .add (.var t) (.binary .u64 .mul (.var slot)
                  (.lit (BitVec.ofNat 64 element.accessKind.bytes)))).eval env₁ by
              simp only [Expr.eval, Word.apply, BinOp.apply, t₁, slotW, bv_mul, bv_add, Nat.mul_comm i]]
            exact .assign
          | false =>
            simp only [elementAddr, hn, Bool.false_eq_true, if_false]
            rw [show BitVec.ofNat 64 (a + 8 * (length * element.words - (i + 1) * element.words)) =
                (Expr.binary .u64 .sub
                  (.binary .u64 .add (.var t) (.lit (BitVec.ofNat 64 (8 * ((length - 1) * element.words)))))
                  (.binary .u64 .mul (.var slot) (.lit (BitVec.ofNat 64 (8 * element.words))))).eval env₁ by
              simp only [Expr.eval, Word.apply, BinOp.apply, t₁, slotW, bv_mul, bv_add]
              obtain ⟨d, rfl⟩ : ∃ d, length = i + 1 + d := ⟨length - (i + 1), by omega⟩
              have e1 : (i + 1 + d - 1) * element.words = i * element.words + d * element.words := by
                rw [show i + 1 + d - 1 = i + d by omega, Nat.add_mul]
              have e2 : (i + 1 + d) * element.words - (i + 1) * element.words = d * element.words := by
                rw [Nat.add_mul (i + 1) d]; omega
              have e3 : i * (8 * element.words) = 8 * (i * element.words) := Nat.mul_left_comm _ _ _
              rw [e1, e2, e3, bv_sub (by omega)]
              congr 1
              omega]
            exact .assign
        refine ⟨x, mem, _, _, xcell, Addressed.sub_snoc xsub hstep,
          .seq run (.seq runI (.ifTrue (by rw [cmp]; decide) addrRun)), Env.set_same _ _ _,
          fun k out ne => by rw [Env.set_other _ _ ne, keep k out]; exact same k out ne⟩

/-- A place whose resolution traps with a checked trap: its code stops. -/
theorem RPlace.traps_stop {sx : Statics} {bud : Budget} {places : List Addressed} {st : State} {hp : Heap}
    {c : RCtx} {t : Nat} {cprog : Lanius.Core.Program} {prog : Program} {depth : Nat} {env : Env}
    {scratch : List Nat} (homes : Homes sx bud places st hp) (agree : RefsAgree c places st env)
    (tout : t ∉ scratch) :
    ∀ (p : RPlace) {code : Stmt} {ty : SrcType} {r : Lanius.Trap} {st' : State},
      p.code c t = some (code, ty) → p.Traps cprog st r st' → undefinedTrap r = false →
      p.IndexRuns cprog st prog depth hp env t scratch → ∀ n, Stops prog depth env hp code n
  | .home _, _, _, _, _, _, htraps, _, _, _ => by cases htraps
  | .deref _, _, _, _, _, _, htraps, _, _, _ => by cases htraps
  | .field base f, code, ty, r, st', hcode, htraps, undef, hruns, n => by
    simp only [RPlace.code] at hcode
    split at hcode
    · cases hcode
    rename_i codeB tyB hb
    split at hcode
    · cases hcode
    simp only [Option.some.injEq, Prod.mk.injEq] at hcode
    obtain ⟨rfl, rfl⟩ := hcode
    cases htraps with
    | field htrapsB =>
      cases hruns with
      | field hrunsB => exact .seqFirst (RPlace.traps_stop homes agree tout base hb htrapsB undef hrunsB n)
  | .index base ie indexCode slot, code, ty, r, st', hcode, htraps, undef, hruns, n => by
    simp only [RPlace.code] at hcode
    split at hcode
    · cases hcode
    rename_i codeB tyB hb
    split at hcode
    · cases hcode
    rename_i length element hinfo
    split at hcode
    · cases hcode
    rename_i small
    simp only [Option.some.injEq, Prod.mk.injEq] at hcode
    obtain ⟨rfl, rfl⟩ := hcode
    obtain rfl := SrcType.indexInfo_some hinfo
    cases hruns with
    | index hrunsB _ hrun htrap =>
      cases htraps with
      | index htrapsB => exact .seqFirst (RPlace.traps_stop homes agree tout base hb htrapsB undef hrunsB n)
      | indexTraps hresB hread hev =>
        obtain ⟨x, mem, a, envB, xcell, xsub, run, envT, same⟩ :=
          RPlace.addr_exec homes agree tout base hb hresB hrunsB hread
        exact .seqSecond run (.seqFirst (htrap _ _ undef hev envB same n))
      | negative hresB hread hev hiv =>
        obtain ⟨x, mem, a, envB, xcell, xsub, run, envT, same⟩ :=
          RPlace.addr_exec homes agree tout base hb hresB hrunsB hread
        obtain ⟨env₁, runI, idx, -⟩ := hrun _ hev envB same
        have big := idx.2 hiv
        have cmp := lt_eval (env := env₁) (slot := slot) (length := length) (by omega)
        rw [if_neg (by omega)] at cmp
        exact .seqSecond run (.seqSecond runI (.ifFalse cmp (refTrap_stops t n)))
      | beyond hresB hread hev hiv ge =>
        obtain ⟨x, mem, a, envB, xcell, xsub, run, envT, same⟩ :=
          RPlace.addr_exec homes agree tout base hb hresB hrunsB hread
        have len := homes.array_length mem xsub (by rw [xcell]; exact hread)
        obtain ⟨env₁, runI, idx, -⟩ := hrun _ hev envB same
        have slotI := idx.1 _ hiv
        have cmp := lt_eval (env := env₁) (slot := slot) (length := length) (by omega)
        rw [if_neg (by omega)] at cmp
        exact .seqSecond run (.seqSecond runI (.ifFalse cmp (refTrap_stops t n)))

end Lanius.Mini
