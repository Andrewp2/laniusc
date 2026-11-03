module

public import Lanius.Faithful.Sim.ProgOk
public import Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.declareFuncs
import all Lanius.Mini.Compiler.P.declareProgram
import all Lanius.Mini.Compiler.P.enumVariants
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.lowerBody
import all Lanius.Mini.Compiler.P.matchVariants
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.Types
public import Lanius.Mini.Compiler.P.declareFuncs
public import Lanius.Mini.Compiler.P.declareProgram
public import Lanius.Mini.Compiler.P.enumVariants
public import Lanius.Mini.Compiler.P.lowerBody
public import Lanius.Mini.Compiler.P.matchVariants
public import Lanius.Mini.Compiler.P.structFields

@[expose] public section
/-! # `declareProgram` a run of functions at a time

`declareProgram` declares the struct and enum types of each function in turn,
each new one in front of those before (`func_grows`). So after any run of
functions the declarations are a suffix of the program's (`declAt decls a b`,
`decls` with `a` structs and `b` enums dropped), and a run of functions' step is
checked on its own (`declsStep`): the declarations it puts in front, and their
number, rather than the whole list. A program's `declareFuncs` is then a chain
of such steps over runs of its functions (`declareFuncs_append`). -/

namespace Lanius.Faithful

open Lanius.Mini

/-- `e` is `d` with declarations put in front. -/
def Grows (d e : SrcDecls) : Prop :=
  ∃ s n, e.structs = s ++ d.structs ∧ e.enums = n ++ d.enums ∧ e.statics = d.statics

theorem Grows.rfl' {d : SrcDecls} : Grows d d := ⟨[], [], rfl, rfl, rfl⟩

