module

public import Lanius.Faithful.Pure

@[expose] public section
/-! # What a statement keeps of the environment

An assignment replaces the newest binding of its local (`Env.set`), so a
statement keeps the environment's locals, in order, and every binding a
newer one of the same local hides (`Agree`, `mstmt_agree`). A `let`'s body
so keeps the binding its local shadows, which the `let` uncovers again. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)

theorem Env.get?_cons'' (env : Env) (k id : Nat) (v : Value) :
    Env.get? ((k, v) :: env) id = if k = id then some v else env.get? id := by
  by_cases h : k = id
  · simp [Env.get?, List.find?, h]
  · have : (k == id) = false := by simpa using h
    simp [Env.get?, List.find?, this, h]

theorem Env.set_get_self : ∀ {env e : Env} {id : Nat} {v : Value}, env.set id v = some e → e.get? id = some v
  | [], _, _, _, h => by simp [Env.set] at h
  | (x, w) :: rest, e, id, v, h => by
    simp only [Env.set] at h
    split at h
    · rename_i hx
      simp only [Option.some.injEq] at h
      subst h hx
      simp [Env.get?_cons'']
    · rename_i hx
      simp only [Option.map_eq_some_iff] at h
      obtain ⟨r, hr, rfl⟩ := h
      rw [Env.get?_cons'', if_neg hx]
      exact Env.set_get_self hr

theorem Env.set_get_ne : ∀ {env e : Env} {id x : Nat} {v : Value}, env.set id v = some e → x ≠ id →
    e.get? x = env.get? x
  | [], _, _, _, _, h, _ => by simp [Env.set] at h
  | (y, w) :: rest, e, id, x, v, h, ne => by
    simp only [Env.set] at h
    split at h
    · rename_i hy
      simp only [Option.some.injEq] at h
      subst h hy
      simp only [Env.get?_cons'']
      by_cases hx : y = x
      · exact absurd hx.symm ne
      · rw [if_neg hx, if_neg hx]
    · simp only [Option.map_eq_some_iff] at h
      obtain ⟨r, hr, rfl⟩ := h
      simp only [Env.get?_cons'']
      split
      · rfl
      · exact Env.set_get_ne hr ne

theorem Env.set_isSome : ∀ {env : Env} {id : Nat} (v : Value), (env.get? id).isSome → ∃ e, env.set id v = some e
  | [], _, _, h => by simp [Env.get?] at h
  | (y, w) :: rest, id, v, h => by
    simp only [Env.set]
    split
    · exact ⟨_, rfl⟩
    · rename_i hy
      rw [Env.get?_cons'', if_neg hy] at h
      obtain ⟨e, he⟩ := Env.set_isSome (env := rest) v h
      exact ⟨_, by rw [he]; rfl⟩

/-- `e` has the locals of `env`, in order, and the value of each binding of a
local in `ks` or hidden by a newer binding. -/
def Agree : List Nat → Env → Env → Prop
  | _, [], [] => True
  | ks, (x, v) :: env, (y, w) :: e => x = y ∧ (x ∈ ks → v = w) ∧ Agree (x :: ks) env e
  | _, [], _ :: _ => False
  | _, _ :: _, [] => False

theorem Agree.refl : ∀ (ks : List Nat) (env : Env), Agree ks env env
  | _, [] => trivial
  | ks, (x, _) :: env => ⟨rfl, fun _ => rfl, Agree.refl (x :: ks) env⟩

theorem Agree.trans : ∀ {ks : List Nat} {a b c : Env}, Agree ks a b → Agree ks b c → Agree ks a c
  | _, [], [], [], _, _ => trivial
  | _, [], [], _ :: _, _, h => h.elim
  | _, [], _ :: _, _, h, _ => h.elim
  | _, _ :: _, [], _, h, _ => h.elim
  | _, _ :: _, _ :: _, [], _, h => h.elim
  | _, (x, u) :: a, (y, v) :: b, (z, w) :: c, ⟨e1, k1, r1⟩, ⟨e2, k2, r2⟩ => by
    subst e1 e2
    exact ⟨rfl, fun m => (k1 m).trans (k2 m), Agree.trans r1 r2⟩

