import Lanius.Mini.Source
import Lanius.Typing

/-! Type checker soundness for the front pass (roadmap step 7).

When the front pass accepts a source program, the program's Core meaning is
well typed by Core's own typing rules, `Lanius.Typing.ProgramWellTyped`.

Two of Core's rules are checked by `compileSource` apart from the lowering:

- Nominal types. Core looks struct and enum types up by id in the program's
  declarations, while the front pass's types carry their fields inline
  (`SrcType.struct id fields`). `declareProgram` derives one declaration per
  id from the program's types and rejects a program that gives one id two
  field or variant lists; `SrcProgram.toCore` emits those declarations, so
  every type the program names agrees with them (`SrcProgram.Declared`,
  `declareProgram_declared`).
- Returns. Core requires a function with a non-unit result to end in a
  `return` on every path (`DefinitelyReturns`: a `while` never counts).
  `SrcStmt.returns` is that check on source statements (`returns_sound`), and
  `compileSource` requires it of every function body. -/

namespace Lanius.Mini

open Lanius.Typing (ExprHasType ExprsHaveTypes StmtHasType PlaceHasType)

/-! ## The premises -/

/-- `TypeDeclared P ty`: every struct and enum type inside `ty` is declared
in `P` with the fields or variants `ty` gives it. -/
inductive TypeDeclared (P : Core.Program) : SrcType → Prop where
  | i32 : TypeDeclared P .i32
  | bool : TypeDeclared P .bool
  | uint (kind : UintTy) : TypeDeclared P (.uint kind)
  | ptr : TypeDeclared P .ptr
  | struct {id : Nat} {fields : List SrcType}
      (found : P.structure? id = some ⟨id, fields.map SrcType.toCore⟩)
      (inner : ∀ f ∈ fields, TypeDeclared P f) : TypeDeclared P (.struct id fields)
  | enum {id : Nat} {variants : List (List SrcType)}
      (found : P.enumeration? id = some ⟨id, variants.map (List.map SrcType.toCore)⟩)
      (inner : ∀ fs ∈ variants, ∀ f ∈ fs, TypeDeclared P f) : TypeDeclared P (.enum id variants)
  | slice {element : SrcType} (inner : TypeDeclared P element) : TypeDeclared P (.slice element)
  | unit : TypeDeclared P .unit
  | isize : TypeDeclared P .isize

/-- The types a statement's bindings name are declared. -/
def SrcStmt.Declared (P : Core.Program) (s : SrcStmt) : Prop :=
  match s with
  | .nop => True
  | .let _ ty _ body => TypeDeclared P ty ∧ SrcStmt.Declared P body
  | .letStruct _ ty _ body => TypeDeclared P ty ∧ SrcStmt.Declared P body
  | .letCall _ ty _ _ body => TypeDeclared P ty ∧ SrcStmt.Declared P body
  | .letEnum _ ty _ _ body => TypeDeclared P ty ∧ SrcStmt.Declared P body
  | .letMatch _ ty _ _ _ body => TypeDeclared P ty ∧ SrcStmt.Declared P body
  | .set _ _ => True
  | .setField _ _ _ => True
  | .setCall _ _ _ => True
  | .then first second => SrcStmt.Declared P first ∧ SrcStmt.Declared P second
  | .if _ thenBranch elseBranch => SrcStmt.Declared P thenBranch ∧ SrcStmt.Declared P elseBranch
  | .while _ body => SrcStmt.Declared P body
  | .return _ => True
  | .letAlloc _ _ _ body => SrcStmt.Declared P body
  | .letLoad _ _ _ body => SrcStmt.Declared P body
  | .setByte _ _ _ => True
  | .free _ _ _ => True
  | .letSlice _ element _ _ body => TypeDeclared P element ∧ SrcStmt.Declared P body
  | .letIndex _ ty _ _ body => TypeDeclared P ty ∧ SrcStmt.Declared P body
  | .setIndex _ _ _ => True
  | .letEval _ ty value body =>
      TypeDeclared P ty ∧ (∀ t ∈ value.types, TypeDeclared P t) ∧ SrcStmt.Declared P body
  | .setEval _ value => ∀ t ∈ value.types, TypeDeclared P t
  | .ifEval condition thenBranch elseBranch =>
      (∀ t ∈ condition.types, TypeDeclared P t) ∧ SrcStmt.Declared P thenBranch ∧ SrcStmt.Declared P elseBranch
  | .whileEval condition body => (∀ t ∈ condition.types, TypeDeclared P t) ∧ SrcStmt.Declared P body
  | .returnEval value => ∀ t ∈ value.types, TypeDeclared P t
  | .discard value => ∀ t ∈ value.types, TypeDeclared P t
  | .setIndexEval _ index value => ∀ t ∈ index.types ++ value.types, TypeDeclared P t
  | .setFieldEval _ _ value => ∀ t ∈ value.types, TypeDeclared P t
  | .returnUnit => True
  | .assert condition => ∀ t ∈ condition.types, TypeDeclared P t

/-- Every parameter type and binding type of every function is declared. -/
def SrcProgram.Declared (P : Core.Program) (sp : SrcProgram) : Prop :=
  ∀ func ∈ sp.funcs, (∀ param ∈ func.params, TypeDeclared P param.ty) ∧ SrcStmt.Declared P func.body

namespace TypeSound

theorem returns_sound : ∀ (s : SrcStmt), s.returns = true → Typing.DefinitelyReturns s.toCore
  | .nop, h => by simp [SrcStmt.returns] at h
  | .let _ _ _ body, h => .letLocal (returns_sound body h)
  | .letStruct _ _ _ body, h => .letLocal (returns_sound body h)
  | .letCall _ _ _ _ body, h => .letLocal (returns_sound body h)
  | .letEnum _ _ _ _ body, h => .letLocal (returns_sound body h)
  | .letMatch _ _ _ _ _ body, h => .letLocal (returns_sound body h)
  | .set _ _, h => by simp [SrcStmt.returns] at h
  | .setField _ _ _, h => by simp [SrcStmt.returns] at h
  | .setCall _ _ _, h => by simp [SrcStmt.returns] at h
  | .then first second, h => by
    simp only [SrcStmt.returns, Bool.or_eq_true] at h
    rcases h with h | h
    · exact .sequenceLeft (returns_sound first h)
    · exact .sequenceRight (returns_sound second h)
  | .if _ thenBranch elseBranch, h => by
    simp only [SrcStmt.returns, Bool.and_eq_true] at h
    exact .ifThenElse (returns_sound thenBranch h.1) (returns_sound elseBranch h.2)
  | .while _ _, h => by simp [SrcStmt.returns] at h
  | .return _, _ => .returnValue
  | .letAlloc _ _ _ body, h => .letLocal (returns_sound body h)
  | .letLoad _ _ _ body, h => .letLocal (returns_sound body h)
  | .setByte _ _ _, h => by simp [SrcStmt.returns] at h
  | .free _ _ _, h => by simp [SrcStmt.returns] at h
  | .letSlice _ _ _ _ body, h => .letLocal (returns_sound body h)
  | .letIndex _ _ _ _ body, h => .letLocal (returns_sound body h)
  | .setIndex _ _ _, h => by simp [SrcStmt.returns] at h
  | .letEval _ _ _ body, h => .letLocal (returns_sound body h)
  | .setEval _ _, h => by simp [SrcStmt.returns] at h
  | .ifEval _ thenBranch elseBranch, h => by
    simp only [SrcStmt.returns, Bool.and_eq_true] at h
    exact .ifThenElse (returns_sound thenBranch h.1) (returns_sound elseBranch h.2)
  | .whileEval _ _, h => by simp [SrcStmt.returns] at h
  | .returnEval _, _ => .returnValue
  | .discard _, h => by simp [SrcStmt.returns] at h
  | .setIndexEval _ _ _, h => by simp [SrcStmt.returns] at h
  | .setFieldEval _ _ _, h => by simp [SrcStmt.returns] at h
  | .returnUnit, _ => .returnValue
  | .assert _, h => by simp [SrcStmt.returns] at h

/-! ## Types -/

theorem eq_i32 {ty : SrcType} (h : ty.isI32 = true) : ty = .i32 := by
  cases ty <;> simp_all [SrcType.isI32]

theorem eq_bool {ty : SrcType} (h : ty.isBool = true) : ty = .bool := by
  cases ty <;> simp_all [SrcType.isBool]

theorem eq_ptr {ty : SrcType} (h : ty.isPtr = true) : ty = .ptr := by
  cases ty <;> simp_all [SrcType.isPtr]

theorem eq_uint {ty : SrcType} {k : UintTy} (h : ty.isUint k = true) : ty = .uint k := by
  cases ty <;> simp only [SrcType.isUint, decide_eq_true_eq, reduceCtorEq] at h ⊢
  rename_i other
  cases other <;> cases k <;> simp_all [UintTy.code]

theorem eq_unit {ty : SrcType} (h : ty.isUnit = true) : ty = .unit := by
  cases ty <;> simp_all [SrcType.isUnit]

theorem eq_isize {ty : SrcType} (h : ty.isIsize = true) : ty = .isize := by
  cases ty <;> simp_all [SrcType.isIsize]

theorem eq_uintKind {ty : SrcType} {k : UintTy} (h : ty.uintKind = some k) : ty = .uint k := by
  cases ty <;> simp_all [SrcType.uintKind]

/-- Types the front pass calls the same are the same Core type. -/
theorem same_toCore : ∀ {a b : SrcType}, a.same b = true → a.toCore = b.toCore
  | .i32, b, h => by
    have := eq_i32 (ty := b) (by simpa [SrcType.same] using h)
    subst this; rfl
  | .bool, b, h => by
    have := eq_bool (ty := b) (by simpa [SrcType.same] using h)
    subst this; rfl
  | .uint k, b, h => by
    have := eq_uint (ty := b) (k := k) (by simpa [SrcType.same] using h)
    subst this; rfl
  | .ptr, b, h => by
    have := eq_ptr (ty := b) (by simpa [SrcType.same] using h)
    subst this; rfl
  | .struct id fields, b, h => by
    cases b <;> simp only [SrcType.same, Bool.and_eq_true, decide_eq_true_eq,
      Bool.false_eq_true] at h
    rw [h.1]; rfl
  | .enum id variants, b, h => by
    cases b <;> simp only [SrcType.same, Bool.and_eq_true, decide_eq_true_eq,
      Bool.false_eq_true] at h
    rw [h.1]; rfl
  | .slice element, b, h => by
    cases b <;> simp only [SrcType.same, Bool.false_eq_true] at h
    simp only [SrcType.toCore, same_toCore h]
  | .unit, b, h => by
    cases b <;> simp_all [SrcType.same, SrcType.isUnit]
  | .isize, b, h => by
    cases b <;> simp_all [SrcType.same, SrcType.isIsize]

/-- An integer type of the front pass. -/
inductive IsInt : SrcType → Prop where
  | i32 : IsInt .i32
  | uint (k : UintTy) : IsInt (.uint k)
  | isize : IsInt .isize

theorem IsInt.scalar {ty : SrcType} : IsInt ty → ty.isScalar = true
  | .i32 => rfl
  | .uint _ => rfl
  | .isize => rfl

theorem IsInt.arith {ty : SrcType} : IsInt ty → Typing.ArithmeticTy ty.toCore
  | .i32 => .signed _
  | .uint _ => .unsigned _
  | .isize => .signed _

theorem IsInt.integer {ty : SrcType} : IsInt ty → Typing.IntegerTy ty.toCore
  | .i32 => .signed _
  | .uint _ => .unsigned _
  | .isize => .signed _

theorem IsInt.ordered {ty : SrcType} : IsInt ty → Typing.OrderedTy ty.toCore
  | .i32 => .signed _
  | .uint _ => .unsigned _
  | .isize => .signed _

theorem equalityTy {ty : SrcType} (scalar : ty.isScalar = true) : Typing.EqualityTy ty.toCore := by
  cases ty with
  | i32 => exact .signed _
  | bool => exact .boolean
  | uint => exact .unsigned _
  | ptr => exact .pointer
  | struct => simp [SrcType.isScalar] at scalar
  | enum => simp [SrcType.isScalar] at scalar
  | slice => simp [SrcType.isScalar] at scalar
  | unit => simp [SrcType.isScalar] at scalar
  | isize => exact .signed _

/-! ## Operators -/

theorem arith_some {op : BinOp} {l r t : Typed} (h : arith op l r = some t) :
    l.ty = t.ty ∧ r.ty = t.ty ∧ IsInt t.ty := by
  unfold arith at h
  split at h
  · rename_i both
    simp only [Bool.and_eq_true] at both
    simp only [Option.some.injEq] at h
    subst h
    exact ⟨eq_i32 both.1, eq_i32 both.2, .i32⟩
  split at h
  · rename_i both
    simp only [Bool.and_eq_true] at both
    simp only [Option.some.injEq] at h
    subst h
    exact ⟨eq_isize both.1, eq_isize both.2, .isize⟩
  · unfold arithUint at h
    split at h
    · simp at h
    · rename_i k kind
      split at h
      · rename_i right
        simp only [Option.some.injEq] at h
        subst h
        exact ⟨eq_uintKind kind, eq_uint right, .uint k⟩
      · simp at h

theorem order_some {op : CmpOp} {l r t : Typed} (h : order op l r = some t) :
    l.ty.toCore = r.ty.toCore ∧ IsInt l.ty ∧ t.ty = .bool := by
  unfold order at h
  split at h
  · rename_i both
    simp only [Bool.and_eq_true] at both
    simp only [Option.some.injEq] at h
    subst h
    rw [eq_i32 both.1, eq_i32 both.2]
    exact ⟨rfl, .i32, rfl⟩
  split at h
  · rename_i both
    simp only [Bool.and_eq_true] at both
    simp only [Option.some.injEq] at h
    subst h
    rw [eq_isize both.1, eq_isize both.2]
    exact ⟨rfl, .isize, rfl⟩
  · unfold orderUint at h
    split at h
    · simp at h
    · rename_i k kind
      split at h
      · rename_i right
        simp only [Option.some.injEq] at h
        subst h
        rw [eq_uintKind kind, eq_uint right]
        exact ⟨rfl, .uint k, rfl⟩
      · simp at h

theorem equality_some {op : CmpOp} {l r t : Typed} (h : equality op l r = some t) :
    l.ty.toCore = r.ty.toCore ∧ t.ty = .bool := by
  unfold equality at h
  split at h
  · rename_i same
    simp only [Option.some.injEq] at h
    subst h
    exact ⟨same_toCore same, rfl⟩
  · simp at h

theorem conjunction_some {l r t : Typed} (h : conjunction l r = some t) :
    l.ty = .bool ∧ r.ty = .bool ∧ t.ty = .bool := by
  unfold conjunction at h
  split at h
  · rename_i both
    simp only [Bool.and_eq_true] at both
    simp only [Option.some.injEq] at h
    subst h
    exact ⟨eq_bool both.1, eq_bool both.2, rfl⟩
  · simp at h

