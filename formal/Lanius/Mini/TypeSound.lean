import Lanius.Mini.Source
import Lanius.Typing

/-! Type checker soundness for the front pass (roadmap step 7).

When the front pass accepts a source program, the program's Core meaning is
well typed by Core's own typing rules, `Lanius.Typing.ProgramWellTyped`.

Core's typing differs from the front pass's checks in two places, so the
theorem has two premises the front pass does not check yet:

- Nominal types. Core looks struct and enum types up by id in the program's
  declarations; the front pass's types carry their fields inline
  (`SrcType.struct id fields`) and `SrcProgram.toCore` emits no declarations.
  The theorem is about `sp.toCore` with declarations `structs` and `enums`
  added, and assumes every type the program names agrees with them
  (`SrcProgram.Declared`). Two types with the same id and different fields
  have no such declarations; the front pass accepts them. A program whose
  types are all scalar agrees with no declarations, which is `sp.toCore`
  itself (`compileSource_wellTyped_scalar`).
- Returns. Core requires a function with a non-unit result to end in a
  `return` on every path (`DefinitelyReturns`: a `while` never counts); the
  front pass has no such check. `SrcStmt.returns` is that check on source
  statements, and the theorem assumes it of every function body. -/

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

/-- Every parameter type and binding type of every function is declared. -/
def SrcProgram.Declared (P : Core.Program) (sp : SrcProgram) : Prop :=
  ∀ func ∈ sp.funcs, (∀ param ∈ func.params, TypeDeclared P param.ty) ∧ SrcStmt.Declared P func.body

/-- Every path through the statement ends in a `return`, the way Core's
`DefinitelyReturns` counts: a `while` body never counts. -/
def SrcStmt.returns (s : SrcStmt) : Bool :=
  match s with
  | .nop => false
  | .let _ _ _ body => SrcStmt.returns body
  | .letStruct _ _ _ body => SrcStmt.returns body
  | .letCall _ _ _ _ body => SrcStmt.returns body
  | .letEnum _ _ _ _ body => SrcStmt.returns body
  | .letMatch _ _ _ _ _ body => SrcStmt.returns body
  | .set _ _ => false
  | .setField _ _ _ => false
  | .setCall _ _ _ => false
  | .then first second => SrcStmt.returns first || SrcStmt.returns second
  | .if _ thenBranch elseBranch => SrcStmt.returns thenBranch && SrcStmt.returns elseBranch
  | .while _ _ => false
  | .return _ => true
  | .letAlloc _ _ _ body => SrcStmt.returns body
  | .letLoad _ _ _ body => SrcStmt.returns body
  | .setByte _ _ _ => false
  | .free _ _ _ => false

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

theorem eq_uintKind {ty : SrcType} {k : UintTy} (h : ty.uintKind = some k) : ty = .uint k := by
  cases ty <;> simp_all [SrcType.uintKind]

/-- Types the front pass calls the same are the same Core type. -/
theorem same_toCore {a b : SrcType} (h : a.same b = true) : a.toCore = b.toCore := by
  cases a with
  | i32 =>
    have := eq_i32 (ty := b) (by simpa [SrcType.same] using h)
    subst this; rfl
  | bool =>
    have := eq_bool (ty := b) (by simpa [SrcType.same] using h)
    subst this; rfl
  | uint k =>
    have := eq_uint (ty := b) (k := k) (by simpa [SrcType.same] using h)
    subst this; rfl
  | ptr =>
    have := eq_ptr (ty := b) (by simpa [SrcType.same] using h)
    subst this; rfl
  | struct id fields =>
    cases b <;> simp only [SrcType.same, Bool.and_eq_true, decide_eq_true_eq,
      Bool.false_eq_true] at h
    rw [h.1]; rfl
  | enum id variants =>
    cases b <;> simp only [SrcType.same, Bool.and_eq_true, decide_eq_true_eq,
      Bool.false_eq_true] at h
    rw [h.1]; rfl

/-- An integer type of the front pass. -/
inductive IsInt : SrcType → Prop where
  | i32 : IsInt .i32
  | uint (k : UintTy) : IsInt (.uint k)

theorem IsInt.scalar {ty : SrcType} : IsInt ty → ty.isScalar = true
  | .i32 => rfl
  | .uint _ => rfl

theorem IsInt.arith {ty : SrcType} : IsInt ty → Typing.ArithmeticTy ty.toCore
  | .i32 => .signed _
  | .uint _ => .unsigned _

theorem IsInt.integer {ty : SrcType} : IsInt ty → Typing.IntegerTy ty.toCore
  | .i32 => .signed _
  | .uint _ => .unsigned _

theorem IsInt.ordered {ty : SrcType} : IsInt ty → Typing.OrderedTy ty.toCore
  | .i32 => .signed _
  | .uint _ => .unsigned _

theorem equalityTy {ty : SrcType} (scalar : ty.isScalar = true) : Typing.EqualityTy ty.toCore := by
  cases ty with
  | i32 => exact .signed _
  | bool => exact .boolean
  | uint => exact .unsigned _
  | ptr => exact .pointer
  | struct => simp [SrcType.isScalar] at scalar
  | enum => simp [SrcType.isScalar] at scalar

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
  | plus => exact arith_typed (fun a _ => .add a) h
  | minus => exact arith_typed (fun a _ => .subtract a) h
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
      · simp at h
      · simp at h
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
        all_goals simp at h
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
        all_goals simp at h
      | bool => simp [castTo] at h
      | struct => simp [castTo] at h
      | enum => simp [castTo] at h
      | ptr => simp [castTo] at h

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
        · simp at h
        · simp at h
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

