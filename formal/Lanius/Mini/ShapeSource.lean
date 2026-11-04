module

public import Lanius.Mini.ShapeStep
public import Lanius.Mini.SourceStops
public import Lanius.Mini.TypeSound
import all Lanius.Mini.Compiler.P.arrayCallSig

@[expose] public section

/-! # Source programs without raw memory never reach `typeMismatch`
(review finding 2, step 5)

A source program is `RawFree` when no function body uses the raw-memory
statements (`alloc`, `load_byte`, `store_byte`, `dealloc`, raw slices and
their indexing) or `slice_stride`. Its Core meaning is in the fragment of
`ShapeEval`, and its host functions are the services the compiler lowers, so
when `compileSource` accepts it (Core well typed, `compileSource_wellTyped`)
Core's call of any of its functions on arguments the compiled code's
parameters hold never traps with `typeMismatch` (`call_ne_typeMismatch`).

`compileSource_behaviour_rawFree` is `compileSource_behaviour` with that
fact: the undefined trap its second case allows is not `typeMismatch`. -/

namespace Lanius.Mini

variable {sx : Statics} {places : List Addressed}

open Lanius.Core (Value Ty)
open Lanius.Semantics (evalExpr evalExprs)
open Lanius.Typing
open Lanius.X86.Machine
open Lanius.Mini.NoMismatch

/-! ## Source programs without raw memory -/

mutual
  def SrcEff.rawFree (e : SrcEff) : Bool :=
    match e with
    | .ePure _ => true
    | .eCall _ args => SrcEff.rawFreeList args
    | .eApply _ a b => a.rawFree && b.rawFree
    | .eNeg a => a.rawFree
    | .eNot a => a.rawFree
    | .eCast _ a => a.rawFree
    | .eIndex _ _ => false
    | .eStruct _ fields => SrcEff.rawFreeList fields
    | .eVariant _ _ payload => SrcEff.rawFreeList payload
    | .eMatch scrutinee _ _ _ values => scrutinee.rawFree && SrcEff.rawFreeList values
    | .eDivide _ a b => a.rawFree && b.rawFree
    | .eStride _ => false
    | .arraySlice _ _ => false
    | .eIf c _ a b => c.rawFree && a.rawFree && b.rawFree
    | .eLet _ _ a _ b => a.rawFree && b.rawFree
    | .eLen _ => false
    | .eStr _ _ => true
    | .eBorrow _ _ => false
    | .eDeref _ _ => false
    | .eField _ _ => false
    | .eAt _ _ => false
  termination_by structural e

  def SrcEff.rawFreeList (es : List SrcEff) : Bool :=
    match es with
    | [] => true
    | e :: rest => e.rawFree && SrcEff.rawFreeList rest
  termination_by structural es
end

def SrcStmt.rawFree : SrcStmt → Bool
  | .nop => true
  | .let _ _ _ body => body.rawFree
  | .letStruct _ _ _ body => body.rawFree
  | .letCall _ _ _ _ body => body.rawFree
  | .letEnum _ _ _ _ body => body.rawFree
  | .letMatch _ _ _ _ _ body => body.rawFree
  | .set _ _ => true
  | .setField _ _ _ => true
  | .setCall _ _ _ => true
  | .then first second => first.rawFree && second.rawFree
  | .if _ thenBranch elseBranch => thenBranch.rawFree && elseBranch.rawFree
  | .while _ body => body.rawFree
  | .return _ => true
  | .letAlloc _ _ _ _ => false
  | .letView _ _ _ _ _ => false
  | .letStr _ _ _ => false
  | .letLoad _ _ _ _ => false
  | .setByte _ _ _ => false
  | .free _ _ _ => false
  | .letSlice _ _ _ _ _ => false
  | .letIndex _ _ _ _ _ => false
  | .setIndex _ _ _ => false
  | .letEval _ _ value body => value.rawFree && body.rawFree
  | .setEval _ value => value.rawFree
  | .ifEval condition thenBranch elseBranch => condition.rawFree && thenBranch.rawFree && elseBranch.rawFree
  | .whileEval condition body => condition.rawFree && body.rawFree
  | .returnEval value => value.rawFree
  | .discard value => value.rawFree
  | .setIndexEval _ _ _ => false
  | .setFieldEval _ _ value => value.rawFree
  | .returnUnit => true
  | .assert condition => condition.rawFree
  | .break => true
  | .continue => true
  | .matchArm _ _ _ _ _ _ body rest => body.rawFree && rest.rawFree
  | .unreachable _ _ => true
  | .setPlace _ _ => false
  | .setPlaceOp _ _ _ => false