theorem disjunction_some {l r t : Typed} (h : disjunction l r = some t) :
    l.ty = .bool ∧ r.ty = .bool ∧ t.ty = .bool := by
  unfold disjunction at h
  split at h
  · rename_i both
    simp only [Bool.and_eq_true] at both
    simp only [Option.some.injEq] at h
    subst h
    exact ⟨eq_bool both.1, eq_bool both.2, rfl⟩
  · simp at h

theorem arith_typed {op : BinOp} {cop : Core.BinaryOp} {l r t : Typed}
    (rule : ∀ {T : Core.Ty}, Typing.ArithmeticTy T → Typing.IntegerTy T →
      Typing.BinaryOpHasType cop T T T)
    (h : arith op l r = some t) :
    Typing.BinaryOpHasType cop l.ty.toCore r.ty.toCore t.ty.toCore ∧ t.ty.isScalar = true := by
  obtain ⟨hl, hr, int⟩ := arith_some h
  rw [hl, hr]
  exact ⟨rule int.arith int.integer, int.scalar⟩

theorem order_typed {op : CmpOp} {cop : Core.BinaryOp} {l r t : Typed}
    (rule : ∀ {T : Core.Ty}, Typing.OrderedTy T → Typing.BinaryOpHasType cop T T (.scalar .bool))
    (h : order op l r = some t) :
    Typing.BinaryOpHasType cop l.ty.toCore r.ty.toCore t.ty.toCore ∧ t.ty.isScalar = true := by
  obtain ⟨same, int, ht⟩ := order_some h
  rw [ht, ← same]
  exact ⟨rule int.ordered, rfl⟩

theorem equality_typed {op : CmpOp} {cop : Core.BinaryOp} {l r t : Typed}
    (rule : ∀ {T : Core.Ty}, Typing.EqualityTy T → Typing.BinaryOpHasType cop T T (.scalar .bool))
    (scalar : l.ty.isScalar = true) (h : equality op l r = some t) :
    Typing.BinaryOpHasType cop l.ty.toCore r.ty.toCore t.ty.toCore ∧ t.ty.isScalar = true := by
  obtain ⟨same, ht⟩ := equality_some h
  rw [ht, ← same]
  exact ⟨rule (equalityTy scalar), rfl⟩

theorem SrcOp.lower_typed {op : SrcOp} {l r t : Typed} (scalar : l.ty.isScalar = true)
    (h : op.lower l r = some t) :
    Typing.BinaryOpHasType op.toCore l.ty.toCore r.ty.toCore t.ty.toCore ∧ t.ty.isScalar = true := by
  cases op with
  | plus =>
    rcases offsetOrArith_some h with ⟨hl, hr, rfl⟩ | h
    · rw [hl, hr]
      exact ⟨.pointerAdd (.unsigned _), rfl⟩
    · exact arith_typed (fun a _ => .add a) h
  | minus =>
    rcases offsetOrArith_some h with ⟨hl, hr, rfl⟩ | h
    · rw [hl, hr]
      exact ⟨.pointerSubtract (.unsigned _), rfl⟩
    · exact arith_typed (fun a _ => .subtract a) h
  | times => exact arith_typed (fun a _ => .multiply a) h
  | bitAnd => exact arith_typed (fun _ i => .bitAnd i) h
  | bitOr => exact arith_typed (fun _ i => .bitOr i) h
  | bitXor => exact arith_typed (fun _ i => .bitXor i) h
  | less => exact order_typed .less h
  | lessEq => exact order_typed .lessEqual h
  | greater => exact order_typed .greater h
  | greaterEq => exact order_typed .greaterEqual h
  | equal => exact equality_typed .equal scalar h
  | notEqual => exact equality_typed .notEqual scalar h
  | logicalAnd =>
    obtain ⟨hl, hr, ht⟩ := conjunction_some h
    rw [hl, hr, ht]
    exact ⟨.logicalAnd, rfl⟩
  | logicalOr =>
    obtain ⟨hl, hr, ht⟩ := disjunction_some h
    rw [hl, hr, ht]
    exact ⟨.logicalOr, rfl⟩

/-! ## Scopes and expressions -/

/-- Every binding the scope finds has its Core type in the context, and its
type is declared. -/
def ScopeOk (P : Core.Program) (ctx : Typing.Context) (scope : List Binding) : Prop :=
  ∀ id b, lookup scope id = some b → ctx id = some b.ty.toCore ∧ TypeDeclared P b.ty

theorem ScopeOk.cons {P : Core.Program} {ctx : Typing.Context} {scope : List Binding}
    (ok : ScopeOk P ctx scope) {id slot : Nat} {ty : SrcType} (declared : TypeDeclared P ty) :
    ScopeOk P (ctx.bind id ty.toCore) ({ id := id, slot := slot, ty := ty } :: scope) := by
  intro x b found
  simp only [lookup] at found
  split at found
  · rename_i same
    simp only [Option.some.injEq] at found
    subst found
    subst same
    simp [Typing.Context.bind, declared]
  · rename_i other
    have := ok x b found
    simp only [Typing.Context.bind]
    rw [if_neg (by simp only [beq_iff_eq]; exact fun h => other h.symm)]
    exact this

theorem i32_literal {P : Core.Program} (target : P.target = Core.Target.x86_64) (v : BitVec 32) :
    Typing.ValueHasType P (.signed .i32 v.toInt) (.scalar (.signed .i32)) := by
  refine .signed .i32 v.toInt ?_ ?_
  · rw [target]
    have := BitVec.le_toInt v
    simp only [Typing.signedMin, Core.SignedIntTy.bits]
    simpa using this
  · rw [target]
    have := BitVec.toInt_lt (x := v)
    simp only [Typing.signedMax, Core.SignedIntTy.bits]
    simp at this
    omega

theorem uint_literal {P : Core.Program} (target : P.target = Core.Target.x86_64) (kind : UintTy)
    {value : BitVec 64} (le : value ≤ kind.mask) :
    Typing.ValueHasType P (.unsigned kind.toCore value.toNat) (.scalar (.unsigned kind.toCore)) := by
  refine .unsigned _ _ ?_
  rw [target]
  rw [BitVec.le_def] at le
  have := value.isLt
  cases kind <;> simp_all [UintTy.mask, UintTy.toCore, Typing.unsignedMax, Core.UnsignedIntTy.bits,
    Core.Target.x86_64, Core.PointerWidth.bits] <;> omega

theorem declared_struct {P : Core.Program} {id : Nat} {fields : List SrcType}
    (declared : TypeDeclared P (.struct id fields)) :
    P.structure? id = some ⟨id, fields.map SrcType.toCore⟩ ∧ ∀ f ∈ fields, TypeDeclared P f := by
  cases declared with
  | struct found inner => exact ⟨found, inner⟩

theorem declared_enum {P : Core.Program} {id : Nat} {variants : List (List SrcType)}
    (declared : TypeDeclared P (.enum id variants)) :
    P.enumeration? id = some ⟨id, variants.map (List.map SrcType.toCore)⟩ ∧
      ∀ fs ∈ variants, ∀ f ∈ fs, TypeDeclared P f := by
  cases declared with
  | enum found inner => exact ⟨found, inner⟩

/-- Field `index` of a struct local, at its Core type. -/
theorem field_typed {P : Core.Program} {ctx : Typing.Context} {scope : List Binding}
    (ok : ScopeOk P ctx scope) {id : Nat} {b : Binding} (found : lookup scope id = some b)
    {sid : Nat} {fields : List SrcType} (hty : b.ty = .struct sid fields) {index : Nat} {f : SrcType}
    (hf : fields[index]? = some f) :
    ExprHasType P ctx (.field (.local id) index) f.toCore ∧ TypeDeclared P f := by
  obtain ⟨inCtx, declared⟩ := ok id b found
  rw [hty] at inCtx declared
  obtain ⟨decl, inner⟩ := declared_struct declared
  exact ⟨.field (.local inCtx) _ decl (by simp [hf]), inner f (List.mem_of_getElem? hf)⟩

theorem SrcExpr.lower_typed {P : Core.Program} (target : P.target = Core.Target.x86_64) :
    ∀ (e : SrcExpr) {scope : List Binding} {ctx : Typing.Context} {t : Typed}, ScopeOk P ctx scope →
      e.lower scope = some t → ExprHasType P ctx e.toCore t.ty.toCore ∧ t.ty.isScalar = true
  | .int v, _, _, _, _, h => by
    simp only [SrcExpr.lower, Option.some.injEq] at h
    subst h
    exact ⟨.value (i32_literal target v) rfl, rfl⟩
  | .boolean v, _, _, _, _, h => by
    simp only [SrcExpr.lower, Option.some.injEq] at h
    subst h
    exact ⟨.value (.boolean v) rfl, rfl⟩
  | .unsigned kind v, _, _, _, _, h => by
    simp only [SrcExpr.lower, lowerUnsigned] at h
    split at h
    · rename_i le
      simp only [Option.some.injEq] at h
      subst h
      exact ⟨.value (uint_literal target kind le) rfl, rfl⟩
    · simp at h
  | .local id, scope, ctx, t, ok, h => by
    simp only [SrcExpr.lower, lowerLocal] at h
    split at h
    · simp at h
    · rename_i b found
      simp only [lowerScalarLocal] at h
      split at h
      · rename_i scalar
        simp only [Option.some.injEq] at h
        subst h
        exact ⟨.local (ok id b found).1, scalar⟩
      · simp at h
  | .field id index, scope, ctx, t, ok, h => by
    simp only [SrcExpr.lower, lowerField] at h
    split at h
    · simp at h
    · rename_i b found
      simp only [lowerFieldOf] at h
      split at h
      · simp at h
      · simp at h
      · simp at h
      · rename_i sid fields hty
        simp only [lowerFieldAt] at h
        split at h
        · simp at h
        · rename_i f hf
          split at h
          · rename_i scalar
            simp only [Option.some.injEq] at h
            subst h
            exact ⟨(field_typed ok found hty hf).1, scalar⟩
          · simp at h
      all_goals simp at h
  | .negate operand, scope, ctx, t, ok, h => by
    simp only [SrcExpr.lower, lowerNegate] at h
    split at h
    · simp at h
    · rename_i o lowered
      simp only [lowerNegateTyped] at h
      split at h
      · rename_i isI32
        simp only [Option.some.injEq] at h
        subst h
        have inner := (SrcExpr.lower_typed target operand ok lowered).1
        rw [eq_i32 isI32] at inner
        exact ⟨.unary inner (.negate (.signed _)), rfl⟩
      split at h
      · rename_i isIsize
        simp only [Option.some.injEq] at h
        subst h
        have inner := (SrcExpr.lower_typed target operand ok lowered).1
        rw [eq_isize isIsize] at inner
        exact ⟨.unary inner (.negate (.signed _)), rfl⟩
      · simp at h
  | .not operand, scope, ctx, t, ok, h => by
    simp only [SrcExpr.lower, lowerNot] at h
    split at h
    · simp at h
    · rename_i o lowered
      simp only [lowerNotTyped] at h
      split at h
      · rename_i isBool
        simp only [Option.some.injEq] at h
        subst h
        have inner := (SrcExpr.lower_typed target operand ok lowered).1
        rw [eq_bool isBool] at inner
        exact ⟨.unary inner .logicalNot, rfl⟩
      · simp at h
  | .apply op left right, scope, ctx, t, ok, h => by
    simp only [SrcExpr.lower, lowerApply] at h
    split at h
    · simp at h
    · rename_i l loweredL
      split at h
      · simp at h
      · rename_i r loweredR
        obtain ⟨typedL, scalarL⟩ := SrcExpr.lower_typed target left ok loweredL
        have typedR := (SrcExpr.lower_typed target right ok loweredR).1
        obtain ⟨rule, scalar⟩ := SrcOp.lower_typed scalarL h
        exact ⟨.binary typedL typedR rule, scalar⟩
  | .cast ty operand, scope, ctx, t, ok, h => by
    simp only [SrcExpr.lower, lowerCast] at h
    split at h
    · simp at h
    · rename_i o lowered
      have inner := (SrcExpr.lower_typed target operand ok lowered).1
      cases ty with
      | i32 =>
        simp only [castTo, castToI32] at h
        split at h
        · rename_i hty
          simp only [Option.some.injEq] at h
          subst h
          rw [hty] at inner ⊢
          exact ⟨.cast inner (.signedToSigned _ _), rfl⟩
        · simp at h
        · rename_i k hty
          simp only [Option.some.injEq] at h
          subst h
          rw [hty] at inner
          exact ⟨.cast inner (.unsignedToSigned _ _), rfl⟩
        all_goals first
          | (simp at h; done)
          | (rename_i hty
             simp only [Option.some.injEq] at h
             subst h
             rw [hty] at inner
             exact ⟨.cast inner (.signedToSigned _ _), rfl⟩)
      | uint kind =>
        simp only [castTo, castToUint] at h
        split at h
        · rename_i hty
          simp only [Option.some.injEq] at h
          subst h
          rw [hty] at inner
          exact ⟨.cast inner (.signedToUnsigned _ _), rfl⟩
        · simp at h
        · rename_i k hty
          simp only [Option.some.injEq] at h
          subst h
          rw [hty] at inner
          exact ⟨.cast inner (.unsignedToUnsigned _ _), rfl⟩
        all_goals first
          | (simp at h; done)
          | (rename_i hty
             simp only [Option.some.injEq] at h
             subst h
             rw [hty] at inner
             exact ⟨.cast inner (.signedToUnsigned _ _), rfl⟩)
      | isize =>
        simp only [castTo, castToIsize] at h
        split at h
        · rename_i hty
          simp only [Option.some.injEq] at h
          subst h
          rw [hty] at inner
          exact ⟨.cast inner (.signedToSigned _ _), rfl⟩
        · simp at h
        · rename_i k hty
          simp only [Option.some.injEq] at h
          subst h
          rw [hty] at inner
          exact ⟨.cast inner (.unsignedToSigned _ _), rfl⟩
        all_goals first
          | (simp at h; done)
          | (rename_i hty
             simp only [Option.some.injEq] at h
             subst h
             rw [hty] at inner ⊢
             exact ⟨.cast inner (.signedToSigned _ _), rfl⟩)
      | bool => simp [castTo] at h
      | struct => simp [castTo] at h
      | enum => simp [castTo] at h
      | ptr => simp [castTo] at h
      | slice => simp [castTo] at h
      | unit => simp [castTo] at h

theorem lowerAs_typed {P : Core.Program} (target : P.target = Core.Target.x86_64)
    {scope : List Binding} {ctx : Typing.Context} (ok : ScopeOk P ctx scope) {e : SrcExpr}
    {ty : SrcType} {x : Expr} (h : lowerAs scope e ty = some x) : ExprHasType P ctx e.toCore ty.toCore := by
  unfold lowerAs at h
  split at h
  · simp at h
  · rename_i t lowered
    unfold expectType at h
    split at h
    · rename_i same
      rw [← same_toCore same]
      exact (SrcExpr.lower_typed target e ok lowered).1
    · simp at h

