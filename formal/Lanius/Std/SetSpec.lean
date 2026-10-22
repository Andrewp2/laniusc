import Lanius.Std.VecSort

/-! # `std::set`: the wrappers over `std::vec`

`struct Set<T> { items: Vec<T> }` is the Core value `.structure sid [v]`
with `v` a vector. A set represents a list without `eqv`-equal pairs
(`Distinct`). Each function below that only forwards to `std::vec` gets
the vector function's spec, with the set wrapped around the vector. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

variable {P : Program} {T : Ty} {ids : VecIds} {g : GrowIds} {mo : MoreIds} {size : Nat}

/-- `T::eq` on the values in `vals`. -/
def EqSpec (P : Program) (eq : FunctionId) (eqv : Value → Value → Bool) (vals : List Value) : Prop :=
  ∀ S : State, S.CellsWellFormed → ∀ a ∈ vals, ∀ b ∈ vals, ∃ after,
    RunsExpr P S (.call eq ([a, b].map Expr.value)) (.boolean (eqv a b)) after ∧ PureFrame S after

theorem EqSpec.against {eq : FunctionId} {eqv : Value → Value → Bool} {vals xs : List Value} {item : Value}
    (spec : EqSpec P eq eqv vals) (itemIn : item ∈ vals) (sub : ∀ z ∈ xs, z ∈ vals) :
    ∀ S : State, S.CellsWellFormed → ∀ a ∈ xs, ∃ after,
      RunsExpr P S (.call eq ([a, item].map Expr.value)) (.boolean (eqv a item)) after ∧ PureFrame S after :=
  fun S formed a member => spec S formed a (sub a member) item itemIn

/-- No two items are `eqv`-equal, in list order. -/
def Distinct (eqv : Value → Value → Bool) (xs : List Value) : Prop := xs.Pairwise (fun a b => eqv a b = false)

theorem Distinct.append_absent {eqv : Value → Value → Bool} {xs : List Value} {x : Value}
    (distinct : Distinct eqv xs) (absent : xs.any (eqv · x) = false) : Distinct eqv (xs ++ [x]) := by
  refine List.pairwise_append.mpr ⟨distinct, List.pairwise_singleton _ _, fun a am b bm => ?_⟩
  rw [List.mem_singleton.mp bm]
  have := List.any_eq_false.mp absent a am
  simpa using this

theorem Distinct.eraseIdx {eqv : Value → Value → Bool} {xs : List Value} (distinct : Distinct eqv xs) (i : Nat) :
    Distinct eqv (xs.eraseIdx i) := distinct.sublist (List.eraseIdx_sublist xs i)

theorem findIdx_nonneg (p : Value → Bool) (xs : List Value) :
    decide ((((xs.findIdx? p).map Int.ofNat).getD (-1)) ≥ 0) = xs.any p := by
  rw [← List.findIdx?_isSome]
  cases xs.findIdx? p with
  | none => decide
  | some i => simp

/-! ## Templates -/

def setTy (sid : TypeId) : Ty := .structure sid

/-- `value.items`, with `value` local 0. -/
def setItems : Expr := .field (.local 0) 0

/-- `pub fn contains<T>(value: Vec<T>, item: T) -> bool { return index_of(value, item) >= 0; }` -/
def vecContainsFn (ids : VecIds) (T : Ty) (f indexOf : FunctionId) : Function where
  id := f
  parameters := [(0, vecTy ids), (1, T)]
  returnType := boolTy
  body := some (.returnValue (some (.binary .greaterEqual (.call indexOf [.local 0, .local 1]) (int 0))))

section templates
variable (ids : VecIds) (g : GrowIds) (mo : MoreIds) (T : Ty) (sid : TypeId) (f : FunctionId)

def setNewFn : Function where
  id := f
  parameters := []
  returnType := setTy sid
  body := some (.letLocal 0 (vecTy ids) (.call ids.new []) (.returnValue (some (.structValue sid [.local 0]))))

/-- `return std::vec::<op>(value.items);` for `len`, `capacity` and `is_empty`. -/
def setForwardFn (op : FunctionId) (ret : Ty) : Function where
  id := f
  parameters := [(0, setTy sid)]
  returnType := ret
  body := some (.returnValue (some (.call op [setItems])))

def setContainsFn (vc : FunctionId) : Function where
  id := f
  parameters := [(0, setTy sid), (1, T)]
  returnType := boolTy
  body := some (.returnValue (some (.call vc [setItems, .local 1])))

def setAtOrFn : Function where
  id := f
  parameters := [(0, setTy sid), (1, i32Ty), (2, T)]
  returnType := T
  body := some (.returnValue (some (.call ids.getOr [setItems, .local 1, .local 2])))

def setTryReserveFn : Function where
  id := f
  parameters := [(0, setTy sid), (1, i32Ty)]
  returnType := setTy sid
  body := some (.returnValue (some (.structValue sid [.call g.tryReserve [setItems, .local 1]])))

def setTryInsertFn (sc : FunctionId) : Function where
  id := f
  parameters := [(0, setTy sid), (1, T)]
  returnType := setTy sid
  body := some <| guardReturn (.call sc [.local 0, .local 1]) (.local 0)
    (.returnValue (some (.structValue sid [.call g.tryPush [setItems, .local 1]])))