theorem Grows.trans {a b c : SrcDecls} : Grows a b → Grows b c → Grows a c
  | ⟨s, n, hs, hn, hc⟩, ⟨s', n', hs', hn', hc'⟩ =>
    ⟨s' ++ s, n' ++ n, by rw [hs', hs, List.append_assoc], by rw [hn', hn, List.append_assoc], by rw [hc', hc]⟩

/-- An `Option` step that grows: none, or a grown value. -/
def GrowsTo (d : SrcDecls) (x : Option SrcDecls) : Prop := ∀ e, x = some e → Grows d e

theorem growsTo_bind {d : SrcDecls} {x : Option SrcDecls} {k : SrcDecls → Option SrcDecls}
    (hx : GrowsTo d x) (hk : ∀ d', GrowsTo d' (k d')) : GrowsTo d (x.bind k) := by
  intro e h
  cases x with
  | none => exact nomatch h
  | some d' => exact (hx d' rfl).trans (hk d' e h)

theorem growsTo_some {d : SrcDecls} : GrowsTo d (some d) := fun _ h => by cases h; exact Grows.rfl'

theorem growsTo_struct {d : SrcDecls} {id : Nat} {fs : List SrcType} {x : Option SrcDecls} (hx : GrowsTo d x) :
    GrowsTo d (declareStruct id fs x) := by
  intro e h
  unfold declareStruct at h
  cases x with
  | none => exact nomatch h
  | some d' =>
    refine (hx d' rfl).trans ?_
    dsimp only at h
    cases hk : structFields d'.structs id with
    | none =>
      rw [hk] at h
      cases h
      exact ⟨[{ id := id, fields := fs }], [], rfl, rfl, rfl⟩
    | some other =>
      rw [hk] at h
      unfold keepIf at h
      dsimp only at h
      cases ha : typesSame other fs with
      | false => rw [ha] at h; exact nomatch h
      | true => rw [ha] at h; cases h; exact Grows.rfl'

theorem growsTo_enum {d : SrcDecls} {id : Nat} {vs : List (List SrcType)} {x : Option SrcDecls} (hx : GrowsTo d x) :
    GrowsTo d (declareEnum id vs x) := by
  intro e h
  unfold declareEnum at h
  cases x with
  | none => exact nomatch h
  | some d' =>
    refine (hx d' rfl).trans ?_
    dsimp only at h
    cases hk : enumVariants d'.enums id with
    | none =>
      rw [hk] at h
      cases h
      exact ⟨[], [{ id := id, variants := vs }], rfl, rfl, rfl⟩
    | some other =>
      rw [hk] at h
      unfold keepIf at h
      dsimp only at h
      cases ha : variantsSame other vs with
      | false => rw [ha] at h; exact nomatch h
      | true => rw [ha] at h; cases h; exact Grows.rfl'

/-- `GrowsTo d (let after := x; match after with | none => none | some d' => k d')`
from `hx : GrowsTo d x` and `hk : ∀ d', GrowsTo d' (k d')`. -/
macro "grow_bind " hx:term:max hk:term:max : tactic =>
  `(tactic| (intro e h; dsimp only at h; split at h
             · exact nomatch h
             · next d' hd' => exact ($hx d' hd').trans ($hk d' e h)))

mutual
theorem type_grows : ∀ (t : SrcType) (d : SrcDecls), GrowsTo d (SrcType.declare t d)
  | .i32, _ => by unfold SrcType.declare; exact growsTo_some
  | .bool, _ => by unfold SrcType.declare; exact growsTo_some
  | .uint _, _ => by unfold SrcType.declare; exact growsTo_some
  | .struct _ fs, d => by
    have ih := types_grows fs d
    unfold SrcType.declare; exact growsTo_struct ih
  | .enum _ vs, d => by
    have ih := variants_grows vs d
    unfold SrcType.declare; exact growsTo_enum ih
  | .ptr, _ => by unfold SrcType.declare; exact growsTo_some
  | .slice e, d => by
    have ih := type_grows e d
    unfold SrcType.declare; exact ih
  | .array e _, d => by
    have ih := type_grows e d
    unfold SrcType.declare; exact ih
  | .unit, _ => by unfold SrcType.declare; exact growsTo_some
  | .isize, _ => by unfold SrcType.declare; exact growsTo_some
  | .char, _ => by unfold SrcType.declare; exact growsTo_some
  | .float _, _ => by unfold SrcType.declare; exact growsTo_some
  | .sint _, _ => by unfold SrcType.declare; exact growsTo_some
  | .view _, _ => by unfold SrcType.declare; exact fun _ h => nomatch h
  | .str, _ => by unfold SrcType.declare; exact growsTo_some
  | .ref _, _ => by unfold SrcType.declare; exact fun _ h => nomatch h
  termination_by structural t => t
theorem types_grows : ∀ (ts : List SrcType) (d : SrcDecls), GrowsTo d (declareTypes ts d)
  | [], _ => by unfold declareTypes; exact growsTo_some
  | t :: rest, d => by
    have ih := type_grows t d
    have ih' := fun d' => types_grows rest d'
    unfold declareTypes
    grow_bind ih ih'
  termination_by structural ts => ts
theorem variants_grows : ∀ (vs : List (List SrcType)) (d : SrcDecls), GrowsTo d (declareVariants vs d)
  | [], _ => by unfold declareVariants; exact growsTo_some
  | v :: rest, d => by
    have ih := types_grows v d
    have ih' := fun d' => variants_grows rest d'
    unfold declareVariants
    grow_bind ih ih'
  termination_by structural vs => vs
end

theorem stmt_grows : ∀ (s : SrcStmt) (d : SrcDecls), GrowsTo d (SrcStmt.declare s d)
  | .nop, _ => by unfold SrcStmt.declare; exact growsTo_some
  | .let _ ty _ body, d => by
    have ih := stmt_grows body
    unfold SrcStmt.declare; grow_bind (type_grows ty d) ih
  | .letStruct _ ty _ body, d => by
    have ih := stmt_grows body
    unfold SrcStmt.declare; grow_bind (type_grows ty d) ih
  | .letCall _ ty _ _ body, d => by
    have ih := stmt_grows body
    unfold SrcStmt.declare; grow_bind (type_grows ty d) ih
  | .letEnum _ ty _ _ body, d => by
    have ih := stmt_grows body
    unfold SrcStmt.declare; grow_bind (type_grows ty d) ih
  | .letMatch _ ty _ _ _ body, d => by
    have ih := stmt_grows body
    unfold SrcStmt.declare; grow_bind (type_grows ty d) ih
  | .set _ _, _ => by unfold SrcStmt.declare; exact growsTo_some
  | .setField _ _ _, _ => by unfold SrcStmt.declare; exact growsTo_some
  | .setCall _ _ _, _ => by unfold SrcStmt.declare; exact growsTo_some
  | .then a b, d => by
    have ia := stmt_grows a d
    have ib := stmt_grows b
    unfold SrcStmt.declare; grow_bind ia ib
  | .if _ a b, d => by
    have ia := stmt_grows a d
    have ib := stmt_grows b
    unfold SrcStmt.declare; grow_bind ia ib
  | .while _ body, d => by
    have ih := stmt_grows body d
    unfold SrcStmt.declare; exact ih
  | .return _, _ => by unfold SrcStmt.declare; exact growsTo_some
  | .letAlloc _ _ _ body, d => by
    have ih := stmt_grows body d
    unfold SrcStmt.declare; exact ih
  | .letView _ _ _ _ body, d => by
    have ih := stmt_grows body d
    unfold SrcStmt.declare; exact ih
  | .letStr _ _ body, d => by
    have ih := stmt_grows body d
    unfold SrcStmt.declare; exact ih
  | .letLoad _ _ _ body, d => by
    have ih := stmt_grows body d
    unfold SrcStmt.declare; exact ih
  | .setByte _ _ _, _ => by unfold SrcStmt.declare; exact growsTo_some
  | .free _ _ _, _ => by unfold SrcStmt.declare; exact growsTo_some
  | .letSlice _ el _ _ body, d => by
    have ih := stmt_grows body
    unfold SrcStmt.declare; grow_bind (type_grows el d) ih
  | .letIndex _ ty _ _ body, d => by
    have ih := stmt_grows body
    unfold SrcStmt.declare; grow_bind (type_grows ty d) ih
  | .setIndex _ _ _, _ => by unfold SrcStmt.declare; exact growsTo_some
  | .letEval _ ty v body, d => by
    have ih := stmt_grows body
    unfold SrcStmt.declare; grow_bind (types_grows (ty :: SrcEff.types v) d) ih
  | .setEval _ v, d => by unfold SrcStmt.declare; exact types_grows _ d
  | .ifEval c a b, d => by
    have ia := stmt_grows a
    have ib := stmt_grows b
    unfold SrcStmt.declare
    have inner : GrowsTo d (let after : Option SrcDecls := declareTypes (SrcEff.types c) d
        match after with
        | none => none
        | some decls => SrcStmt.declare a decls) := by grow_bind (types_grows _ d) ia
    grow_bind inner ib
  | .whileEval c body, d => by
    have ih := stmt_grows body
    unfold SrcStmt.declare; grow_bind (types_grows (SrcEff.types c) d) ih
  | .returnEval v, d => by unfold SrcStmt.declare; exact types_grows _ d
  | .discard v, d => by unfold SrcStmt.declare; exact types_grows _ d
  | .setIndexEval _ i v, d => by unfold SrcStmt.declare; exact types_grows _ d
  | .setFieldEval _ _ v, d => by unfold SrcStmt.declare; exact types_grows _ d
  | .returnUnit, _ => by unfold SrcStmt.declare; exact growsTo_some
  | .assert c, d => by unfold SrcStmt.declare; exact types_grows _ d
  | .break, _ => by unfold SrcStmt.declare; exact growsTo_some
  | .continue, _ => by unfold SrcStmt.declare; exact growsTo_some
  | .matchArm _ _ _ _ _ ty body rest, d => by
    have ib := stmt_grows body
    have ir := stmt_grows rest
    unfold SrcStmt.declare
    have inner : GrowsTo d (let after : Option SrcDecls := SrcType.declare ty d
        match after with
        | none => none
        | some decls => SrcStmt.declare body decls) := by grow_bind (type_grows ty d) ib
    grow_bind inner ir
  | .unreachable _ ty, d => by unfold SrcStmt.declare; exact type_grows ty d

theorem params_grows : ∀ (ps : List SrcParam) (d : SrcDecls), GrowsTo d (declareParams ps d)
  | [], _ => by unfold declareParams; exact growsTo_some
  | p :: rest, d => by
    have ih := params_grows rest
    unfold declareParams; grow_bind (type_grows p.ty d) ih

theorem func_grows (f : SrcFunc) (d : SrcDecls) : GrowsTo d (declareFunc f d) := by
  unfold declareFunc
  intro e h
  dsimp only at h
  split at h
  · exact nomatch h
  · next d1 h1 =>
    split at h
    · exact nomatch h
    · next d2 h2 => exact ((params_grows _ d d1 h1).trans (type_grows _ d1 d2 h2)).trans (stmt_grows _ d2 e h)

/-! ## One function's step -/

/-- `d` with its first `a` structs and `b` enums dropped. -/
def declAt (d : SrcDecls) (a b : Nat) : SrcDecls := ⟨d.structs.drop a, d.enums.drop b, d.statics⟩

theorem declAt_zero (d : SrcDecls) : declAt d 0 0 = d := by
  cases d; rfl

/-- `r`, the result of declaring from `declAt d a b`, is `declAt d a' b'`:
what it put in front is `d`'s structs `a'` to `a` and enums `b'` to `b`. -/
def stepFits (r : Option SrcDecls) (d : SrcDecls) (a b a' b' : Nat) : Bool :=
  match r with
  | none => false
  | some e =>
    decide (a' ≤ a) && decide (a ≤ d.structs.length) && decide (b' ≤ b) && decide (b ≤ d.enums.length) &&
      e.structs.length == (d.structs.drop a').length && e.enums.length == (d.enums.drop b').length &&
      structsSame (e.structs.take (a - a')) ((d.structs.drop a').take (a - a')) &&
      enumsSame (e.enums.take (b - b')) ((d.enums.drop b').take (b - b'))

/-- A list that is `s ++ L.drop a`, as long as `L.drop a'`, with `s` the first
`a - a'` of `L.drop a'`, is `L.drop a'`. -/
theorem drop_of_front {α : Type} {L s e : List α} {a a' : Nat} (le : a' ≤ a) (fit : a ≤ L.length)
    (he : e = s ++ L.drop a) (len : e.length = (L.drop a').length) (front : e.take (a - a') = (L.drop a').take (a - a')) :
    e = L.drop a' := by
  have ls : s.length = a - a' := by
    rw [he] at len
    simp only [List.length_append, List.length_drop] at len
    omega
  have hs : s = (L.drop a').take (a - a') := by
    rw [← front, he, List.take_left' ls]
  have rest : (L.drop a').drop (a - a') = L.drop a := by
    rw [List.drop_drop]
    congr 1
    omega
  rw [he, hs, ← rest, List.take_append_drop]

theorem stepFits_eq {r : Option SrcDecls} {d : SrcDecls} {a b a' b' : Nat} (hg : GrowsTo (declAt d a b) r)
    (h : stepFits r d a b a' b' = true) : r = some (declAt d a' b') := by
  unfold stepFits at h
  split at h
  · exact nomatch h
  · next e =>
    simp only [Bool.and_eq_true, decide_eq_true_eq, beq_iff_eq] at h
    obtain ⟨⟨⟨⟨⟨⟨⟨le, fit⟩, le'⟩, fit'⟩, len⟩, len'⟩, fs⟩, fe⟩ := h
    obtain ⟨s, n, hs, hn, hc⟩ := hg e rfl
    obtain ⟨es, ee, ec⟩ := e
    simp only [declAt] at hs hn hc ⊢
    rw [drop_of_front le fit hs len (structsSame_eq fs), drop_of_front le' fit' hn len' (enumsSame_eq fe), hc]

theorem funcs_grows : ∀ (fs : List SrcFunc) (d : SrcDecls), GrowsTo d (declareFuncs fs d)
  | [], _ => by unfold declareFuncs; exact growsTo_some
  | f :: rest, d => by
    have ih := funcs_grows rest
    unfold declareFuncs; grow_bind (func_grows f d) ih

/-- `declareFuncs fs` takes `declAt d a b` to `declAt d a' b'`. -/
def declsStep (fs : List SrcFunc) (d : SrcDecls) (a b a' b' : Nat) : Bool :=
  stepFits (declareFuncs fs (declAt d a b)) d a b a' b'

theorem declsStep_eq {fs : List SrcFunc} {d : SrcDecls} {a b a' b' : Nat} (h : declsStep fs d a b a' b' = true) :
    declareFuncs fs (declAt d a b) = some (declAt d a' b') :=
  stepFits_eq (funcs_grows fs _) h

theorem declareFuncs_append : ∀ {xs ys : List SrcFunc} {d d' e : SrcDecls},
    declareFuncs xs d = some d' → declareFuncs ys d' = some e → declareFuncs (xs ++ ys) d = some e
  | [], _, _, _, _, hx, hy => by
    unfold declareFuncs at hx
    cases hx
    exact hy
  | f :: rest, _, d, _, _, hx, hy => by
    unfold declareFuncs at hx
    dsimp only at hx
    split at hx
    · exact nomatch hx
    · next d1 h1 =>
      rw [List.cons_append]
      unfold declareFuncs
      dsimp only
      rw [h1]
      exact declareFuncs_append hx hy

theorem decls_of_funcs {sp : SrcProgram} {d : SrcDecls} (h : declareFuncs sp.funcs ⟨[], [], sp.statics⟩ = some d) :
    sp.decls = d := by
  unfold SrcProgram.decls declareProgram
  rw [h]

end Lanius.Faithful