/-- A value lowered slot by slot has its type in Core. -/
theorem lowerValue_typed {P : Core.Program} (target : P.target = Core.Target.x86_64)
    {scope : List Binding} {ctx : Typing.Context} (ok : ScopeOk P ctx scope) {e : SrcExpr}
    {ty : SrcType} {xs : List Expr} (h : lowerValue scope e ty = some xs) :
    ExprHasType P ctx e.toCore ty.toCore := by
  unfold lowerValue at h
  split at h
  · unfold lowerSingle at h
    split at h
    · simp at h
    · rename_i x hx
      exact lowerAs_typed target ok hx
  · cases e with
    | «local» id =>
      simp only [lowerCopy, copyBinding] at h
      split at h
      · simp at h
      · rename_i b found
        split at h
        · rename_i same
          rw [← same_toCore same]
          exact .local (ok id b found).1
        · simp at h
    | field id index =>
      simp only [lowerCopy, copyField] at h
      split at h
      · simp at h
      · rename_i b found
        simp only [copyFieldOf] at h
        split at h
        · simp at h
        · simp at h
        · simp at h
        · rename_i sid fields hty
          simp only [copyFieldAt] at h
          split at h
          · simp at h
          · rename_i f hf
            split at h
            · rename_i cond
              simp only [Bool.and_eq_true] at cond
              rw [← same_toCore cond.1]
              exact (field_typed ok found hty hf).1
            · simp at h
        all_goals simp at h
    | int => simp [lowerCopy] at h
    | boolean => simp [lowerCopy] at h
    | unsigned => simp [lowerCopy] at h
    | negate => simp [lowerCopy] at h
    | not => simp [lowerCopy] at h
    | apply => simp [lowerCopy] at h
    | cast => simp [lowerCopy] at h

theorem lowerArgs_typed {P : Core.Program} (target : P.target = Core.Target.x86_64)
    {scope : List Binding} {ctx : Typing.Context} (ok : ScopeOk P ctx scope) :
    ∀ (args : List SrcExpr) (types : List SrcType) {xs : List Expr}, lowerArgs scope args types = some xs →
      ExprsHaveTypes P ctx (args.map SrcExpr.toCore) (types.map SrcType.toCore)
  | [], [], _, _ => .nil
  | [], _ :: _, _, h => by simp [lowerArgs] at h
  | _ :: _, [], _, h => by simp [lowerArgs] at h
  | arg :: rest, ty :: more, _, h => by
    simp only [lowerArgs, lowerAppend] at h
    split at h
    · simp at h
    · rename_i es hes
      split at h
      · simp at h
      · rename_i ms hms
        exact .cons (lowerValue_typed target ok hes) (lowerArgs_typed target ok rest more hms)

/-! ## Calls -/

/-- Each signature is its function's Core signature. -/
def SigsOk (P : Core.Program) (sigs : List Sig) : Prop :=
  ∀ callee sig, sigs[callee]? = some sig → ∃ f, P.function? callee = some f ∧
    f.parameters.map Prod.snd = sig.params.map SrcType.toCore ∧ f.returnType = sig.ret.toCore

theorem lowerCall_typed {P : Core.Program} (target : P.target = Core.Target.x86_64)
    {sigs : List Sig} (sigsOk : SigsOk P sigs) {scope : List Binding} {ctx : Typing.Context}
    (ok : ScopeOk P ctx scope) {callee : Nat} {args : List SrcExpr} {ty : SrcType} {xs : List Expr}
    (h : lowerCall sigs scope callee args ty = some xs) :
    ExprHasType P ctx (.call callee (args.map SrcExpr.toCore)) ty.toCore := by
  unfold lowerCall at h
  split at h
  · simp at h
  · rename_i sig hsig
    unfold lowerCallSig at h
    split at h
    · rename_i same
      obtain ⟨f, found, params, ret⟩ := sigsOk callee sig hsig
      have call := ExprHasType.call f found (by rw [params]; exact lowerArgs_typed target ok _ _ h)
      rw [ret, same_toCore same] at call
      exact call
    · simp at h

/-! ## Struct and enum values -/

theorem lowerLiteral_typed {P : Core.Program} (target : P.target = Core.Target.x86_64)
    {scope : List Binding} {ctx : Typing.Context} (ok : ScopeOk P ctx scope) {ty : SrcType}
    (declared : TypeDeclared P ty) {fields : List SrcExpr} {xs : List Expr}
    (h : lowerLiteral scope ty fields = some xs) :
    ExprHasType P ctx (.structValue ty.typeId (fields.map SrcExpr.toCore)) ty.toCore := by
  cases ty with
  | struct sid types =>
    simp only [lowerLiteral, lowerStructFields] at h
    split at h
    · simp at h
    · exact .structValue _ (declared_struct declared).1 (lowerArgs_typed target ok _ _ h)
  | i32 => simp [lowerLiteral] at h
  | bool => simp [lowerLiteral] at h
  | uint => simp [lowerLiteral] at h
  | enum => simp [lowerLiteral] at h
  | ptr => simp [lowerLiteral] at h
  | slice => simp [lowerLiteral] at h
  | unit => simp [lowerLiteral] at h
  | isize => simp [lowerLiteral] at h

theorem lowerEnumValue_typed {P : Core.Program} (target : P.target = Core.Target.x86_64)
    {scope : List Binding} {ctx : Typing.Context} (ok : ScopeOk P ctx scope) {ty : SrcType}
    (declared : TypeDeclared P ty) {variant : Nat} {payload : List SrcExpr} {xs : List Expr}
    (h : lowerEnumValue scope ty variant payload = some xs) :
    ExprHasType P ctx (.enumValue ty.typeId variant (payload.map SrcExpr.toCore)) ty.toCore := by
  cases ty with
  | enum eid variants =>
    simp only [lowerEnumValue, lowerTagged] at h
    split at h
    · simp only [lowerVariant] at h
      split at h
      · simp at h
      · rename_i types found
        simp only [lowerTag] at h
        split at h
        · simp at h
        · rename_i es hes
          exact .enumValue _ (declared_enum declared).1 (by simp [found])
            (lowerArgs_typed target ok _ _ hes)
    · simp at h
  | i32 => simp [lowerEnumValue] at h
  | bool => simp [lowerEnumValue] at h
  | uint => simp [lowerEnumValue] at h
  | struct => simp [lowerEnumValue] at h
  | ptr => simp [lowerEnumValue] at h
  | slice => simp [lowerEnumValue] at h
  | unit => simp [lowerEnumValue] at h
  | isize => simp [lowerEnumValue] at h

/-! ## Match -/

