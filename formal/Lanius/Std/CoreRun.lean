import Lanius.Semantics.CallRun
import Lanius.Semantics.RawSlice
import Lanius.Semantics.RawStore
import Lanius.Semantics.Bindings
import Lanius.Semantics.MutableLocal

/-! # Small Core run rules for the stdlib specs

Rules in the `RunsExpr` style (`Semantics/StmtList.lean`) for the expression
and statement forms the `std::vec` templates use, kept here so the Core and
program-logic files stay as they are. `PureRun` is a statement run that
leaves the heap, world and views as they were and only appends fresh cells
(`PureFrame`). -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

/-! ## Expressions that do not change the state -/

theorem RunsExpr.value' {P : Program} {S : State} (v : Value) : RunsExpr P S (.value v) v S :=
  .ofStable .value rfl

theorem RunsExpr.local' {P : Program} {S : State} {id : VarId} {v : Value}
    (found : S.local? id = some v) : RunsExpr P S (.local id) v S :=
  .ofStable (StableExpr.local found) rfl

theorem RunsExpr.field' {P : Program} {S S' : State} {e : Expr} {tid : TypeId}
    {fields : List Value} {j : Nat} {v : Value}
    (base : RunsExpr P S e (.structure tid fields) S') (found : fields[j]? = some v) :
    RunsExpr P S (.field e j) v S' := by
  obtain ⟨n, run, locals⟩ := base
  exact .ofStable (StableExpr.field run found) locals

theorem RunsExpr.cast' {P : Program} {S S' : State} {e : Expr} {v r : Value} {dest : ScalarTy}
    (operand : RunsExpr P S e v S') (evaluates : evalScalarCast P.target dest v = .ok r) :
    RunsExpr P S (.cast dest e) r S' := by
  obtain ⟨n, run, locals⟩ := operand
  exact .ofStable (StableExpr.cast run evaluates) locals

/-- A true left operand skips the right one. -/
theorem RunsExpr.logicalOrTrue' {P : Program} {S S' : State} {l r : Expr}
    (left : RunsExpr P S l (.boolean true) S') :
    RunsExpr P S (.binary .logicalOr l r) (.boolean true) S' := by
  obtain ⟨n, run, locals⟩ := left
  exact .ofStable (StableExpr.logicalOrTrue run) locals

theorem RunsExpr.logicalOrBool {P : Program} {S : State} {l r : Expr} {a b : Bool}
    (left : RunsExpr P S l (.boolean a) S) (right : RunsExpr P S r (.boolean b) S) :
    RunsExpr P S (.binary .logicalOr l r) (.boolean (a || b)) S := by
  cases a with
  | true => exact RunsExpr.logicalOrTrue' left
  | false => exact RunsExpr.logicalOrFalse left right

theorem RunsExpr.intrinsic' {P : Program} {S S' : State} {e : Expr} {v r : Value} {op : Intrinsic}
    (operand : RunsExpr P S e v S')
    (result : (match op, v with
      | .printI32, .signed .i32 integer =>
          Outcome.done Value.unit { S' with world := S'.world.afterPrintI32 integer }
      | .assert, .boolean true => .done .unit S'
      | .assert, .boolean false => .trapped .assertionFailed S'
      | .sliceStride, view =>
          match rawSliceStride? P view with
          | some stride => .done (.signed .isize stride) S'
          | none => .trapped .typeMismatch S'
      | _, _ => .trapped .typeMismatch S') = .done r S') :
    RunsExpr P S (.intrinsic op e) r S' := by
  obtain ⟨n, run, locals⟩ := operand
  refine .ofStable (threshold := n + 1) ?_ locals
  intro fuel enough
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [run (fuel - 1) (by omega)]
  exact result

theorem RunsExpr.assertTrue {P : Program} {S S' : State} {e : Expr}
    (operand : RunsExpr P S e (.boolean true) S') :
    RunsExpr P S (.intrinsic .assert e) .unit S' :=
  RunsExpr.intrinsic' operand rfl

theorem RunsExpr.sliceStride' {P : Program} {S S' : State} {e : Expr} {v : Value} {stride : Int}
    (operand : RunsExpr P S e v S') (found : rawSliceStride? P v = some stride) :
    RunsExpr P S (.intrinsic .sliceStride e) (.signed .isize stride) S' :=
  RunsExpr.intrinsic' operand (by simp only [found])

theorem RunsExprs.toRun {P : Program} {S S' : State} {es : List Expr} {vs : List Value}
    (run : RunsExprs P S es vs S') :
    RunsExpr P S (.structValue tid es) (.structure tid vs) S' := by
  obtain ⟨n, run, locals⟩ := run
  refine .ofStable (threshold := n + 1) ?_ locals
  intro fuel enough
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [run (fuel - 1) (by omega)]

theorem RunsExprs.toEnum {P : Program} {S S' : State} {es : List Expr} {vs : List Value}
    (run : RunsExprs P S es vs S') :
    RunsExpr P S (.enumValue tid variant es) (.enumeration tid variant vs) S' := by
  obtain ⟨n, run, locals⟩ := run
  refine .ofStable (threshold := n + 1) ?_ locals
  intro fuel enough
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [run (fuel - 1) (by omega)]

theorem RunsExpr.rawIndex {P : Program} {S : State} {src idx : VarId} {T : Ty}
    {address length position : Nat} {v : Value}
    (source : S.local? src = some (.rawSlice T address length))
    (index : S.local? idx = some (.signed .i32 (Int.ofNat position)))
    (readable : readRawSliceIndex P S T address length position = .ok v) :
    RunsExpr P S (.index (.local src) (.local idx)) v S :=
  .ofStable (StableExpr.rawSliceIndex source index readable) rfl

theorem RunsExpr.i32View {P : Program} {S S' S'' : State} {pe le : Expr} {address : Nat} {count : Int}
    {v : Value} (pointer : RunsExpr P S pe (.pointer address) S')
    (length : RunsExpr P S' le (.signed .i32 count) S'')
    (construct : mapRawI32Slice S'' address count = .done v S'') :
    RunsExpr P S (.i32SliceFromRawParts pe le) v S'' :=
  RunsExpr.rawSliceFromParts pointer length construct rfl

theorem RunsExpr.nominalView {P : Program} {S S' S'' : State} {pe le : Expr} {address : Nat}
    {count : Int} {T : Ty} {v : Value} (pointer : RunsExpr P S pe (.pointer address) S')
    (length : RunsExpr P S' le (.signed .i32 count) S'')
    (construct : mapRawNominalSlice P S'' T address count = .done v S'') :
    RunsExpr P S (.typedSliceFromRawParts T pe le) v S'' :=
  RunsExpr.nominalSliceFromParts pointer length construct rfl

/-! ## Locals after binding -/

theorem State.formed_noLocals {S : State} (formed : S.CellsWellFormed) :
    ({ S with locals := [] } : State).CellsWellFormed := formed

theorem local_bound {S : State} (formed : S.CellsWellFormed) (id : VarId) (v : Value) :
    (S.bindLocal id v).local? id = some v :=
  State.bindLocal_local? S formed id v

theorem local_kept {S : State} (formed : S.CellsWellFormed) {old new : VarId} {w : Value}
    (v : Value) (different : new ≠ old) (found : S.local? old = some w) :
    (S.bindLocal new v).local? old = some w :=
  State.bindLocal_local?_of_ne S formed old new w v different found

/-! ## Statement runs that leave the heap as it was -/

def PureRun (P : Program) (S : State) (s : Stmt) (c : Completion) : Prop :=
  ∃ after, RunsStmt P S s c after ∧ PureFrame S after

theorem PureRun.ret {P : Program} {S : State} {e : Expr} {v : Value}
    (formed : S.CellsWellFormed) (run : RunsExpr P S e v S) :
    PureRun P S (.returnValue (some e)) (.returned (some v)) :=
  ⟨S, RunsStmt.returnValue run, PureFrame.refl formed⟩

theorem PureRun.guardTaken {P : Program} {S : State} {c : Expr} {t rest : Stmt} {k : Completion}
    (cond : RunsExpr P S c (.boolean true) S) (branch : PureRun P S t k) (notNext : k ≠ .next) :
    PureRun P S (.sequence (.ifThenElse c t .skip) rest) k := by
  obtain ⟨after, run, frame⟩ := branch
  exact ⟨after, RunsStmt.sequenceCompleted (RunsStmt.ifThenElseTrue cond run) notNext rest, frame⟩

theorem PureRun.guardSkip {P : Program} {S : State} {c : Expr} {t rest : Stmt} {k : Completion}
    (cond : RunsExpr P S c (.boolean false) S) (tail : PureRun P S rest k) :
    PureRun P S (.sequence (.ifThenElse c t .skip) rest) k := by
  obtain ⟨after, run, frame⟩ := tail
  exact ⟨after, RunsStmt.sequenceNext (RunsStmt.ifThenElseFalse cond (RunsStmt.skip P S)) run, frame⟩

theorem PureRun.assert {P : Program} {S : State} {c : Expr} {rest : Stmt} {k : Completion}
    (cond : RunsExpr P S c (.boolean true) S) (tail : PureRun P S rest k) :
    PureRun P S (.sequence (.expression (.intrinsic .assert c)) rest) k := by
  obtain ⟨after, run, frame⟩ := tail
  exact ⟨after, RunsStmt.sequenceNext (RunsStmt.expression (RunsExpr.assertTrue cond)) run, frame⟩

/-- A `let` whose initializer may call pure functions. -/
theorem PureRun.letRun {P : Program} {S S' : State} {id : VarId} {ty : Ty} {e : Expr} {v : Value}
    {body : Stmt} {k : Completion}
    (init : RunsExpr P S e v S') (initFrame : PureFrame S S') (tail : PureRun P (S'.bindLocal id v) body k) :
    PureRun P S (.letLocal id ty e body) k := by
  obtain ⟨after, run, frame⟩ := tail
  exact RunsStmt.letLocalPure (type := ty) init initFrame run frame

theorem PureRun.letPure {P : Program} {S : State} {id : VarId} {ty : Ty} {e : Expr} {v : Value}
    {body : Stmt} {k : Completion} (formed : S.CellsWellFormed)
    (init : RunsExpr P S e v S) (tail : PureRun P (S.bindLocal id v) body k) :
    PureRun P S (.letLocal id ty e body) k :=
  PureRun.letRun init (PureFrame.refl formed) tail

/-- A call of a function whose body is a pure run returning `v`. -/
theorem PureRun.call {P : Program} {caller : State} {f : FunctionId} {fn : Function} {body : Stmt}
    {vs : List Value} {bindings : List (VarId × Value)} {v : Value}
    (found : P.function? f = some fn) (bodyFound : fn.body = some body)
    (parameters : bindParameters fn.parameters vs = some bindings)
    (formed : caller.CellsWellFormed)
    (run : PureRun P (({ caller with locals := [] } : State).bindLocals bindings) body (.returned (some v))) :
    ∃ after, RunsExpr P caller (.call f (vs.map Expr.value)) v after ∧ PureFrame caller after :=
  RunsExpr.callPure found bodyFound parameters formed run

/-- Calling with argument expressions that evaluate without changing the state. -/
theorem callArgs {P : Program} {S after : State} {f : FunctionId} {args : List Expr} {vs : List Value}
    {v : Value} (argsRun : RunsExprs P S args vs S)
    (call : RunsExpr P S (.call f (vs.map Expr.value)) v after) :
    RunsExpr P S (.call f args) v after :=
  RunsExpr.callArguments argsRun call

theorem RunsExprs.one {P : Program} {S : State} {e : Expr} {v : Value} (run : RunsExpr P S e v S) :
    RunsExprs P S [e] [v] S := .cons run .nil

theorem RunsExprs.two {P : Program} {S : State} {e₁ e₂ : Expr} {v₁ v₂ : Value}
    (r₁ : RunsExpr P S e₁ v₁ S) (r₂ : RunsExpr P S e₂ v₂ S) :
    RunsExprs P S [e₁, e₂] [v₁, v₂] S := .cons r₁ (.cons r₂ .nil)

theorem RunsExprs.three {P : Program} {S : State} {e₁ e₂ e₃ : Expr} {v₁ v₂ v₃ : Value}
    (r₁ : RunsExpr P S e₁ v₁ S) (r₂ : RunsExpr P S e₂ v₂ S) (r₃ : RunsExpr P S e₃ v₃ S) :
    RunsExprs P S [e₁, e₂, e₃] [v₁, v₂, v₃] S := .cons r₁ (.cons r₂ (.cons r₃ .nil))

end Lanius.Std
