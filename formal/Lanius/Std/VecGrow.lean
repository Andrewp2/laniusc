import Lanius.Std.VecHeap

/-! # Growth templates, `capacity_limit` and `grown_capacity`

The growth functions of `stdlib/std/vec.lani` as templates, in the front
end's reading: the constants `MAX_CAPACITY`, `MAX_BYTES` and `ALIGN` are
their literals, `x += e` is `x = x + e`, `alloc(n, ALIGN)` is Core's
`.alloc n 8` and `dealloc(p, n, ALIGN)` its `.dealloc p n 8`. As in
`VecTemplate.lean`, the literal `0` at `ptr` is `.pointer 0`. -/

namespace Lanius.Std

open Lanius Lanius.Core Lanius.Semantics Lanius.Memory

/-- The callee ids of the growth functions. -/
structure GrowIds where
  sizeOf : FunctionId
  capacityLimit : FunctionId
  grownCapacity : FunctionId
  tryReserve : FunctionId
  tryPush : FunctionId
  push : FunctionId
  panic : FunctionId

def usize (n : Nat) : Expr := .value (.unsigned .usize n)

section templates
variable (ids : VecIds) (g : GrowIds) (T : Ty)

/-- `fn capacity_limit<T>() -> i32 { let size: usize = size_of<T>();
if (size == 0) { return MAX_CAPACITY; } return (MAX_BYTES / size) as i32; }` -/
def capacityLimitFn : Function where
  id := g.capacityLimit
  parameters := []
  returnType := i32Ty
  body := some <|
    .letLocal 0 usizeTy (.call g.sizeOf [])
    (guardReturn (.binary .equal (.local 0) (usize 0)) (int 2147483647)
      (.returnValue (some (.cast (.signed .i32) (.binary .divide (usize 2147483647) (.local 0))))))

/-- `fn grown_capacity<T>(value: Vec<T>, needed: i32) -> i32` -/
def grownCapacityFn : Function where
  id := g.grownCapacity
  parameters := [(0, vecTy ids), (1, i32Ty)]
  returnType := i32Ty
  body := some <|
    .letLocal 2 i32Ty (.call g.capacityLimit [])
    (.letLocal 3 i32Ty (int 4)
    (.sequence
      (.ifThenElse (.binary .greater (.field (.local 0) 2) (int 0))
        (.ifThenElse (.binary .greater (.field (.local 0) 2) (.binary .divide (.local 2) (int 2)))
          (.expression (.assign .set (.local 3) (.local 2)))
          (.expression (.assign .set (.local 3) (.binary .multiply (.field (.local 0) 2) (int 2)))))
        .skip)
    (.sequence
      (.ifThenElse (.binary .less (.local 3) (.local 1)) (.expression (.assign .set (.local 3) (.local 1))) .skip)
      (.returnValue (some (.local 3))))))

/-- `pub fn try_reserve<T>(value: Vec<T>, minimum_capacity: i32) -> Vec<T>` -/
def tryReserveFn : Function where
  id := g.tryReserve
  parameters := [(0, vecTy ids), (1, i32Ty)]
  returnType := vecTy ids
  body := some <|
    guardReturn (.binary .lessEqual (.local 1) (.field (.local 0) 2)) (.local 0)
    (guardReturn (.binary .greater (.local 1) (.call g.capacityLimit [])) (.local 0)
    (.letLocal 2 usizeTy (.call g.sizeOf [])
    (guardReturn (.binary .equal (.local 2) (usize 0))
      (.structValue ids.vec [.field (.local 0) 0, .field (.local 0) 1, int 2147483647])
    (.letLocal 3 ptrTy (.alloc (.binary .multiply (.local 2) (.cast (.unsigned .usize) (.local 1))) (usize 8))
    (guardReturn (.binary .equal (.local 3) (.value (.pointer 0))) (.local 0)
    (.sequence
      (.ifThenElse (.binary .greater (.field (.local 0) 2) (int 0))
        (.letLocal 4 (.slice T) (.call ids.fromStorage [.field (.local 0) 0, .field (.local 0) 2])
        (.letLocal 5 (.slice T) (.call ids.fromStorage [.local 3, .local 1])
        (.letLocal 6 i32Ty (int 0)
        (.sequence (copyLoop 6 0 4 5)
          (.expression (.dealloc (.field (.local 0) 0)
            (.binary .multiply (.local 2) (.cast (.unsigned .usize) (.field (.local 0) 2))) (usize 8)))))))
        .skip)
      (.returnValue (some (.structValue ids.vec [.local 3, .field (.local 0) 1, .local 1])))))))))