/-- No function of the program uses raw memory. -/
def SrcProgram.RawFree (sp : SrcProgram) : Prop := ∀ func ∈ sp.funcs, func.body.rawFree = true

/-! ## Their Core meaning is in the fragment -/

theorem SrcExpr.toCore_frag : ∀ e : SrcExpr, ExprFrag e.toCore = true
  | .int _ | .boolean _ | .unsigned _ _ | .local _ | .null | .char _ | .float _ _ => by
    simp [SrcExpr.toCore, ExprFrag]
  | .field _ _ => by simp [SrcExpr.toCore, ExprFrag]
  | .negate a | .not a | .cast _ a => by simp [SrcExpr.toCore, ExprFrag, SrcExpr.toCore_frag a]
  | .apply _ a b => by simp [SrcExpr.toCore, ExprFrag, SrcExpr.toCore_frag a, SrcExpr.toCore_frag b]

theorem SrcExpr.toCore_list_frag : ∀ es : List SrcExpr, ExprsFrag (es.map SrcExpr.toCore) = true
  | [] => by simp [ExprsFrag]
  | e :: es => by simp [ExprsFrag, SrcExpr.toCore_frag e, SrcExpr.toCore_list_frag es]

theorem literal_frag (ty : SrcType) {xs : List Core.Expr} (h : ExprsFrag xs = true) : ExprFrag (ty.literal xs) = true := by
  cases ty <;> simp [SrcType.literal, ExprFrag, h]

theorem coreArms_frag (id : Nat) : ∀ (k : Nat) (arms : List SrcArm), ArmsFrag (coreArms id k arms) = true
  | _, [] => by simp [coreArms, ArmsFrag]
  | k, arm :: rest => by simp [coreArms, ArmsFrag, SrcExpr.toCore_frag, coreArms_frag id (k + 1) rest]

