module

public import Lanius.Open.F14.ValidateFilesHeight.Stmt
public import Lanius.Mini.Frontend.P.isEmptyUsize
public import Lanius.Mini.Frontend.P.noTokens
public import Lanius.Mini.Frontend.P.nodeProd
public import Lanius.Mini.Frontend.P.usedUp
public import Lanius.Mini.Frontend.P.validateTree
public import Lanius.Mini.Frontend.P.whole
import all Lanius.Mini.Compiler.P.UintTy_code
import all Lanius.Mini.Compiler.P.entriesAt
import all Lanius.Mini.Compiler.P.funcsSize
import all Lanius.Mini.Compiler.P.funcsSlots
import all Lanius.Mini.Compiler.P.linkObjects
import all Lanius.Mini.Compiler.P.objectExports
import all Lanius.Mini.Compiler.P.objectFirsts
import all Lanius.Mini.Compiler.P.objectLayout
import all Lanius.Mini.Compiler.P.objectsLayout
import all Lanius.Mini.Compiler.P.objectsOk
import all Lanius.Mini.Compiler.P.objectsSlots
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.renderFuncs
import all Lanius.Mini.Compiler.P.renderObjects
import all Lanius.Mini.Frontend.P.isEmptyUsize
import all Lanius.Mini.Frontend.P.noTokens
import all Lanius.Mini.Frontend.P.nodeProd
import all Lanius.Mini.Frontend.P.usedUp
import all Lanius.Mini.Frontend.P.validateTree
import all Lanius.Mini.Frontend.P.whole
import all Lanius.Mini.Frontend.P.attach
import all Lanius.Mini.Frontend.P.only
import all Lanius.Mini.Frontend.P.shrFirst
import all Lanius.Mini.Frontend.P.shrSecond
import all Lanius.Mini.Frontend.P.build
import all Lanius.Mini.Frontend.P.buildChecked
import all Lanius.Mini.Frontend.P.buildClosed
import all Lanius.Mini.Frontend.P.buildCollected
import all Lanius.Mini.Frontend.P.buildFiles
import all Lanius.Mini.Frontend.P.buildMono
import all Lanius.Mini.Frontend.P.consRoot
import all Lanius.Mini.Frontend.P.filesFuel
import all Lanius.Mini.Frontend.P.frontEnd
import all Lanius.Mini.Frontend.P.frontEndFiles
import all Lanius.Mini.Frontend.P.lxDigit
import all Lanius.Mini.Frontend.P.lxIdentContinue
import all Lanius.Mini.Frontend.P.lxIdentStart
import all Lanius.Mini.Frontend.P.lxSpace
import all Lanius.Mini.Frontend.P.untypedRejected
import all Lanius.Mini.Frontend.P.validateFiles
import all Lanius.Mini.Frontend.P.wideLeftFuncs
import all Lanius.Mini.Frontend.P.wideLeftStmt
import all Lanius.Mini.Frontend.P.genericTail
import all Lanius.Mini.Frontend.P.kid
import all Lanius.Mini.Frontend.P.kidsOf
import all Lanius.Mini.Frontend.P.noToken
import all Lanius.Mini.Frontend.P.startsWithKind
import all Lanius.Mini.Frontend.P.withKid

@[expose] public section

/-! # `ValidateFilesHeight`: the trees validated are lower than `2 ^ 61`

`attach` takes one fuel for each child it attaches, so the children it builds
with fuel `f` are at most `f` higher than the tokens (`attach_hb`): a leaf is a
token, a node's children were attached with less fuel. A `>>` split in two
makes tokens one later, still within the bound when the `>>` was lower than it
(`TokH`). `validateTree`'s fuel is twice the productions and tokens and two,
so each tree is lower than `2 ^ 43`, and the trees together lower than `2 ^ 44`. -/

open Lanius.Mini
open Lanius.Faithful.SelfPre

namespace Lanius.Open.ValidateFilesHeight

/-- Every token is at most `T` high, and a `>>` starts before `T`. -/
def TokH (T : Nat) (ts : List Token) : Prop :=
  ∀ t ∈ ts, hb t ≤ T ∧ (t.kind = 44 → t.start + 1 ≤ T)

theorem hb_text62 : hb ([62] : List Nat) = 1 := rfl

theorem hb_shrFirst {T : Nat} (hT : 1 ≤ T) {t : Token} (h : hb t ≤ T) : hb (shrFirst t) ≤ T := by
  have := hb_le_Token_start t
  unfold shrFirst
  simp only [hb_Token_mk, hb_text62]
  omega

theorem tokH_shrSecond {T : Nat} (hT : 1 ≤ T) {t : Token} (hk : t.kind = 44)
    (h : hb t ≤ T ∧ (t.kind = 44 → t.start + 1 ≤ T)) :
    hb (shrSecond t) ≤ T ∧ ((shrSecond t).kind = 44 → (shrSecond t).start + 1 ≤ T) := by
  have := h.2 hk
  refine ⟨?_, fun e => absurd (show (13 : Nat) = 44 from e) (by decide)⟩
  unfold shrSecond
  simp only [hb_Token_mk, hb_text62]
  omega