theorem SrcStmt.lower_typed {P : Core.Program} (target : P.target = Core.Target.x86_64)
    {sigs : List Sig} (sigsOk : SigsOk P sigs) {ret : SrcType} :
    ∀ (s : SrcStmt) {scope : List Binding} {ctx : Typing.Context} {next : Nat} {inLoop : Bool}
      {out : Stmt}, ScopeOk P ctx scope → s.Declared P → s.lower sigs ret scope next = some out →
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
      · simp at h
      · simp at h
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

theorem lowerFuncs_each {sigs : List Sig} : ∀ {funcs : List SrcFunc} {out : List Func},
    lowerFuncs sigs funcs = some out → ∀ func ∈ funcs, ∃ c, lowerFunc sigs func = some c
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

theorem lowerFunc_body {sigs : List Sig} {func : SrcFunc} {c : Func} (h : lowerFunc sigs func = some c) :
    ∃ out, func.body.lower sigs func.ret (paramScope func.params 0 []) (paramsSize func.params) = some out := by
  unfold lowerFunc at h
  split at h
  · unfold lowerBody at h
    dsimp only at h
    split at h
    · simp at h
    · rename_i b hb
      exact ⟨b, hb⟩
  · simp at h

end TypeSound

/-- `sp.toCore` with these struct and enum declarations. -/
def SrcProgram.toCoreWith (sp : SrcProgram) (structs : List Core.StructDecl)
    (enums : List Core.EnumDecl) : Core.Program :=
  { sp.toCore with structures := structs, enumerations := enums }

namespace TypeSound

theorem sigsOk_program (sp : SrcProgram) (structs : List Core.StructDecl) (enums : List Core.EnumDecl) :
    SigsOk (sp.toCoreWith structs enums) (sigs sp.funcs) := by
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
/-- Type checker soundness: when the front pass lowers every function, the
Core meaning of the program, with struct and enum declarations its types
agree with, is well typed by Core's rules, provided every function body ends
in a `return` on every path. -/
theorem lowerFuncs_wellTyped {sp : SrcProgram} {funcs : List Func}
    {structs : List Core.StructDecl} {enums : List Core.EnumDecl}
    (lowered : lowerFuncs (sigs sp.funcs) sp.funcs = some funcs)
    (declared : sp.Declared (sp.toCoreWith structs enums))
    (returns : ∀ func ∈ sp.funcs, func.body.returns = true) :
    Typing.ProgramWellTyped (sp.toCoreWith structs enums) := by
  refine ⟨fun c hc => by simp [SrcProgram.toCoreWith, SrcProgram.toCore] at hc, ?_⟩
  intro f hf
  obtain ⟨i, func, mem, rfl⟩ := mem_coreFuncs (n := 0) (funcs := sp.funcs) hf
  obtain ⟨c, hc⟩ := lowerFuncs_each lowered func mem
  obtain ⟨out, hout⟩ := lowerFunc_body hc
  obtain ⟨dparams, dbody⟩ := declared func mem
  have stmt := SrcStmt.lower_typed rfl (sigsOk_program sp structs enums) func.body (inLoop := false)
    (paramScope_ok func.params (scopeOk_empty _) dparams) dbody hout
  simp only [Typing.FunctionWellTyped, SrcFunc.toCore]
  exact ⟨trivial, stmt, Or.inr (returns_sound _ (returns func mem))⟩

/-- The same for `compileSource`, the whole compiler. -/
theorem compileSource_wellTyped {sp : SrcProgram} {binary : Binary}
    {structs : List Core.StructDecl} {enums : List Core.EnumDecl}
    (compiled : compileSource sp = some binary)
    (declared : sp.Declared (sp.toCoreWith structs enums))
    (returns : ∀ func ∈ sp.funcs, func.body.returns = true) :
    Typing.ProgramWellTyped (sp.toCoreWith structs enums) := by
  unfold compileSource at compiled
  split at compiled
  · simp at compiled
  · rename_i funcs lowered
    exact lowerFuncs_wellTyped lowered declared returns

/-- A program whose types are all scalar needs no declarations: `sp.toCore`
itself is well typed. -/
theorem compileSource_wellTyped_scalar {sp : SrcProgram} {binary : Binary}
    (compiled : compileSource sp = some binary) (declared : sp.Declared sp.toCore)
    (returns : ∀ func ∈ sp.funcs, func.body.returns = true) :
    Typing.ProgramWellTyped sp.toCore :=
  compileSource_wellTyped (structs := []) (enums := []) compiled declared returns

/-! ## Why the premises are there

Two programs the front pass lowers that Core rejects, one per premise. -/

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

theorem noReturn_lowers : ∃ funcs, lowerFuncs (sigs noReturn.funcs) noReturn.funcs = some funcs :=
  ⟨_, rfl⟩

theorem idClash_lowers : ∃ funcs, lowerFuncs (sigs idClash.funcs) idClash.funcs = some funcs :=
  ⟨_, rfl⟩

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