mutual
  theorem SrcEff.toCore_frag (e : SrcEff) (h : e.rawFree = true) : ExprFrag e.toCore = true := by
    match e with
    | .ePure a => simp [SrcEff.toCore, SrcExpr.toCore_frag]
    | .eCall _ args =>
      simp only [SrcEff.rawFree] at h
      simp only [SrcEff.toCore, ExprFrag]; exact SrcEff.toCoreList_frag args h
    | .eApply _ a b | .eDivide _ a b =>
      simp only [SrcEff.rawFree, Bool.and_eq_true] at h
      simp only [SrcEff.toCore, ExprFrag, SrcEff.toCore_frag a h.1, SrcEff.toCore_frag b h.2, Bool.and_self]
    | .eNeg a | .eNot a | .eCast _ a =>
      simp only [SrcEff.rawFree] at h
      simp only [SrcEff.toCore, ExprFrag, SrcEff.toCore_frag a h]
    | .eIndex _ _ => simp [SrcEff.rawFree] at h
    | .eStride _ => simp [SrcEff.rawFree] at h
    | .arraySlice _ _ => simp [SrcEff.rawFree] at h
    | .eIf c _ a b =>
      simp only [SrcEff.rawFree, Bool.and_eq_true] at h
      simp only [SrcEff.toCore, ExprFrag, ArmsFrag, SrcEff.toCore_frag c h.1.1, SrcEff.toCore_frag a h.1.2,
        SrcEff.toCore_frag b h.2, Bool.and_self]
    | .eLet _ _ a _ b =>
      simp only [SrcEff.rawFree, Bool.and_eq_true] at h
      simp only [SrcEff.toCore, ExprFrag, ArmsFrag, SrcEff.toCore_frag a h.1, SrcEff.toCore_frag b h.2, Bool.and_self]
    | .eLen _ => simp [SrcEff.rawFree] at h
    | .eStr _ _ => simp [SrcEff.toCore, ExprFrag]
    | .eBorrow _ _ => simp [SrcEff.rawFree] at h
    | .eDeref _ _ => simp [SrcEff.rawFree] at h
    | .eField _ _ => simp [SrcEff.rawFree] at h
    | .eAt _ _ => simp [SrcEff.rawFree] at h
    | .eStruct ty fields =>
      simp only [SrcEff.rawFree] at h
      simp only [SrcEff.toCore]; exact literal_frag ty (SrcEff.toCoreList_frag fields h)
    | .eVariant _ _ payload =>
      simp only [SrcEff.rawFree] at h
      simp only [SrcEff.toCore, ExprFrag]; exact SrcEff.toCoreList_frag payload h
    | .eMatch scrutinee ety _ binders values =>
      simp only [SrcEff.rawFree, Bool.and_eq_true] at h
      simp only [SrcEff.toCore, ExprFrag, SrcEff.toCore_frag scrutinee h.1, Bool.true_and]
      exact SrcEff.coreArms_frag ety.typeId 0 binders values h.2
  termination_by structural e

  theorem SrcEff.toCoreList_frag (es : List SrcEff) (h : SrcEff.rawFreeList es = true) :
      ExprsFrag (SrcEff.toCoreList es) = true := by
    match es with
    | [] => simp [SrcEff.toCoreList, ExprsFrag]
    | e :: rest =>
      simp only [SrcEff.rawFreeList, Bool.and_eq_true] at h
      simp only [SrcEff.toCoreList, ExprsFrag, SrcEff.toCore_frag e h.1, SrcEff.toCoreList_frag rest h.2,
        Bool.and_self]
  termination_by structural es

  theorem SrcEff.coreArms_frag (id : Nat) (k : Nat) (binders : List (List Nat)) (values : List SrcEff)
      (h : SrcEff.rawFreeList values = true) : ArmsFrag (SrcEff.coreArms id k binders values) = true := by
    match binders, values with
    | [], _ => simp [SrcEff.coreArms, ArmsFrag]
    | _ :: _, [] => simp [SrcEff.coreArms, ArmsFrag]
    | _ :: rest, value :: values =>
      simp only [SrcEff.rawFreeList, Bool.and_eq_true] at h
      simp only [SrcEff.coreArms, ArmsFrag, SrcEff.toCore_frag value h.1,
        SrcEff.coreArms_frag id (k + 1) rest values h.2, Bool.and_self]
  termination_by structural values
end

