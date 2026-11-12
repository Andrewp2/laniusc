module

public import Lanius.Machines.Machine
public import Lanius.Machines.SqliteStatement
-- import all: Lanius.Machines.SqliteStatement
import all Lanius.Machines.SqliteStatement.Types
import all Lanius.Machines.SqliteStatement.P.statementStart
import all Lanius.Machines.SqliteStatement.P.Statement_inFailed
-- end import all

/-! # The sqlite statement machine

`ext::sqlite_statement.Statement`, extracted from its `machine`: the output
is whether an operation may proceed. The native wrapper stores and steps
this machine, so these properties describe its actual lifecycle. -/

public section
namespace Lanius.Mini
open Lanius.Machines

/-- The statement machine: the verdict, then the next state. -/
def statementStep (s : StatementState) (e : Event) : Bool × StatementState :=
  let (allowed, next) := Statement.step ⟨s⟩ e
  (allowed, next.state)

/-- Columns are read only while a row is current. -/
theorem column_needs_row (s : StatementState) (h : (statementStep s .column).1 = true) : s = .row := by
  cases s <;> simp_all [statementStep, Statement.step, Statement.inReady, Statement.inRow, Statement.inDone,
    Statement.inFailed, Statement.inFinalized]

/-- A finalized statement stays finalized, whatever comes after. -/
theorem finalized_absorbs (es : List Event) : Machine.run statementStep .finalized es = .finalized :=
  Machine.inv_run (Inv := (· = StatementState.finalized)) es rfl (by
    intro s e h; subst h
    cases e <;> simp [statementStep, Statement.step, Statement.inFinalized])

/-- The machine with a monitor (as in P's spec machines): the flag records
whether `Finalize` has been seen. -/
def monitored (m : StatementState × Bool) (e : Event) : Bool × (StatementState × Bool) :=
  ((statementStep m.1 e).1, ((statementStep m.1 e).2, m.2 || decide (e = .finalize)))

/-- Once `Finalize` has been seen, the statement is finalized. -/
theorem finalize_is_final (es : List Event) :
    (Machine.run monitored (statementStart.state, false) es).2 = true →
      (Machine.run monitored (statementStart.state, false) es).1 = .finalized :=
  Machine.inv_run (Inv := fun (m : StatementState × Bool) => m.2 = true → m.1 = StatementState.finalized) es
    (by simp [statementStart]) (by
      intro ⟨s, seen⟩ e h
      cases s <;> cases e <;> cases seen <;>
        simp_all [monitored, statementStep, Statement.step, Statement.inReady, Statement.inRow,
          Statement.inDone, Statement.inFailed, Statement.inFinalized])

/-- After `Finalize`, every operation but `Finalize` is refused: every output
of the monitored machine from a state where `Finalize` was seen, for another
event, is `false`. -/
theorem refused_after_finalize (es : List Event) (e : Event) (other : e ≠ .finalize)
    (seen : (Machine.run monitored (statementStart.state, false) es).2 = true) :
    (monitored (Machine.run monitored (statementStart.state, false) es) e).1 = false := by
  have fin := finalize_is_final es seen
  simp only [monitored, statementStep]
  rw [fin]
  cases e <;> simp_all [Statement.step, Statement.inFinalized]

end Lanius.Mini
