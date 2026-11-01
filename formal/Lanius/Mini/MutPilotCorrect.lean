module

public import Lanius.Mini.MutPilot
-- import all: Lanius.Mini.MutPilot
import all Lanius.Mini.MutPilot.Types
import all Lanius.Mini.MutPilot.P.Account_deposit
import all Lanius.Mini.MutPilot.P.relay
import all Lanius.Mini.MutPilot.P.payAll
-- end import all

/-! # The `&mut` extraction pilot

`formal/lani/mini/mut_pilot.lani` uses `&mut` parameters, and extract.py
translates them as Aeneas translates a mutable borrow: a function takes each
`&mut` argument's value and returns it updated, after its result. So
`transfer : Account → Account → BitVec 32 → Bool × Account × Account`.

These theorems are about the extracted definitions. That they describe the
compiled Lanius program is the difftest's job (formal/tools/fn_difftest.py
with `--source formal/lani/mini/mut_pilot.lani`). That rests on exclusivity:
no other argument of a call reaches a `&mut` argument's value, which laniusc
checks (LNC0006) and extract.py checks again. -/

public section
namespace Lanius.Mini

theorem Account.deposit_eq (a : Account) (amount : BitVec 32) :
    a.deposit amount = { balance := a.balance + amount, moves := a.moves + 1 } := by
  cases a; rfl

/-- A withdrawal happens only when the balance covers it, and then takes
exactly the amount out. -/
theorem Account.withdraw_covered (a : Account) (amount : BitVec 32)
    (h : (a.withdraw amount).1 = true) :
    amount ≤ a.balance ∧ (a.withdraw amount).2.balance = a.balance - amount := by
  unfold Account.withdraw at h ⊢
  by_cases hc : a.balance < amount
  · rw [if_pos hc] at h; simp at h
  · rw [if_neg hc]; exact ⟨BitVec.not_lt.mp hc, rfl⟩

/-- A failed withdrawal leaves the account as it was. -/
theorem Account.withdraw_refused (a : Account) (amount : BitVec 32)
    (h : (a.withdraw amount).1 = false) : (a.withdraw amount).2 = a := by
  unfold Account.withdraw at h ⊢
  by_cases hc : a.balance < amount
  · rw [if_pos hc]
  · rw [if_neg hc] at h; simp at h

/-- A transfer conserves the sum of the two balances (mod 2^32). -/
theorem transfer_conserves (source target : Account) (amount : BitVec 32) :
    (transfer source target amount).2.1.balance + (transfer source target amount).2.2.balance =
      source.balance + target.balance := by
  unfold transfer Account.withdraw
  by_cases hc : source.balance < amount
  · rw [if_pos hc]; rfl
  · rw [if_neg hc]; simp [Account.deposit_eq] <;> bv_omega

/-- Two transfers along a chain: the result is the total of the balances
before them. -/
theorem relay_total (a b c : Account) (amount : BitVec 32) :
    (relay a b c amount).1 = a.balance + b.balance + c.balance := by
  have first := transfer_conserves a b amount
  unfold relay
  generalize transfer a b amount = t at first ⊢
  obtain ⟨_, a1, b1⟩ := t
  simp only at first ⊢
  have second := transfer_conserves b1 c amount
  generalize transfer b1 c amount = u at second ⊢
  obtain ⟨_, b2, c2⟩ := u
  simp only at second ⊢
  bv_omega

/-- `paid` updates its own copy: the result is a deposit into the argument. -/
theorem paid_eq (a : Account) (amount : BitVec 32) : paid a amount = a.deposit amount := by
  unfold paid; rfl

theorem payAll_length (accounts : List Account) (amount : BitVec 32) :
    (payAll accounts amount).length = accounts.length := by
  induction accounts <;> simp_all [payAll]

end Lanius.Mini