theorem SrcStmt.toCore_frag : ∀ (s : SrcStmt), s.rawFree = true → StmtFrag s.toCore = true
  | .nop, _ => rfl
  | .let _ _ v body, h => by
    simp only [SrcStmt.rawFree] at h
    simp [SrcStmt.toCore, StmtFrag, SrcExpr.toCore_frag, SrcStmt.toCore_frag body h]
  | .letStruct _ ty fields body, h => by
    simp only [SrcStmt.rawFree] at h
    simp [SrcStmt.toCore, StmtFrag, literal_frag ty (SrcExpr.toCore_list_frag fields), SrcStmt.toCore_frag body h]
  | .letCall _ _ _ args body, h => by
    simp only [SrcStmt.rawFree] at h
    simp [SrcStmt.toCore, StmtFrag, ExprFrag, SrcExpr.toCore_list_frag args, SrcStmt.toCore_frag body h]
  | .letEnum _ _ _ payload body, h => by
    simp only [SrcStmt.rawFree] at h
    simp [SrcStmt.toCore, StmtFrag, ExprFrag, SrcExpr.toCore_list_frag payload, SrcStmt.toCore_frag body h]
  | .letMatch _ _ _ enumId arms body, h => by
    simp only [SrcStmt.rawFree] at h
    simp [SrcStmt.toCore, StmtFrag, ExprFrag, coreArms_frag enumId 0 arms, SrcStmt.toCore_frag body h]
  | .set _ v, _ => by simp [SrcStmt.toCore, StmtFrag, ExprFrag, PlaceFrag, SrcExpr.toCore_frag]
  | .setField _ _ v, _ => by simp [SrcStmt.toCore, StmtFrag, ExprFrag, PlaceFrag, SrcExpr.toCore_frag]
  | .setCall _ _ args, _ => by
    simp [SrcStmt.toCore, StmtFrag, ExprFrag, PlaceFrag, SrcExpr.toCore_list_frag args]
  | .then a b, h => by
    simp only [SrcStmt.rawFree, Bool.and_eq_true] at h
    simp [SrcStmt.toCore, StmtFrag, SrcStmt.toCore_frag a h.1, SrcStmt.toCore_frag b h.2]
  | .if c a b, h => by
    simp only [SrcStmt.rawFree, Bool.and_eq_true] at h
    simp [SrcStmt.toCore, StmtFrag, SrcExpr.toCore_frag, SrcStmt.toCore_frag a h.1, SrcStmt.toCore_frag b h.2]
  | .while c body, h => by
    simp only [SrcStmt.rawFree] at h
    simp [SrcStmt.toCore, StmtFrag, SrcExpr.toCore_frag, SrcStmt.toCore_frag body h]
  | .return v, _ => by simp [SrcStmt.toCore, StmtFrag, SrcExpr.toCore_frag]
  | .letAlloc _ _ _ _, h | .letView _ _ _ _ _, h | .letStr _ _ _, h | .letLoad _ _ _ _, h | .setByte _ _ _, h | .free _ _ _, h
  | .letSlice _ _ _ _ _, h | .letIndex _ _ _ _ _, h | .setIndex _ _ _, h | .setIndexEval _ _ _, h => by
    simp [SrcStmt.rawFree] at h
  | .letEval _ _ v body, h => by
    simp only [SrcStmt.rawFree, Bool.and_eq_true] at h
    simp [SrcStmt.toCore, StmtFrag, SrcEff.toCore_frag v h.1, SrcStmt.toCore_frag body h.2]
  | .setEval _ v, h => by
    simp only [SrcStmt.rawFree] at h
    simp [SrcStmt.toCore, StmtFrag, ExprFrag, PlaceFrag, SrcEff.toCore_frag v h]
  | .ifEval c a b, h => by
    simp only [SrcStmt.rawFree, Bool.and_eq_true] at h
    simp [SrcStmt.toCore, StmtFrag, SrcEff.toCore_frag c h.1.1, SrcStmt.toCore_frag a h.1.2,
      SrcStmt.toCore_frag b h.2]
  | .whileEval c body, h => by
    simp only [SrcStmt.rawFree, Bool.and_eq_true] at h
    simp [SrcStmt.toCore, StmtFrag, SrcEff.toCore_frag c h.1, SrcStmt.toCore_frag body h.2]
  | .returnEval v, h => by
    simp only [SrcStmt.rawFree] at h
    simp [SrcStmt.toCore, StmtFrag, SrcEff.toCore_frag v h]
  | .discard v, h => by
    simp only [SrcStmt.rawFree] at h
    simp [SrcStmt.toCore, StmtFrag, SrcEff.toCore_frag v h]
  | .setFieldEval _ _ v, h => by
    simp only [SrcStmt.rawFree] at h
    simp [SrcStmt.toCore, StmtFrag, ExprFrag, PlaceFrag, SrcEff.toCore_frag v h]
  | .setPlace _ _, h => by simp [SrcStmt.rawFree] at h
  | .setPlaceOp _ _ _, h => by simp [SrcStmt.rawFree] at h
  | .returnUnit, _ => rfl
  | .assert c, h => by
    simp only [SrcStmt.rawFree] at h
    simp [SrcStmt.toCore, StmtFrag, ExprFrag, IntrinsicFrag, SrcEff.toCore_frag c h]
  | .break, _ => rfl
  | .continue, _ => rfl
  | .matchArm _ _ _ binds _ _ body rest, h => by
    simp only [SrcStmt.rawFree, Bool.and_eq_true] at h
    have fb := SrcStmt.toCore_frag body h.1
    have fr := SrcStmt.toCore_frag rest h.2
    cases binds <;> simp [SrcStmt.toCore, StmtFrag, ExprFrag, ArmsFrag, fb, fr]
  | .unreachable _ _, _ => by simp [SrcStmt.toCore, StmtFrag, ExprFrag]

