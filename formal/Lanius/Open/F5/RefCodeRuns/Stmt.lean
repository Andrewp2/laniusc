import Lanius.Mini.Refs.Machine

open Lanius.Mini

/-- **The reference code runs on the machine.** A reference code template
(`RefCode`: a read, a write or a place's address, its slots within the
locals) placed at `pos` runs on the abstract machine as the mini statement
does: a mini run's outcome is the machine's (`StmtResult`), and a run that
stops (`Stops`, as at an out-of-range index's `refTrap`) stops the machine
(`AStops`), by the existing compilation proofs and no new trusted
definition. -/
def Lanius.Open.RefCodeRuns : Prop :=
  ∀ (prog : Program) (base : Nat) (arities : List Arity) (results : Nat) (code : List Instr) (depth : Nat)
    (env : Env) (heap : Heap) (stmt : Stmt) (pos brk cont : Nat) (m : Machine),
    RefCode base arities results stmt →
    Block code pos (compileStmt base pos brk cont stmt) → m.pc = pos → Agree base env m → m.heap = heap →
    (∀ outcome, Exec prog depth env heap stmt outcome →
      StmtResult (SourceCalls prog depth) code base pos (compileStmt base pos brk cont stmt) brk cont m outcome) ∧
    ∀ n, Stops prog depth env heap stmt n → AStops (SourceCalls prog depth) (SourceStops prog depth) code m n
