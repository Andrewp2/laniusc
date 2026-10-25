import Lanius.Faithful.Sim.Check

/-! # `PureProg` one function at a time

`PureProg` of a concrete program, from one fact per function (`FuncOk`): a
prim, a function `outside`, or a pure function. `FuncsOk n fs` says it of the
functions `fs` numbered from `n`, so a run of functions is checked on its
own (`funcsOk_cons`) and runs are put together (`funcsOk_append`). -/

namespace Lanius.Faithful

open Lanius.Mini

section
variable {sp : SrcProgram} {prims : Prims} {outside : List Nat}

/-- What `PureProg` asks of function `i`, `f`. -/
def FuncOk (sp : SrcProgram) (prims : Prims) (outside : List Nat) (i : Nat) (f : SrcFunc) : Prop :=
  prims.isPrim i = false → outside.contains i = false → PureFunc sp prims outside f = true

/-- What `PureProg` asks of the functions `fs`, numbered from `n`. -/
def FuncsOk (sp : SrcProgram) (prims : Prims) (outside : List Nat) (n : Nat) (fs : List SrcFunc) : Prop :=
  ∀ j f, fs[j]? = some f → FuncOk sp prims outside (n + j) f

theorem funcOk_pure {i : Nat} {f : SrcFunc} (h : PureFunc sp prims outside f = true) :
    FuncOk sp prims outside i f :=
  fun _ _ => h

theorem funcOk_prim {i : Nat} {f : SrcFunc} (h : prims.isPrim i = true) : FuncOk sp prims outside i f :=
  fun np _ => absurd h (by rw [np]; exact Bool.false_ne_true)

theorem funcOk_outside {i : Nat} {f : SrcFunc} (h : outside.contains i = true) :
    FuncOk sp prims outside i f :=
  fun _ no => absurd h (by rw [no]; exact Bool.false_ne_true)

theorem funcsOk_nil {n : Nat} : FuncsOk sp prims outside n [] :=
  fun _ _ h => nomatch h

theorem funcsOk_cons {n : Nat} {f : SrcFunc} {fs : List SrcFunc} (head : FuncOk sp prims outside n f)
    (tail : FuncsOk sp prims outside (n + 1) fs) : FuncsOk sp prims outside n (f :: fs)
  | 0, g, h => by
    rw [List.getElem?_cons_zero, Option.some.injEq] at h
    subst h
    exact head
  | j + 1, g, h => by
    rw [List.getElem?_cons_succ] at h
    have := tail j g h
    rwa [Nat.add_assoc, Nat.add_comm 1 j] at this