theorem coreFuncs_frag {funcs : List SrcFunc} (raw : ∀ func ∈ funcs, func.body.rawFree = true) :
    ∀ (id : Nat), ∀ f ∈ coreFuncs id funcs, FunctionFrag f := by
  induction funcs with
  | nil => intro id f mem; cases mem
  | cons func rest ih =>
    intro id f mem
    simp only [coreFuncs, List.mem_cons] at mem
    rcases mem with rfl | mem
    · exact .inl ⟨_, rfl, SrcStmt.toCore_frag _ (raw func (by simp))⟩
    · exact ih (fun g hg => raw g (by simp [hg])) (id + 1) f mem

theorem hostFuncs_frag : ∀ f ∈ hostFuncs, FunctionFrag f := by
  intro f mem
  simp only [hostFuncs, List.mem_cons, List.not_mem_nil, or_false] at mem
  rcases mem with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    exact .inr ⟨rfl, _, rfl, by simp [LoweredService]⟩

theorem toCore_progOk {sp : SrcProgram} (wt : ProgramWellTyped sp.toCore) (raw : sp.RawFree) :
    ProgOk sp.toCore := by
  refine ⟨wt, fun f mem => ?_⟩
  simp only [SrcProgram.toCore, List.mem_append] at mem
  rcases mem with mem | mem
  · exact coreFuncs_frag raw 0 f mem
  · exact hostFuncs_frag f mem

/-! ## Arguments the compiled code's parameters hold have their shapes -/

mutual
  theorem holdsAt_shape {P : Core.Program} {ty : SrcType} {v : Value} {env : Env} {slot : Nat}
      (declared : TypeDeclared P ty) (h : ty.HoldsAt sx places v env slot) : Shape P v ty.toCore := by
    match h with
    | .i32 h => obtain ⟨rfl, -⟩ := h; exact .signed _ _
    | .bool h => obtain ⟨b, rfl, -⟩ := h; exact .boolean b
    | .uint h => obtain ⟨rfl, -⟩ := h; exact .unsigned _ _
    | .ptr h => cases h; exact .pointer _
    | .unit => exact .unit
    | .isize h => cases h; exact .signed _ _
    | .char h => obtain ⟨rfl, -⟩ := h; exact .character _
    | @SrcType.HoldsAt.float _ _ t _ _ _ h =>
      obtain ⟨rfl, -⟩ := h
      cases t
      · exact .f32 _
      · exact .f64 _
    | @SrcType.HoldsAt.sint _ _ kind _ _ _ h =>
      cases kind
      all_goals first
        | (obtain ⟨rfl, -⟩ := h; exact .signed _ _)
        | (cases h; exact .signed _ _)
    | .slice _ _ => exact .rawSlice _ _ _
    | .borrowed .. => exact .slice _ _ _ _ _
    | .view len i32s =>
      exact .array _ _ _ len fun x m => by obtain ⟨i, rfl, -⟩ := i32s x m; exact .signed _ _
    | .str .. => exact .string _
    | .struct fields =>
      cases declared with
      | «struct» found inner =>
        exact Shape.mk_struct found (fieldsHold_shapes inner fields)
    | @SrcType.HoldsAt.enum _ _ id variants k fs vs _ _ variant tag payload =>
      cases declared with
      | enum found inner =>
        have variantFound : (variants.map (List.map SrcType.toCore))[k]? = some (fs.map SrcType.toCore) := by
          rw [List.getElem?_map, variant]; rfl
        exact Shape.mk_enum found variantFound (fieldsHold_shapes (inner _ (List.mem_of_getElem? variant)) payload)
    | .array fields =>
      cases declared with
      | array inner =>
        have shapes := fieldsHold_shapes (fun f mem => by rw [List.eq_of_mem_replicate mem]; exact inner) fields
        rw [List.map_replicate] at shapes
        obtain ⟨len, each⟩ := shapes.replicate
        exact .array _ _ _ len each
  termination_by structural h

  theorem fieldsHold_shapes {P : Core.Program} {tys : List SrcType} {vs : List Value} {env : Env} {slot : Nat}
      (declared : ∀ ty ∈ tys, TypeDeclared P ty) (h : FieldsHold sx places tys vs env slot) :
      Shapes P vs (tys.map SrcType.toCore) := by
    match h with
    | .nil => exact Shapes.nil P
    | .cons head tail =>
      exact Shapes.cons (holdsAt_shape (declared _ (by simp)) head)
        (fieldsHold_shapes (fun ty mem => declared ty (by simp [mem])) tail)
  termination_by structural h