def setTryRemoveFn (indexOf vr : FunctionId) : Function where
  id := f
  parameters := [(0, setTy sid), (1, T)]
  returnType := setTy sid
  body := some <| .letLocal 2 i32Ty (.call indexOf [setItems, .local 1])
    (guardReturn (.binary .less (.local 2) (int 0)) (.local 0)
      (.returnValue (some (.structValue sid [.call vr [setItems, .local 2]]))))

/-- `return Set { items: std::vec::<op>(value.items) };` for `clear`,
`try_shrink_to_fit` and `try_clone`. -/
def setRewrapFn (op : FunctionId) : Function where
  id := f
  parameters := [(0, setTy sid)]
  returnType := setTy sid
  body := some (.returnValue (some (.structValue sid [.call op [setItems]])))

def setDestroyFn : Function where
  id := f
  parameters := [(0, setTy sid)]
  returnType := .unit
  body := some (.expression (.call mo.destroy [setItems]))

end templates

/-! ## Running the wrappers -/

theorem PureRun.retCall {S : State} {op : FunctionId} {args : List Expr} {ws : List Value} {v : Value}
    (argsRun : RunsExprs P S args ws S)
    (call : ∃ after, RunsExpr P S (.call op (ws.map Expr.value)) v after ∧ PureFrame S after) :
    PureRun P S (.returnValue (some (.call op args))) (.returned (some v)) := by
  obtain ⟨after, run, frame⟩ := call
  exact ⟨after, RunsStmt.returnValue (callArgs argsRun run), frame⟩

theorem PureRun.retWrap {S : State} {sid : TypeId} {op : FunctionId} {args : List Expr} {ws : List Value}
    {v : Value} (argsRun : RunsExprs P S args ws S)
    (call : ∃ after, RunsExpr P S (.call op (ws.map Expr.value)) v after ∧ PureFrame S after) :
    PureRun P S (.returnValue (some (.structValue sid [.call op args]))) (.returned (some (.structure sid [v]))) := by
  obtain ⟨after, run, frame⟩ := call
  exact ⟨after, RunsStmt.returnValue (RunsExpr.structValue (RunsExprs.cons (callArgs argsRun run) RunsExprs.nil)),
    frame⟩

theorem Grow.retWrap {S : State} {sid : TypeId} {op : FunctionId} {args : List Expr} {ws : List Value}
    {v : Value} {Q : Heap → Prop} (formed : S.CellsWellFormed) (argsRun : RunsExprs P S args ws S)
    (call : ∃ after, RunsExpr P S (.call op (ws.map Expr.value)) v after ∧ FreshCellFrame S after ∧
      after.world = S.world ∧ after.i32ArrayViews = S.i32ArrayViews ∧ Q after.heap) :
    Grow P S (.returnValue (some (.structValue sid [.call op args]))) (.returned (some (.structure sid [v]))) Q := by
  obtain ⟨after, run, cells, world, views, q⟩ := call
  exact ⟨after, RunsStmt.returnValue (RunsExpr.structValue (RunsExprs.cons (callArgs argsRun run) RunsExprs.nil)),
    ⟨formed, cells, world, views⟩, q⟩

/-- The entry state of a one-parameter set function. -/
theorem set_entry1 {caller : State} (formed : caller.CellsWellFormed) {sid : TypeId} (v : Value) :
    let E := ({ caller with locals := [] } : State).bindLocal 0 (.structure sid [v])
    E.CellsWellFormed ∧ RunsExpr P E setItems v E ∧ E.local? 0 = some (.structure sid [v]) := by
  intro E
  have f0 : ({ caller with locals := [] } : State).CellsWellFormed := formed
  have l0 : E.local? 0 = some (.structure sid [v]) := local_bound f0 0 _
  exact ⟨f0.bindLocal _ _, RunsExpr.field' (j := 0) (RunsExpr.local' l0) rfl, l0⟩

/-- The entry state of a two-parameter set function. -/
theorem set_entry2 {caller : State} (formed : caller.CellsWellFormed) {sid : TypeId} (v x : Value) :
    let E := (({ caller with locals := [] } : State).bindLocal 0 (.structure sid [v])).bindLocal 1 x
    E.CellsWellFormed ∧ RunsExpr P E setItems v E ∧ E.local? 0 = some (.structure sid [v]) ∧
      E.local? 1 = some x := by
  intro E
  have f0 : ({ caller with locals := [] } : State).CellsWellFormed := formed
  have f1 := f0.bindLocal 0 (.structure sid [v])
  have l0 : E.local? 0 = some (.structure sid [v]) := local_kept f1 _ (by decide) (local_bound f0 0 _)
  exact ⟨f1.bindLocal _ _, RunsExpr.field' (j := 0) (RunsExpr.local' l0) rfl, l0, local_bound f1 1 _⟩

/-! ## `std::vec::contains` -/

