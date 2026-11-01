module

public import Lanius.Machines.Machine
public import Lanius.Machines.TlsLifecycle
-- import all: Lanius.Machines.TlsLifecycle
import all Lanius.Machines.TlsLifecycle.Types
import all Lanius.Machines.TlsLifecycle.P.lifecycleStart
-- end import all

/-! # The TLS session lifecycle (phase M2)

`ext::openssl_tls_lifecycle.Lifecycle`, extracted from its `machine`. Every
ext::openssl_tls session changes state only by stepping it, so these are
facts about every session: once a session has failed or been destroyed, it
never reads or writes again. -/

public section
namespace Lanius.Mini
open Lanius.Machines

/-- The lifecycle as a `Machine`. -/
def lifecycle : Lifecycle → Signal → Unit × Lifecycle := Machine.silent Lifecycle.step

/-- The spec monitor: whether a `Failed` or `Destroyed` signal has been seen. -/
def ended : Bool → Signal → Lifecycle → Bool
  | seen, .verified, _ => seen
  | seen, .peerClosed, _ => seen
  | seen, .shutdown, _ => seen
  | _, .failed, _ => true
  | _, .destroyed, _ => true

/-- The property, an invariant of the machine and its monitor: after a failure
or a destroy the session is `Closed` or `Failed`. -/
def EndedInv (p : Lifecycle × Bool) : Prop := p.2 = true → p.1.state = .closed ∨ p.1.state = .failed

theorem endedInv_step (p : Lifecycle × Bool) (e : Signal) (h : EndedInv p) :
    EndedInv (Machine.withSpec lifecycle ended p e).2 := by
  obtain ⟨⟨st⟩, w⟩ := p
  cases st <;> cases e <;> cases w <;>
    simp_all [EndedInv, Machine.withSpec, lifecycle, Machine.silent, ended, Lifecycle.step,
      Lifecycle.inHandshake, Lifecycle.inOpen, Lifecycle.inPeerClosed, Lifecycle.inClosing,
      Lifecycle.inClosed, Lifecycle.inFailed]

/-- The trace property: every state a session passes through after a failure
or a destroy is `Closed` or `Failed`. -/
theorem ended_stays_ended (es : List Signal) :
    ∀ p ∈ Machine.states (Machine.withSpec lifecycle ended) (lifecycleStart, false) es, EndedInv p :=
  Machine.inv_states es (by simp [EndedInv]) endedInv_step

theorem ended_remembers (s : Lifecycle) (es : List Signal) :
    (Machine.run (Machine.withSpec lifecycle ended) (s, true) es).2 = true := by
  induction es generalizing s with
  | nil => rfl
  | cons e es ih => cases e <;> exact ih _

theorem ended_sees_failure (s : Lifecycle) (w : Bool) (es : List Signal) (h : Signal.failed ∈ es) :
    (Machine.run (Machine.withSpec lifecycle ended) (s, w) es).2 = true := by
  induction es generalizing s w with
  | nil => simp at h
  | cons e es ih =>
    rcases List.mem_cons.mp h with rfl | h
    · exact ended_remembers _ es
    · exact ih _ _ h

/-- The same property without the monitor: a session that has failed is never
`Open` again, whatever comes after. -/
theorem never_open_after_failure (pre post : List Signal) (h : Signal.failed ∈ pre) :
    (Machine.run lifecycle lifecycleStart (pre ++ post)).state ≠ .open := by
  have inv := Machine.inv_run (Inv := EndedInv) (s := (lifecycleStart, false)) (pre ++ post)
    (by simp [EndedInv]) endedInv_step
  have seen := ended_sees_failure lifecycleStart false (pre ++ post) (List.mem_append_left post h)
  rw [← Machine.run_withSpec_fst lifecycle ended lifecycleStart false]
  rcases inv seen with h | h <;> rw [h] <;> simp

end Lanius.Mini