theorem funcsOk_append {n : Nat} {xs ys : List SrcFunc} (left : FuncsOk sp prims outside n xs)
    (right : FuncsOk sp prims outside (n + xs.length) ys) : FuncsOk sp prims outside n (xs ++ ys) := by
  intro j f h
  by_cases lt : j < xs.length
  · rw [List.getElem?_append_left lt] at h
    exact left j f h
  · have le : xs.length ≤ j := Nat.le_of_not_lt lt
    rw [List.getElem?_append_right le] at h
    have := right (j - xs.length) f h
    rwa [Nat.add_assoc, Nat.add_sub_cancel' le] at this

theorem pureProg_of_funcsOk (h : FuncsOk sp prims outside 0 sp.funcs) : PureProg sp prims outside := by
  intro i f found np no
  have := h i f found
  rw [Nat.zero_add] at this
  exact this np no

end

/-! ## The box structs, computed once

`boxElem` looks each `boxed` prim up in the program at every field read; a
concrete program's box structs are listed once (`boxPairs`) and looked up in
the list (`boxElem_eq`). -/

/-- The box struct id and element type of function `i`, a `boxed` prim. -/
def boxPair (sp : SrcProgram) (i : Nat) : Option (Nat × SrcType) :=
  (sp.funcs[i]?).bind fun f =>
    match f.params with
    | [] => none
    | [p] => some (f.ret.typeId, p.ty)
    | _ :: _ :: _ => none

/-- The element type of box struct `id` in a list of `boxPair`s. -/
def lookupBox (pairs : List (Option (Nat × SrcType))) (id : Nat) : Option SrcType :=
  pairs.findSome? fun pair => pair.bind fun kt => if kt.1 = id then some kt.2 else none

theorem boxElem_eq_lookup (sp : SrcProgram) (prims : Prims) (id : Nat) :
    boxElem sp prims id = lookupBox (prims.boxed.map (boxPair sp)) id := by
  unfold boxElem lookupBox
  induction prims.boxed with
  | nil => rfl
  | cons i rest ih =>
    rw [List.map_cons, List.findSome?_cons, List.findSome?_cons, ih]
    unfold boxPair
    cases sp.funcs[i]? with
    | none => rfl
    | some f =>
      simp only [Option.bind_some]
      match f.params with
      | [] => rfl
      | [p] => rfl
      | _ :: _ :: _ => rfl

def pairsSame : List (Option (Nat × SrcType)) → List (Option (Nat × SrcType)) → Bool
  | [], [] => true
  | [], _ :: _ => false
  | _ :: _, [] => false
  | none :: as, none :: bs => pairsSame as bs
  | none :: _, some _ :: _ => false
  | some _ :: _, none :: _ => false
  | some (i, s) :: as, some (j, t) :: bs => decide (i = j) && s.same t && pairsSame as bs

theorem pairsSame_eq : ∀ {as bs : List (Option (Nat × SrcType))}, pairsSame as bs = true → as = bs
  | [], [], _ => rfl
  | [], _ :: _, h => nomatch h
  | _ :: _, [], h => nomatch h
  | none :: as, none :: bs, h => by rw [pairsSame_eq (as := as) (bs := bs) h]
  | none :: _, some _ :: _, h => nomatch h
  | some _ :: _, none :: _, h => nomatch h
  | some (i, s) :: as, some (j, t) :: bs, h => by
    simp only [pairsSame, Bool.and_eq_true, decide_eq_true_eq] at h
    obtain ⟨⟨rfl, same⟩, rest⟩ := h
    rw [SrcType.same_eq same, pairsSame_eq rest]

theorem boxElem_eq {sp : SrcProgram} {prims : Prims} {pairs : List (Option (Nat × SrcType))}
    (h : pairsSame (prims.boxed.map (boxPair sp)) pairs = true) : boxElem sp prims = lookupBox pairs := by
  funext id
  rw [boxElem_eq_lookup, pairsSame_eq h]

/-! ## Declarations, computed once

`PrimsOk` asks `wordElement sp.decls t` of each prim's type; `declareProgram`
is slow to reduce, so a concrete program's declarations are compared once
with their value (`declsSame_eq`). -/

def structsSame : List SrcStructDecl → List SrcStructDecl → Bool
  | [], [] => true
  | [], _ :: _ => false
  | _ :: _, [] => false
  | a :: as, b :: bs => decide (a.id = b.id) && typesSame a.fields b.fields && structsSame as bs

def enumsSame : List SrcEnumDecl → List SrcEnumDecl → Bool
  | [], [] => true
  | [], _ :: _ => false
  | _ :: _, [] => false
  | a :: as, b :: bs => decide (a.id = b.id) && variantsSame a.variants b.variants && enumsSame as bs

def declsSame (a b : SrcDecls) : Bool := structsSame a.structs b.structs && enumsSame a.enums b.enums

theorem structsSame_eq : ∀ {as bs : List SrcStructDecl}, structsSame as bs = true → as = bs
  | [], [], _ => rfl
  | [], _ :: _, h => nomatch h
  | _ :: _, [], h => nomatch h
  | ⟨i, fs⟩ :: as, ⟨j, gs⟩ :: bs, h => by
    simp only [structsSame, Bool.and_eq_true, decide_eq_true_eq] at h
    obtain ⟨⟨rfl, same⟩, rest⟩ := h
    rw [typesSame_eq fs same, structsSame_eq rest]

theorem enumsSame_eq : ∀ {as bs : List SrcEnumDecl}, enumsSame as bs = true → as = bs
  | [], [], _ => rfl
  | [], _ :: _, h => nomatch h
  | _ :: _, [], h => nomatch h
  | ⟨i, vs⟩ :: as, ⟨j, ws⟩ :: bs, h => by
    simp only [enumsSame, Bool.and_eq_true, decide_eq_true_eq] at h
    obtain ⟨⟨rfl, same⟩, rest⟩ := h
    rw [variantsSame_eq vs same, enumsSame_eq rest]

theorem declsSame_eq {a b : SrcDecls} (h : declsSame a b = true) : a = b := by
  obtain ⟨as, ae⟩ := a
  obtain ⟨bs, be⟩ := b
  simp only [declsSame, Bool.and_eq_true] at h
  rw [structsSame_eq h.1, enumsSame_eq h.2]

end Lanius.Faithful