/-- An arm's binders bind its variant's payload types, in order, as Core's
pattern typing does. -/
theorem armScope_ok {P : Core.Program} :
    ∀ (binders : List Nat) (types : List SrcType) {slot : Nat} {scope scope' : List Binding}
      {ctx : Typing.Context}, ScopeOk P ctx scope → (∀ f ∈ types, TypeDeclared P f) →
      armScope binders types slot scope = some scope' →
      ScopeOk P (ctx.bindAll (binders.zip (types.map SrcType.toCore))) scope' ∧
        Typing.PatternsHaveTypes P (binders.map Core.Pattern.bind) (types.map SrcType.toCore)
          (binders.zip (types.map SrcType.toCore))
  | [], [], _, _, _, _, ok, _, h => by
    simp only [armScope, Option.some.injEq] at h
    subst h
    exact ⟨ok, .nil⟩
  | [], _ :: _, _, _, _, _, _, _, h => by simp [armScope] at h
  | _ :: _, [], _, _, _, _, _, _, h => by simp [armScope] at h
  | binder :: rest, ty :: more, slot, scope, scope', ctx, ok, declared, h => by
    simp only [armScope] at h
    split at h
    · have tail := armScope_ok rest more (ok.cons (id := binder) (slot := slot) (declared ty (by simp)))
        (fun f hf => declared f (by simp [hf])) h
      exact ⟨tail.1, .cons (.bind binder) tail.2⟩
    · simp at h

theorem lowerArms_typed {P : Core.Program} (target : P.target = Core.Target.x86_64)
    {scope : List Binding} {ctx : Typing.Context} (ok : ScopeOk P ctx scope)
    {slot tgt enumId : Nat} {ty : SrcType} {decl : Core.EnumDecl}
    (found : P.enumeration? enumId = some decl) :
    ∀ (k : Nat) (variants : List (List SrcType)) (arms : List SrcArm) {out : Stmt},
      (∀ j fs, variants[j]? = some fs → decl.variants[k + j]? = some (fs.map SrcType.toCore)) →
      (∀ fs ∈ variants, ∀ f ∈ fs, TypeDeclared P f) →
      lowerArms scope slot tgt ty k variants arms = some out →
      Typing.MatchArmsHaveType P ctx (coreArms enumId k arms) (.enumeration enumId) ty.toCore
  | _, _, [], _, _, _, h => by simp [lowerArms] at h
  | _, [], _ :: _, _, _, _, h => by simp [lowerArms] at h
  | k, types :: more, arm :: rest, out, vars, declared, h => by
    simp only [lowerArms] at h
    generalize hv : lowerArmValue (armScope arm.binders types (slot + 1) scope) arm.value ty = values at h
    cases values with
    | none => simp [lowerArm] at h
    | some vs =>
      unfold lowerArmValue at hv
      split at hv
      · simp at hv
      · rename_i scope' hscope
        obtain ⟨ok', pats⟩ := armScope_ok arm.binders types ok (declared types (by simp)) hscope
        have body := lowerValue_typed target ok' hv
        have variantFound : decl.variants[k]? = some (types.map SrcType.toCore) := by
          simpa using vars 0 types (by simp)
        have pat := Typing.PatternHasType.enumVariant decl found variantFound pats
        cases rest with
        | nil => exact .one pat body
        | cons next others =>
          simp only [lowerArm] at h
          split at h
          · simp at h
          · rename_i o ho
            have tail := lowerArms_typed target ok found (k + 1) more (next :: others)
              (fun j fs hj => by
                have := vars (j + 1) fs (by simpa using hj)
                rwa [show k + (j + 1) = k + 1 + j by omega] at this)
              (fun fs hfs => declared fs (by simp [hfs])) ho
            exact .cons pat body tail

theorem lowerMatch_typed {P : Core.Program} (target : P.target = Core.Target.x86_64)
    {scope : List Binding} {ctx : Typing.Context} (ok : ScopeOk P ctx scope)
    {scrutinee enumId tgt : Nat} {arms : List SrcArm} {ty : SrcType} {out : Stmt}
    (h : lowerMatch scope (lookup scope scrutinee) enumId arms ty tgt = some out) :
    ExprHasType P ctx (.matchValue (.local scrutinee) (coreArms enumId 0 arms)) ty.toCore := by
  unfold lowerMatch at h
  split at h
  · simp at h
  · rename_i b found
    unfold lowerMatchOn at h
    split at h
    · simp at h
    · simp at h
    · simp at h
    · simp at h
    · rename_i eid variants hty
      unfold lowerMatchArms at h
      split at h
      · rename_i cond
        simp only [Bool.and_eq_true, decide_eq_true_eq] at cond
        obtain ⟨⟨⟨same, _⟩, _⟩, _⟩ := cond
        subst same
        obtain ⟨inCtx, declared⟩ := ok scrutinee b found
        rw [hty] at inCtx declared
        obtain ⟨decl, inner⟩ := declared_enum declared
        exact .matchValue (.local inCtx)
          (lowerArms_typed target ok decl 0 variants arms (fun j fs hj => by simp [hj]) inner h)
      · simp at h
    · simp at h
    · simp at h
    · simp at h
    · simp at h

/-! ## Statements -/

theorem align_literal {P : Core.Program} (target : P.target = Core.Target.x86_64) {shift : Nat}
    (small : shift < 32) :
    ExprHasType P ctx (.value (.unsigned .usize (2 ^ shift))) (.scalar (.unsigned .usize)) := by
  refine .value (.unsigned _ _ ?_) rfl
  rw [target]
  have : 2 ^ shift ≤ 2 ^ 32 := Nat.pow_le_pow_right (by omega) (by omega)
  simp only [Typing.unsignedMax, Core.UnsignedIntTy.bits, Core.Target.x86_64, Core.PointerWidth.bits]
  omega

theorem lowerAddress_some {p o : Option Expr} {a : Expr} (h : lowerAddress p o = some a) :
    ∃ x y, p = some x ∧ o = some y := by
  unfold lowerAddress at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · exact ⟨_, _, rfl, rfl⟩

theorem elementWidths_struct {ds : SrcDecls} {e : SrcType} {ws : List MemWidth} (h : elementWidths ds e = some ws) :
    ∃ id fields, e = .struct id fields := by
  cases e with
  | struct id fields => exact ⟨id, fields, rfl⟩
  | i32 | bool | uint | enum | ptr | slice | unit | isize => simp [elementWidths] at h

theorem enumWidths_enum {ds : SrcDecls} {e : SrcType} {wss : List (List MemWidth)}
    (h : enumWidths ds e = some wss) : ∃ id variants, e = .enum id variants := by
  cases e with
  | enum id variants => exact ⟨id, variants, rfl⟩
  | i32 | bool | uint | struct | ptr | slice | unit | isize => simp [enumWidths] at h

theorem lowerSlice_some {ds : SrcDecls} {element : SrcType} {p l : Option Expr} {xs : List Expr}
    (h : lowerSlice ds element p l = some xs) :
    (element = .i32 ∨ (∃ id fields, element = .struct id fields) ∨ ∃ id variants, element = .enum id variants) ∧
      ∃ x y, p = some x ∧ l = some y := by
  unfold lowerSlice at h
  split at h
  · rename_i cond
    have kind : element = .i32 ∨ (∃ id fields, element = .struct id fields) ∨
        ∃ id variants, element = .enum id variants := by
      simp only [Bool.or_eq_true] at cond
      rcases cond with (c | c) | c
      · exact .inl (eq_i32 c)
      · right; left
        unfold isWordStruct at c
        split at c
        · simp at c
        · rename_i ws hws
          exact elementWidths_struct hws
      · right; right
        unfold isWordEnum at c
        split at c
        · simp at c
        · rename_i wss hwss
          exact enumWidths_enum hwss
    split at h
    · simp at h
    · split at h
      · simp at h
      · exact ⟨kind, _, _, rfl, rfl⟩
  · simp at h

/-- An index the front pass accepts is an `i32` or a `usize`, both integer
types in Core. -/
theorem lowerIndex_typed {P : Core.Program} (target : P.target = Core.Target.x86_64)
    {scope : List Binding} {ctx : Typing.Context} (ok : ScopeOk P ctx scope) {index : SrcExpr}
    {i : Expr} (h : lowerIndex scope index = some i) :
    ∃ T, ExprHasType P ctx index.toCore T ∧ Typing.IntegerTy T := by
  unfold lowerIndex at h
  split at h
  · simp at h
  · rename_i t lowered
    unfold indexOf at h
    split at h
    · rename_i cond
      refine ⟨t.ty.toCore, (SrcExpr.lower_typed target index ok lowered).1, ?_⟩
      simp only [Bool.or_eq_true] at cond
      rcases cond with c | c
      · rw [eq_i32 c]; exact .signed _
      · rw [eq_uint c]; exact .unsigned _
    · simp at h

theorem elementOf_some {ty e : SrcType} (h : elementOf ty = some e) : ty = .slice e := by
  cases ty <;> simp_all [elementOf]

theorem elementAddress_some {b : Binding} {index : Option Expr} {a : Expr}
    (h : elementAddress b index = some a) : ∃ e i, b.ty = .slice e ∧ index = some i := by
  unfold elementAddress at h
  split at h
  · simp at h
  · rename_i e he
    split at h
    · simp at h
    · exact ⟨e, _, elementOf_some he, rfl⟩

/-! ## Effectful expressions -/

theorem typesSame_toCore : ∀ {a b : List SrcType}, typesSame a b = true →
    a.map SrcType.toCore = b.map SrcType.toCore
  | [], [], _ => rfl
  | [], _ :: _, h => by simp [typesSame] at h
  | _ :: _, [], h => by simp [typesSame] at h
  | x :: xs, y :: ys, h => by
    simp only [typesSame, Bool.and_eq_true] at h
    simp only [List.map_cons, same_toCore h.1, typesSame_toCore h.2]

theorem castTo_typed {P : Core.Program} {ctx : Typing.Context} {ce : Core.Expr} {ty : SrcType} {o t : Typed}
    (inner : ExprHasType P ctx ce o.ty.toCore) (h : castTo ty o = some t) :
    ExprHasType P ctx (.cast ty.toScalar ce) t.ty.toCore := by
  cases ty with
  | i32 =>
    simp only [castTo, castToI32] at h
    split at h
    · rename_i hty
      simp only [Option.some.injEq] at h
      subst h
      rw [hty] at inner ⊢
      exact .cast inner (.signedToSigned _ _)
    · simp at h
    · rename_i k hty
      simp only [Option.some.injEq] at h
      subst h
      rw [hty] at inner
      exact .cast inner (.unsignedToSigned _ _)
    all_goals first
      | (simp at h; done)
      | (rename_i hty
         simp only [Option.some.injEq] at h
         subst h
         rw [hty] at inner
         exact .cast inner (.signedToSigned _ _))
  | uint kind =>
    simp only [castTo, castToUint] at h
    split at h
    · rename_i hty
      simp only [Option.some.injEq] at h
      subst h
      rw [hty] at inner
      exact .cast inner (.signedToUnsigned _ _)
    · simp at h
    · rename_i k hty
      simp only [Option.some.injEq] at h
      subst h
      rw [hty] at inner
      exact .cast inner (.unsignedToUnsigned _ _)
    all_goals first
      | (simp at h; done)
      | (rename_i hty
         simp only [Option.some.injEq] at h
         subst h
         rw [hty] at inner
         exact .cast inner (.signedToUnsigned _ _))
  | isize =>
    simp only [castTo, castToIsize] at h
    split at h
    · rename_i hty
      simp only [Option.some.injEq] at h
      subst h
      rw [hty] at inner
      exact .cast inner (.signedToSigned _ _)
    · simp at h
    · rename_i k hty
      simp only [Option.some.injEq] at h
      subst h
      rw [hty] at inner
      exact .cast inner (.unsignedToSigned _ _)
    all_goals first
      | (simp at h; done)
      | (rename_i hty
         simp only [Option.some.injEq] at h
         subst h
         rw [hty] at inner ⊢
         exact .cast inner (.signedToSigned _ _))
  | bool => simp [castTo] at h
  | struct => simp [castTo] at h
  | enum => simp [castTo] at h
  | ptr => simp [castTo] at h
  | slice => simp [castTo] at h
  | unit => simp [castTo] at h

/-- An element read of a word struct or enum slice has the element's type. -/
theorem evalWordElement_ty {decls : SrcDecls} {b : Binding} {element : SrcType} {slot : Nat}
    {i ev : Evaluated} (h : evalWordElement decls b element slot i = some ev) :
    ev.ty = element ∧ (i.ty.isI32 || i.ty.isUint .usize) = true := by
  simp only [evalWordElement] at h
  split at h
  · simp only [evalFields] at h
    split at h
    · rename_i c
      simp only [Option.some.injEq] at h
      subst h
      exact ⟨rfl, c⟩
    · simp at h
  · split at h
    · simp at h
    · simp only [evalEnumElement] at h
      split at h
      · rename_i c
        simp only [Option.some.injEq] at h
        subst h
        exact ⟨rfl, c⟩
      · simp at h

mutual

theorem SrcEff.eval_typed {P : Core.Program} (target : P.target = Core.Target.x86_64)
    {sigs : List Sig} {decls : SrcDecls} (sigsOk : SigsOk P sigs) :
    ∀ (e : SrcEff) {scope : List Binding} {ctx : Typing.Context} {slot : Nat} {ev : Evaluated},
      ScopeOk P ctx scope → (∀ t ∈ e.types, TypeDeclared P t) → e.eval sigs decls scope slot = some ev →
        ExprHasType P ctx e.toCore ev.ty.toCore
  | .ePure e, scope, ctx, slot, ev, ok, dd, h => by
    simp only [SrcEff.eval, evalPure] at h
    split at h
    · rename_i t lowered
      simp only [evalScalar, Option.some.injEq] at h
      subst h
      exact (SrcExpr.lower_typed target e ok lowered).1
    · cases e with
      | «local» id =>
        simp only [evalCopy] at h
        split at h
        · simp at h
        · rename_i b found
          simp only [evalValues] at h
          split at h
          · simp at h
          · rename_i xs hxs
            simp only [Option.some.injEq] at h
            subst h
            exact lowerValue_typed target ok hxs
      | int => simp at h
      | boolean => simp at h
      | unsigned => simp at h
      | field => simp at h
      | negate => simp at h
      | not => simp at h
      | apply => simp at h
      | cast => simp at h
  | .eCall callee args, scope, ctx, slot, ev, ok, dd, h => by
    simp only [SrcEff.eval, evalCall] at h
    split at h
    · simp at h
    · rename_i sig hsig
      split at h
      · simp at h
      · rename_i ea hea
        simp only [evalCallSig] at h
        split at h
        · rename_i checks
          simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
          simp only [Option.some.injEq] at h
          subst h
          obtain ⟨f, found, params, ret⟩ := sigsOk callee sig hsig
          have typedArgs := evalArgs_typed target sigsOk args ok (by simpa [SrcEff.types] using dd) hea
          rw [typesSame_toCore checks.1, ← params] at typedArgs
          have call := ExprHasType.call f found typedArgs
          rw [ret] at call
          exact call
        · simp at h
  | .eApply op left right, scope, ctx, slot, ev, ok, dd, h => by
    simp only [SrcEff.eval, evalApply] at h
    split at h
    · simp at h
    · rename_i l hl
      split at h
      · simp at h
      · rename_i r hr
        have typedL := SrcEff.eval_typed target sigsOk left ok (fun t mem => dd t (by simp [SrcEff.types, mem])) hl
        have typedR := SrcEff.eval_typed target sigsOk right ok (fun t mem => dd t (by simp [SrcEff.types, mem])) hr
        simp only [evalOperands] at h
        split at h
        · rename_i checks
          simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
          split at h
          · simp at h
          · rename_i t lowered
            simp only [Option.some.injEq] at h
            subst h
            exact .binary typedL typedR (SrcOp.lower_typed checks.1.1 lowered).1
        · split at h
          · rename_i checks
            simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
            simp only [Option.some.injEq] at h
            subst h
            have opEq : op = .logicalAnd := by cases op <;> simp_all [shortCircuit]
            subst opEq
            rw [eq_bool checks.1.1] at typedL
            rw [eq_bool checks.1.2] at typedR
            exact .binary typedL typedR .logicalAnd
          · split at h
            · rename_i checks
              simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
              simp only [Option.some.injEq] at h
              subst h
              have opEq : op = .logicalOr := by cases op <;> simp_all [shortCircuit]
              subst opEq
              rw [eq_bool checks.1.1] at typedL
              rw [eq_bool checks.1.2] at typedR
              exact .binary typedL typedR .logicalOr
            · simp at h
  | .eNeg operand, scope, ctx, slot, ev, ok, dd, h => by
    simp only [SrcEff.eval, evalNegate] at h
    split at h
    · simp at h
    · rename_i o ho
      have inner := SrcEff.eval_typed target sigsOk operand ok (by simpa [SrcEff.types] using dd) ho
      simp only [evalThen] at h
      split at h
      · simp at h
      · rename_i t ht
        simp only [Option.some.injEq] at h
        subst h
        simp only [lowerNegateTyped] at ht
        split at ht
        · rename_i isI32
          simp only [Option.some.injEq] at ht
          subst ht
          rw [eq_i32 isI32] at inner
          exact .unary inner (.negate (.signed _))
        split at ht
        · rename_i isIsize
          simp only [Option.some.injEq] at ht
          subst ht
          rw [eq_isize isIsize] at inner
          exact .unary inner (.negate (.signed _))
        · simp at ht
  | .eNot operand, scope, ctx, slot, ev, ok, dd, h => by
    simp only [SrcEff.eval, evalNot] at h
    split at h
    · simp at h
    · rename_i o ho
      have inner := SrcEff.eval_typed target sigsOk operand ok (by simpa [SrcEff.types] using dd) ho
      simp only [evalThen] at h
      split at h
      · simp at h
      · rename_i t ht
        simp only [Option.some.injEq] at h
        subst h
        simp only [lowerNotTyped] at ht
        split at ht
        · rename_i isBool
          simp only [Option.some.injEq] at ht
          subst ht
          rw [eq_bool isBool] at inner
          exact .unary inner .logicalNot
        · simp at ht
  | .eCast ty operand, scope, ctx, slot, ev, ok, dd, h => by
    simp only [SrcEff.eval, evalCast] at h
    split at h
    · simp at h
    · rename_i o ho
      have inner := SrcEff.eval_typed target sigsOk operand ok (by simpa [SrcEff.types] using dd) ho
      simp only [evalThen] at h
      split at h
      · simp at h
      · rename_i t ht
        simp only [Option.some.injEq] at h
        subst h
        simp only [scalarCast] at ht
        split at ht
        · exact castTo_typed (o := { expr := Expr.var slot, ty := o.ty }) inner ht
        · simp at ht
  | .eIndex slice index, scope, ctx, slot, ev, ok, dd, h => by
    simp only [SrcEff.eval, evalIndex] at h
    split at h
    · simp at h
    · rename_i b found
      split at h
      · simp at h
      · rename_i element he
        simp only [evalElement] at h
        split at h
        · rename_i isI32
          split at h
          · simp at h
          · rename_i i hi
            simp only [evalLoad] at h
            split at h
            · rename_i cond
              simp only [Option.some.injEq] at h
              subst h
              have typedIndex := SrcEff.eval_typed target sigsOk index ok (by simpa [SrcEff.types] using dd) hi
              have inCtx := (ok slice b found).1
              have bty : b.ty = .slice element := by cases hb : b.ty <;> simp_all [elementOf]
              rw [bty, eq_i32 isI32] at inCtx
              have integer : Typing.IntegerTy i.ty.toCore := by
                simp only [Bool.or_eq_true] at cond
                rcases cond with c | c
                · rw [eq_i32 c]; exact .signed _
                · rw [eq_uint c]; exact .unsigned _
              exact .indexSlice (.local inCtx) typedIndex integer
            · simp at h
        · split at h
          · simp at h
          · rename_i i hi
            obtain ⟨tyEq, cond⟩ := evalWordElement_ty h
            have typedIndex := SrcEff.eval_typed target sigsOk index ok (by simpa [SrcEff.types] using dd) hi
            have inCtx := (ok slice b found).1
            have bty : b.ty = .slice element := by cases hb : b.ty <;> simp_all [elementOf]
            rw [bty] at inCtx
            have integer : Typing.IntegerTy i.ty.toCore := by
              simp only [Bool.or_eq_true] at cond
              rcases cond with c | c
              · rw [eq_i32 c]; exact .signed _
              · rw [eq_uint c]; exact .unsigned _
            rw [tyEq]
            exact .indexSlice (.local inCtx) typedIndex integer
  | .eStruct ty fields, scope, ctx, slot, ev, ok, dd, h => by
    simp only [SrcEff.eval, evalStruct] at h
    split at h
    · simp at h
    · rename_i ea hea
      have typedArgs := evalArgs_typed target sigsOk fields ok (fun t mem => dd t (by simp [SrcEff.types, mem])) hea
      have declared := dd ty (by simp [SrcEff.types])
      cases ty with
      | struct sid types =>
        simp only [evalStructOf] at h
        split at h
        · rename_i checks
          simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
          simp only [Option.some.injEq] at h
          subst h
          rw [typesSame_toCore checks.1] at typedArgs
          exact .structValue _ (declared_struct declared).1 typedArgs
        · simp at h
      | i32 => simp at h
      | bool => simp at h
      | uint => simp at h
      | enum => simp at h
      | ptr => simp at h
      | slice => simp at h
      | unit => simp at h
      | isize => simp at h
  | .eVariant ty variant payload, scope, ctx, slot, ev, ok, dd, h => by
    simp only [SrcEff.eval, evalVariant] at h
    split at h
    · simp at h
    · rename_i ea hea
      have typedArgs := evalArgs_typed target sigsOk payload ok (fun t mem => dd t (by simp [SrcEff.types, mem])) hea
      have declared := dd ty (by simp [SrcEff.types])
      cases ty with
      | enum eid variants =>
        simp only [evalTagged] at h
        split at h
        · split at h
          · simp at h
          · rename_i types found
            simp only [evalPayload] at h
            split at h
            · rename_i same
              simp only [Option.some.injEq] at h
              subst h
              rw [typesSame_toCore same] at typedArgs
              exact .enumValue _ (declared_enum declared).1 (by simp [found]) typedArgs
            · simp at h
        · simp at h
      | i32 => simp at h
      | bool => simp at h
      | uint => simp at h
      | struct => simp at h
      | ptr => simp at h
      | slice => simp at h
      | unit => simp at h
      | isize => simp at h
  | .eMatch scrutinee ety ty binders values, scope, ctx, slot, ev, ok, dd, h => by
    simp only [SrcEff.eval, evalMatch] at h
    split at h
    · simp at h
    · rename_i s hs
      split at h
      · simp at h
      · rename_i a ha
        simp only [evalMatchOf] at h
        split at h
        · rename_i cond
          simp only [Option.some.injEq] at h
          subst h
          simp only [Bool.and_eq_true, decide_eq_true_eq] at cond
          obtain ⟨⟨⟨⟨same, _⟩, _⟩, _⟩, _⟩ := cond
          have typedS := SrcEff.eval_typed target sigsOk scrutinee ok
            (fun t mem => dd t (by simp [SrcEff.types, mem])) hs
          rw [same_toCore same] at typedS
          have declared := dd ety (by simp [SrcEff.types])
          cases ety with
          | enum eid variants =>
            obtain ⟨found, inner⟩ := declared_enum declared
            exact .matchValue typedS (evalArms_typed target sigsOk found values 0 variants binders ok
              (fun t mem => dd t (by simp [SrcEff.types, mem])) (fun j fs hj => by simp [hj]) inner ha)
          | i32 => cases values <;> simp [matchVariants, evalArms] at ha
          | bool => cases values <;> simp [matchVariants, evalArms] at ha
          | uint => cases values <;> simp [matchVariants, evalArms] at ha
          | struct => cases values <;> simp [matchVariants, evalArms] at ha
          | ptr => cases values <;> simp [matchVariants, evalArms] at ha
          | slice => cases values <;> simp [matchVariants, evalArms] at ha
          | unit => cases values <;> simp [matchVariants, evalArms] at ha
          | isize => cases values <;> simp [matchVariants, evalArms] at ha
        · simp at h
  | .eDivide op left right, scope, ctx, slot, ev, ok, dd, h => by
    simp only [SrcEff.eval, evalDivision] at h
    split at h
    · simp at h
    · rename_i l hl
      split at h
      · simp at h
      · rename_i r hr
        have typedL := SrcEff.eval_typed target sigsOk left ok (fun t mem => dd t (by simp [SrcEff.types, mem])) hl
        have typedR := SrcEff.eval_typed target sigsOk right ok (fun t mem => dd t (by simp [SrcEff.types, mem])) hr
        simp only [evalDivide] at h
        split at h
        · rename_i both
          simp only [Bool.and_eq_true] at both
          simp only [Option.some.injEq] at h
          subst h
          rw [eq_i32 both.1] at typedL
          rw [eq_i32 both.2] at typedR
          cases op
          · exact .binary typedL typedR (.divide IsInt.i32.arith)
          · exact .binary typedL typedR (.remainder IsInt.i32.integer)
        · split at h
          · simp at h
          · rename_i k hk
            simp only [evalDivideUint] at h
            split at h
            · rename_i hr'
              simp only [Option.some.injEq] at h
              subst h
              rw [eq_uintKind hk] at typedL
              rw [eq_uint hr'] at typedR
              cases op
              · exact .binary typedL typedR (.divide (IsInt.uint k).arith)
              · exact .binary typedL typedR (.remainder (IsInt.uint k).integer)
            · simp at h
  | .eStride slice, scope, ctx, slot, ev, ok, dd, h => by
    simp only [SrcEff.eval, evalStride] at h
    split at h
    · simp at h
    · rename_i b found
      split at h
      · simp at h
      · rename_i element he
        have inCtx := (ok slice b found).1
        have bty : b.ty = .slice element := by cases hb : b.ty <;> simp_all [elementOf]
        rw [bty] at inCtx
        have tyEq : ev.ty = .isize := by
          simp only [evalStrideOf, evalWordStride, wordStride] at h
          split at h
          · simp only [Option.some.injEq] at h; subst h; rfl
          · split at h
            · simp only [Option.some.injEq] at h; subst h; rfl
            · split at h
              · simp at h
              · simp only [Option.some.injEq] at h; subst h; rfl
        rw [tyEq]
        exact .sliceStride (.local inCtx)

theorem evalArgs_typed {P : Core.Program} (target : P.target = Core.Target.x86_64)
    {sigs : List Sig} {decls : SrcDecls} (sigsOk : SigsOk P sigs) :
    ∀ (args : List SrcEff) {scope : List Binding} {ctx : Typing.Context} {slot : Nat} {ea : EvaluatedArgs},
      ScopeOk P ctx scope → (∀ t ∈ effsTypes args, TypeDeclared P t) → evalArgs sigs decls scope args slot = some ea →
      ExprsHaveTypes P ctx (SrcEff.toCoreList args) (ea.types.map SrcType.toCore)
  | [], scope, ctx, slot, ea, ok, dd, h => by
    simp only [evalArgs, Option.some.injEq] at h
    subst h
    exact .nil
  | arg :: rest, scope, ctx, slot, ea, ok, dd, h => by
    simp only [evalArgs] at h
    split at h
    · simp at h
    · rename_i first hfirst
      simp only [consArgs] at h
      split at h
      · simp at h
      · rename_i r hr
        simp only [Option.some.injEq] at h
        subst h
        exact .cons (SrcEff.eval_typed target sigsOk arg ok (fun t mem => dd t (by simp [effsTypes, mem])) hfirst) (evalArgs_typed target sigsOk rest ok (fun t mem => dd t (by simp [effsTypes, mem])) hr)

theorem evalArms_typed {P : Core.Program} (target : P.target = Core.Target.x86_64)
    {sigs : List Sig} {decls : SrcDecls} (sigsOk : SigsOk P sigs) {eid : Nat} {decl : Core.EnumDecl}
    (found : P.enumeration? eid = some decl) :
    ∀ (values : List SrcEff) (k : Nat) (variants : List (List SrcType)) (binders : List (List Nat))
      {scope : List Binding} {ctx : Typing.Context} {slot dst : Nat} {ty : SrcType} {out : Stmt},
      ScopeOk P ctx scope → (∀ t ∈ effsTypes values, TypeDeclared P t) →
      (∀ j fs, variants[j]? = some fs → decl.variants[k + j]? = some (fs.map SrcType.toCore)) →
      (∀ fs ∈ variants, ∀ f ∈ fs, TypeDeclared P f) →
      evalArms sigs decls scope slot dst ty k variants binders values = some out →
      Typing.MatchArmsHaveType P ctx (SrcEff.coreArms eid k binders values) (.enumeration eid) ty.toCore
  | [], _, _, _, _, _, _, _, _, _, _, _, _, _, h => by simp [evalArms] at h
  | _ :: _, _, [], _, _, _, _, _, _, _, _, _, _, _, h => by simp [evalArms] at h
  | _ :: _, _, _ :: _, [], _, _, _, _, _, _, _, _, _, _, h => by simp [evalArms] at h
  | value :: rest, k, types :: more, bs :: others, scope, ctx, slot, dst, ty, out, ok, dd, vars, declared, h => by
    simp only [evalArms] at h
    split at h
    · simp at h
    · rename_i s' hscope
      split at h
      · simp at h
      · rename_i e he
        obtain ⟨ok', pats⟩ := armScope_ok bs types ok (declared types (by simp)) hscope
        have body := SrcEff.eval_typed target sigsOk value ok' (fun t mem => dd t (by simp [effsTypes, mem])) he
        have variantFound : decl.variants[k]? = some (types.map SrcType.toCore) := by
          simpa using vars 0 types (by simp)
        have pat := Typing.PatternHasType.enumVariant decl found variantFound pats
        simp only [evalArm, evalSame] at h
        by_cases same : e.ty.same ty = true
        · rw [if_pos same] at h
          rw [same_toCore same] at body
          cases rest with
          | nil => cases others <;> exact .one pat body
          | cons next more' =>
            cases ho : evalArms sigs decls scope slot dst ty (k + 1) more others (next :: more') with
            | none => simp [ho] at h
            | some o =>
              have tail := evalArms_typed target sigsOk found (next :: more') (k + 1) more others ok
                (fun t mem => dd t (List.mem_append_right _ mem))
                (fun j fs hj => by
                  have := vars (j + 1) fs (by simpa using hj)
                  rwa [show k + (j + 1) = k + 1 + j by omega] at this)
                (fun fs hfs => declared fs (by simp [hfs])) ho
              exact .cons pat body tail
        · rw [if_neg same] at h
          simp at h

end

theorem SrcStmt.lower_typed {P : Core.Program} (target : P.target = Core.Target.x86_64)
    {sigs : List Sig} {decls : SrcDecls} (sigsOk : SigsOk P sigs) {ret : SrcType} :
    ∀ (s : SrcStmt) {scope : List Binding} {ctx : Typing.Context} {next : Nat} {inLoop : Bool}
      {out : Stmt}, ScopeOk P ctx scope → s.Declared P → s.lower sigs decls ret scope next = some out →
      StmtHasType P ret.toCore ctx inLoop s.toCore
  | .nop, _, _, _, _, _, _, _, _ => .skip
  | .let id ty value body, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.Declared] at d
    simp only [SrcStmt.lower, lowerLet] at h
    split at h
    · simp at h
    · rename_i vs hvs
      split at h
      · simp at h
      · rename_i b hb
        exact .letLocal (lowerValue_typed target ok hvs)
          (SrcStmt.lower_typed target sigsOk body (ok.cons d.1) d.2 hb)
  | .letStruct id ty fields body, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.Declared] at d
    simp only [SrcStmt.lower, lowerLet] at h
    split at h
    · simp at h
    · rename_i vs hvs
      split at h
      · simp at h
      · rename_i b hb
        exact .letLocal (lowerLiteral_typed target ok d.1 hvs)
          (SrcStmt.lower_typed target sigsOk body (ok.cons d.1) d.2 hb)
  | .letCall id ty callee args body, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.Declared] at d
    simp only [SrcStmt.lower, lowerLetCall] at h
    split at h
    · simp at h
    · rename_i a ha
      split at h
      · simp at h
      · rename_i b hb
        exact .letLocal (lowerCall_typed target sigsOk ok ha)
          (SrcStmt.lower_typed target sigsOk body (ok.cons d.1) d.2 hb)
  | .letEnum id ty variant payload body, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.Declared] at d
    simp only [SrcStmt.lower, lowerLet] at h
    split at h
    · simp at h
    · rename_i vs hvs
      split at h
      · simp at h
      · rename_i b hb
        exact .letLocal (lowerEnumValue_typed target ok d.1 hvs)
          (SrcStmt.lower_typed target sigsOk body (ok.cons d.1) d.2 hb)
  | .letMatch id ty scrutinee enumId arms body, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.Declared] at d
    simp only [SrcStmt.lower, lowerThen] at h
    split at h
    · simp at h
    · rename_i m hm
      split at h
      · simp at h
      · rename_i b hb
        exact .letLocal (lowerMatch_typed target ok hm)
          (SrcStmt.lower_typed target sigsOk body (ok.cons d.1) d.2 hb)
  | .set id value, scope, ctx, next, inLoop, out, ok, _, h => by
    simp only [SrcStmt.lower, lowerSet] at h
    split at h
    · simp at h
    · rename_i b found
      simp only [lowerSetValues] at h
      split at h
      · simp at h
      · rename_i vs hvs
        exact .expression (.assign (.local (ok id b found).1) (lowerValue_typed target ok hvs) .set)
  | .setField id index value, scope, ctx, next, inLoop, out, ok, _, h => by
    simp only [SrcStmt.lower, lowerSetField] at h
    split at h
    · simp at h
    · rename_i b found
      simp only [lowerSetFieldOf] at h
      split at h
      · simp at h
      · simp at h
      · simp at h
      · rename_i sid fields hty
        simp only [lowerSetFieldAt] at h
        split at h
        · simp at h
        · rename_i f hf
          split at h
          · simp only [lowerSetValue] at h
            split at h
            · simp at h
            · rename_i v hv
              obtain ⟨inCtx, declared⟩ := ok id b found
              rw [hty] at inCtx declared
              exact .expression (.assign
                (.field (.local inCtx) _ (declared_struct declared).1 (by simp [hf]))
                (lowerAs_typed target ok hv) .set)
          · simp at h
      all_goals simp at h
  | .setCall id callee args, scope, ctx, next, inLoop, out, ok, _, h => by
    simp only [SrcStmt.lower, lowerSetCall] at h
    split at h
    · simp at h
    · rename_i b found
      simp only [lowerSetCallArgs] at h
      split at h
      · simp at h
      · rename_i a ha
        exact .expression (.assign (.local (ok id b found).1) (lowerCall_typed target sigsOk ok ha) .set)
  | .then first second, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.Declared] at d
    simp only [SrcStmt.lower, lowerThen] at h
    split at h
    · simp at h
    · rename_i a ha
      split at h
      · simp at h
      · rename_i b hb
        exact .sequence (SrcStmt.lower_typed target sigsOk first ok d.1 ha)
          (SrcStmt.lower_typed target sigsOk second ok d.2 hb)
  | .if condition thenBranch elseBranch, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.Declared] at d
    simp only [SrcStmt.lower, lowerIf] at h
    split at h
    · simp at h
    · rename_i c hc
      split at h
      · simp at h
      · rename_i a ha
        split at h
        · simp at h
        · rename_i b hb
          exact .ifThenElse (lowerAs_typed target ok hc)
            (SrcStmt.lower_typed target sigsOk thenBranch ok d.1 ha)
            (SrcStmt.lower_typed target sigsOk elseBranch ok d.2 hb)
  | .while condition body, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.Declared] at d
    simp only [SrcStmt.lower, lowerWhile] at h
    split at h
    · simp at h
    · rename_i c hc
      split at h
      · simp at h
      · rename_i b hb
        exact .whileLoop (lowerAs_typed target ok hc) (SrcStmt.lower_typed target sigsOk body ok d hb)
  | .return value, scope, ctx, next, inLoop, out, ok, _, h => by
    simp only [SrcStmt.lower, lowerReturn] at h
    split at h
    · simp at h
    · rename_i vs hvs
      exact .returnValue (lowerValue_typed target ok hvs)
  | .letAlloc id size shift body, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.Declared] at d
    simp only [SrcStmt.lower, lowerAlloc] at h
    split at h
    · rename_i small
      split at h
      · simp at h
      · rename_i sz hsz
        split at h
        · simp at h
        · rename_i b hb
          exact .letLocal (.alloc (lowerAs_typed target ok hsz) (align_literal target small))
            (SrcStmt.lower_typed target sigsOk body (ok.cons (ty := .ptr) .ptr) d hb)
    · simp at h
  | .letLoad id pointer offset body, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.Declared] at d
    simp only [SrcStmt.lower, lowerLoad] at h
    split at h
    · simp at h
    · rename_i a ha
      split at h
      · simp at h
      · rename_i b hb
        obtain ⟨x, y, hx, hy⟩ := lowerAddress_some ha
        exact .letLocal (.loadByte (lowerAs_typed target ok hx) (lowerAs_typed target ok hy))
          (SrcStmt.lower_typed target sigsOk body (ok.cons (ty := .uint .uint8) (.uint _)) d hb)
  | .setByte pointer offset value, scope, ctx, next, inLoop, out, ok, _, h => by
    simp only [SrcStmt.lower, lowerStore] at h
    split at h
    · simp at h
    · rename_i a ha
      split at h
      · simp at h
      · rename_i v hv
        obtain ⟨x, y, hx, hy⟩ := lowerAddress_some ha
        exact .expression (.storeByte (lowerAs_typed target ok hx) (lowerAs_typed target ok hy)
          (lowerAs_typed target ok hv))
  | .free pointer size shift, scope, ctx, next, inLoop, out, ok, _, h => by
    simp only [SrcStmt.lower, lowerFree] at h
    split at h
    · rename_i small
      split at h
      · simp at h
      · rename_i p hp
        split at h
        · simp at h
        · rename_i sz hsz
          exact .expression (.dealloc (lowerAs_typed target ok hp) (lowerAs_typed target ok hsz)
            (align_literal target small))
    · simp at h
  | .letSlice id element pointer length body, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.Declared] at d
    simp only [SrcStmt.lower, lowerLet] at h
    split at h
    · simp at h
    · rename_i vs hvs
      split at h
      · simp at h
      · rename_i b hb
        obtain ⟨kind, x, y, hx, hy⟩ := lowerSlice_some hvs
        rcases kind with rfl | ⟨sid, fields, rfl⟩ | ⟨eid, variants, rfl⟩
        · exact .letLocal (.i32SliceFromRawParts (lowerAs_typed target ok hx) (lowerAs_typed target ok hy))
            (SrcStmt.lower_typed target sigsOk body (ok.cons (ty := .slice .i32) (.slice d.1)) d.2 hb)
        · obtain ⟨found, -⟩ := declared_struct d.1
          exact .letLocal (.typedSliceFromRawParts (.structureType sid _ found) (lowerAs_typed target ok hx)
              (lowerAs_typed target ok hy))
            (SrcStmt.lower_typed target sigsOk body (ok.cons (ty := .slice (.struct sid fields)) (.slice d.1))
              d.2 hb)
        · obtain ⟨found, -⟩ := declared_enum d.1
          exact .letLocal (.typedSliceFromRawParts (.enumerationType eid _ found) (lowerAs_typed target ok hx)
              (lowerAs_typed target ok hy))
            (SrcStmt.lower_typed target sigsOk body (ok.cons (ty := .slice (.enum eid variants)) (.slice d.1))
              d.2 hb)
  | .letIndex id ty slice index body, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.Declared] at d
    simp only [SrcStmt.lower, lowerLetIndex] at h
    split at h
    case isFalse =>
      split at h
      case isFalse =>
        unfold lowerLoadEnum at h
        split at h
        · simp at h
        rename_i sb found
        split at h
        · simp at h
        split at h
        · simp at h
        rename_i i hi
        split at h
        · simp at h
        rename_i b hb
        split at h
        · rename_i same
          obtain ⟨T, typedIndex, integer⟩ := lowerIndex_typed target ok hi
          have inCtx := (ok slice sb found).1
          rw [same_toCore same] at inCtx
          exact .letLocal (.indexSlice (.local inCtx) typedIndex integer)
            (SrcStmt.lower_typed target sigsOk body (ok.cons d.1) d.2 hb)
        · simp at h
      unfold lowerLoadFields at h
      split at h
      · simp at h
      rename_i sb found
      split at h
      · simp at h
      split at h
      · simp at h
      rename_i i hi
      split at h
      · simp at h
      rename_i b hb
      split at h
      · rename_i same
        obtain ⟨T, typedIndex, integer⟩ := lowerIndex_typed target ok hi
        have inCtx := (ok slice sb found).1
        rw [same_toCore same] at inCtx
        exact .letLocal (.indexSlice (.local inCtx) typedIndex integer)
          (SrcStmt.lower_typed target sigsOk body (ok.cons d.1) d.2 hb)
      · simp at h
    simp only [lowerLoadWord] at h
    split at h
    · simp at h
    · rename_i a ha
      split at h
      · simp at h
      · rename_i b hb
        unfold lowerElement at ha
        split at ha
        · simp at ha
        · rename_i sb found
          split at ha
          · rename_i same
            obtain ⟨_, i, _, hi⟩ := elementAddress_some ha
            obtain ⟨T, typedIndex, integer⟩ := lowerIndex_typed target ok hi
            have inCtx := (ok slice sb found).1
            rw [same_toCore same] at inCtx
            exact .letLocal (.indexSlice (.local inCtx) typedIndex integer)
              (SrcStmt.lower_typed target sigsOk body (ok.cons d.1) d.2 hb)
          · simp at ha
  | .setIndex slice index value, scope, ctx, next, inLoop, out, ok, _, h => by
    simp only [SrcStmt.lower, lowerSetIndex] at h
    split at h
    · simp at h
    · rename_i sb found
      simp only [lowerSetIndexOf] at h
      split at h
      · simp at h
      · rename_i e he
        simp only [storeAny] at h
        split at h
        case isFalse =>
          split at h
          case isFalse =>
            unfold storeEnum at h
            split at h
            · simp at h
            split at h
            · simp at h
            rename_i i hi
            split at h
            · simp at h
            rename_i vs hvs
            obtain ⟨T, typedIndex, integer⟩ := lowerIndex_typed target ok hi
            have inCtx := (ok slice sb found).1
            rw [elementOf_some he] at inCtx
            exact .expression (.assign (.indexSlice (.local inCtx) typedIndex integer)
              (lowerValue_typed target ok hvs) .set)
          unfold storeStruct at h
          split at h
          · simp at h
          split at h
          · simp at h
          rename_i i hi
          split at h
          · simp at h
          rename_i vs hvs
          obtain ⟨T, typedIndex, integer⟩ := lowerIndex_typed target ok hi
          have inCtx := (ok slice sb found).1
          rw [elementOf_some he] at inCtx
          exact .expression (.assign (.indexSlice (.local inCtx) typedIndex integer)
            (lowerValue_typed target ok hvs) .set)
        split at h
        · simp at h
        · rename_i a ha
          split at h
          · simp at h
          · rename_i v hv
            obtain ⟨_, i, _, hi⟩ := elementAddress_some ha
            obtain ⟨T, typedIndex, integer⟩ := lowerIndex_typed target ok hi
            have inCtx := (ok slice sb found).1
            rw [elementOf_some he] at inCtx
            exact .expression (.assign (.indexSlice (.local inCtx) typedIndex integer)
              (lowerAs_typed target ok hv) .set)
  | .letEval id ty value body, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.Declared] at d
    simp only [SrcStmt.lower, lowerLetEval] at h
    split at h
    · simp at h
    · rename_i v hv
      split at h
      · simp at h
      · rename_i b hb
        simp only [evalSame] at h
        split at h
        · rename_i same
          have typed := SrcEff.eval_typed target sigsOk value ok d.2.1 hv
          rw [same_toCore same] at typed
          exact .letLocal typed (SrcStmt.lower_typed target sigsOk body (ok.cons d.1) d.2.2 hb)
        · simp at h
  | .setEval id value, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.lower, lowerSetEval] at h
    split at h
    · simp at h
    · rename_i b found
      split at h
      · simp at h
      · rename_i v hv
        simp only [evalSame] at h
        split at h
        · rename_i same
          have typed := SrcEff.eval_typed target sigsOk value ok d hv
          rw [same_toCore same] at typed
          exact .expression (.assign (.local (ok id b found).1) typed .set)
        · simp at h
  | .ifEval condition thenBranch elseBranch, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.Declared] at d
    simp only [SrcStmt.lower, lowerIfEval] at h
    split at h
    · simp at h
    · rename_i c hc
      split at h
      · simp at h
      · rename_i a ha
        split at h
        · simp at h
        · rename_i b hb
          simp only [evalSame] at h
          split at h
          · rename_i same
            have typed := SrcEff.eval_typed target sigsOk condition ok d.1 hc
            rw [same_toCore same] at typed
            exact .ifThenElse typed (SrcStmt.lower_typed target sigsOk thenBranch ok d.2.1 ha)
              (SrcStmt.lower_typed target sigsOk elseBranch ok d.2.2 hb)
          · simp at h
  | .whileEval condition body, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.Declared] at d
    simp only [SrcStmt.lower, lowerWhileEval] at h
    split at h
    · simp at h
    · rename_i c hc
      split at h
      · simp at h
      · rename_i b hb
        simp only [evalSame] at h
        split at h
        · rename_i same
          have typed := SrcEff.eval_typed target sigsOk condition ok d.1 hc
          rw [same_toCore same] at typed
          exact .whileLoop typed (SrcStmt.lower_typed target sigsOk body ok d.2 hb)
        · simp at h
  | .returnEval value, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.lower, lowerReturnEval] at h
    split at h
    · simp at h
    · rename_i v hv
      simp only [evalSame] at h
      split at h
      · rename_i same
        have typed := SrcEff.eval_typed target sigsOk value ok d hv
        rw [same_toCore same] at typed
        exact .returnValue typed
      · simp at h
  | .discard value, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.lower, lowerDiscard] at h
    split at h
    · simp at h
    · rename_i v hv
      exact .expression (SrcEff.eval_typed target sigsOk value ok d hv)
  | .returnUnit, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.lower, lowerReturnUnit] at h
    split at h
    · rename_i isUnit
      rw [eq_unit isUnit]
      exact .returnUnit rfl
    · simp at h
  | .assert condition, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.lower, lowerAssert] at h
    split at h
    · simp at h
    · rename_i c hc
      simp only [evalSame] at h
      split at h
      · rename_i same
        have typed := SrcEff.eval_typed target sigsOk condition ok d hc
        rw [same_toCore same] at typed
        exact .expression (.assert typed)
      · simp at h
  | .setIndexEval slice index value, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.lower, lowerSetIndexEval] at h
    split at h
    · simp at h
    · rename_i sb found
      split at h
      · simp at h
      · rename_i e he
        simp only [storeEvalElement] at h
        split at h
        · rename_i isI32
          split at h
          · simp at h
          · rename_i i hi
            split at h
            · simp at h
            · rename_i v hv
              simp only [storeEval] at h
              split at h
              · rename_i cond
                simp only [Bool.and_eq_true, Bool.or_eq_true] at cond
                have typedIndex := SrcEff.eval_typed target sigsOk index ok
                  (fun t mem => d t (List.mem_append_left _ mem)) hi
                have typedValue := SrcEff.eval_typed target sigsOk value ok
                  (fun t mem => d t (List.mem_append_right _ mem)) hv
                have inCtx := (ok slice sb found).1
                rw [elementOf_some he, eq_i32 isI32] at inCtx
                rw [eq_i32 cond.2] at typedValue
                have integer : Typing.IntegerTy i.ty.toCore := by
                  rcases cond.1 with c | c
                  · rw [eq_i32 c]; exact .signed _
                  · rw [eq_uint c]; exact .unsigned _
                exact .expression (.assign (.indexSlice (.local inCtx) typedIndex integer) typedValue .set)
              · simp at h
        · split at h
          · simp at h
          · rename_i i hi
            split at h
            · simp at h
            · rename_i v hv
              have cond := storeEvalWord_cond h
              simp only [Bool.and_eq_true, Bool.or_eq_true] at cond
              have typedIndex := SrcEff.eval_typed target sigsOk index ok
                (fun t mem => d t (List.mem_append_left _ mem)) hi
              have typedValue := SrcEff.eval_typed target sigsOk value ok
                (fun t mem => d t (List.mem_append_right _ mem)) hv
              have inCtx := (ok slice sb found).1
              rw [elementOf_some he] at inCtx
              rw [same_toCore cond.2] at typedValue
              have integer : Typing.IntegerTy i.ty.toCore := by
                rcases cond.1 with c | c
                · rw [eq_i32 c]; exact .signed _
                · rw [eq_uint c]; exact .unsigned _
              exact .expression (.assign (.indexSlice (.local inCtx) typedIndex integer) typedValue .set)
  | .setFieldEval id index value, scope, ctx, next, inLoop, out, ok, d, h => by
    simp only [SrcStmt.lower, lowerSetFieldEval] at h
    split at h
    · simp at h
    · rename_i b found
      split at h
      · simp at h
      · rename_i v hv
        simp only [setFieldEvalOf] at h
        split at h
        · simp at h
        · simp at h
        · simp at h
        · rename_i sid fields hty
          simp only [setFieldEvalAt] at h
          split at h
          · simp at h
          · rename_i f hf
            split at h
            · simp only [evalSame] at h
              split at h
              · rename_i same
                obtain ⟨inCtx, declared⟩ := ok id b found
                rw [hty] at inCtx declared
                have typed := SrcEff.eval_typed target sigsOk value ok d hv
                rw [same_toCore same] at typed
                exact .expression (.assign
                  (.field (.local inCtx) _ (declared_struct declared).1 (by simp [hf])) typed .set)
              · simp at h
            · simp at h
        all_goals simp at h

