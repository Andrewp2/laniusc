import Lanius.Std.VecClient
import Lanius.Std.MapSpec

/-! # S7: `std::set` and `std::map` clients through the verified compiler

`has(s, x)` calls `std::set::contains` and `lookup_or_zero(m, k)` calls
`std::map::get_or` with fallback 0. In a source program that `compileSource`
accepts and whose Core image has the set (map) functions as the templates,
the compiled client returns slots representing what the specs give, and a
heap representing Core's. The map lookup's `HeapBlocksDisjoint` comes from
`HeapCorr`. -/

namespace Lanius.Std

section core
open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {ids : VecIds}

/-- `fn has(s: Set<i32>, x: i32) -> bool { return std::set::contains(s, x); }` -/
def setHasSrc (sid vec sc : Nat) : Mini.SrcFunc where
  params := [⟨0, .struct sid [.struct vec [.ptr, .i32, .i32]]⟩, ⟨1, .i32⟩]
  ret := .bool
  body := .returnEval (.eCall sc [.ePure (.local 0), .ePure (.local 1)])

/-- `fn lookup_or_zero(m: Map<i32, V>, k: i32) -> i32 { return std::map::get_or(m, k, 0); }` -/
def mapLookupSrc (mid vec go : Nat) : Mini.SrcFunc where
  params := [⟨0, .struct mid [.struct vec [.ptr, .i32, .i32]]⟩, ⟨1, .i32⟩]
  ret := .i32
  body := .returnEval (.eCall go [.ePure (.local 0), .ePure (.local 1), .ePure (.int 0)])

theorem setHas_core (inst : VecInstance P i32Ty ids) {sid : TypeId} {f sc vc indexOf eq : FunctionId}
    (found : P.function? f = some ((setHasSrc sid ids.vec sc).toCore f))
    (scFound : P.function? sc = some (setContainsFn i32Ty sid sc vc))
    (vcFound : P.function? vc = some (vecContainsFn ids i32Ty vc indexOf))
    (indexFound : P.function? indexOf = some (indexOfFn ids i32Ty indexOf eq))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {v x : Value} {xs : List Value}
    (rep : VecRep P i32Ty 4 ids.vec caller.heap v xs) (itemIn : x ∈ vals) (sub : ∀ z ∈ xs, z ∈ vals) :
    ∃ after, RunsExpr P caller (.call f ([Value.structure sid [v], x].map Expr.value))
      (.boolean (xs.any (eqv · x))) after ∧ PureFrame caller after := by
  refine PureRun.call found rfl rfl formed ?_
  obtain ⟨fE, _, l0, l1⟩ := set_entry2 (P := P) formed (sid := sid) v x
  exact PureRun.retCall (RunsExprs.two (RunsExpr.local' l0) (RunsExpr.local' l1))
    (setContains_spec inst ElemKind.i32 scFound vcFound indexFound eqSpec fE rep itemIn sub)

