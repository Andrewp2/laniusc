module

public import Lanius.Mini.ShapeState
public import Lanius.Mini.ShapeHost

@[expose] public section

/-! # The fragment without raw memory, and what each evaluator promises
(review finding 2, step 4a)

`ExprFrag`, `PlaceFrag`, `StmtFrag`: the Core syntax the verified compiler's
programs without raw memory use — values, locals, casts, operators, arrays,
structs and their fields, enums and matches, assignment to a local or a
field of one, calls, `assert` and `print_i32`; and the structured statements
without `for`. A program is `ProgOk` when it is well typed and each of its
functions is either a body in the fragment or one of the host services the
compiler lowers.

`EOk`, `EsOk`, `PlOk`, `SOk`: what an evaluator's outcome promises on a typed
state — a value of the expression's shape (statements: a completion its
context allows), on a state typed by a larger store typing with the same
locals, or a trap other than `typeMismatch`. The helper lemmas here (field
paths, writes through them, binding a list of locals) feed the induction on
fuel in `ShapeStep`. -/

namespace Lanius.Mini.NoMismatch

open Lanius.Core (Value Ty Expr Place Stmt Pattern)
open Lanius.Semantics (State Cell Outcome Completion ResolvedPlace)
open Lanius.Typing

/-! ## The fragment -/

def IntrinsicFrag : Core.Intrinsic → Bool
  | .printI32 => true
  | .assert => true
  | .sliceStride => false
  | .sliceLength => false

mutual
  def ExprFrag (e : Expr) : Bool :=
    match e with
    | .value _ => true
    | .local _ => true
    | .cast _ a => ExprFrag a
    | .unary _ a => ExprFrag a
    | .binary _ a b => ExprFrag a && ExprFrag b
    | .array _ es => ExprsFrag es
    | .arrayToSlice _ _ => false
    | .index _ _ => false
    | .structValue _ es => ExprsFrag es
    | .field a _ => ExprFrag a
    | .enumValue _ _ es => ExprsFrag es
    | .matchValue a arms => ExprFrag a && ArmsFrag arms
    | .assign _ p a => PlaceFrag p && ExprFrag a
    | .borrow _ _ => false
    | .dereference _ => false
    | .constant _ => false
    | .call _ es => ExprsFrag es
    | .intrinsic op a => IntrinsicFrag op && ExprFrag a
    | .i32ArrayDataPtr _ => false
    | .i32SliceFromRawParts _ _ => false
    | .typedSliceFromRawParts _ _ _ => false
    | .i32SliceDataPtr _ => false
    | .stringDataPtr _ => false
    | .alloc _ _ => false
    | .realloc _ _ _ _ => false
    | .dealloc _ _ _ => false
    | .loadByte _ _ => false
    | .storeByte _ _ _ => false
  termination_by structural e

  def PlaceFrag (p : Place) : Bool :=
    match p with
    | .local _ => true
    | .field b _ => PlaceFrag b
    | .index _ _ => false
    | .deref _ => false
  termination_by structural p

  def ExprsFrag (es : List Expr) : Bool :=
    match es with
    | [] => true
    | e :: rest => ExprFrag e && ExprsFrag rest
  termination_by structural es

  def ArmsFrag (arms : List (Pattern × Expr)) : Bool :=
    match arms with
    | [] => true
    | (_, e) :: rest => ExprFrag e && ArmsFrag rest
  termination_by structural arms
end

def StmtFrag : Stmt → Bool
  | .skip => true
  | .expression e => ExprFrag e
  | .sequence a b => StmtFrag a && StmtFrag b
  | .letLocal _ _ e body => ExprFrag e && StmtFrag body
  | .letUninitialized _ _ body => StmtFrag body
  | .ifThenElse c a b => ExprFrag c && StmtFrag a && StmtFrag b
  | .whileLoop c body => ExprFrag c && StmtFrag body
  | .forValues _ _ _ => false
  | .forRange _ _ _ _ _ => false
  | .returnValue none => true
  | .returnValue (some e) => ExprFrag e
  | .breakLoop => true
  | .continueLoop => true