/-! ## Functions and programs -/

theorem scopeOk_empty (P : Core.Program) : ScopeOk P Typing.Context.empty [] := by
  intro id b found
  simp [lookup] at found

theorem paramScope_ok {P : Core.Program} :
    ∀ (params : List SrcParam) {slot : Nat} {scope : List Binding} {ctx : Typing.Context},
      ScopeOk P ctx scope → (∀ param ∈ params, TypeDeclared P param.ty) →
      ScopeOk P ((params.map fun param => (param.id, param.ty.toCore)).foldl
        (fun context parameter => context.bind parameter.1 parameter.2) ctx)
        (paramScope params slot scope)
  | [], _, _, _, ok, _ => ok
  | param :: rest, slot, scope, ctx, ok, declared => by
    simp only [List.map_cons, List.foldl_cons, paramScope]
    exact paramScope_ok rest (ok.cons (declared param (by simp)))
      (fun p hp => declared p (by simp [hp]))

theorem paramTypes_toCore : ∀ (params : List SrcParam),
    (params.map fun param => (param.id, param.ty.toCore)).map Prod.snd =
      (paramTypes params).map SrcType.toCore
  | [] => rfl
  | param :: rest => by simp only [List.map_cons, paramTypes, paramTypes_toCore rest]

theorem sigs_getElem : ∀ (funcs : List SrcFunc) (i : Nat),
    (sigs funcs)[i]? = funcs[i]?.map fun func => ({ params := paramTypes func.params, ret := func.ret } : Sig)
  | [], _ => rfl
  | _ :: _, 0 => rfl
  | _ :: rest, i + 1 => by simp only [sigs, List.getElem?_cons_succ, sigs_getElem rest i]

