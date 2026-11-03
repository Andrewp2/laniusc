import Lanius.Mini.Room

/-! The frame block's room check (F14): `frame_block` takes each parameter's and each let's block
bytes (`declBytes`) out of `blockLimit` as they add up (`paramsRoom`, `blockRoom`), so no sum the
lowering makes passes `2 ^ 64`, and a block over the limit is `2 ^ 31`.

`paramsRoom` and `blockRoom` take out the sums `paramsBytes` and `SrcStmt.blockBytes` (the
unchecked sums the compiler added before the check), so `frameBlock` is `frameBytes`, the unchecked
block, when it fits and `2 ^ 31` when not (`frameBlock_eq`). `lowerFunc` rejects a block of `2 ^ 31`
or more either way, and `lowerFuncs` fails when one function does, so the check changes no result
of the compiler: `compileSource` is `compileSourceUnchecked`, the compiler with the unchecked sums
(`compileSource_unchecked`). -/

set_option linter.unusedVariables false

namespace Lanius.Mini

/-! The unchecked sums. -/

def paramsBytes : List SrcParam → List Nat → Nat
  | [], _ => 0
  | p :: rest, uses => declBytes uses p.id p.ty + paramsBytes rest uses

def SrcStmt.blockBytes (self : SrcStmt) (uses : List Nat) : Nat :=
  match self with
  | .nop => 0
  | .let id ty value body => declBytes uses id ty + SrcStmt.blockBytes body uses
  | .letStruct id ty fields body => declBytes uses id ty + SrcStmt.blockBytes body uses
  | .letCall id ty callee args body => declBytes uses id ty + SrcStmt.blockBytes body uses
  | .letEnum id ty variant payload body => declBytes uses id ty + SrcStmt.blockBytes body uses
  | .letMatch id ty scrutinee enumId arms body => declBytes uses id ty + SrcStmt.blockBytes body uses
  | .set id value => 0
  | .setField id index value => 0
  | .setCall id callee args => 0
  | .then first second => SrcStmt.blockBytes first uses + SrcStmt.blockBytes second uses
  | .if condition thenBranch elseBranch => SrcStmt.blockBytes thenBranch uses + SrcStmt.blockBytes elseBranch uses
  | .while condition body => SrcStmt.blockBytes body uses
  | .return value => 0
  | .letAlloc id size shift body => SrcStmt.blockBytes body uses
  | .letLoad id pointer offset body => SrcStmt.blockBytes body uses
  | .setByte pointer offset value => 0
  | .free pointer size shift => 0
  | .letSlice id element pointer length body => SrcStmt.blockBytes body uses
  | .letIndex id ty slice index body => declBytes uses id ty + SrcStmt.blockBytes body uses
  | .setIndex slice index value => 0
  | .letEval id ty value body => declBytes uses id ty + SrcStmt.blockBytes body uses
  | .setEval id value => 0
  | .ifEval condition thenBranch elseBranch => SrcStmt.blockBytes thenBranch uses + SrcStmt.blockBytes elseBranch uses
  | .whileEval condition body => SrcStmt.blockBytes body uses
  | .returnEval value => 0
  | .discard value => 0
  | .setIndexEval slice index value => 0
  | .setFieldEval id field value => 0
  | .returnUnit => 0
  | .assert condition => 0
  | .break => 0
  | .continue => 0
  | .matchArm scrutinee enumId variant binds binder ty body rest => SrcStmt.blockBytes body uses + SrcStmt.blockBytes rest uses
  | .unreachable id ty => 0
  | .letView id length fields pointer body => SrcStmt.blockBytes body uses
  | .letStr pointer chars body => SrcStmt.blockBytes body uses

/-- The block without the check: every parameter's and let's block bytes. -/
def frameBytes (func : SrcFunc) : Nat :=
  let uses : List Nat := SrcStmt.sliceUses func.body
  paramsBytes func.params uses + SrcStmt.blockBytes func.body uses

theorem paramsRoom_eq (uses : List Nat) :
    ∀ (params : List SrcParam) (room : Nat), paramsRoom room params uses = takeOut room (paramsBytes params uses)
  | [], room => by simp [paramsRoom, paramsBytes, takeOut]
  | p :: rest, room => by
    simp only [paramsRoom, paramsBytes, spend, paramsRoom_eq uses rest, takeOut]
    by_cases h1 : declBytes uses p.id p.ty ≤ room <;>
      by_cases h2 : declBytes uses p.id p.ty + paramsBytes rest uses ≤ room <;> room_fin