/-- `pub fn try_push<T>(value: Vec<T>, item: T) -> Vec<T>` -/
def tryPushFn : Function where
  id := g.tryPush
  parameters := [(0, vecTy ids), (1, T)]
  returnType := vecTy ids
  body := some <|
    guardReturn (.binary .equal (.field (.local 0) 1) (int 2147483647)) (.local 0)
    (.letLocal 2 (vecTy ids) (.local 0)
    (.sequence
      (.ifThenElse (.binary .equal (.field (.local 2) 1) (.field (.local 2) 2))
        (.letLocal 3 i32Ty (.call g.grownCapacity [.local 2, .binary .add (.field (.local 2) 1) (int 1)])
          (.sequence (.expression (.assign .set (.local 2) (.call g.tryReserve [.local 2, .local 3])))
            (.ifThenElse (.binary .equal (.field (.local 2) 1) (.field (.local 2) 2))
              (.returnValue (some (.local 0))) .skip)))
        .skip)
    (.letLocal 4 (.slice T) (.call ids.slots [.local 2])
    (.sequence (.expression (.assign .set (.index (.local 4) (.field (.local 2) 1)) (.local 1)))
      (.returnValue (some (.structValue ids.vec
        [.field (.local 2) 0, .binary .add (.field (.local 2) 1) (int 1), .field (.local 2) 2])))))))

/-- `pub fn push<T>(value: Vec<T>, item: T) -> Vec<T>` -/
def pushFn : Function where
  id := g.push
  parameters := [(0, vecTy ids), (1, T)]
  returnType := vecTy ids
  body := some <|
    .letLocal 2 (vecTy ids) (.call g.tryPush [.local 0, .local 1])
    (.sequence
      (.ifThenElse (.binary .equal (.field (.local 2) 1) (.field (.local 0) 1)) (.expression (.call g.panic [])) .skip)
      (.returnValue (some (.local 2))))

end templates

/-- A program holding the growth functions of one `std::vec` instance. -/
structure GrowInstance (P : Program) (T : Ty) (ids : VecIds) (g : GrowIds) : Prop where
  vec : VecInstance P T ids
  sizeOf : P.function? g.sizeOf = some (sizeOfFn g.sizeOf T)
  capacityLimit : P.function? g.capacityLimit = some (capacityLimitFn g)
  grownCapacity : P.function? g.grownCapacity = some (grownCapacityFn ids g)
  tryReserve : P.function? g.tryReserve = some (tryReserveFn ids g T)
  tryPush : P.function? g.tryPush = some (tryPushFn ids g T)
  push : P.function? g.push = some (pushFn ids g T)

variable {P : Program} {T : Ty} {ids : VecIds} {g : GrowIds} {size : Nat}

/-! ## Operators -/

theorem eval_usize_eq (t : Target) (a b : Nat) :
    evalBinaryValue t .equal (.unsigned .usize a) (.unsigned .usize b) = .ok (.boolean (a == b)) := by
  simp [evalBinaryValue, scalarEqual]

theorem eval_ptr_eq (t : Target) (a b : Nat) :
    evalBinaryValue t .equal (.pointer a) (.pointer b) = .ok (.boolean (a == b)) := by
  simp [evalBinaryValue, scalarEqual]

theorem eval_usize_div {a b : Nat} (positive : 0 < b) (hi : a < 18446744073709551616) :
    evalBinaryValue Target.x86_64 .divide (.unsigned .usize a) (.unsigned .usize b) =
      .ok (.unsigned .usize (a / b)) := by
  simp only [evalBinaryValue, evalUnsignedBinary, beq_self_eq_true, if_true]
  rw [if_neg (by simp; omega), wrap_usize (by have := Nat.div_le_self a b; omega)]