theorem find_coreFuncs : ∀ (funcs : List SrcFunc) (n i : Nat),
    (coreFuncs n funcs).find? (fun f => f.id == n + i) = funcs[i]?.map (SrcFunc.toCore (n + i))
  | [], _, _ => rfl
  | func :: rest, n, 0 => by simp [coreFuncs, SrcFunc.toCore]
  | func :: rest, n, i + 1 => by
    simp only [coreFuncs, List.find?_cons, List.getElem?_cons_succ]
    have ne : ((func.toCore n).id == n + (i + 1)) = false := by simp [SrcFunc.toCore]
    simp only [ne]
    have := find_coreFuncs rest (n + 1) i
    rw [show n + 1 + i = n + (i + 1) by omega] at this
    exact this

theorem mem_coreFuncs : ∀ {funcs : List SrcFunc} {n : Nat} {f : Core.Function},
    f ∈ coreFuncs n funcs → ∃ i, ∃ func ∈ funcs, f = func.toCore i
  | [], _, _, h => by simp [coreFuncs] at h
  | func :: rest, n, f, h => by
    simp only [coreFuncs, List.mem_cons] at h
    rcases h with h | h
    · exact ⟨n, func, by simp, h⟩
    · obtain ⟨i, g, hg, rfl⟩ := mem_coreFuncs h
      exact ⟨i, g, by simp [hg], rfl⟩

theorem lowerFuncs_each {sigs : List Sig} {decls : SrcDecls} : ∀ {funcs : List SrcFunc} {out : List Func},
    lowerFuncs sigs decls funcs = some out → ∀ func ∈ funcs, ∃ c, lowerFunc sigs decls func = some c
  | [], _, _, _, h => by simp at h
  | func :: rest, out, lowered, g, hg => by
    simp only [lowerFuncs, lowerFuncCons] at lowered
    split at lowered
    · simp at lowered
    · rename_i c hc
      split at lowered
      · simp at lowered
      · rename_i cs hcs
        simp only [List.mem_cons] at hg
        rcases hg with rfl | hg
        · exact ⟨c, hc⟩
        · exact lowerFuncs_each hcs g hg