theorem blockRoom_eq (uses : List Nat) (s : SrcStmt) :
    ∀ room, blockRoom room uses s = takeOut room (SrcStmt.blockBytes s uses) := by
  induction s with
  | nop => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | «let» id ty value body ih =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, spend, ih, takeOut]
    by_cases h1 : declBytes uses id ty ≤ room <;>
      by_cases h2 : declBytes uses id ty + SrcStmt.blockBytes body uses ≤ room <;> room_fin
  | letStruct id ty fields body ih =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, spend, ih, takeOut]
    by_cases h1 : declBytes uses id ty ≤ room <;>
      by_cases h2 : declBytes uses id ty + SrcStmt.blockBytes body uses ≤ room <;> room_fin
  | letCall id ty callee args body ih =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, spend, ih, takeOut]
    by_cases h1 : declBytes uses id ty ≤ room <;>
      by_cases h2 : declBytes uses id ty + SrcStmt.blockBytes body uses ≤ room <;> room_fin
  | letEnum id ty variant payload body ih =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, spend, ih, takeOut]
    by_cases h1 : declBytes uses id ty ≤ room <;>
      by_cases h2 : declBytes uses id ty + SrcStmt.blockBytes body uses ≤ room <;> room_fin
  | letMatch id ty scrutinee enumId arms body ih =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, spend, ih, takeOut]
    by_cases h1 : declBytes uses id ty ≤ room <;>
      by_cases h2 : declBytes uses id ty + SrcStmt.blockBytes body uses ≤ room <;> room_fin
  | set id value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | setField id index value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | setCall id callee args => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | «then» first second ih1 ih2 =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, ih1, ih2, takeOut]
    by_cases h1 : SrcStmt.blockBytes first uses ≤ room <;>
      by_cases h2 : SrcStmt.blockBytes first uses + SrcStmt.blockBytes second uses ≤ room <;> room_fin
  | «if» condition thenBranch elseBranch ih1 ih2 =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, ih1, ih2, takeOut]
    by_cases h1 : SrcStmt.blockBytes thenBranch uses ≤ room <;>
      by_cases h2 : SrcStmt.blockBytes thenBranch uses + SrcStmt.blockBytes elseBranch uses ≤ room <;> room_fin
  | «while» condition body ih => intro room; simp only [blockRoom, SrcStmt.blockBytes, ih]
  | «return» value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | letAlloc id size shift body ih => intro room; simp only [blockRoom, SrcStmt.blockBytes, ih]
  | letLoad id pointer offset body ih => intro room; simp only [blockRoom, SrcStmt.blockBytes, ih]
  | setByte pointer offset value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | free pointer size shift => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | letSlice id element pointer length body ih => intro room; simp only [blockRoom, SrcStmt.blockBytes, ih]
  | letIndex id ty slice index body ih =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, spend, ih, takeOut]
    by_cases h1 : declBytes uses id ty ≤ room <;>
      by_cases h2 : declBytes uses id ty + SrcStmt.blockBytes body uses ≤ room <;> room_fin
  | setIndex slice index value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | letEval id ty value body ih =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, spend, ih, takeOut]
    by_cases h1 : declBytes uses id ty ≤ room <;>
      by_cases h2 : declBytes uses id ty + SrcStmt.blockBytes body uses ≤ room <;> room_fin
  | setEval id value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | ifEval condition thenBranch elseBranch ih1 ih2 =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, ih1, ih2, takeOut]
    by_cases h1 : SrcStmt.blockBytes thenBranch uses ≤ room <;>
      by_cases h2 : SrcStmt.blockBytes thenBranch uses + SrcStmt.blockBytes elseBranch uses ≤ room <;> room_fin
  | whileEval condition body ih => intro room; simp only [blockRoom, SrcStmt.blockBytes, ih]
  | returnEval value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | discard value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | setIndexEval slice index value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | setFieldEval id field value => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | returnUnit => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | assert condition => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | «break» => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | «continue» => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | matchArm scrutinee enumId variant binds binder ty body rest ih1 ih2 =>
    intro room
    simp only [blockRoom, SrcStmt.blockBytes, ih1, ih2, takeOut]
    by_cases h1 : SrcStmt.blockBytes body uses ≤ room <;>
      by_cases h2 : SrcStmt.blockBytes body uses + SrcStmt.blockBytes rest uses ≤ room <;> room_fin
  | unreachable id ty => intro room; simp [blockRoom, SrcStmt.blockBytes, takeOut]
  | letView id length fields pointer body ih => intro room; simp only [blockRoom, SrcStmt.blockBytes, ih]
  | letStr pointer chars body ih => intro room; simp only [blockRoom, SrcStmt.blockBytes, ih]