theorem cast_i32_of_usize {n : Nat} (hi : n < 2147483648) :
    evalScalarCast Target.x86_64 (.signed .i32) (.unsigned .usize n) = .ok (.signed .i32 n) := by
  simp only [evalScalarCast]
  rw [wrap_i32 (by simp only [Int.ofNat_eq_natCast]; omega) (by simp only [Int.ofNat_eq_natCast]; omega)]
  rfl

theorem eval_i32_gt (t : Target) (a b : Int) :
    evalBinaryValue t .greater (.signed .i32 a) (.signed .i32 b) = .ok (.boolean (decide (a > b))) := by
  simp [evalBinaryValue, evalSignedBinary]

theorem eval_i32_le (t : Target) (a b : Int) :
    evalBinaryValue t .lessEqual (.signed .i32 a) (.signed .i32 b) = .ok (.boolean (decide (a ≤ b))) := by
  simp [evalBinaryValue, evalSignedBinary]

theorem eval_i32_div2 {a : Nat} (hi : a < 2147483648) :
    evalBinaryValue Target.x86_64 .divide (.signed .i32 a) (.signed .i32 2) = .ok (.signed .i32 ((a / 2 : Nat) : Int)) := by
  simp only [evalBinaryValue, evalSignedBinary, beq_self_eq_true, if_true]
  have q : truncDiv (a : Int) 2 = ((a / 2 : Nat) : Int) := by simp [truncDiv]
  rw [if_neg (by decide), if_neg (by simp), q, wrap_i32 (by omega) (by omega)]

theorem eval_i32_mul2 {a : Nat} (hi : 2 * a < 2147483648) :
    evalBinaryValue Target.x86_64 .multiply (.signed .i32 a) (.signed .i32 2) = .ok (.signed .i32 ((2 * a : Nat) : Int)) := by
  simp only [evalBinaryValue, evalSignedBinary, beq_self_eq_true, if_true]
  rw [wrap_i32 (by omega) (by omega)]
  congr 2
  omega

theorem eval_i32_add {a b : Int} (lo : -2147483648 ≤ a + b) (hi : a + b < 2147483648) :
    evalBinaryValue Target.x86_64 .add (.signed .i32 a) (.signed .i32 b) = .ok (.signed .i32 (a + b)) := by
  simp only [evalBinaryValue, evalSignedBinary, beq_self_eq_true, if_true]
  rw [wrap_i32 lo hi]

/-! ## `capacity_limit` -/

/-- The largest capacity whose storage fits `MAX_BYTES`. -/
def capLimit (size : Nat) : Nat := 2147483647 / size

theorem capacity_limit_spec (inst : GrowInstance P T ids g) (kind : ElemKind P T size)
    {caller : State} (formed : caller.CellsWellFormed) :
    ∃ after, RunsExpr P caller (.call g.capacityLimit (([] : List Value).map Expr.value))
      (.signed .i32 (capLimit size)) after ∧ PureFrame caller after := by
  have target := inst.vec.target
  refine PureRun.call inst.capacityLimit rfl rfl formed ?_
  let E : State := { caller with locals := [] }
  have fE : E.CellsWellFormed := formed
  change PureRun P E _ _
  obtain ⟨S, sizeRun, frame⟩ := size_of_spec target kind inst.sizeOf fE
  refine PureRun.letRun sizeRun frame ?_
  have fS := frame.afterFormed
  have l0 := local_bound fS 0 (.unsigned .usize size)
  have positive := kind.size_pos
  have cond := RunsExpr.binary (program := P) (RunsExpr.local' l0) (RunsExpr.value' (.unsigned .usize 0))
    (by decide) (eval_usize_eq _ _ _)
  rw [show (size == 0) = false by simp; omega] at cond
  refine PureRun.guardSkip cond (PureRun.ret (fS.bindLocal _ _) (RunsExpr.cast'
    (RunsExpr.binary (RunsExpr.value' _) (RunsExpr.local' l0) (by decide)
      (by rw [target]; exact eval_usize_div positive (by decide))) ?_))
  rw [target]
  exact cast_i32_of_usize (by have := Nat.div_le_self 2147483647 size; omega)