theorem unitTail_some {ret : SrcType} {body : Option Stmt} {b : Stmt} (h : unitTail ret body = some b) :
    ∃ out, body = some out := by
  simp only [unitTail] at h
  split at h
  · cases body with
    | none => simp at h
    | some out => exact ⟨out, rfl⟩
  · exact ⟨b, h⟩

theorem lowerFunc_body {sigs : List Sig} {decls : SrcDecls} {func : SrcFunc} {c : Func} (h : lowerFunc sigs decls func = some c) :
    ∃ out, func.body.lower sigs decls func.ret (paramScope func.params 0 []) (paramsSize func.params) = some out := by
  unfold lowerFunc at h
  split at h
  · unfold lowerBody at h
    dsimp only at h
    split at h
    · simp at h
    · rename_i b hb
      exact unitTail_some hb
  · simp at h


/-! ## Declarations

`declareProgram` threads a table of declarations through the program's
types. A table only grows (`Extends`), and every type it has passed is
declared in any Core program that has the final table's declarations
(`Agrees`). -/

/-- Every declaration in `d` is in `P`, at its Core types. -/
def Agrees (P : Core.Program) (d : SrcDecls) : Prop :=
  (∀ id fs, structFields d.structs id = some fs →
      P.structure? id = some ⟨id, fs.map SrcType.toCore⟩) ∧
    (∀ id vs, enumVariants d.enums id = some vs →
      P.enumeration? id = some ⟨id, vs.map (List.map SrcType.toCore)⟩)