/-- A function of the fragment: a body in it, or a lowered host service. -/
def FunctionFrag (f : Core.Function) : Prop :=
  (∃ body, f.body = some body ∧ StmtFrag body = true) ∨
    (f.body = none ∧ ∃ s, f.external = some (.host s) ∧ LoweredService s)

/-- A well-typed program whose functions are all in the fragment. -/
def ProgOk (P : Core.Program) : Prop :=
  ProgramWellTyped P ∧ ∀ f ∈ P.functions, FunctionFrag f

/-! ## What the evaluators promise -/

def EOk (P : Core.Program) (S : CellTypes) (st : State) (t : Ty) : Outcome Value → Prop
  | .done v st' => ∃ S', S.Le S' ∧ CellsOk P S' st' ∧ st'.locals = st.locals ∧ Shape P v t
  | .trapped r _ => r ≠ .typeMismatch
  | .exited _ _ => True
  | .outOfFuel => True

def EsOk (P : Core.Program) (S : CellTypes) (st : State) (ts : List Ty) : Outcome (List Value) → Prop
  | .done vs st' => ∃ S', S.Le S' ∧ CellsOk P S' st' ∧ st'.locals = st.locals ∧ Shapes P vs ts
  | .trapped r _ => r ≠ .typeMismatch
  | .exited _ _ => True
  | .outOfFuel => True

/-- A path of field projections from a value of type `T0` to one of type `t`. -/
inductive ProjTy (P : Core.Program) : Ty → List Core.ValueProjection → Ty → Prop where
  | nil : ProjTy P t [] t
  | field {id : Nat} {d : Core.StructDecl} {i : Nat} {u t : Ty} {ps : List Core.ValueProjection}
      (found : P.structure? id = some d) (fieldFound : d.fields[i]? = some u) (rest : ProjTy P u ps t) :
      ProjTy P (.structure id) (.field i :: ps) t

def PlOk (P : Core.Program) (S : CellTypes) (st : State) (t : Ty) : Outcome ResolvedPlace → Prop
  | .done rp st' => st' = st ∧ rp.raw = none ∧
      (∃ T0, S rp.root = some T0 ∧ ProjTy P T0 rp.projections t) ∧ ∀ v, rp.value = some v → Shape P v t
  | .trapped r _ => r ≠ .typeMismatch
  | .exited _ _ => True
  | .outOfFuel => True

/-- A completion a statement typed for `ret` and `inLoop` may give. -/
def CompOk (P : Core.Program) (ret : Ty) (inLoop : Bool) : Completion → Prop
  | .next => True
  | .returned none => True
  | .returned (some v) => Shape P v ret
  | .breakLoop => inLoop = true
  | .continueLoop => inLoop = true

def SOk (P : Core.Program) (S : CellTypes) (st : State) (ret : Ty) (inLoop : Bool) : Outcome Completion → Prop
  | .done c st' => ∃ S', S.Le S' ∧ CellsOk P S' st' ∧ st'.locals = st.locals ∧ CompOk P ret inLoop c
  | .trapped r _ => r ≠ .typeMismatch
  | .exited _ _ => True
  | .outOfFuel => True

/-! ## Weakening and restoring locals -/

theorem EOk.weaken {P : Core.Program} {S S' : CellTypes} {st st' : State} {t : Ty} {o : Outcome Value}
    (le : S.Le S') (same : st'.locals = st.locals) (h : EOk P S' st' t o) : EOk P S st t o := by
  cases o with
  | done v s =>
    obtain ⟨S'', le', cells, locals, shape⟩ := h
    exact ⟨S'', le.trans le', cells, locals.trans same, shape⟩
  | _ => exact h

theorem EsOk.weaken {P : Core.Program} {S S' : CellTypes} {st st' : State} {ts : List Ty}
    {o : Outcome (List Value)} (le : S.Le S') (same : st'.locals = st.locals) (h : EsOk P S' st' ts o) :
    EsOk P S st ts o := by
  cases o with
  | done v s =>
    obtain ⟨S'', le', cells, locals, shape⟩ := h
    exact ⟨S'', le.trans le', cells, locals.trans same, shape⟩
  | _ => exact h