/-- **The children `attach` builds with fuel `f` are at most `f` higher than the tokens.** -/
theorem attach_hb {T : Nat} (hT : 1 ≤ T) (g : List Rule) :
    ∀ (fuel : Nat) (rhs : List Sym) (parent : Nat) (cur : Cursor) (a : Attached),
      TokH T cur.tokens → attach g fuel rhs parent cur = some a → hb a.kids ≤ fuel + T ∧ TokH T a.rest.tokens
  | 0, _, _, _, _, _, h => by unfold attach at h; simp at h
  | fuel + 1, rhs, parent, cur, a, hc, h => by
    unfold attach at h
    simp only [Nat.add_one_ne_zero, if_false, Nat.add_sub_cancel] at h
    split at h
    · simp only [Option.some.injEq] at h
      subst h
      exact ⟨by simp, hc⟩
    · rename_i sym more
      split at h
      · split at h
        · cases h
        · rename_i tok toks e
          rw [e] at hc
          have htok := hc tok List.mem_cons_self
          have hrest : TokH T toks := fun t ht => hc t (List.mem_cons_of_mem _ ht)
          split at h
          · unfold withKid at h
            split at h
            · cases h
            · rename_i a' e'
              simp only [Option.some.injEq] at h
              subst h
              have ih := attach_hb hT g fuel more parent ⟨cur.prods, cur.parents, toks, cur.index⟩ a' hrest e'
              refine ⟨?_, ih.2⟩
              simp only [hb_cons, hb_CTree_leaf]
              have := htok.1
              omega
          · split at h
            · rename_i hk
              simp only [Bool.and_eq_true, decide_eq_true_eq] at hk
              unfold withKid at h
              split at h
              · cases h
              · rename_i a' e'
                simp only [Option.some.injEq] at h
                subst h
                have hc' : TokH T (shrSecond tok :: toks) := by
                  intro t ht
                  simp only [List.mem_cons] at ht
                  rcases ht with rfl | ht
                  · exact tokH_shrSecond hT hk.1 htok
                  · exact hrest t ht
                have ih := attach_hb hT g fuel more parent ⟨cur.prods, cur.parents, shrSecond tok :: toks, cur.index⟩
                  a' hc' e'
                refine ⟨?_, ih.2⟩
                simp only [hb_cons, hb_CTree_leaf]
                have := hb_shrFirst hT htok.1
                omega
            · cases h
      · split at h
        · cases h
        · rename_i p ps ep
          split at h
          · cases h
          · rename_i q qs eq
            split at h
            · cases h
            · split at h
              · cases h
              · rename_i prod _
                split at h
                · cases h
                · split at h
                  · cases h
                  · rename_i a1 e1
                    have c1 := attach_hb hT g fuel prod.rhs cur.index ⟨ps, qs, cur.tokens, cur.index + 1⟩ a1 hc e1
                    unfold withKid at h
                    split at h
                    · cases h
                    · rename_i a2 e2
                      simp only [Option.some.injEq] at h
                      subst h
                      have c2 := attach_hb hT g fuel more parent _ a2 c1.2 e2
                      refine ⟨?_, c2.2⟩
                      simp only [hb_cons, hb_CTree_node]
                      have := c1.1
                      have := c2.1
                      omega

theorem whole_hb {a : Attached} {root : CTree} (h : whole a = some root) : hb root < hb a.kids := by
  unfold whole at h
  split at h
  · split at h
    · cases h
    · rename_i r more e
      unfold only at h
      split at h
      · simp only [Option.some.injEq] at h
        subst h
        rw [e]
        exact hb_le_of_mem List.mem_cons_self
      · cases h
  · cases h

theorem hb_nats : ∀ l : List Nat, hb l = l.length
  | [] => rfl
  | a :: l => by simp only [hb_cons, hb_nat, Nat.zero_max, List.length_cons, hb_nats l]

/-- A tree `validateTree` builds is at most five times the file's height and five higher. -/
theorem validateTree_hb (g : List Rule) (f : FileInput) {root : CTree}
    (h : validateTree g f.tokens f.prods f.parents = some root) : hb root ≤ 5 * hb f + 5 := by
  unfold validateTree at h
  dsimp only at h
  split at h
  · cases h
  · rename_i a e
    have hT : TokH (hb f.tokens + 1) f.tokens := by
      intro t ht
      have h1 := hb_le_of_mem ht
      have h2 := hb_le_Token_start t
      exact ⟨by omega, fun _ => by omega⟩
    have ha := attach_hb (T := hb f.tokens + 1) (by omega) g _ _ _ _ a hT e
    have hr := whole_hb h
    have l1 := length_le_hb f.tokens
    have l2 := hb_le_FileInput_tokens f
    have l3 := hb_le_FileInput_prods f
    rw [hb_nats] at l3
    have := ha.1
    omega

theorem validateFiles_hb (g : List Rule) : ∀ (fs : List FileInput) (ts : List CTree),
    validateFiles g fs = some ts → hb ts ≤ 5 * hb fs + 5
  | [], ts, h => by
    unfold validateFiles at h
    simp only [Option.some.injEq] at h
    subst h
    simp
  | f :: fs, ts, h => by
    unfold validateFiles at h
    unfold consRoot at h
    split at h
    · cases h
    · rename_i r er
      split at h
      · cases h
      · rename_i rs ers
        simp only [Option.some.injEq] at h
        subst h
        have h1 := validateTree_hb g f er
        have h2 := validateFiles_hb g fs rs ers
        simp only [hb_cons]
        omega

end Lanius.Open.ValidateFilesHeight

open Lanius.Open.ValidateFilesHeight in
theorem Lanius.Open.ValidateFilesHeight.proof : Lanius.Open.ValidateFilesHeight := by
  intro fs ts h hfs
  have := validateFiles_hb grammar fs ts h
  omega