/-- The checked block is the unchecked one when it fits the limit, and `2 ^ 31` when not. -/
theorem frameBlock_eq (func : SrcFunc) :
    frameBlock func = if frameBytes func ≤ blockLimit then frameBytes func else 2147483648 := by
  simp only [frameBlock, frameBytes, paramsRoom_eq, blockRoom_eq, takeOut]
  by_cases h1 : paramsBytes func.params (SrcStmt.sliceUses func.body) ≤ blockLimit <;>
    by_cases h2 : paramsBytes func.params (SrcStmt.sliceUses func.body) +
      SrcStmt.blockBytes func.body (SrcStmt.sliceUses func.body) ≤ blockLimit <;> room_fin

theorem frameBlock_le (func : SrcFunc) : frameBlock func ≤ 2147483648 := by
  rw [frameBlock_eq]
  by_cases h : frameBytes func ≤ blockLimit <;> simp only [h, if_true, if_false] <;> simp only [blockLimit] at * <;> omega

/-! The compiler with the unchecked sums. -/

def needRoundUnchecked : List SrcFunc → List Nat → List Nat
  | [], _ => []
  | f :: rest, prev => (frameBytes f + SrcStmt.calleeNeed f.body prev) :: needRoundUnchecked rest prev

def needsAfterUnchecked (funcs : List SrcFunc) (prev : List Nat) : Nat → List Nat
  | 0 => needRoundUnchecked funcs prev
  | rounds + 1 =>
    if sameNeeds (needRoundUnchecked funcs prev) prev then needRoundUnchecked funcs prev
    else needsAfterUnchecked funcs (needRoundUnchecked funcs prev) rounds

def sigsUnchecked (funcs : List SrcFunc) : List Sig :=
  sigsWith funcs (needsAfterUnchecked funcs [] funcs.length)

def lowerFuncUnchecked (sigs : List Sig) (own : Sig) (decls : SrcDecls) (func : SrcFunc) : Option Func :=
  let count : Nat := paramsSize func.params
  let block : Nat := frameBytes func
  if decide (0 < SrcType.size func.ret) && paramsValid func.params && !(SrcStmt.breaksOut func.body) &&
      decide (block ≤ own.need) && decide (block < 2147483648) then
    lowerBody count (SrcType.size func.ret) (SrcStmt.depth func.body) (unitTail func.ret (withFrame count block
      (SrcStmt.lower func.body (withBudget sigs (own.need - block) block) decls func.ret (paramScope func.params 0 []) count)))
  else
    none

def lowerFuncsUnchecked (sigs : List Sig) : List Sig → SrcDecls → List SrcFunc → Option (List Func)
  | _, _, [] => some []
  | [], _, _ :: _ => none
  | sig :: others, decls, func :: rest =>
    lowerFuncCons (lowerFuncUnchecked sigs sig decls func) (lowerFuncsUnchecked sigs others decls rest)

def compileSourceUnchecked (prog : SrcProgram) : Option Binary :=
  if funcsReturn prog.funcs then
    match declareProgram prog with
    | none => none
    | some d => compileLowered (lowerFuncsUnchecked (sigsUnchecked prog.funcs) (sigsUnchecked prog.funcs) d prog.funcs) d.statics
  else
    none

/-! Every block fits: the two compilers agree. -/

theorem needRound_unchecked {funcs : List SrcFunc} (fits : ∀ f ∈ funcs, frameBytes f ≤ blockLimit) (prev : List Nat) :
    needRound funcs prev = needRoundUnchecked funcs prev := by
  induction funcs with
  | nil => rfl
  | cons f rest ih =>
    have hf : frameBlock f = frameBytes f := by
      rw [frameBlock_eq]; simp only [fits f (List.mem_cons_self ..), if_true]
    simp only [needRound, needRoundUnchecked, hf, ih (fun g mem => fits g (List.mem_cons_of_mem f mem))]

theorem needsAfter_unchecked {funcs : List SrcFunc} (fits : ∀ f ∈ funcs, frameBytes f ≤ blockLimit) :
    ∀ (rounds : Nat) (prev : List Nat), needsAfter funcs prev rounds = needsAfterUnchecked funcs prev rounds
  | 0, prev => by
    rw [needsAfter]; simp only [if_true, needsAfterUnchecked, needRound_unchecked fits]
  | rounds + 1, prev => by
    rw [needsAfter]
    simp only [Nat.add_one_ne_zero, if_false, needsAfterUnchecked, needRound_unchecked fits,
      needsAfter_unchecked fits rounds, Nat.add_sub_cancel]