theorem SOk.weaken {P : Core.Program} {S S' : CellTypes} {st st' : State} {ret : Ty} {inLoop : Bool}
    {o : Outcome Completion} (le : S.Le S') (same : st'.locals = st.locals) (h : SOk P S' st' ret inLoop o) :
    SOk P S st ret inLoop o := by
  cases o with
  | done v s =>
    obtain ⟨S'', le', cells, locals, shape⟩ := h
    exact ⟨S'', le.trans le', cells, locals.trans same, shape⟩
  | _ => exact h

theorem EOk.restore {P : Core.Program} {S S' : CellTypes} {caller st st1 : State} {t : Ty} {o : Outcome Value}
    (le : S.Le S') (same : caller.locals = st.locals) (h : EOk P S' st1 t o) :
    EOk P S st t (Lanius.Semantics.restoreOutcomeLocals caller o) := by
  cases o with
  | done v s =>
    obtain ⟨S'', le', cells, -, shape⟩ := h
    exact ⟨S'', le.trans le', cells.restore, same, shape⟩
  | _ => exact h

theorem SOk.restore {P : Core.Program} {S S' : CellTypes} {caller st st1 : State} {ret : Ty} {inLoop : Bool}
    {o : Outcome Completion} (le : S.Le S') (same : caller.locals = st.locals) (h : SOk P S' st1 ret inLoop o) :
    SOk P S st ret inLoop (Lanius.Semantics.restoreOutcomeLocals caller o) := by
  cases o with
  | done v s =>
    obtain ⟨S'', le', cells, -, shape⟩ := h
    exact ⟨S'', le.trans le', cells.restore, same, shape⟩
  | _ => exact h

/-! ## Declarations, structs and enums -/

theorem structure?_id {P : Core.Program} {id : Nat} {d : Core.StructDecl} (h : P.structure? id = some d) :
    d.id = id := by
  simpa [Core.Program.structure?] using List.find?_some h

theorem enumeration?_id {P : Core.Program} {id : Nat} {d : Core.EnumDecl} (h : P.enumeration? id = some d) :
    d.id = id := by
  simpa [Core.Program.enumeration?] using List.find?_some h

theorem function?_mem {P : Core.Program} {id : Nat} {f : Core.Function} (h : P.function? id = some f) :
    f ∈ P.functions :=
  List.mem_of_find?_eq_some h

theorem Shape.mk_struct {P : Core.Program} {id : Nat} {d : Core.StructDecl} {vs : List Value}
    (found : P.structure? id = some d) (h : Shapes P vs d.fields) : Shape P (.structure id vs) (.structure id) := by
  have eq := structure?_id found
  have := Shape.structure d vs (by rw [eq]; exact found) h.1 h.2
  rwa [eq] at this

theorem Shape.mk_enum {P : Core.Program} {id : Nat} {d : Core.EnumDecl} {variant : Nat} {tys : List Ty}
    {vs : List Value} (found : P.enumeration? id = some d) (variantFound : d.variants[variant]? = some tys)
    (h : Shapes P vs tys) : Shape P (.enumeration id variant vs) (.enumeration id) := by
  have eq := enumeration?_id found
  have := Shape.enumeration d variant tys vs (by rw [eq]; exact found) variantFound h.1 h.2
  rwa [eq] at this

theorem Shape.struct_fields {P : Core.Program} {v : Value} {id : Nat} {d : Core.StructDecl}
    (h : Shape P v (.structure id)) (found : P.structure? id = some d) :
    ∃ vs, v = .structure id vs ∧ Shapes P vs d.fields := by
  cases h with
  | «structure» d' vs found' len each =>
    rw [found] at found'
    cases found'
    exact ⟨vs, rfl, len, each⟩

theorem Shape.bool_inv {P : Core.Program} {v : Value} (h : Shape P v (.scalar .bool)) : ∃ b, v = .boolean b := by
  cases h
  exact ⟨_, rfl⟩

theorem Shapes.replicate {P : Core.Program} {t : Ty} :
    ∀ {vs : List Value} {n : Nat}, Shapes P vs (List.replicate n t) → vs.length = n ∧ ∀ v ∈ vs, Shape P v t
  | [], n, h => by
    refine ⟨?_, fun _ m => by cases m⟩
    have := h.1
    simp at this ⊢
    omega
  | v :: vs, 0, h => by simp [Shapes] at h
  | v :: vs, n + 1, h => by
    rw [List.replicate_succ] at h
    obtain ⟨hv, hvs⟩ := h.cons_inv
    obtain ⟨len, each⟩ := Shapes.replicate hvs
    refine ⟨by simp [len], fun w m => ?_⟩
    rcases List.mem_cons.1 m with rfl | m
    · exact hv
    · exact each w m

/-! ## Field paths and writes through them -/

theorem ProjTy.snoc {P : Core.Program} {T0 : Ty} {ps : List Core.ValueProjection} {id : Nat}
    (h : ProjTy P T0 ps (.structure id)) {d : Core.StructDecl} (found : P.structure? id = some d) {i : Nat}
    {t : Ty} (fieldFound : d.fields[i]? = some t) : ProjTy P T0 (ps ++ [.field i]) t := by
  generalize eq : Ty.structure id = T at h
  induction h with
  | nil => subst eq; exact .field found fieldFound .nil
  | field found' fieldFound' _ ih => exact .field found' fieldFound' (ih eq)

theorem setValue_eq : ∀ (vs : List Value) (i : Nat) (w : Value), Lanius.Semantics.setValue vs i w = vs.set i w
  | [], _, _ => rfl
  | _ :: _, 0, _ => rfl
  | v :: rest, i + 1, w => by
    simp only [Lanius.Semantics.setValue, List.set_cons_succ, setValue_eq rest i w]

theorem replace_ok {P : Core.Program} {T0 t : Ty} {ps : List Core.ValueProjection} (path : ProjTy P T0 ps t) :
    ∀ {root w : Value}, Shape P root T0 → Shape P w t →
      ∃ u, Lanius.Semantics.replaceProjectedValue root ps w = .ok u ∧ Shape P u T0 := by
  induction path with
  | nil => intro root w _ hw; exact ⟨w, rfl, hw⟩
  | @field id d i u t ps found fieldFound _ ih =>
    intro root w hroot hw
    obtain ⟨vs, rfl, fields⟩ := hroot.struct_fields found
    obtain ⟨old, oldFound, oldShape⟩ := fields.get fieldFound
    obtain ⟨upd, updRun, updShape⟩ := ih oldShape hw
    refine ⟨.structure id (vs.set i upd), ?_, Shape.mk_struct found (fields.set fieldFound updShape)⟩
    simp only [Lanius.Semantics.replaceProjectedValue, oldFound, updRun, setValue_eq]

def StOk (P : Core.Program) (S : CellTypes) (st : State) : Except Lanius.Trap State → Prop
  | .ok st' => CellsOk P S st' ∧ st'.locals = st.locals
  | .error r => r ≠ .typeMismatch

theorem assignCell_some {st : State} {c : Nat} {cell : Cell} (h : st.cellEntry? c = some cell) (v : Value) :
    ∃ st', st.assignCell c v = some st' := by
  simp only [State.assignCell, h, Option.isSome_some, if_true]
  exact ⟨_, rfl⟩

theorem write_ok {P : Core.Program} {S : CellTypes} {st : State} {rp : ResolvedPlace} {w : Value} {T0 t : Ty}
    (cells : CellsOk P S st) (root : S rp.root = some T0) (path : ProjTy P T0 rp.projections t)
    (hw : Shape P w t) : StOk P S st (Lanius.Semantics.writeResolvedPlace st rp w) := by
  obtain ⟨cell, found, shaped⟩ := cells.typed _ _ root
  have assign : ∀ {u}, Shape P u T0 → ∀ o, st.assignCell rp.root u = o →
      StOk P S st (match o with | some assigned => .ok assigned | none => .error .typeMismatch) := by
    intro u hu o ho
    obtain ⟨st', h'⟩ := assignCell_some found u
    rw [h'] at ho
    subst ho
    exact ⟨cells.assignCell root hu h', (assignCell_locals h').1⟩
  unfold Lanius.Semantics.writeResolvedPlace
  split
  · rename_i nil
    rw [nil] at path
    cases path
    exact assign hw _ rfl
  · rw [found]
    obtain ⟨id, value⟩ := cell
    cases value with
    | none => simp only [StOk]; decide
    | some rv =>
      obtain ⟨u, run, hu⟩ := replace_ok path (shaped rv rfl) hw
      simp only [run]
      exact assign hu _ rfl

theorem syncTo_nil {st : State} (h : st.i32ArrayViews = []) : Lanius.Semantics.syncI32ViewsToHeap st = .ok st := by
  simp [Lanius.Semantics.syncI32ViewsToHeap, h, Lanius.Semantics.syncI32ViewsToHeapFrom]

theorem syncFrom_nil {st : State} (h : st.i32ArrayViews = []) :
    Lanius.Semantics.syncI32ViewsFromHeap st = .ok st := by
  simp [Lanius.Semantics.syncI32ViewsFromHeap, h, Lanius.Semantics.syncI32ViewsFromHeapFrom]

/-! ## Binding a list of locals -/

theorem bindLocals_ok {P : Core.Program} :
    ∀ {bs : List (Nat × Value)} {typed : List (Nat × Ty)} {S : CellTypes} {Γ : Context} {st : State},
      BindsAs P bs typed → CellsOk P S st → LocalsOk S Γ st →
        ∃ S', S.Le S' ∧ CellsOk P S' (st.bindLocals bs) ∧ LocalsOk S' (Γ.bindAll typed) (st.bindLocals bs)
  | [], typed, S, Γ, st, h, cells, locals => by
    have : typed = [] := by
      have := congrArg List.length h.1
      simp at this
      exact List.length_eq_zero_iff.1 this.symm
    subst this
    exact ⟨S, .refl S, cells, locals⟩
  | b :: bs, [], _, _, _, h, _, _ => by simp [BindsAs] at h
  | b :: bs, t :: ts, S, Γ, st, h, cells, locals => by
    obtain ⟨fst, snd⟩ := h
    simp only [List.map_cons, List.cons.injEq] at fst
    obtain ⟨hv, rest⟩ := snd.cons_inv
    obtain ⟨cells1, le1⟩ := cells.bindCell b.1 (value := some b.2) (t := t.2)
      (fun v hv' => by cases hv'; exact hv)
    have locals1 : LocalsOk (S.set st.nextCell t.2) (Γ.bind t.1 t.2) (st.bindCell b.1 (some b.2)) := by
      rw [← fst.1]; exact locals.bindCell cells b.1 (some b.2) t.2
    obtain ⟨S', le', cells', locals'⟩ := bindLocals_ok (bs := bs) (typed := ts) ⟨fst.2, rest⟩ cells1 locals1
    exact ⟨S', le1.trans le', cells', locals'⟩

theorem bindParameters_binds {P : Core.Program} :
    ∀ {params : List (Nat × Ty)} {vs : List Value}, Shapes P vs (params.map Prod.snd) →
      Lanius.Semantics.bindParameters params vs = some ((params.zip vs).map fun pair => (pair.1.1, pair.2)) ∧
        BindsAs P ((params.zip vs).map fun pair => (pair.1.1, pair.2)) params := by
  intro params vs h
  have len : params.length = vs.length := by
    have := h.1
    simp at this
    exact this.symm
  refine ⟨by simp [Lanius.Semantics.bindParameters, len], ?_⟩
  induction params generalizing vs with
  | nil => exact ⟨by simp, by simpa using Shapes.nil P⟩
  | cons p params ih =>
    cases vs with
    | nil => simp at len
    | cons v vs =>
      simp only [List.map_cons] at h
      obtain ⟨hv, hvs⟩ := h.cons_inv
      obtain ⟨fst, snd⟩ := ih hvs (by simpa using len)
      refine ⟨by simp only [List.zip_cons_cons, List.map_cons]; rw [← fst], ?_⟩
      simp only [List.zip_cons_cons, List.map_cons]
      exact Shapes.cons hv snd

end Lanius.Mini.NoMismatch