end

theorem paramTypes_mem : ∀ {params : List SrcParam} {ty : SrcType}, ty ∈ paramTypes params →
    ∃ param ∈ params, param.ty = ty
  | [], _, mem => by simp [paramTypes] at mem
  | param :: rest, ty, mem => by
    simp only [paramTypes, List.mem_cons] at mem
    rcases mem with rfl | mem
    · exact ⟨param, by simp, rfl⟩
    · obtain ⟨p, hp, eq⟩ := paramTypes_mem mem
      exact ⟨p, by simp [hp], eq⟩

/-- Values in `.value` form evaluate to themselves. -/
theorem values_ok {P : Core.Program} {S : CellTypes} {st : Semantics.State} (cells : CellsOk P S st) :
    ∀ (k : Nat) {vs : List Value} {ts : List Ty}, Shapes P vs ts →
      EsOk P S st ts (evalExprs k P st (vs.map Core.Expr.value))
  | 0, _, _, _ => by simp only [evalExprs]; trivial
  | _ + 1, [], _, h => by
    simp only [List.map_nil, evalExprs]
    exact EsOk.of (.refl S) cells rfl h
  | k + 1, v :: vs, ts, h => by
    cases ts with
    | nil => exact absurd h.1 (by simp)
    | cons t ts =>
      obtain ⟨hv, hvs⟩ := h.cons_inv
      simp only [List.map_cons, evalExprs]
      cases k with
      | zero => simp only [evalExpr]; trivial
      | succ j =>
        simp only [evalExpr]
        have rest := values_ok cells (j + 1) hvs
        cases hr : evalExprs (j + 1) P st (vs.map Core.Expr.value) with
        | done ws c =>
          rw [hr] at rest
          obtain ⟨S1, le1, cells1, same1, shs⟩ := rest
          exact EsOk.of le1 cells1 same1 (Shapes.cons hv shs)
        | _ => rw [hr] at rest; pass rest

/-! ## The call `compileSource`'s theorems are about -/

theorem startState_cellsOk (P : Core.Program) (io : Lanius.X86.Machine.Io) :
    CellsOk P (fun _ => none) (startState io) :=
  ⟨rfl, (fun _ _ h => by cases h), (fun _ mem => by simp [startState] at mem)⟩