theorem sigs_unchecked {funcs : List SrcFunc} (fits : ∀ f ∈ funcs, frameBytes f ≤ blockLimit) :
    sigs funcs = sigsUnchecked funcs := by
  simp only [sigs, sigsUnchecked, funcNeeds, needsAfter_unchecked fits]

theorem lowerFuncs_unchecked (S : List Sig) (decls : SrcDecls) :
    ∀ (own : List Sig) (funcs : List SrcFunc), (∀ f ∈ funcs, frameBytes f ≤ blockLimit) →
      lowerFuncs S own decls funcs = lowerFuncsUnchecked S own decls funcs
  | own, [], _ => by cases own <;> rfl
  | [], _ :: _, _ => rfl
  | sig :: others, func :: rest, fits => by
    have hf : frameBlock func = frameBytes func := by
      rw [frameBlock_eq]; simp only [fits func (List.mem_cons_self ..), if_true]
    simp only [lowerFuncs, lowerFuncsUnchecked, lowerFunc, lowerFuncUnchecked, hf,
      lowerFuncs_unchecked S decls others rest (fun g mem => fits g (List.mem_cons_of_mem func mem))]

/-! A block does not fit: both compilers reject the program. -/

theorem lowerFuncs_none {lower : List Sig → Sig → SrcDecls → SrcFunc → Option Func}
    {lowers : List Sig → List Sig → SrcDecls → List SrcFunc → Option (List Func)}
    (nil : ∀ S decls, lowers S [] decls [] = some [])
    (empty : ∀ S decls func rest, lowers S [] decls (func :: rest) = none)
    (cons : ∀ S sig others decls func rest,
      lowers S (sig :: others) decls (func :: rest) = lowerFuncCons (lower S sig decls func) (lowers S others decls rest))
    {big : SrcFunc} (bad : ∀ S sig decls, lower S sig decls big = none) (S : List Sig) (decls : SrcDecls) :
    ∀ (own : List Sig) (funcs : List SrcFunc), big ∈ funcs → lowers S own decls funcs = none
  | _, [], mem => by cases mem
  | [], func :: rest, _ => empty S decls func rest
  | sig :: others, func :: rest, mem => by
    rw [cons]
    rcases List.mem_cons.mp mem with h | h
    · subst h; simp only [bad, lowerFuncCons]
    · rw [lowerFuncs_none nil empty cons bad S decls others rest h]
      cases lower S sig decls func <;> rfl

theorem lowerFunc_big {func : SrcFunc} (big : ¬ frameBytes func ≤ blockLimit) (S : List Sig) (sig : Sig)
    (decls : SrcDecls) : lowerFunc S sig decls func = none := by
  have hf : frameBlock func = 2147483648 := by rw [frameBlock_eq]; simp only [big, if_false]
  simp only [lowerFunc, hf, Nat.lt_irrefl, decide_false, Bool.and_false, Bool.false_eq_true, if_false]

theorem lowerFuncUnchecked_big {func : SrcFunc} (big : ¬ frameBytes func ≤ blockLimit) (S : List Sig) (sig : Sig)
    (decls : SrcDecls) : lowerFuncUnchecked S sig decls func = none := by
  have h : ¬ frameBytes func < 2147483648 := by simp only [blockLimit] at big; omega
  simp only [lowerFuncUnchecked, h, decide_false, Bool.and_false, Bool.false_eq_true, if_false]

/-- The frame block's room check changes no result of the compiler. -/
theorem compileSource_unchecked (prog : SrcProgram) : compileSource prog = compileSourceUnchecked prog := by
  simp only [compileSource, compileSourceUnchecked, compileDeclared]
  split
  · cases declareProgram prog with
    | none => rfl
    | some d =>
      simp only
      by_cases fits : ∀ f ∈ prog.funcs, frameBytes f ≤ blockLimit
      · rw [sigs_unchecked fits, lowerFuncs_unchecked _ d _ _ fits]
      · rcases Classical.not_forall.mp fits with ⟨big, hbig⟩
        rcases Classical.not_imp.mp hbig with ⟨mem, over⟩
        rw [lowerFuncs_none (lower := lowerFunc) (lowers := lowerFuncs) (fun _ _ => rfl) (fun _ _ _ _ => rfl)
            (fun _ _ _ _ _ _ => rfl) (lowerFunc_big over) _ d _ _ mem,
          lowerFuncs_none (lower := lowerFuncUnchecked) (lowers := lowerFuncsUnchecked) (fun _ _ => rfl)
            (fun _ _ _ _ => rfl) (fun _ _ _ _ _ _ => rfl) (lowerFuncUnchecked_big over) _ d _ _ mem]
  · rfl

end Lanius.Mini