theorem contains_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {vc indexOf eq : FunctionId}
    (found : P.function? vc = some (vecContainsFn ids T vc indexOf))
    (indexFound : P.function? indexOf = some (indexOfFn ids T indexOf eq))
    {eqv : Value → Value → Bool} {item : Value} {xs : List Value}
    (eqSpec : ∀ S : State, S.CellsWellFormed → ∀ a ∈ xs, ∃ after,
      RunsExpr P S (.call eq ([a, item].map Expr.value)) (.boolean (eqv a item)) after ∧ PureFrame S after)
    {caller : State} (formed : caller.CellsWellFormed) {v : Value}
    (rep : VecRep P T size ids.vec caller.heap v xs) :
    ∃ after, RunsExpr P caller (.call vc ([v, item].map Expr.value)) (.boolean (xs.any (eqv · item))) after ∧
      PureFrame caller after := by
  refine PureRun.call found rfl rfl formed ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 v
  let E := (E0.bindLocal 0 v).bindLocal 1 item
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some item := local_bound f1 1 _
  have l0 : E.local? 0 = some v := local_kept f1 _ (by decide) (local_bound f0 0 _)
  obtain ⟨S', run, frame⟩ := index_of_spec inst kind indexFound eqSpec fE rep
  obtain ⟨after, cmp, frame'⟩ := RunsExpr.binaryPure (operation := .greaterEqual)
    ⟨S', callArgs (RunsExprs.two (RunsExpr.local' l0) (RunsExpr.local' l1)) run, frame⟩
    (fun m fm => ⟨m, RunsExpr.value' (.signed .i32 0), PureFrame.refl fm.afterFormed⟩) (by decide)
    (eval_i32_ge _ _ _)
  rw [findIdx_nonneg] at cmp
  exact ⟨after, RunsStmt.returnValue cmp, frame'⟩

/-! ## Loop-free set functions -/

theorem setNew_spec (inst : VecInstance P T ids) {sid f : FunctionId} {caller : State}
    (found : P.function? f = some (setNewFn ids sid f)) (formed : caller.CellsWellFormed) :
    ∃ after v, RunsExpr P caller (.call f (([] : List Value).map Expr.value)) (.structure sid [v]) after ∧
      PureFrame caller after ∧ ∀ h, VecRep P T size ids.vec h v [] := by
  let E : State := { caller with locals := [] }
  have fE : E.CellsWellFormed := formed
  obtain ⟨S', v, run, frame, rep⟩ := new_spec (size := size) inst fE
  have fS := frame.afterFormed
  obtain ⟨after, call, pure⟩ := PureRun.call (v := .structure sid [v]) (vs := []) (bindings := []) found rfl rfl formed
    (PureRun.letRun (callArgs RunsExprs.nil run) frame
      (PureRun.ret (fS.bindLocal 0 v) (RunsExpr.structValue (RunsExprs.cons
        (RunsExpr.local' (local_bound fS 0 v)) RunsExprs.nil))))
  exact ⟨after, v, call, pure, rep⟩

theorem setLen_spec (inst : VecInstance P T ids) {sid : TypeId} {f : FunctionId}
    (found : P.function? f = some (setForwardFn sid f ids.len i32Ty)) {caller : State}
    (formed : caller.CellsWellFormed) {v : Value} {xs : List Value}
    (rep : VecRep P T size ids.vec caller.heap v xs) :
    ∃ after, RunsExpr P caller (.call f ([Value.structure sid [v]].map Expr.value)) (.signed .i32 xs.length) after ∧
      PureFrame caller after := by
  refine PureRun.call found rfl rfl formed ?_
  obtain ⟨fE, items, _⟩ := set_entry1 (P := P) formed (sid := sid) v
  exact PureRun.retCall (RunsExprs.one items) (len_spec inst fE rep)

theorem setCapacity_spec (inst : VecInstance P T ids) {sid : TypeId} {f : FunctionId}
    (found : P.function? f = some (setForwardFn sid f ids.capacity i32Ty)) {caller : State}
    (formed : caller.CellsWellFormed) {v : Value} {xs : List Value}
    (rep : VecRep P T size ids.vec caller.heap v xs) :
    ∃ (after : State) (cap : Nat), RunsExpr P caller (.call f ([Value.structure sid [v]].map Expr.value))
      (.signed .i32 cap) after ∧ PureFrame caller after ∧ xs.length ≤ cap := by
  obtain ⟨fE, items, _⟩ := set_entry1 (P := P) formed (sid := sid) v
  obtain ⟨S', cap, run, frame, le⟩ := capacity_spec inst fE rep
  obtain ⟨after, call, pure⟩ := PureRun.call (vs := [.structure sid [v]]) (bindings := [(0, .structure sid [v])]) found rfl rfl formed
    (PureRun.retCall (RunsExprs.one items) ⟨S', run, frame⟩)
  exact ⟨after, cap, call, pure, le⟩

theorem setIsEmpty_spec (inst : VecInstance P T ids) {sid : TypeId} {f : FunctionId}
    (found : P.function? f = some (setForwardFn sid f ids.isEmpty boolTy)) {caller : State}
    (formed : caller.CellsWellFormed) {v : Value} {xs : List Value}
    (rep : VecRep P T size ids.vec caller.heap v xs) :
    ∃ after, RunsExpr P caller (.call f ([Value.structure sid [v]].map Expr.value)) (.boolean xs.isEmpty) after ∧
      PureFrame caller after := by
  refine PureRun.call found rfl rfl formed ?_
  obtain ⟨fE, items, _⟩ := set_entry1 (P := P) formed (sid := sid) v
  exact PureRun.retCall (RunsExprs.one items) (isEmpty_spec inst fE rep)

theorem setContains_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {sid : TypeId}
    {f vc indexOf eq : FunctionId} (found : P.function? f = some (setContainsFn T sid f vc))
    (vcFound : P.function? vc = some (vecContainsFn ids T vc indexOf))
    (indexFound : P.function? indexOf = some (indexOfFn ids T indexOf eq))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {v item : Value} {xs : List Value}
    (rep : VecRep P T size ids.vec caller.heap v xs) (itemIn : item ∈ vals) (sub : ∀ z ∈ xs, z ∈ vals) :
    ∃ after, RunsExpr P caller (.call f ([Value.structure sid [v], item].map Expr.value))
      (.boolean (xs.any (eqv · item))) after ∧ PureFrame caller after := by
  refine PureRun.call found rfl rfl formed ?_
  obtain ⟨fE, items, _, l1⟩ := set_entry2 (P := P) formed (sid := sid) v item
  exact PureRun.retCall (RunsExprs.two items (RunsExpr.local' l1))
    (contains_spec inst kind vcFound indexFound (eqSpec.against itemIn sub) fE rep)

theorem setAtOr_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {sid : TypeId} {f : FunctionId}
    (found : P.function? f = some (setAtOrFn ids T sid f)) {caller : State}
    (formed : caller.CellsWellFormed) {v : Value} {xs : List Value}
    (rep : VecRep P T size ids.vec caller.heap v xs) (ordinal : Int) (fallback : Value) :
    ∃ after, RunsExpr P caller (.call f ([Value.structure sid [v], .signed .i32 ordinal, fallback].map Expr.value))
      (if 0 ≤ ordinal then (xs[ordinal.toNat]?).getD fallback else fallback) after ∧ PureFrame caller after := by
  refine PureRun.call found rfl rfl formed ?_
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 (.structure sid [v])
  have f2 := f1.bindLocal 1 (.signed .i32 ordinal)
  let E := ((E0.bindLocal 0 (.structure sid [v])).bindLocal 1 (.signed .i32 ordinal)).bindLocal 2 fallback
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f2.bindLocal _ _
  have l2 : E.local? 2 = some fallback := local_bound f2 2 _
  have l1 : E.local? 1 = some (.signed .i32 ordinal) := local_kept f2 _ (by decide) (local_bound f1 1 _)
  have l0 : E.local? 0 = some (.structure sid [v]) :=
    local_kept f2 _ (by decide) (local_kept f1 _ (by decide) (local_bound f0 0 _))
  exact PureRun.retCall (RunsExprs.three (RunsExpr.field' (j := 0) (RunsExpr.local' l0) rfl) (RunsExpr.local' l1)
    (RunsExpr.local' l2)) (getOr_spec inst kind fE rep ordinal fallback)

theorem setClear_spec (inst : VecInstance P T ids) {sid : TypeId} {f : FunctionId}
    (found : P.function? f = some (setRewrapFn sid f ids.clear)) {caller : State}
    (formed : caller.CellsWellFormed) {v : Value} {xs : List Value}
    (rep : VecRep P T size ids.vec caller.heap v xs) :
    ∃ after v', RunsExpr P caller (.call f ([Value.structure sid [v]].map Expr.value)) (.structure sid [v']) after ∧
      PureFrame caller after ∧ VecRep P T size ids.vec caller.heap v' [] := by
  obtain ⟨fE, items, _⟩ := set_entry1 (P := P) formed (sid := sid) v
  obtain ⟨S', v', run, frame, rep'⟩ := clear_spec inst fE rep
  obtain ⟨after, call, pure⟩ := PureRun.call (vs := [.structure sid [v]]) (bindings := [(0, .structure sid [v])]) found rfl rfl formed
    (PureRun.retWrap (RunsExprs.one items) ⟨S', run, frame⟩)
  exact ⟨after, v', call, pure, rep'⟩

/-- `try_reserve` when the capacity already suffices. -/
theorem setTryReserve_skip_spec (inst : GrowInstance P T ids g) {sid : TypeId} {f : FunctionId}
    (found : P.function? f = some (setTryReserveFn g sid f)) {caller : State}
    (formed : caller.CellsWellFormed) {ptr len : Value} {cap min : Int} (enough : min ≤ cap) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure sid [.structure ids.vec [ptr, len, .signed .i32 cap]], .signed .i32 min].map Expr.value))
      (.structure sid [.structure ids.vec [ptr, len, .signed .i32 cap]]) after ∧ PureFrame caller after := by
  refine PureRun.call found rfl rfl formed ?_
  obtain ⟨fE, items, _, l1⟩ := set_entry2 (P := P) formed (sid := sid)
    (.structure ids.vec [ptr, len, .signed .i32 cap]) (.signed .i32 min)
  exact PureRun.retWrap (RunsExprs.two items (RunsExpr.local' l1)) (tryReserve_skip_spec inst fE enough)

/-- `try_reserve` that grows: as `std::vec::try_reserve`. -/
theorem setTryReserve_grow_spec (inst : GrowInstance P T ids g) (kind : ElemKind P T size) {sid : TypeId}
    {f : FunctionId} (found : P.function? f = some (setTryReserveFn g sid f))
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap min : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (grows : cap < min) (fits : size * min ≤ 2147483647)
    {budget : Option Nat} (available : consumeBudget caller.heap.remaining (size * min) = some budget)
    (room : caller.heap.allocationAddress 8 + size * min < 2 ^ 64)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) (stores : ∀ x ∈ xs, ElemStore P T size x) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure sid [.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]],
          .signed .i32 min].map Expr.value))
      (.structure sid [.structure ids.vec [.pointer (caller.heap.allocationAddress 8), .signed .i32 xs.length,
        .signed .i32 min]]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧ after.i32ArrayViews = caller.i32ArrayViews ∧
      Grown P T size ids.vec caller.heap p (size * cap) (caller.heap.allocationAddress 8) min xs after.heap := by
  refine Grow.call (Q := fun H => Grown P T size ids.vec caller.heap p (size * cap)
    (caller.heap.allocationAddress 8) min xs H) found rfl rfl ?_
  obtain ⟨fE, items, _, l1⟩ := set_entry2 (P := P) formed (sid := sid)
    (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) (.signed .i32 min)
  exact Grow.retWrap fE (RunsExprs.two items (RunsExpr.local' l1))
    (tryReserve_grow_spec inst kind fE rep grows fits available room below unique noViews stores)

/-- `try_insert(s, x)` with `x` already in the set returns `s`. -/
theorem setTryInsert_present_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {sid : TypeId}
    {f sc vc indexOf eq : FunctionId} (found : P.function? f = some (setTryInsertFn g T sid f sc))
    (scFound : P.function? sc = some (setContainsFn T sid sc vc))
    (vcFound : P.function? vc = some (vecContainsFn ids T vc indexOf))
    (indexFound : P.function? indexOf = some (indexOfFn ids T indexOf eq))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {v x : Value} {xs : List Value}
    (rep : VecRep P T size ids.vec caller.heap v xs) (itemIn : x ∈ vals) (sub : ∀ z ∈ xs, z ∈ vals)
    (present : xs.any (eqv · x) = true) :
    ∃ after, RunsExpr P caller (.call f ([Value.structure sid [v], x].map Expr.value))
      (.structure sid [v]) after ∧ PureFrame caller after := by
  refine PureRun.call found rfl rfl formed ?_
  obtain ⟨fE, _, l0, l1⟩ := set_entry2 (P := P) formed (sid := sid) v x
  obtain ⟨S', run, frame⟩ := setContains_spec inst kind scFound vcFound indexFound eqSpec fE rep itemIn sub
  rw [present] at run
  exact PureRun.guardTakenAfter (callArgs (RunsExprs.two (RunsExpr.local' l0) (RunsExpr.local' l1)) run) frame
    (PureRun.ret frame.afterFormed (RunsExpr.local' (frame.localFound l0))) nofun

/-- `try_insert(s, x)` with `x` not in the set: `try_push` of `x`; the
result is still distinct. -/
theorem setTryInsert_absent_spec (inst : GrowInstance P T ids g) (kind : ElemKind P T size) {sid : TypeId}
    {f sc vc indexOf eq : FunctionId} (found : P.function? f = some (setTryInsertFn g T sid f sc))
    (scFound : P.function? sc = some (setContainsFn T sid sc vc))
    (vcFound : P.function? vc = some (vecContainsFn ids T vc indexOf))
    (indexFound : P.function? indexOf = some (indexOfFn ids T indexOf eq))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat} {x : Value}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (itemIn : x ∈ vals) (sub : ∀ z ∈ xs, z ∈ vals) (absent : xs.any (eqv · x) = false)
    (distinct : Distinct eqv xs)
    (fits : size * (xs.length + 1) ≤ 2147483647)
    (growth : xs.length = cap →
      (∃ budget, consumeBudget caller.heap.remaining (size * pushTarget size cap) = some budget) ∧
        caller.heap.allocationAddress 8 + size * pushTarget size cap < 2 ^ 64)
    (store : ElemStore P T size x) (stores : ∀ y ∈ xs, ElemStore P T size y)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) :
    ∃ (after : State) (q m : Nat), RunsExpr P caller (.call f
        ([Value.structure sid [.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]], x].map
          Expr.value))
      (.structure sid [.structure ids.vec [.pointer q, .signed .i32 (xs ++ [x]).length, .signed .i32 m]]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧
      Pushed P T size ids.vec caller.heap p cap q m (xs ++ [x]) after.heap ∧ Distinct eqv (xs ++ [x]) := by
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  obtain ⟨fE, _, l0, l1⟩ := set_entry2 (P := P) formed (sid := sid) vv x
  obtain ⟨S', run, frame⟩ := setContains_spec inst.vec kind scFound vcFound indexFound eqSpec fE rep itemIn sub
  rw [absent] at run
  have fS := frame.afterFormed
  have hS : S'.heap = caller.heap := frame.heap
  have items' : RunsExpr P S' setItems vv S' := RunsExpr.field' (j := 0) (RunsExpr.local' (frame.localFound l0)) rfl
  obtain ⟨after, q, m, pushRun, cells, world, views, pushed⟩ := tryPush_spec inst kind (caller := S') fS
    (by rw [hS]; exact rep) fits (by rw [hS]; exact growth) store stores (by rw [hS]; exact below)
    (by rw [hS]; exact unique) (frame.views.trans noViews)
  rw [hS] at pushed
  obtain ⟨final, call, cellsF, worldF, viewsF, pushedF⟩ := Grow.call (vs := [.structure sid [vv], x]) (bindings := [(0, .structure sid [vv]), (1, x)])
    (Q := fun H => Pushed P T size ids.vec caller.heap p cap q m (xs ++ [x]) H) found rfl rfl
    (Grow.guardSkip (callArgs (RunsExprs.two (RunsExpr.local' l0) (RunsExpr.local' l1)) run) (Ext.ofPure frame)
      (Grow.retWrap fS (RunsExprs.two items' (RunsExpr.local' (frame.localFound l1)))
        ⟨after, pushRun, cells, world, views, pushed⟩))
  exact ⟨final, q, m, call, cellsF, worldF, viewsF, pushedF, distinct.append_absent absent⟩

/-- `try_remove(s, x)` with no item equal to `x` returns `s`. -/
theorem setTryRemove_absent_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {sid : TypeId}
    {f indexOf eq vr : FunctionId} (found : P.function? f = some (setTryRemoveFn T sid f indexOf vr))
    (indexFound : P.function? indexOf = some (indexOfFn ids T indexOf eq))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {v x : Value} {xs : List Value}
    (rep : VecRep P T size ids.vec caller.heap v xs) (itemIn : x ∈ vals) (sub : ∀ z ∈ xs, z ∈ vals)
    (absent : xs.any (eqv · x) = false) :
    ∃ after, RunsExpr P caller (.call f ([Value.structure sid [v], x].map Expr.value))
      (.structure sid [v]) after ∧ PureFrame caller after := by
  refine PureRun.call found rfl rfl formed ?_
  obtain ⟨fE, items, l0, l1⟩ := set_entry2 (P := P) formed (sid := sid) v x
  obtain ⟨S', run, frame⟩ := index_of_spec inst kind indexFound (eqSpec.against itemIn sub) fE rep
  have missing : xs.findIdx? (eqv · x) = none := by
    rw [List.findIdx?_eq_none_iff]
    exact fun y m => by simpa using List.any_eq_false.mp absent y m
  rw [missing] at run
  have fS := frame.afterFormed
  refine PureRun.letRun (callArgs (RunsExprs.two items (RunsExpr.local' l1)) run) frame ?_
  have b2 := local_bound fS 2 (.signed .i32 ((Option.none.map Int.ofNat).getD (-1) : Int))
  have b0 := local_kept fS (.signed .i32 ((Option.none.map Int.ofNat).getD (-1) : Int)) (show (2 : VarId) ≠ 0 by decide)
    (frame.localFound l0)
  exact PureRun.guardTaken (RunsExpr.binary (RunsExpr.local' b2) (RunsExpr.value' _) (by decide)
    (by rw [eval_i32_lt]; rfl)) (PureRun.ret (fS.bindLocal _ _) (RunsExpr.local' b0)) nofun

/-- `try_remove(s, x)` with `x` first matching at `i`: `std::vec::try_remove`
at `i`; the result is still distinct. -/
theorem setTryRemove_found_spec (inst : VecInstance P T ids) (kind : ElemKind P T size) {sid : TypeId}
    {f indexOf eq vr : FunctionId} (found : P.function? f = some (setTryRemoveFn T sid f indexOf vr))
    (indexFound : P.function? indexOf = some (indexOfFn ids T indexOf eq))
    (vrFound : P.function? vr = some (tryRemoveFn (T := T) ids vr))
    {eqv : Value → Value → Bool} {vals : List Value} (eqSpec : EqSpec P eq eqv vals)
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat} {x : Value}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (itemIn : x ∈ vals) (sub : ∀ z ∈ xs, z ∈ vals) {i : Nat} (at_ : xs.findIdx? (eqv · x) = some i)
    (distinct : Distinct eqv xs) (stores : ∀ y ∈ xs, ElemStore P T size y)
    (noViews : caller.i32ArrayViews = []) (unique : HeapBlockBasesUnique caller.heap) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure sid [.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]], x].map
          Expr.value))
      (.structure sid [.structure ids.vec [.pointer p, .signed .i32 (xs.eraseIdx i).length, .signed .i32 cap]])
        after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧ after.i32ArrayViews = caller.i32ArrayViews ∧
      VecRep P T size ids.vec after.heap
        (.structure ids.vec [.pointer p, .signed .i32 (xs.eraseIdx i).length, .signed .i32 cap]) (xs.eraseIdx i) ∧
      HeapRegionWrite caller.heap after.heap p (size * cap) ∧ Distinct eqv (xs.eraseIdx i) := by
  let vv := Value.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]
  have inside : i < xs.length := (List.findIdx?_eq_some_iff_findIdx_eq.mp at_).1
  obtain ⟨fE, items, l0, l1⟩ := set_entry2 (P := P) formed (sid := sid) vv x
  obtain ⟨S', run, frame⟩ := index_of_spec inst kind indexFound (eqSpec.against itemIn sub) fE rep
  rw [at_] at run
  have fS := frame.afterFormed
  have hS : S'.heap = caller.heap := frame.heap
  let B := S'.bindLocal 2 (.signed .i32 (((some i).map Int.ofNat).getD (-1)))
  have fB : B.CellsWellFormed := fS.bindLocal _ _
  have b2 : B.local? 2 = some (.signed .i32 (i : Int)) := local_bound fS 2 _
  have b0 : B.local? 0 = some (.structure sid [vv]) := local_kept fS _ (by decide) (frame.localFound l0)
  have cond : RunsExpr P B (.binary .less (.local 2) (int 0)) (.boolean false) B :=
    RunsExpr.binary (RunsExpr.local' b2) (RunsExpr.value' _) (by decide)
      (by rw [eval_i32_lt]; simp)
  obtain ⟨after, rmRun, cells, world, views, rep', write⟩ := tryRemove_spec inst kind vrFound (caller := B) fB
    (by rw [show B.heap = caller.heap from hS]; exact rep) inside stores (frame.views.trans noViews)
    (by rw [show B.heap = caller.heap from hS]; exact unique)
  rw [show B.heap = caller.heap from hS] at write
  obtain ⟨final, call, cellsF, worldF, viewsF, repF, writeF⟩ := Grow.call (vs := [.structure sid [vv], x]) (bindings := [(0, .structure sid [vv]), (1, x)])
    (Q := fun H => VecRep P T size ids.vec H
        (.structure ids.vec [.pointer p, .signed .i32 (xs.eraseIdx i).length, .signed .i32 cap]) (xs.eraseIdx i) ∧
      HeapRegionWrite caller.heap H p (size * cap)) found rfl rfl
    (Grow.letRun (callArgs (RunsExprs.two items (RunsExpr.local' l1)) run) (Ext.ofPure frame)
      (Grow.guardSkip cond (Ext.refl fB)
        (Grow.retWrap fB (RunsExprs.two (RunsExpr.field' (j := 0) (RunsExpr.local' b0) rfl) (RunsExpr.local' b2))
          ⟨after, rmRun, cells, world, views, rep', write⟩)))
  exact ⟨final, call, cellsF, worldF, viewsF, repF, writeF, distinct.eraseIdx i⟩

/-- `try_shrink_to_fit` with spare capacity: the items move to storage of
exactly their length. -/
theorem setTryShrinkToFit_spec (inst : GrowInstance P T ids g) (kind : ElemKind P T size) {sid : TypeId}
    {f vs : FunctionId} (found : P.function? f = some (setRewrapFn sid f vs))
    (vsFound : P.function? vs = some (tryShrinkToFitFn ids g mo T vs))
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (nonempty : 0 < xs.length) (spare : xs.length < cap)
    {budget : Option Nat} (available : consumeBudget caller.heap.remaining (size * xs.length) = some budget)
    (room : caller.heap.allocationAddress 8 + size * xs.length < 2 ^ 64)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) (stores : ∀ x ∈ xs, ElemStore P T size x) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure sid [.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]]].map
          Expr.value))
      (.structure sid [.structure ids.vec [.pointer (caller.heap.allocationAddress 8), .signed .i32 xs.length,
        .signed .i32 xs.length]]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧ after.i32ArrayViews = caller.i32ArrayViews ∧
      Grown P T size ids.vec caller.heap p (size * cap) (caller.heap.allocationAddress 8) xs.length xs
        after.heap := by
  refine Grow.call (Q := fun H => Grown P T size ids.vec caller.heap p (size * cap)
    (caller.heap.allocationAddress 8) xs.length xs H) found rfl rfl ?_
  obtain ⟨fE, items, _⟩ := set_entry1 (P := P) formed (sid := sid)
    (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap])
  exact Grow.retWrap fE (RunsExprs.one items)
    (tryShrinkToFit_spec inst kind vsFound fE rep nonempty spare available room below unique noViews stores)

/-- `try_shrink_to_fit` with no spare capacity returns the set. -/
theorem setTryShrinkToFit_same_spec (inst : GrowInstance P T ids g) (kind : ElemKind P T size) {sid : TypeId}
    {f vs : FunctionId} (found : P.function? f = some (setRewrapFn sid f vs))
    (vsFound : P.function? vs = some (tryShrinkToFitFn ids g mo T vs))
    {caller : State} (formed : caller.CellsWellFormed) {ptr : Value} {len : Int} :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure sid [.structure ids.vec [ptr, .signed .i32 len, .signed .i32 len]]].map Expr.value))
      (.structure sid [.structure ids.vec [ptr, .signed .i32 len, .signed .i32 len]]) after ∧
      PureFrame caller after := by
  refine PureRun.call found rfl rfl formed ?_
  obtain ⟨fE, items, _⟩ := set_entry1 (P := P) formed (sid := sid)
    (.structure ids.vec [ptr, .signed .i32 len, .signed .i32 len])
  exact PureRun.retWrap (RunsExprs.one items) (tryShrinkToFit_same_spec inst kind vsFound fE)

/-- `try_shrink_to_fit` of an empty set with storage frees it. -/
theorem setTryShrinkToFit_empty_spec (inst : MoreInstance P T ids g mo) (kind : ElemKind P T size)
    {sid : TypeId} {f vs : FunctionId} (found : P.function? f = some (setRewrapFn sid f vs))
    (vsFound : P.function? vs = some (tryShrinkToFitFn ids g mo T vs))
    {caller : State} (formed : caller.CellsWellFormed) {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 0, .signed .i32 cap]) [])
    (capPos : 0 < cap) (unique : HeapBlockBasesUnique caller.heap) (noViews : caller.i32ArrayViews = []) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure sid [.structure ids.vec [.pointer p, .signed .i32 0, .signed .i32 cap]]].map Expr.value))
      (.structure sid [.structure ids.vec [.pointer 0, .signed .i32 0, .signed .i32 0]]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧ Freed caller.heap after.heap p (size * cap) := by
  refine Grow.call (Q := fun H => Freed caller.heap H p (size * cap)) found rfl rfl ?_
  obtain ⟨fE, items, _⟩ := set_entry1 (P := P) formed (sid := sid)
    (.structure ids.vec [.pointer p, .signed .i32 0, .signed .i32 cap])
  exact Grow.retWrap fE (RunsExprs.one items)
    (tryShrinkToFit_empty_spec inst kind vsFound fE rep capPos unique noViews)

/-- `try_clone` of a nonempty set: fresh storage with the same items. -/
theorem setTryClone_spec (inst : MoreInstance P T ids g mo) (kind : ElemKind P T size) {sid : TypeId}
    {f : FunctionId} (found : P.function? f = some (setRewrapFn sid f mo.tryClone))
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (nonempty : 0 < xs.length) (fits : size * xs.length ≤ 2147483647)
    {budget : Option Nat} (available : consumeBudget caller.heap.remaining (size * xs.length) = some budget)
    (room : caller.heap.allocationAddress 8 + size * xs.length < 2 ^ 64)
    (below : HeapBlocksBelowNext caller.heap) (unique : HeapBlockBasesUnique caller.heap)
    (noViews : caller.i32ArrayViews = []) (stores : ∀ x ∈ xs, ElemStore P T size x) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure sid [.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]]].map
          Expr.value))
      (.structure sid [.structure ids.vec [.pointer (caller.heap.allocationAddress 8), .signed .i32 xs.length,
        .signed .i32 xs.length]]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧ after.i32ArrayViews = caller.i32ArrayViews ∧
      Grown P T size ids.vec caller.heap 0 0 (caller.heap.allocationAddress 8) xs.length xs after.heap := by
  refine Grow.call (Q := fun H => Grown P T size ids.vec caller.heap 0 0
    (caller.heap.allocationAddress 8) xs.length xs H) found rfl rfl ?_
  obtain ⟨fE, items, _⟩ := set_entry1 (P := P) formed (sid := sid)
    (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap])
  exact Grow.retWrap fE (RunsExprs.one items)
    (tryClone_spec inst kind fE rep nonempty fits available room below unique noViews stores)