/-- `d'` keeps every declaration of `d`. -/
def Extends (d d' : SrcDecls) : Prop :=
  (∀ id fs, structFields d.structs id = some fs → structFields d'.structs id = some fs) ∧
    (∀ id vs, enumVariants d.enums id = some vs → enumVariants d'.enums id = some vs)

theorem Extends.refl (d : SrcDecls) : Extends d d := ⟨fun _ _ h => h, fun _ _ h => h⟩

theorem Extends.trans {a b c : SrcDecls} (ab : Extends a b) (bc : Extends b c) : Extends a c :=
  ⟨fun id fs h => bc.1 id fs (ab.1 id fs h), fun id vs h => bc.2 id vs (ab.2 id vs h)⟩

theorem Agrees.of_extends {P : Core.Program} {d D : SrcDecls} (ext : Extends d D) (agrees : Agrees P D) :
    Agrees P d :=
  ⟨fun id fs h => agrees.1 id fs (ext.1 id fs h), fun id vs h => agrees.2 id vs (ext.2 id vs h)⟩

theorem variantsSame_toCore : ∀ {a b : List (List SrcType)}, variantsSame a b = true →
    a.map (List.map SrcType.toCore) = b.map (List.map SrcType.toCore)
  | [], [], _ => rfl
  | [], _ :: _, h => by simp [variantsSame] at h
  | _ :: _, [], h => by simp [variantsSame] at h
  | x :: xs, y :: ys, h => by
    simp only [variantsSame, Bool.and_eq_true] at h
    simp only [List.map_cons, typesSame_toCore h.1, variantsSame_toCore h.2]

theorem structFields_cons_self {id : Nat} {fields : List SrcType} {rest : List SrcStructDecl} :
    structFields ({ id := id, fields := fields } :: rest) id = some fields := by
  simp [structFields]

theorem structFields_cons_other {id x : Nat} {fields : List SrcType} {rest : List SrcStructDecl}
    (ne : x ≠ id) : structFields ({ id := id, fields := fields } :: rest) x = structFields rest x := by
  simp only [structFields]
  rw [if_neg (fun h => ne h.symm)]

theorem enumVariants_cons_self {id : Nat} {variants : List (List SrcType)} {rest : List SrcEnumDecl} :
    enumVariants ({ id := id, variants := variants } :: rest) id = some variants := by
  simp [enumVariants]

theorem enumVariants_cons_other {id x : Nat} {variants : List (List SrcType)} {rest : List SrcEnumDecl}
    (ne : x ≠ id) :
    enumVariants ({ id := id, variants := variants } :: rest) x = enumVariants rest x := by
  simp only [enumVariants]
  rw [if_neg (fun h => ne h.symm)]

theorem keepIf_some {agrees : Bool} {d d' : SrcDecls} (h : keepIf agrees d = some d') :
    agrees = true ∧ d' = d := by
  unfold keepIf at h
  split at h
  · rename_i yes
    simp only [Option.some.injEq] at h
    exact ⟨yes, h.symm⟩
  · simp at h

/-- A struct declaration step keeps the table and leaves `id` declared with
fields of the same Core types. -/
theorem declareStruct_some {id : Nat} {fields : List SrcType} {after : Option SrcDecls} {d' : SrcDecls}
    (h : declareStruct id fields after = some d') :
    ∃ d, after = some d ∧ Extends d d' ∧ ∃ fs, structFields d'.structs id = some fs ∧
      fs.map SrcType.toCore = fields.map SrcType.toCore := by
  unfold declareStruct at h
  split at h
  · simp at h
  · rename_i d
    dsimp only at h
    split at h
    · rename_i absent
      simp only [Option.some.injEq] at h
      subst h
      refine ⟨d, rfl, ⟨fun x fs found => ?_, fun _ _ found => found⟩, fields, structFields_cons_self, rfl⟩
      have ne : x ≠ id := by
        rintro rfl
        rw [absent] at found
        cases found
      rw [structFields_cons_other ne]
      exact found
    · rename_i other known
      obtain ⟨same, rfl⟩ := keepIf_some h
      exact ⟨d', rfl, Extends.refl d', other, known, typesSame_toCore same⟩

theorem declareEnum_some {id : Nat} {variants : List (List SrcType)} {after : Option SrcDecls}
    {d' : SrcDecls} (h : declareEnum id variants after = some d') :
    ∃ d, after = some d ∧ Extends d d' ∧ ∃ vs, enumVariants d'.enums id = some vs ∧
      vs.map (List.map SrcType.toCore) = variants.map (List.map SrcType.toCore) := by
  unfold declareEnum at h
  split at h
  · simp at h
  · rename_i d
    dsimp only at h
    split at h
    · rename_i absent
      simp only [Option.some.injEq] at h
      subst h
      refine ⟨d, rfl, ⟨fun _ _ found => found, fun x vs found => ?_⟩, variants,
        enumVariants_cons_self, rfl⟩
      have ne : x ≠ id := by
        rintro rfl
        rw [absent] at found
        cases found
      rw [enumVariants_cons_other ne]
      exact found
    · rename_i other known
      obtain ⟨same, rfl⟩ := keepIf_some h
      exact ⟨d', rfl, Extends.refl d', other, known, variantsSame_toCore same⟩

mutual
theorem SrcType.declare_sound : ∀ (ty : SrcType) {d d' : SrcDecls}, ty.declare d = some d' →
    Extends d d' ∧ ∀ {P : Core.Program} {D : SrcDecls}, Extends d' D → Agrees P D → TypeDeclared P ty
  | .i32, _, _, h => by
    simp only [SrcType.declare, Option.some.injEq] at h
    subst h
    exact ⟨Extends.refl _, fun _ _ => .i32⟩
  | .bool, _, _, h => by
    simp only [SrcType.declare, Option.some.injEq] at h
    subst h
    exact ⟨Extends.refl _, fun _ _ => .bool⟩
  | .uint kind, _, _, h => by
    simp only [SrcType.declare, Option.some.injEq] at h
    subst h
    exact ⟨Extends.refl _, fun _ _ => .uint kind⟩
  | .ptr, _, _, h => by
    simp only [SrcType.declare, Option.some.injEq] at h
    subst h
    exact ⟨Extends.refl _, fun _ _ => .ptr⟩
  | .struct id fields, d, d', h => by
    simp only [SrcType.declare] at h
    obtain ⟨d1, inner, ext, fs, found, same⟩ := declareStruct_some h
    obtain ⟨ext1, declared⟩ := declareTypes_sound fields inner
    refine ⟨ext1.trans ext, fun extD agrees => .struct ?_ (declared (ext.trans extD) agrees)⟩
    rw [agrees.1 id fs (extD.1 id fs found), same]
  | .enum id variants, d, d', h => by
    simp only [SrcType.declare] at h
    obtain ⟨d1, inner, ext, vs, found, same⟩ := declareEnum_some h
    obtain ⟨ext1, declared⟩ := declareVariants_sound variants inner
    refine ⟨ext1.trans ext, fun extD agrees => .enum ?_ (declared (ext.trans extD) agrees)⟩
    rw [agrees.2 id vs (extD.2 id vs found), same]
  | .slice element, d, d', h => by
    simp only [SrcType.declare] at h
    obtain ⟨ext, declared⟩ := SrcType.declare_sound element h
    exact ⟨ext, fun extD agrees => .slice (declared extD agrees)⟩
  | .unit, _, _, h => by
    simp only [SrcType.declare, Option.some.injEq] at h
    subst h
    exact ⟨Extends.refl _, fun _ _ => .unit⟩
  | .isize, _, _, h => by
    simp only [SrcType.declare, Option.some.injEq] at h
    subst h
    exact ⟨Extends.refl _, fun _ _ => .isize⟩

theorem declareTypes_sound : ∀ (types : List SrcType) {d d' : SrcDecls}, declareTypes types d = some d' →
    Extends d d' ∧ ∀ {P : Core.Program} {D : SrcDecls}, Extends d' D → Agrees P D →
      ∀ f ∈ types, TypeDeclared P f
  | [], _, _, h => by
    simp only [declareTypes, Option.some.injEq] at h
    subst h
    exact ⟨Extends.refl _, fun _ _ f mem => by cases mem⟩
  | ty :: rest, d, d', h => by
    simp only [declareTypes] at h
    split at h
    · simp at h
    · rename_i d1 first
      obtain ⟨ext1, head⟩ := SrcType.declare_sound ty first
      obtain ⟨ext2, tail⟩ := declareTypes_sound rest h
      refine ⟨ext1.trans ext2, fun extD agrees f mem => ?_⟩
      simp only [List.mem_cons] at mem
      rcases mem with rfl | mem
      · exact head (ext2.trans extD) agrees
      · exact tail extD agrees f mem

theorem declareVariants_sound : ∀ (variants : List (List SrcType)) {d d' : SrcDecls},
    declareVariants variants d = some d' →
    Extends d d' ∧ ∀ {P : Core.Program} {D : SrcDecls}, Extends d' D → Agrees P D →
      ∀ fs ∈ variants, ∀ f ∈ fs, TypeDeclared P f
  | [], _, _, h => by
    simp only [declareVariants, Option.some.injEq] at h
    subst h
    exact ⟨Extends.refl _, fun _ _ fs mem => by cases mem⟩
  | types :: rest, d, d', h => by
    simp only [declareVariants] at h
    split at h
    · simp at h
    · rename_i d1 first
      obtain ⟨ext1, head⟩ := declareTypes_sound types first
      obtain ⟨ext2, tail⟩ := declareVariants_sound rest h
      refine ⟨ext1.trans ext2, fun extD agrees fs mem => ?_⟩
      simp only [List.mem_cons] at mem
      rcases mem with rfl | mem
      · exact head (ext2.trans extD) agrees
      · exact tail extD agrees fs mem
end

/-- A binding's type, then the statement after it. -/
theorem declare_let {ty : SrcType} {d d1 d' : SrcDecls} (first : ty.declare d = some d1)
    {Q : Core.Program → Prop}
    (body : Extends d1 d' ∧ ∀ {P : Core.Program} {D : SrcDecls}, Extends d' D → Agrees P D → Q P) :
    Extends d d' ∧ ∀ {P : Core.Program} {D : SrcDecls}, Extends d' D → Agrees P D →
      TypeDeclared P ty ∧ Q P := by
  obtain ⟨ext1, head⟩ := SrcType.declare_sound ty first
  exact ⟨ext1.trans body.1, fun extD agrees => ⟨head (body.1.trans extD) agrees, body.2 extD agrees⟩⟩

theorem SrcStmt.declare_sound : ∀ (s : SrcStmt) {d d' : SrcDecls}, s.declare d = some d' →
    Extends d d' ∧ ∀ {P : Core.Program} {D : SrcDecls}, Extends d' D → Agrees P D → s.Declared P
  | .nop, _, _, h => by
    simp only [SrcStmt.declare, Option.some.injEq] at h
    subst h
    exact ⟨Extends.refl _, fun _ _ => trivial⟩
  | .let _ ty _ body, d, d', h => by
    simp only [SrcStmt.declare] at h
    split at h
    · simp at h
    · rename_i d1 first
      exact declare_let first (SrcStmt.declare_sound body h)
  | .letStruct _ ty _ body, d, d', h => by
    simp only [SrcStmt.declare] at h
    split at h
    · simp at h
    · rename_i d1 first
      exact declare_let first (SrcStmt.declare_sound body h)
  | .letCall _ ty _ _ body, d, d', h => by
    simp only [SrcStmt.declare] at h
    split at h
    · simp at h
    · rename_i d1 first
      exact declare_let first (SrcStmt.declare_sound body h)
  | .letEnum _ ty _ _ body, d, d', h => by
    simp only [SrcStmt.declare] at h
    split at h
    · simp at h
    · rename_i d1 first
      exact declare_let first (SrcStmt.declare_sound body h)
  | .letMatch _ ty _ _ _ body, d, d', h => by
    simp only [SrcStmt.declare] at h
    split at h
    · simp at h
    · rename_i d1 first
      exact declare_let first (SrcStmt.declare_sound body h)
  | .set _ _, _, _, h => by
    simp only [SrcStmt.declare, Option.some.injEq] at h
    subst h
    exact ⟨Extends.refl _, fun _ _ => trivial⟩
  | .setField _ _ _, _, _, h => by
    simp only [SrcStmt.declare, Option.some.injEq] at h
    subst h
    exact ⟨Extends.refl _, fun _ _ => trivial⟩
  | .setCall _ _ _, _, _, h => by
    simp only [SrcStmt.declare, Option.some.injEq] at h
    subst h
    exact ⟨Extends.refl _, fun _ _ => trivial⟩
  | .then first second, d, d', h => by
    simp only [SrcStmt.declare] at h
    split at h
    · simp at h
    · rename_i d1 hfirst
      obtain ⟨ext1, declared1⟩ := SrcStmt.declare_sound first hfirst
      obtain ⟨ext2, declared2⟩ := SrcStmt.declare_sound second h
      exact ⟨ext1.trans ext2, fun extD agrees =>
        ⟨declared1 (ext2.trans extD) agrees, declared2 extD agrees⟩⟩
  | .if _ thenBranch elseBranch, d, d', h => by
    simp only [SrcStmt.declare] at h
    split at h
    · simp at h
    · rename_i d1 hthen
      obtain ⟨ext1, declared1⟩ := SrcStmt.declare_sound thenBranch hthen
      obtain ⟨ext2, declared2⟩ := SrcStmt.declare_sound elseBranch h
      exact ⟨ext1.trans ext2, fun extD agrees =>
        ⟨declared1 (ext2.trans extD) agrees, declared2 extD agrees⟩⟩
  | .while _ body, d, d', h => by
    simp only [SrcStmt.declare] at h
    exact SrcStmt.declare_sound body h
  | .return _, _, _, h => by
    simp only [SrcStmt.declare, Option.some.injEq] at h
    subst h
    exact ⟨Extends.refl _, fun _ _ => trivial⟩
  | .letAlloc _ _ _ body, d, d', h => by
    simp only [SrcStmt.declare] at h
    exact SrcStmt.declare_sound body h
  | .letLoad _ _ _ body, d, d', h => by
    simp only [SrcStmt.declare] at h
    exact SrcStmt.declare_sound body h
  | .setByte _ _ _, _, _, h => by
    simp only [SrcStmt.declare, Option.some.injEq] at h
    subst h
    exact ⟨Extends.refl _, fun _ _ => trivial⟩
  | .free _ _ _, _, _, h => by
    simp only [SrcStmt.declare, Option.some.injEq] at h
    subst h
    exact ⟨Extends.refl _, fun _ _ => trivial⟩
  | .letSlice _ element _ _ body, d, d', h => by
    simp only [SrcStmt.declare] at h
    split at h
    · simp at h
    · rename_i d1 first
      exact declare_let first (SrcStmt.declare_sound body h)
  | .letIndex _ ty _ _ body, d, d', h => by
    simp only [SrcStmt.declare] at h
    split at h
    · simp at h
    · rename_i d1 first
      exact declare_let first (SrcStmt.declare_sound body h)
  | .setIndex _ _ _, _, _, h => by
    simp only [SrcStmt.declare, Option.some.injEq] at h
    subst h
    exact ⟨Extends.refl _, fun _ _ => trivial⟩
  | .letEval _ ty value body, d, d', h => by
    simp only [SrcStmt.declare] at h
    split at h
    · simp at h
    · rename_i d1 first
      obtain ⟨ext1, head⟩ := declareTypes_sound _ first
      obtain ⟨ext2, tail⟩ := SrcStmt.declare_sound body h
      exact ⟨ext1.trans ext2, fun extD agrees =>
        ⟨head (ext2.trans extD) agrees ty (by simp), fun t mem => head (ext2.trans extD) agrees t (by simp [mem]),
          tail extD agrees⟩⟩
  | .setEval _ value, d, d', h => by
    simp only [SrcStmt.declare] at h
    exact declareTypes_sound _ h
  | .ifEval condition thenBranch elseBranch, d, d', h => by
    simp only [SrcStmt.declare] at h
    split at h
    · simp at h
    · rename_i d2 h2
      split at h2
      · simp at h2
      · rename_i d1 first
        obtain ⟨ext1, head⟩ := declareTypes_sound _ first
        obtain ⟨ext2, declared2⟩ := SrcStmt.declare_sound thenBranch h2
        obtain ⟨ext3, declared3⟩ := SrcStmt.declare_sound elseBranch h
        exact ⟨(ext1.trans ext2).trans ext3, fun extD agrees =>
          ⟨head ((ext2.trans ext3).trans extD) agrees, declared2 (ext3.trans extD) agrees, declared3 extD agrees⟩⟩
  | .whileEval condition body, d, d', h => by
    simp only [SrcStmt.declare] at h
    split at h
    · simp at h
    · rename_i d1 first
      obtain ⟨ext1, head⟩ := declareTypes_sound _ first
      obtain ⟨ext2, declared2⟩ := SrcStmt.declare_sound body h
      exact ⟨ext1.trans ext2, fun extD agrees => ⟨head (ext2.trans extD) agrees, declared2 extD agrees⟩⟩
  | .returnEval value, d, d', h => by
    simp only [SrcStmt.declare] at h
    exact declareTypes_sound _ h
  | .discard value, d, d', h => by
    simp only [SrcStmt.declare] at h
    exact declareTypes_sound _ h
  | .setIndexEval _ index value, d, d', h => by
    simp only [SrcStmt.declare] at h
    exact declareTypes_sound _ h
  | .setFieldEval _ _ value, d, d', h => by
    simp only [SrcStmt.declare] at h
    exact declareTypes_sound _ h
  | .returnUnit, _, _, h => by
    simp only [SrcStmt.declare, Option.some.injEq] at h
    subst h
    exact ⟨Extends.refl _, fun _ _ => trivial⟩
  | .assert condition, d, d', h => by
    simp only [SrcStmt.declare] at h
    exact declareTypes_sound _ h

theorem declareParams_sound : ∀ (params : List SrcParam) {d d' : SrcDecls},
    declareParams params d = some d' →
    Extends d d' ∧ ∀ {P : Core.Program} {D : SrcDecls}, Extends d' D → Agrees P D →
      ∀ param ∈ params, TypeDeclared P param.ty
  | [], _, _, h => by
    simp only [declareParams, Option.some.injEq] at h
    subst h
    exact ⟨Extends.refl _, fun _ _ param mem => by cases mem⟩
  | param :: rest, d, d', h => by
    simp only [declareParams] at h
    split at h
    · simp at h
    · rename_i d1 first
      obtain ⟨ext1, head⟩ := SrcType.declare_sound param.ty first
      obtain ⟨ext2, tail⟩ := declareParams_sound rest h
      refine ⟨ext1.trans ext2, fun extD agrees p mem => ?_⟩
      simp only [List.mem_cons] at mem
      rcases mem with rfl | mem
      · exact head (ext2.trans extD) agrees
      · exact tail extD agrees p mem

theorem declareFunc_sound {func : SrcFunc} {d d' : SrcDecls} (h : declareFunc func d = some d') :
    Extends d d' ∧ ∀ {P : Core.Program} {D : SrcDecls}, Extends d' D → Agrees P D →
      (∀ param ∈ func.params, TypeDeclared P param.ty) ∧ func.body.Declared P := by
  unfold declareFunc at h
  split at h
  · simp at h
  · rename_i d1 hparams
    dsimp only at h
    split at h
    · simp at h
    · rename_i d2 hret
      obtain ⟨ext1, params⟩ := declareParams_sound func.params hparams
      obtain ⟨ext2, _⟩ := SrcType.declare_sound func.ret hret
      obtain ⟨ext3, body⟩ := SrcStmt.declare_sound func.body h
      exact ⟨ext1.trans (ext2.trans ext3), fun extD agrees =>
        ⟨params (ext2.trans (ext3.trans extD)) agrees, body extD agrees⟩⟩

theorem declareFuncs_sound : ∀ (funcs : List SrcFunc) {d d' : SrcDecls},
    declareFuncs funcs d = some d' →
    Extends d d' ∧ ∀ {P : Core.Program} {D : SrcDecls}, Extends d' D → Agrees P D →
      ∀ func ∈ funcs, (∀ param ∈ func.params, TypeDeclared P param.ty) ∧ func.body.Declared P
  | [], _, _, h => by
    simp only [declareFuncs, Option.some.injEq] at h
    subst h
    exact ⟨Extends.refl _, fun _ _ func mem => by cases mem⟩
  | func :: rest, d, d', h => by
    simp only [declareFuncs] at h
    split at h
    · simp at h
    · rename_i d1 first
      obtain ⟨ext1, head⟩ := declareFunc_sound first
      obtain ⟨ext2, tail⟩ := declareFuncs_sound rest h
      refine ⟨ext1.trans ext2, fun extD agrees g mem => ?_⟩
      simp only [List.mem_cons] at mem
      rcases mem with rfl | mem
      · exact head (ext2.trans extD) agrees
      · exact tail extD agrees g mem

/-- `sp.toCore` has the declarations the front pass derives. -/
theorem agrees_toCore {sp : SrcProgram} {decls : SrcDecls} (found : declareProgram sp = some decls) :
    Agrees sp.toCore decls := by
  have : sp.decls = decls := by simp [SrcProgram.decls, found]
  refine ⟨fun id fs h => ?_, fun id vs h => ?_⟩
  · simp only [Core.Program.structure?, SrcProgram.toCore, this, find_structs, h, Option.map_some]
  · simp only [Core.Program.enumeration?, SrcProgram.toCore, this, find_enums, h, Option.map_some]

/-- Every type an accepted program names is declared in its Core meaning. -/
theorem declareProgram_declared {sp : SrcProgram} {decls : SrcDecls}
    (found : declareProgram sp = some decls) : sp.Declared sp.toCore :=
  (declareFuncs_sound sp.funcs found).2 (Extends.refl decls) (agrees_toCore found)

theorem funcsReturn_each : ∀ {funcs : List SrcFunc}, funcsReturn funcs = true →
    ∀ func ∈ funcs, (func.ret.isUnit || func.body.returns) = true
  | [], _, _, mem => by cases mem
  | func :: rest, h, g, mem => by
    simp only [funcsReturn, Bool.and_eq_true] at h
    simp only [List.mem_cons] at mem
    rcases mem with rfl | mem
    · exact h.1
    · exact funcsReturn_each h.2 g mem

theorem sigsOk_program (sp : SrcProgram) : SigsOk sp.toCore (sigs sp.funcs) := by
  intro callee sig found
  rw [sigs_getElem] at found
  cases hf : sp.funcs[callee]? with
  | none => simp [hf] at found
  | some func =>
    simp only [hf, Option.map_some, Option.some.injEq] at found
    subst found
    refine ⟨func.toCore callee, ?_, paramTypes_toCore func.params, rfl⟩
    have := find_coreFuncs sp.funcs 0 callee
    simp only [Nat.zero_add, hf, Option.map_some] at this
    exact this

end TypeSound

open TypeSound in
/-- When the front pass lowers every function, every type the program names
is declared in `sp.toCore`, and every function body ends in a `return` on
every path, the Core meaning of the program is well typed by Core's rules. -/
theorem lowerFuncs_wellTyped {sp : SrcProgram} {funcs : List Func}
    (lowered : lowerFuncs (sigs sp.funcs) sp.decls sp.funcs = some funcs)
    (declared : sp.Declared sp.toCore)
    (returns : ∀ func ∈ sp.funcs, (func.ret.isUnit || func.body.returns) = true) :
    Typing.ProgramWellTyped sp.toCore := by
  refine ⟨fun c hc => by simp [SrcProgram.toCore] at hc, ?_⟩
  intro f hf
  obtain ⟨i, func, mem, rfl⟩ := mem_coreFuncs (n := 0) (funcs := sp.funcs) hf
  obtain ⟨c, hc⟩ := lowerFuncs_each lowered func mem
  obtain ⟨out, hout⟩ := lowerFunc_body hc
  obtain ⟨dparams, dbody⟩ := declared func mem
  have stmt := SrcStmt.lower_typed rfl (sigsOk_program sp) func.body (inLoop := false)
    (paramScope_ok func.params (scopeOk_empty _) dparams) dbody hout
  simp only [Typing.FunctionWellTyped, SrcFunc.toCore]
  have r := returns func mem
  simp only [Bool.or_eq_true] at r
  rcases r with unit | r
  · exact ⟨trivial, stmt, Or.inl (by simp [SrcFunc.toCore, eq_unit unit, SrcType.toCore])⟩
  · exact ⟨trivial, stmt, Or.inr (returns_sound _ r)⟩

open TypeSound in
/-- Type checker soundness: when the front pass accepts a program, its Core
meaning is well typed by Core's rules. -/
theorem compileSource_wellTyped {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) : Typing.ProgramWellTyped sp.toCore := by
  obtain ⟨returns, ⟨decls, found⟩, funcs, lowered, _⟩ := compileSource_some compiled
  exact lowerFuncs_wellTyped lowered (declareProgram_declared found) (funcsReturn_each returns)

/-! ## What the two checks reject

Two programs the lowering accepts and Core rejects, one per check, whatever
declarations they are given; `compileSource` rejects both. -/

/-- `sp.toCore` with other struct and enum declarations. -/
def SrcProgram.toCoreWith (sp : SrcProgram) (structs : List Core.StructDecl)
    (enums : List Core.EnumDecl) : Core.Program :=
  { sp.toCore with structures := structs, enumerations := enums }

namespace TypeSound

/-- `fn f() -> i32 {}`: no `return`. -/
def noReturn : SrcProgram := { funcs := [{ params := [], ret := .i32, body := .nop }] }

/-- `let a = S0 { 5 }; let b = S0 { true }; return a.0`: struct id 0 with two
field lists. -/
def idClash : SrcProgram :=
  let body := SrcStmt.letStruct 1 (SrcType.struct 0 [SrcType.i32]) [SrcExpr.int 5]
    (SrcStmt.letStruct 2 (SrcType.struct 0 [SrcType.bool]) [SrcExpr.boolean true]
      (SrcStmt.return (SrcExpr.field 1 0)))
  { funcs := [{ params := [], ret := .i32, body := body }] }

theorem noReturn_lowers : ∃ funcs, lowerFuncs (sigs noReturn.funcs) noReturn.decls noReturn.funcs = some funcs :=
  ⟨_, rfl⟩

theorem idClash_lowers : ∃ funcs, lowerFuncs (sigs idClash.funcs) idClash.decls idClash.funcs = some funcs :=
  ⟨_, rfl⟩

theorem noReturn_rejected : compileSource noReturn = none := rfl

theorem idClash_rejected : compileSource idClash = none := rfl

theorem noReturn_not_wellTyped (structs : List Core.StructDecl) (enums : List Core.EnumDecl) :
    ¬ Typing.ProgramWellTyped (noReturn.toCoreWith structs enums) := by
  intro ⟨_, funcs⟩
  have h := funcs _ (List.mem_singleton_self _)
  simp only [Typing.FunctionWellTyped, noReturn, SrcFunc.toCore, SrcType.toCore, SrcStmt.toCore,
    reduceCtorEq, false_or] at h
  cases h.2.2

theorem idClash_not_wellTyped (structs : List Core.StructDecl) (enums : List Core.EnumDecl) :
    ¬ Typing.ProgramWellTyped (idClash.toCoreWith structs enums) := by
  intro ⟨_, funcs⟩
  have h := funcs _ (List.mem_singleton_self _)
  simp only [Typing.FunctionWellTyped, idClash, SrcFunc.toCore, SrcStmt.toCore, SrcType.toCore,
    SrcType.typeId, List.map_cons, List.map_nil] at h
  obtain ⟨_, typed, _⟩ := h
  cases typed with
  | letLocal first rest =>
    cases rest with
    | letLocal second _ =>
      cases first with
      | structValue d1 found1 fields1 =>
        cases second with
        | structValue d2 found2 fields2 =>
          rw [found1] at found2
          cases found2
          generalize d1.fields = fs at fields1 fields2
          cases fields1 with
          | cons head1 _ =>
            cases fields2 with
            | cons head2 _ =>
              cases head1 with
              | value typed1 =>
                cases head2 with
                | value typed2 => cases typed1; cases typed2

end TypeSound

end Lanius.Mini