theorem Agree.weaken : ∀ {ks ks' : List Nat} {a b : Env}, (∀ k ∈ ks, k ∈ ks') → Agree ks' a b → Agree ks a b
  | _, _, [], [], _, _ => trivial
  | _, _, [], _ :: _, _, h => h.elim
  | _, _, _ :: _, [], _, h => h.elim
  | _, _, (x, _) :: _, (_, _) :: _, sub, ⟨e, k, r⟩ =>
    ⟨e, fun m => k (sub x m), Agree.weaken (fun k' m => by
      rcases List.mem_cons.mp m with h | h
      · exact h ▸ List.mem_cons_self
      · exact List.mem_cons_of_mem _ (sub k' h)) r⟩

theorem Agree.get : ∀ {ks : List Nat} {env e : Env} {x : Nat}, Agree ks env e → x ∈ ks → e.get? x = env.get? x
  | _, [], [], _, _, _ => rfl
  | _, [], _ :: _, _, h, _ => h.elim
  | _, _ :: _, [], _, h, _ => h.elim
  | _, (y, v) :: env, (y', w) :: e, x, ⟨eq, k, r⟩, m => by
    subst eq
    simp only [Env.get?_cons'']
    split
    · rename_i hx
      exact (k (hx ▸ m)).symm ▸ rfl
    · exact Agree.get r (List.mem_cons_of_mem _ m)

theorem Agree.cons_inv {ks : List Nat} {id : Nat} {v : Value} {env e : Env} (h : Agree ks ((id, v) :: env) e) :
    ∃ w rest, e = (id, w) :: rest ∧ Agree (id :: ks) env rest := by
  cases e with
  | nil => exact h.elim
  | cons b rest =>
    obtain ⟨y, w⟩ := b
    obtain ⟨eq, -, r⟩ := h
    subst eq
    exact ⟨w, rest, rfl, r⟩

/-- After a `let`'s body: the bindings below the `let`'s are kept, and the
one its local hid. -/
theorem Agree.pop {id : Nat} {v : Value} {env e : Env} (h : Agree [] ((id, v) :: env) e) :
    Agree [] env e.tail ∧ Env.get? e.tail id = env.get? id ∧ ∃ w, e = (id, w) :: e.tail := by
  obtain ⟨w, rest, rfl, r⟩ := h.cons_inv
  exact ⟨Agree.weaken (fun _ m => by simp at m) r, Agree.get r List.mem_cons_self, w, rfl⟩

theorem Agree.set : ∀ {ks : List Nat} {env e : Env} {id : Nat} {v : Value}, id ∉ ks → env.set id v = some e →
    Agree ks env e
  | _, [], _, _, _, _, h => by simp [Env.set] at h
  | ks, (x, w) :: rest, e, id, v, notIn, h => by
    simp only [Env.set] at h
    split at h
    · rename_i hx
      simp only [Option.some.injEq] at h
      subst h hx
      exact ⟨rfl, fun m => absurd m notIn, Agree.refl _ _⟩
    · rename_i hx
      simp only [Option.map_eq_some_iff] at h
      obtain ⟨r, hr, rfl⟩ := h
      refine ⟨rfl, fun _ => rfl, Agree.set ?_ hr⟩
      intro m
      rcases List.mem_cons.mp m with h | h
      · exact hx h.symm
      · exact notIn h

theorem Out.pop_env {o : Out} {e : Env} (h : o.pop.env? = some e) : ∃ eb, o.env? = some eb ∧ e = eb.tail := by
  cases o with
  | next eb => simp only [Out.pop, Out.env?, Option.some.injEq] at h; exact ⟨eb, rfl, h.symm⟩
  | brk eb => simp only [Out.pop, Out.env?, Option.some.injEq] at h; exact ⟨eb, rfl, h.symm⟩
  | cont eb => simp only [Out.pop, Out.env?, Option.some.injEq] at h; exact ⟨eb, rfl, h.symm⟩
  | ret v => simp [Out.pop, Out.env?] at h

/-- A `let`'s ending keeps what its body's kept, below the binding. -/
theorem agree_pop {id : Nat} {v : Value} {env : Env} {ob : Out}
    (ih : ∀ e, ob.env? = some e → Agree [] ((id, v) :: env) e) : ∀ e, ob.pop.env? = some e → Agree [] env e := by
  intro e he
  obtain ⟨eb, heb, rfl⟩ := Out.pop_env he
  exact (ih eb heb).pop.1

theorem agree_then {env : Env} {o1 o : Out} {k : Env → Option Out}
    (ih1 : ∀ e, o1.env? = some e → Agree [] env e)
    (ih2 : ∀ e1, o1 = .next e1 → ∀ o', k e1 = some o' → ∀ e, o'.env? = some e → Agree [] e1 e)
    (h : Out.then k o1 = some o) : ∀ e, o.env? = some e → Agree [] env e := by
  intro e he
  cases o1 with
  | next e1 => exact (ih1 e1 rfl).trans (ih2 e1 rfl o h e he)
  | brk e1 =>
    simp only [Out.then, Option.some.injEq] at h
    subst h
    exact ih1 e he
  | cont e1 =>
    simp only [Out.then, Option.some.injEq] at h
    subst h
    exact ih1 e he
  | ret v =>
    simp only [Out.then, Option.some.injEq] at h
    subst h
    simp [Out.env?] at he

/-- A loop keeps what its body keeps. -/
theorem ploop_agree {test : Env → Option Bool} {body : Env → Option Out}
    (hb : ∀ env o, body env = some o → ∀ e, o.env? = some e → Agree [] env e) :
    ∀ (n : Nat) {env : Env} {o : Out}, ploop test body n env = some o → ∀ e, o.env? = some e → Agree [] env e
  | 0, _, _, h => by simp [ploop] at h
  | n + 1, env, o, h => by
    simp only [ploop, Option.bind_eq_some_iff] at h
    obtain ⟨b, -, h⟩ := h
    cases b with
    | false =>
      simp only [Bool.false_eq_true, if_false, Option.some.injEq] at h
      subst h
      intro e he
      simp only [Out.env?, Option.some.injEq] at he
      subst he
      exact Agree.refl _ _
    | true =>
      simp only [if_true, Option.bind_eq_some_iff] at h
      obtain ⟨ob, hob, h⟩ := h
      cases ob with
      | next e1 => exact fun e he => (hb env _ hob e1 rfl).trans (ploop_agree hb n h e he)
      | cont e1 => exact fun e he => (hb env _ hob e1 rfl).trans (ploop_agree hb n h e he)
      | brk e1 =>
        simp only [Option.some.injEq] at h
        subst h
        intro e he
        simp only [Out.env?, Option.some.injEq] at he
        subst he
        exact hb env _ hob _ rfl
      | ret v =>
        simp only [Option.some.injEq] at h
        subst h
        intro e he
        simp [Out.env?] at he

/-- **A statement keeps the environment's locals and its hidden bindings.** -/
theorem mstmt_agree (call : Calls) (fuel : Nat) :
    ∀ (s : SrcStmt) {env : Env} {o : Out}, mstmt call fuel env s = some o →
      ∀ e, o.env? = some e → Agree [] env e := by
  intro s
  induction s with
  | nop =>
    intro env o h e he
    simp only [mstmt, Option.some.injEq] at h
    subst h
    simp only [Out.env?, Option.some.injEq] at he
    subst he
    exact Agree.refl _ _
  | «let» id _ value body ih =>
    intro env o h
    simp only [mstmt, Option.bind_eq_some_iff, Option.map_eq_some_iff] at h
    obtain ⟨v, -, ob, hb, rfl⟩ := h
    exact agree_pop (ih hb)
  | letStruct id ty fields body ih =>
    intro env o h
    simp only [mstmt, Option.bind_eq_some_iff, Option.map_eq_some_iff] at h
    obtain ⟨v, -, ob, hb, rfl⟩ := h
    exact agree_pop (ih hb)
  | letCall id _ callee args body ih =>
    intro env o h
    simp only [mstmt, Option.bind_eq_some_iff, Option.map_eq_some_iff] at h
    obtain ⟨v, -, ob, hb, rfl⟩ := h
    exact agree_pop (ih hb)
  | letEnum id ty variant payload body ih =>
    intro env o h
    simp only [mstmt, Option.bind_eq_some_iff, Option.map_eq_some_iff] at h
    obtain ⟨v, -, ob, hb, rfl⟩ := h
    exact agree_pop (ih hb)
  | letEval id _ value body ih =>
    intro env o h
    simp only [mstmt, Option.bind_eq_some_iff, Option.map_eq_some_iff] at h
    obtain ⟨v, -, ob, hb, rfl⟩ := h
    exact agree_pop (ih hb)
  | set id value =>
    intro env o h e he
    simp only [mstmt, Option.bind_eq_some_iff, Option.map_eq_some_iff] at h
    obtain ⟨v, -, e', hs, rfl⟩ := h
    simp only [Out.env?, Option.some.injEq] at he
    subst he
    exact Agree.set (by simp) hs
  | setEval id value =>
    intro env o h e he
    simp only [mstmt, Option.bind_eq_some_iff, Option.map_eq_some_iff] at h
    obtain ⟨v, -, e', hs, rfl⟩ := h
    simp only [Out.env?, Option.some.injEq] at he
    subst he
    exact Agree.set (by simp) hs
  | «then» first second ih1 ih2 =>
    intro env o h
    simp only [mstmt, Option.bind_eq_some_iff] at h
    obtain ⟨o1, h1, h2⟩ := h
    exact agree_then (ih1 h1) (fun e1 _ o' h' => ih2 h') h2
  | «if» condition a b iha ihb =>
    intro env o h
    simp only [mstmt, Option.bind_eq_some_iff] at h
    obtain ⟨x, -, hx⟩ := h
    cases x
    · exact ihb hx
    · exact iha hx
  | ifEval condition a b iha ihb =>
    intro env o h
    simp only [mstmt, Option.bind_eq_some_iff] at h
    obtain ⟨x, -, hx⟩ := h
    cases x
    · exact ihb hx
    · exact iha hx
  | «return» value =>
    intro env o h e he
    simp only [mstmt, Option.map_eq_some_iff] at h
    obtain ⟨v, -, rfl⟩ := h
    simp [Out.env?] at he
  | returnEval value =>
    intro env o h e he
    simp only [mstmt, Option.map_eq_some_iff] at h
    obtain ⟨v, -, rfl⟩ := h
    simp [Out.env?] at he
  | discard value =>
    intro env o h e he
    simp only [mstmt, Option.map_eq_some_iff] at h
    obtain ⟨v, -, rfl⟩ := h
    simp only [Out.env?, Option.some.injEq] at he
    subst he
    exact Agree.refl _ _
  | «assert» condition =>
    intro env o h e he
    simp only [mstmt, Option.bind_eq_some_iff] at h
    obtain ⟨x, -, hx⟩ := h
    cases x
    · simp at hx
    · simp only [if_true, Option.some.injEq] at hx
      subst hx
      simp only [Out.env?, Option.some.injEq] at he
      subst he
      exact Agree.refl _ _
  | returnUnit =>
    intro env o h e he
    simp only [mstmt, Option.some.injEq] at h
    subst h
    simp [Out.env?] at he
  | «while» condition body ih =>
    intro env o h
    exact ploop_agree (fun _ _ h' => ih h') fuel h
  | whileEval condition body ih =>
    intro env o h
    exact ploop_agree (fun _ _ h' => ih h') fuel h
  | «break» | «continue» =>
    intro env o h e he
    simp only [mstmt, Option.some.injEq] at h
    subst h
    simp only [Out.env?, Option.some.injEq] at he
    subst he
    exact Agree.refl _ _
  | letMatch | setField | setCall | letAlloc | letView | letStr | letLoad | setByte | free | letSlice | letIndex
  | setIndex | setIndexEval | setFieldEval | setPlace | setPlaceOp | matchArm | unreachable =>
    intro env o h; simp [mstmt] at h

/-- A `let`'s ending keeps the locals its body did not assign, below the
binding. -/
theorem unwritten_pop {id : Nat} {v : Value} {env : Env} {ob : Out} {ws : List Nat}
    (hag : ∀ e, ob.env? = some e → Agree [] ((id, v) :: env) e)
    (ih : ∀ e, ob.env? = some e → ∀ x, x ∉ ws → e.get? x = Env.get? ((id, v) :: env) x) :
    ∀ e, ob.pop.env? = some e → ∀ x, x ∉ ws → e.get? x = env.get? x := by
  intro e he x hx
  obtain ⟨eb, heb, rfl⟩ := Out.pop_env he
  obtain ⟨-, hid, w, hw⟩ := (hag eb heb).pop
  by_cases hxi : x = id
  · subst hxi
    exact hid
  · have h := ih eb heb x hx
    rw [hw] at h
    simp only [Env.get?_cons'', if_neg (Ne.symm hxi)] at h
    exact h

theorem unwritten_then {env : Env} {o1 o : Out} {k : Env → Option Out} {ws1 ws2 : List Nat}
    (ih1 : ∀ e, o1.env? = some e → ∀ x, x ∉ ws1 → e.get? x = env.get? x)
    (ih2 : ∀ e1, o1 = .next e1 → ∀ o', k e1 = some o' → ∀ e, o'.env? = some e → ∀ x, x ∉ ws2 →
      e.get? x = e1.get? x)
    (h : Out.then k o1 = some o) : ∀ e, o.env? = some e → ∀ x, x ∉ ws1 ++ ws2 → e.get? x = env.get? x := by
  intro e he x hx
  rw [List.mem_append, not_or] at hx
  cases o1 with
  | next e1 => exact (ih2 e1 rfl o h e he x hx.2).trans (ih1 e1 rfl x hx.1)
  | brk e1 =>
    simp only [Out.then, Option.some.injEq] at h
    subst h
    exact ih1 e he x hx.1
  | cont e1 =>
    simp only [Out.then, Option.some.injEq] at h
    subst h
    exact ih1 e he x hx.1
  | ret v =>
    simp only [Out.then, Option.some.injEq] at h
    subst h
    simp [Out.env?] at he

/-- A loop keeps the locals its body does not assign. -/
theorem ploop_unwritten {test : Env → Option Bool} {body : Env → Option Out} {ws : List Nat}
    (hb : ∀ env o, body env = some o → ∀ e, o.env? = some e → ∀ x, x ∉ ws → e.get? x = env.get? x) :
    ∀ (n : Nat) {env : Env} {o : Out}, ploop test body n env = some o →
      ∀ e, o.env? = some e → ∀ x, x ∉ ws → e.get? x = env.get? x
  | 0, _, _, h => by simp [ploop] at h
  | n + 1, env, o, h => by
    simp only [ploop, Option.bind_eq_some_iff] at h
    obtain ⟨b, -, h⟩ := h
    cases b with
    | false =>
      simp only [Bool.false_eq_true, if_false, Option.some.injEq] at h
      subst h
      intro e he _ _
      simp only [Out.env?, Option.some.injEq] at he
      subst he
      rfl
    | true =>
      simp only [if_true, Option.bind_eq_some_iff] at h
      obtain ⟨ob, hob, h⟩ := h
      cases ob with
      | next e1 => exact fun e he x hx => (ploop_unwritten hb n h e he x hx).trans (hb env _ hob e1 rfl x hx)
      | cont e1 => exact fun e he x hx => (ploop_unwritten hb n h e he x hx).trans (hb env _ hob e1 rfl x hx)
      | brk e1 =>
        simp only [Option.some.injEq] at h
        subst h
        intro e he x hx
        simp only [Out.env?, Option.some.injEq] at he
        subst he
        exact hb env _ hob _ rfl x hx
      | ret v =>
        simp only [Option.some.injEq] at h
        subst h
        intro e he
        simp [Out.env?] at he

/-- **A statement keeps the locals it does not assign.** -/
theorem mstmt_unwritten (call : Calls) (fuel : Nat) :
    ∀ (s : SrcStmt) {env : Env} {o : Out}, mstmt call fuel env s = some o →
      ∀ e, o.env? = some e → ∀ x, x ∉ s.writes → e.get? x = env.get? x := by
  intro s
  induction s with
  | nop =>
    intro env o h e he _ _
    simp only [mstmt, Option.some.injEq] at h
    subst h
    simp only [Out.env?, Option.some.injEq] at he
    subst he
    rfl
  | «let» id _ value body ih =>
    intro env o h
    simp only [mstmt, Option.bind_eq_some_iff, Option.map_eq_some_iff] at h
    obtain ⟨v, -, ob, hb, rfl⟩ := h
    exact unwritten_pop (mstmt_agree call fuel body hb) (ih hb)
  | letStruct id ty fields body ih =>
    intro env o h
    simp only [mstmt, Option.bind_eq_some_iff, Option.map_eq_some_iff] at h
    obtain ⟨v, -, ob, hb, rfl⟩ := h
    exact unwritten_pop (mstmt_agree call fuel body hb) (ih hb)
  | letCall id _ callee args body ih =>
    intro env o h
    simp only [mstmt, Option.bind_eq_some_iff, Option.map_eq_some_iff] at h
    obtain ⟨v, -, ob, hb, rfl⟩ := h
    exact unwritten_pop (mstmt_agree call fuel body hb) (ih hb)
  | letEnum id ty variant payload body ih =>
    intro env o h
    simp only [mstmt, Option.bind_eq_some_iff, Option.map_eq_some_iff] at h
    obtain ⟨v, -, ob, hb, rfl⟩ := h
    exact unwritten_pop (mstmt_agree call fuel body hb) (ih hb)
  | letEval id _ value body ih =>
    intro env o h
    simp only [mstmt, Option.bind_eq_some_iff, Option.map_eq_some_iff] at h
    obtain ⟨v, -, ob, hb, rfl⟩ := h
    exact unwritten_pop (mstmt_agree call fuel body hb) (ih hb)
  | set id value =>
    intro env o h e he x hx
    simp only [mstmt, Option.bind_eq_some_iff, Option.map_eq_some_iff] at h
    obtain ⟨v, -, e', hs, rfl⟩ := h
    simp only [Out.env?, Option.some.injEq] at he
    subst he
    exact Env.set_get_ne hs (by simpa [SrcStmt.writes] using hx)
  | setEval id value =>
    intro env o h e he x hx
    simp only [mstmt, Option.bind_eq_some_iff, Option.map_eq_some_iff] at h
    obtain ⟨v, -, e', hs, rfl⟩ := h
    simp only [Out.env?, Option.some.injEq] at he
    subst he
    exact Env.set_get_ne hs (by simpa [SrcStmt.writes] using hx)
  | «then» first second ih1 ih2 =>
    intro env o h
    simp only [mstmt, Option.bind_eq_some_iff] at h
    obtain ⟨o1, h1, h2⟩ := h
    exact unwritten_then (ih1 h1) (fun e1 _ o' h' => ih2 h') h2
  | «if» condition a b iha ihb =>
    intro env o h e he x hx
    simp only [SrcStmt.writes, List.mem_append, not_or] at hx
    simp only [mstmt, Option.bind_eq_some_iff] at h
    obtain ⟨c, -, hc⟩ := h
    cases c
    · exact ihb hc e he x hx.2
    · exact iha hc e he x hx.1
  | ifEval condition a b iha ihb =>
    intro env o h e he x hx
    simp only [SrcStmt.writes, List.mem_append, not_or] at hx
    simp only [mstmt, Option.bind_eq_some_iff] at h
    obtain ⟨c, -, hc⟩ := h
    cases c
    · exact ihb hc e he x hx.2
    · exact iha hc e he x hx.1
  | «return» value =>
    intro env o h e he
    simp only [mstmt, Option.map_eq_some_iff] at h
    obtain ⟨v, -, rfl⟩ := h
    simp [Out.env?] at he
  | returnEval value =>
    intro env o h e he
    simp only [mstmt, Option.map_eq_some_iff] at h
    obtain ⟨v, -, rfl⟩ := h
    simp [Out.env?] at he
  | discard value =>
    intro env o h e he _ _
    simp only [mstmt, Option.map_eq_some_iff] at h
    obtain ⟨v, -, rfl⟩ := h
    simp only [Out.env?, Option.some.injEq] at he
    subst he
    rfl
  | «assert» condition =>
    intro env o h e he _ _
    simp only [mstmt, Option.bind_eq_some_iff] at h
    obtain ⟨c, -, hc⟩ := h
    cases c
    · simp at hc
    · simp only [if_true, Option.some.injEq] at hc
      subst hc
      simp only [Out.env?, Option.some.injEq] at he
      subst he
      rfl
  | returnUnit =>
    intro env o h e he
    simp only [mstmt, Option.some.injEq] at h
    subst h
    simp [Out.env?] at he
  | «while» condition body ih =>
    intro env o h
    exact ploop_unwritten (fun _ _ h' => ih h') fuel h
  | whileEval condition body ih =>
    intro env o h
    exact ploop_unwritten (fun _ _ h' => ih h') fuel h
  | «break» | «continue» =>
    intro env o h e he _ _
    simp only [mstmt, Option.some.injEq] at h
    subst h
    simp only [Out.env?, Option.some.injEq] at he
    subst he
    rfl
  | letMatch | setField | setCall | letAlloc | letView | letStr | letLoad | setByte | free | letSlice | letIndex
  | setIndex | setIndexEval | setFieldEval | setPlace | setPlaceOp | matchArm | unreachable =>
    intro env o h; simp [mstmt] at h

end Lanius.Faithful