/-- `try_clone` of an empty set allocates nothing. -/
theorem setTryClone_empty_spec (inst : MoreInstance P T ids g mo) (kind : ElemKind P T size) {sid : TypeId}
    {f : FunctionId} (found : P.function? f = some (setRewrapFn sid f mo.tryClone))
    {caller : State} (formed : caller.CellsWellFormed) {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 0, .signed .i32 cap]) [])
    (unique : HeapBlockBasesUnique caller.heap) (noViews : caller.i32ArrayViews = []) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure sid [.structure ids.vec [.pointer p, .signed .i32 0, .signed .i32 cap]]].map Expr.value))
      (.structure sid [.structure ids.vec [.pointer 0, .signed .i32 0, .signed .i32 0]]) after ∧
      FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧ HeapRegionWrite caller.heap after.heap 0 0 := by
  refine Grow.call (Q := fun H => HeapRegionWrite caller.heap H 0 0) found rfl rfl ?_
  obtain ⟨fE, items, _⟩ := set_entry1 (P := P) formed (sid := sid)
    (.structure ids.vec [.pointer p, .signed .i32 0, .signed .i32 cap])
  exact Grow.retWrap fE (RunsExprs.one items) (tryClone_empty_spec inst kind fE rep unique noViews)

theorem setDestroy_spec (inst : MoreInstance P T ids g mo) (kind : ElemKind P T size) {sid : TypeId}
    {f : FunctionId} (found : P.function? f = some (setDestroyFn mo sid f))
    {caller : State} (formed : caller.CellsWellFormed) {xs : List Value} {p cap : Nat}
    (rep : VecRep P T size ids.vec caller.heap
      (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]) xs)
    (unique : HeapBlockBasesUnique caller.heap) (noViews : caller.i32ArrayViews = []) :
    ∃ after, RunsExpr P caller (.call f
        ([Value.structure sid [.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap]]].map
          Expr.value))
      .unit after ∧ FreshCellFrame caller after ∧ after.world = caller.world ∧
      after.i32ArrayViews = caller.i32ArrayViews ∧ Freed caller.heap after.heap p (size * cap) := by
  refine Grow.callUnit (Q := fun H => Freed caller.heap H p (size * cap)) found rfl rfl rfl ?_
  obtain ⟨fE, items, _⟩ := set_entry1 (P := P) formed (sid := sid)
    (.structure ids.vec [.pointer p, .signed .i32 xs.length, .signed .i32 cap])
  obtain ⟨after, run, cells, world, views, freed⟩ := destroy_spec inst kind fE rep unique noViews
  exact ⟨after, RunsStmt.expression (callArgs (RunsExprs.one items) run), ⟨fE, cells, world, views⟩, freed⟩

#print axioms contains_spec
#print axioms setNew_spec
#print axioms setLen_spec
#print axioms setCapacity_spec
#print axioms setIsEmpty_spec
#print axioms setContains_spec
#print axioms setAtOr_spec
#print axioms setClear_spec
#print axioms setTryReserve_skip_spec
#print axioms setTryReserve_grow_spec
#print axioms setTryInsert_present_spec
#print axioms setTryInsert_absent_spec
#print axioms setTryRemove_absent_spec
#print axioms setTryRemove_found_spec
#print axioms setTryShrinkToFit_spec
#print axioms setTryShrinkToFit_same_spec
#print axioms setTryShrinkToFit_empty_spec
#print axioms setTryClone_spec
#print axioms setTryClone_empty_spec
#print axioms setDestroy_spec

end Lanius.Std