theorem mapLookup_core {T : Ty} {size : Nat} {mid eid : TypeId} {fi : MapFindIds}
    (inst : MapFindInstance P T ids mid fi) (kind : ElemKind P T size) {fnd go f : FunctionId}
    (found : P.function? f = some ((mapLookupSrc mid ids.vec go).toCore f))
    (fndFound : P.function? fnd = some (mapFindFn i32Ty T mid fnd fi.asl fi.ml fi.eq))
    (goFound : P.function? go = some (mapGetOrFn i32Ty T mid go i32Ty fnd fi.asl))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P fi.eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {kvs : List (Value × Value)} {p cap : Nat} {key : Value}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap])
      (kvs.map (entryOf eid)))
    (keyIn : key ∈ vals) (sub : ∀ e ∈ kvs, e.1 ∈ vals) (disjoint : HeapBlocksDisjoint caller.heap) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure mid [.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length,
          .signed .i32 cap]], key].map Expr.value))
      (((kvs.find? (fun e => eqv e.1 key)).map Prod.snd).getD (.signed .i32 0)) after ∧ PureFrame caller after := by
  refine PureRun.call found rfl rfl formed ?_
  obtain ⟨fE, _, l0, l1⟩ := set_entry2 (P := P) formed (sid := mid)
    (.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap]) key
  have zero : (0 : BitVec 32).toInt = 0 := rfl
  obtain ⟨S', run, frame⟩ := mapGetOr_spec inst kind fndFound goFound eqSpec fE rep keyIn sub disjoint
    (.signed .i32 (0 : BitVec 32).toInt)
  rw [zero] at run
  exact PureRun.retCall (RunsExprs.three (RunsExpr.local' l0) (RunsExpr.local' l1) (RunsExpr.value' _))
    ⟨S', run, frame⟩

end core

section compiled
open Lanius.Mini
open Lanius.Core (Value)

/-- The compiled `has(s, x)` returns slots representing whether some item of
the set is `eqv` to `x`. -/
theorem set_client_correct {sp : SrcProgram} {binary : Binary} (compiled : compileSource sp = some binary)
    {ids : VecIds} (inst : VecInstance sp.toCore i32Ty ids) {sid : Nat} {f sc vc indexOf eq : Nat}
    (found : sp.funcs[f]? = some (setHasSrc sid ids.vec sc))
    (scFound : sp.toCore.function? sc = some (setContainsFn i32Ty sid sc vc))
    (vcFound : sp.toCore.function? vc = some (vecContainsFn ids i32Ty vc indexOf))
    (indexFound : sp.toCore.function? indexOf = some (indexOfFn ids i32Ty indexOf eq))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec sp.toCore eq eqv vals)
    {v x : Value} {bits : List (BitVec 64)}
    (typed : FieldsHold (paramTypes (setHasSrc sid ids.vec sc).params) [.structure sid [v], x] (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize (setHasSrc sid ids.vec sc).params)
    {st : Semantics.State} {heap : Heap} (fresh : st.Fresh) (hc : HeapCorr st.heap st.world heap)
    {xs : List Value} (rep : VecRep sp.toCore i32Ty 4 ids.vec st.heap v xs) (itemIn : x ∈ vals)
    (sub : ∀ z ∈ xs, z ∈ vals) (fits : st.heap.nextAddress ≤ heap.limit) :
    ∃ depth results after, SrcType.bool.HoldsAt (.boolean (xs.any (eqv · x))) (Func.entry results) 0 ∧
      results.length = SrcType.bool.size ∧ HeapCorr st.heap st.world after ∧
      MachineReturns binary depth f bits heap results after := by
  have coreFound : sp.toCore.function? f = some ((setHasSrc sid ids.vec sc).toCore f) := by
    rw [SrcProgram.function?_toCore, found]
  exact compiled_of_pure compiled found typed bitsLen fresh hc fits
    (setHas_core inst coreFound scFound vcFound indexFound eqSpec fresh.1 rep itemIn sub)

/-- The compiled `lookup_or_zero(m, k)` returns slots representing the value
of the first entry whose key is `eqv` to `k`, or 0. -/
theorem map_client_correct {sp : SrcProgram} {binary : Binary} (compiled : compileSource sp = some binary)
    {ids : VecIds} {T : Core.Ty} {size : Nat} {mid eid : Nat} {fi : MapFindIds}
    (inst : MapFindInstance sp.toCore T ids mid fi) (kind : ElemKind sp.toCore T size) {fnd go f : Nat}
    (found : sp.funcs[f]? = some (mapLookupSrc mid ids.vec go))
    (fndFound : sp.toCore.function? fnd = some (mapFindFn i32Ty T mid fnd fi.asl fi.ml fi.eq))
    (goFound : sp.toCore.function? go = some (mapGetOrFn i32Ty T mid go i32Ty fnd fi.asl))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec sp.toCore fi.eq eqv vals)
    {kvs : List (Value × Value)} {p cap : Nat} {key : Value} {bits : List (BitVec 64)}
    (typed : FieldsHold (paramTypes (mapLookupSrc mid ids.vec go).params)
      [.structure mid [.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length,
        .signed .i32 cap]], key] (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize (mapLookupSrc mid ids.vec go).params)
    {st : Semantics.State} {heap : Heap} (fresh : st.Fresh) (hc : HeapCorr st.heap st.world heap)
    (rep : VecRep sp.toCore T size ids.vec st.heap
      (.structure ids.vec [.pointer p, .signed .i32 (kvs.map (entryOf eid)).length, .signed .i32 cap])
      (kvs.map (entryOf eid)))
    (keyIn : key ∈ vals) (sub : ∀ e ∈ kvs, e.1 ∈ vals) (fits : st.heap.nextAddress ≤ heap.limit) :
    ∃ depth results after,
      SrcType.i32.HoldsAt (((kvs.find? (fun e => eqv e.1 key)).map Prod.snd).getD (.signed .i32 0))
        (Func.entry results) 0 ∧
      results.length = SrcType.i32.size ∧ HeapCorr st.heap st.world after ∧
      MachineReturns binary depth f bits heap results after := by
  have coreFound : sp.toCore.function? f = some ((mapLookupSrc mid ids.vec go).toCore f) := by
    rw [SrcProgram.function?_toCore, found]
  exact compiled_of_pure compiled found typed bitsLen fresh hc fits
    (mapLookup_core inst kind coreFound fndFound goFound eqSpec fresh.1 rep keyIn sub (Lanius.Std.HeapCorr.blocksDisjoint hc))

end compiled

#print axioms setHas_core
#print axioms mapLookup_core
#print axioms set_client_correct
#print axioms map_client_correct

end Lanius.Std