#print axioms capacity_limit_spec

/-! ## `grown_capacity` -/

/-- Double, starting at 4, at most the limit; at least `needed`. -/
def grownTarget (limit cap needed : Nat) : Nat :=
  let t := if 0 < cap then (if limit / 2 < cap then limit else 2 * cap) else 4
  if t < needed then needed else t

theorem grown_capacity_spec (inst : GrowInstance P T ids g) (kind : ElemKind P T size)
    {caller : State} (formed : caller.CellsWellFormed) {p cap : Nat} {len : Value} (needed : Nat)
    (capBound : cap < 2 ^ 31) :
    ∃ after, RunsExpr P caller (.call g.grownCapacity
        ([Value.structure ids.vec [.pointer p, len, .signed .i32 cap], .signed .i32 needed].map Expr.value))
      (.signed .i32 (grownTarget (capLimit size) cap needed)) after ∧ PureFrame caller after := by
  have target := inst.vec.target
  refine PureRun.call inst.grownCapacity rfl rfl formed ?_
  let vv := Value.structure ids.vec [.pointer p, len, .signed .i32 cap]
  let E0 : State := { caller with locals := [] }
  have f0 : E0.CellsWellFormed := formed
  have f1 := f0.bindLocal 0 vv
  let E := (E0.bindLocal 0 vv).bindLocal 1 (.signed .i32 needed)
  change PureRun P E _ _
  have fE : E.CellsWellFormed := f1.bindLocal _ _
  have l1 : E.local? 1 = some (.signed .i32 needed) := local_bound f1 1 _
  have l0 : E.local? 0 = some vv := local_kept f1 _ (by decide) (local_bound f0 0 _)
  obtain ⟨S, limitRun, frame⟩ := capacity_limit_spec inst kind fE
  refine PureRun.letRun limitRun frame ?_
  have fS := frame.afterFormed
  let L := capLimit size
  have limitSmall : L < 2147483648 := by
    show 2147483647 / size < 2147483648; have := Nat.div_le_self 2147483647 size; omega
  let B := S.bindLocal 2 (.signed .i32 L)
  have fB : B.CellsWellFormed := fS.bindLocal _ _
  have b2 : B.local? 2 = some (.signed .i32 L) := local_bound fS 2 _
  have b1 : B.local? 1 = some (.signed .i32 needed) := local_kept fS _ (by decide) (frame.localFound l1)
  have b0 : B.local? 0 = some vv := local_kept fS _ (by decide) (frame.localFound l0)
  refine PureRun.letValue fB ?_
  -- states with the target rebound
  let st : Nat → State := fun t => B.bindLocal 3 (.signed .i32 t)
  have kept : ∀ t (id : VarId) (v : Value), id ≠ 3 → B.local? id = some v → (st t).local? id = some v :=
    fun t id v ne found => local_kept fB _ (Ne.symm ne) found
  have assign : ∀ (t t' : Nat) (e : Expr), RunsExpr P (st t) e (.signed .i32 t') (st t) →
      RunsStmt P (st t) (.expression (.assign .set (.local 3) e)) .next (st t') := fun t t' e run => by
    obtain ⟨th, stable, _⟩ := run
    exact RunsStmt.expression (RunsExpr.ofStable
      (Lanius.Extraction.CertificateEmitterFrame.StableExpr.assignSetLocal P (st t) 3 B.nextCell _ e _
        (st t) (st t') (bindLocal_cellId _ _ _) (local_bound fB 3 _) stable rfl
        (bindLocal_assignLocal fB 3 _ _) rfl rfl) rfl)
  have capField : ∀ t, RunsExpr P (st t) (.field (.local 0) 2) (.signed .i32 cap) (st t) := fun t =>
    RunsExpr.field' (j := 2) (RunsExpr.local' (kept t 0 vv (by decide) b0)) rfl
  -- the first `if`
  let t1 := if 0 < cap then (if L / 2 < cap then L else 2 * cap) else 4
  have first : RunsStmt P (st 4)
      (.ifThenElse (.binary .greater (.field (.local 0) 2) (int 0))
        (.ifThenElse (.binary .greater (.field (.local 0) 2) (.binary .divide (.local 2) (int 2)))
          (.expression (.assign .set (.local 3) (.local 2)))
          (.expression (.assign .set (.local 3) (.binary .multiply (.field (.local 0) 2) (int 2)))))
        .skip) .next (st t1) := by
    have outer := RunsExpr.binary (operation := .greater) (capField 4) (RunsExpr.value' (P := P) (S := st 4) (.signed .i32 0)) (by decide)
      (eval_i32_gt _ _ _)
    by_cases positive : 0 < cap
    · rw [show decide ((cap : Int) > 0) = true by simp; omega] at outer
      refine RunsStmt.ifThenElseTrue outer ?_
      have half := RunsExpr.binary (operation := .divide) (RunsExpr.local' (kept 4 2 _ (by decide) b2))
        (RunsExpr.value' (P := P) (S := st 4) (.signed .i32 2)) (by decide)
        (by rw [target]; exact eval_i32_div2 limitSmall)
      have inner := RunsExpr.binary (capField 4) half (by decide) (eval_i32_gt _ _ _)
      by_cases big : L / 2 < cap
      · rw [show decide ((cap : Int) > ((L / 2 : Nat) : Int)) = true by simp; omega] at inner
        have t1eq : t1 = L := by simp [t1, positive, big]
        rw [t1eq]
        exact RunsStmt.ifThenElseTrue inner (assign 4 L _ (RunsExpr.local' (kept 4 2 _ (by decide) b2)))
      · rw [show decide ((cap : Int) > ((L / 2 : Nat) : Int)) = false by simp; omega] at inner
        have t1eq : t1 = 2 * cap := by simp [t1, positive, big]
        rw [t1eq]
        exact RunsStmt.ifThenElseFalse inner (assign 4 (2 * cap) _ (RunsExpr.binary (capField 4)
          (RunsExpr.value' _) (by decide) (by rw [target]; exact eval_i32_mul2 (by omega))))
    · rw [show decide ((cap : Int) > 0) = false by simp; omega] at outer
      have t1eq : t1 = 4 := by simp [t1, positive]
      rw [t1eq]
      exact RunsStmt.ifThenElseFalse outer (RunsStmt.skip P _)
  -- the second `if`
  have second : RunsStmt P (st t1)
      (.ifThenElse (.binary .less (.local 3) (.local 1)) (.expression (.assign .set (.local 3) (.local 1))) .skip)
      .next (st (grownTarget L cap needed)) := by
    have cond := RunsExpr.binary (RunsExpr.local' (local_bound fB 3 (.signed .i32 t1)))
      (RunsExpr.local' (kept t1 1 _ (by decide) b1)) (by decide) (eval_i32_lt P.target _ _)
    by_cases below : t1 < needed
    · rw [show decide ((t1 : Int) < needed) = true by simp; omega] at cond
      have eq : grownTarget L cap needed = needed := by simp only [grownTarget]; exact if_pos below
      rw [eq]
      exact RunsStmt.ifThenElseTrue cond (assign t1 needed _ (RunsExpr.local' (kept t1 1 _ (by decide) b1)))
    · rw [show decide ((t1 : Int) < needed) = false by simp; omega] at cond
      have eq : grownTarget L cap needed = t1 := by simp only [grownTarget]; exact if_neg below
      rw [eq]
      exact RunsStmt.ifThenElseFalse cond (RunsStmt.skip P _)
  refine ⟨st (grownTarget L cap needed), RunsStmt.sequenceNext first (RunsStmt.sequenceNext second
    (RunsStmt.returnValue (RunsExpr.local' (local_bound fB 3 _)))), FreshCellFrame.bindLocal B 3 _, rfl, rfl, rfl⟩

#print axioms grown_capacity_spec

end Lanius.Std
