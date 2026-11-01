module

public import Lanius.Machines.Machine
public import Lanius.Machines.SqliteStatement
-- import all: Lanius.Machines.SqliteStatement
import all Lanius.Machines.SqliteStatement.Types
import all Lanius.Machines.SqliteStatement.P.start
import all Lanius.Machines.SqliteStatement.P.inDone
import all Lanius.Machines.SqliteStatement.P.transition
-- end import all

/-! # The sqlite statement machine (phase M0)

`ext::sqlite_statement.transition`, extracted, as a `Machine`: the output is
whether the operation may go ahead. ext::sqlite stores the state only from
`transition`, so these are facts about every statement it hands out. -/

public section
namespace Lanius.Mini
open Lanius.Machines

/-- The statement machine: the verdict, then the next state. -/
def statementStep (s : State) (e : Event) : Bool × State :=
  ((transition s e).allowed, (transition s e).next)

/-- Columns are read only while a row is current. -/
theorem column_needs_row (s : State) (h : (statementStep s .column).1 = true) : s = .row := by
  cases s <;> simp_all [statementStep, transition, inReady, inRow, inDone, inFailed, inFinalized,
    go, stay, refuse]

/-- A finalized statement stays finalized, whatever comes after. -/
theorem finalized_absorbs (es : List Event) : Machine.run statementStep .finalized es = .finalized :=
  Machine.inv_run (Inv := (· = State.finalized)) es rfl (by
    intro s e h; subst h
    cases e <;> simp [statementStep, transition, inFinalized, stay, refuse])

/-- The machine with a monitor (as in P's spec machines): the flag records
whether `Finalize` has been seen. -/
def monitored (m : State × Bool) (e : Event) : Bool × (State × Bool) :=
  ((statementStep m.1 e).1, ((statementStep m.1 e).2, m.2 || decide (e = .finalize)))

/-- Once `Finalize` has been seen, the statement is finalized. -/
theorem finalize_is_final (es : List Event) :
    (Machine.run monitored (start, false) es).2 = true →
      (Machine.run monitored (start, false) es).1 = .finalized :=
  Machine.inv_run (Inv := fun (m : State × Bool) => m.2 = true → m.1 = State.finalized) es
    (by simp) (by
      intro ⟨s, seen⟩ e h
      cases s <;> cases e <;> cases seen <;>
        simp_all [monitored, statementStep, transition, inReady, inRow, inDone, inFailed,
          inFinalized, go, stay, refuse])

/-- After `Finalize`, every operation but `Finalize` is refused: every output
of the monitored machine from a state where `Finalize` was seen, for another
event, is `false`. -/
theorem refused_after_finalize (es : List Event) (e : Event) (other : e ≠ .finalize)
    (seen : (Machine.run monitored (start, false) es).2 = true) :
    (monitored (Machine.run monitored (start, false) es) e).1 = false := by
  have fin := finalize_is_final es seen
  simp only [monitored, statementStep]
  rw [fin]
  cases e <;> simp_all [transition, inFinalized, refuse]

end Lanius.Mini