/-- Finding 2 for the verified compiler: when `compileSource` accepts a
program without raw memory, Core's call of any of its functions on arguments
its parameters hold never traps with `typeMismatch`. -/
theorem call_ne_typeMismatch {sp : SrcProgram} {binary : Binary} (compiled : compileSource sp = some binary)
    (raw : sp.RawFree) {f : Nat} {func : SrcFunc} (found : sp.funcs[f]? = some func) {args : List Value}
    {env : Env} {slot : Nat} (typed : FieldsHold sx [] (paramTypes func.params) args env slot)
    (io : Lanius.X86.Machine.Io) (fuel : Nat) (r : Lanius.Trap) (st : Semantics.State)
    (run : evalExpr fuel sp.toCore (startState io) (.call f (args.map Core.Expr.value)) = .trapped r st) :
    r ≠ .typeMismatch := by
  have prog := toCore_progOk (compileSource_wellTyped compiled) raw
  obtain ⟨returns, ⟨decls, declaredOk⟩, _⟩ := compileSource_some compiled
  have declared := (TypeSound.declareProgram_declared declaredOk func (List.mem_of_getElem? found)).1
  have shapes := fieldsHold_shapes (fun ty mem => by
    obtain ⟨param, pm, rfl⟩ := paramTypes_mem mem
    exact declared param pm) typed
  rw [← TypeSound.paramTypes_toCore] at shapes
  have lookup : sp.toCore.function? f = some (func.toCore f) := by
    rw [SrcProgram.function?_toCore, found]
  cases fuel with
  | zero => simp [evalExpr] at run
  | succ k =>
    have := step_call_of (good prog k) prog lookup
      (values_ok (startState_cellsOk sp.toCore io) k shapes)
    rw [run] at this
    exact this

/-- `compileSource_behaviour` for a program without raw memory: the
undefined trap its second case allows is not `typeMismatch`. -/
theorem compileSource_behaviour_rawFree {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) (raw : sp.RawFree) {f : Nat} {func : SrcFunc}
    (found : sp.funcs[f]? = some func) {args : List Value} {bits : List (BitVec 64)}
    (typed : FieldsHold sx [] (paramTypes func.params) args (Func.entry bits) 0)
    (bitsLen : bits.length = paramsSize func.params) {heap : Heap} (start : heap.cursor = 1)
    (zero : ∀ a, 1 ≤ a → heap.bytes a = 0) (small : heap.limit < 2 ^ 62) (silent : heap.io.trace = [])
    (room : 1 ≤ heap.limit) (frameRoom : 0 < sp.need f → heap.limit + sp.need f ≤ heap.fsp ∧ heap.fsp ≤ heap.top ∧ heap.top < 2 ^ 62)
    (statics : heap.StaticsAt sx) (ofSp : sx.bytes = sp.decls.statics)
    (s : State) (imageBase : BitVec 64) (window : Nat) (bounded : window ≤ 2 ^ 62)
    (loaded : CodeAt s.memory imageBase binary.image)
    (apart : ∀ index, index < binary.image.length →
      ¬Below (s.registers rspRegister) window (imageBase + BitVec.ofNat 64 index))
    (imageHeap : ∀ index, index < binary.image.length → ¬s.InHeap (imageBase + BitVec.ofNat 64 index))
    (entry : s.rip = imageBase + BitVec.ofNat 64 (binary.entries.getD f 0))
    (params : ∀ k (bound : k < bits.length),
      read64 s.memory (s.registers rspRegister - BitVec.ofNat 64 (8 * k + 16)) = bits[k])
    (heapAt : HeapAt window s heap) (stack : StackAt binary.guard window s)
    {m : Nat} {u : State} (run : Steps m s u) (stuck : ∀ v, ¬Lanius.X86.Machine.Step u v)
    (clean : ¬Lanius.X86.Machine.Fault u) :
    (∃ fuel v final, Semantics.evalExpr fuel sp.toCore (startState heap.io) (.call f (args.map Core.Expr.value)) =
        .done v final ∧ final.heap.nextAddress ≤ heap.limit) ∨
    ∃ fuel r st, Semantics.evalExpr fuel sp.toCore (startState heap.io) (.call f (args.map Core.Expr.value)) =
        .trapped r st ∧ undefinedTrap r = true ∧ r ≠ .typeMismatch ∧ st.heap.nextAddress ≤ heap.limit := by
  rcases compileSource_behaviour compiled found typed bitsLen start zero small silent room frameRoom statics ofSp s imageBase
      window bounded loaded apart imageHeap entry params heapAt stack run stuck clean with
    done | ⟨fuel, r, st, trapped, undefined, within⟩
  · exact .inl done
  · exact .inr ⟨fuel, r, st, trapped, undefined,
      call_ne_typeMismatch compiled raw found typed heap.io fuel r st trapped, within⟩

end Lanius.Mini
