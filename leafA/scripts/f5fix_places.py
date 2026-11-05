import sys
p = sys.argv[1]
s = open(p).read()
def rep(old, new):
    global s
    n = s.count(old)
    assert n == 1, (n, old[:80])
    s = s.replace(old, new)

rep("""at a pure index expression. Core evaluates the index after the base; the
verified compiler evaluates it before the place's code, into `slot` (both
are pure, so the order does not matter). -/
inductive RPlace where
  | home (id : Lanius.VarId)
  | deref (id : Lanius.VarId)
  | field (base : RPlace) (field : Nat)
  | index (base : RPlace) (index : Core.Expr) (slot : Nat)""",
"""at an index expression that does not change the state (it may trap). In
Core's order: an index is evaluated right after its base resolves, so an
out-of-range base index traps before a later index runs (`a[i][e]`). The
verified compiler's code for the index, `code`, runs right after the
base's code and leaves the index's word in `slot` (`RPlace.code`,
`RPlace.IndexRuns`). -/
inductive RPlace where
  | home (id : Lanius.VarId)
  | deref (id : Lanius.VarId)
  | field (base : RPlace) (field : Nat)
  | index (base : RPlace) (index : Core.Expr) (code : Stmt) (slot : Nat)""")
rep("  | .index base ie _ => .index base.toCore ie", "  | .index base ie _ _ => .index base.toCore ie")
rep("  | .index base ie _ => .index base.read ie", "  | .index base ie _ _ => .index base.read ie")
rep("""local's slot holds the address, a field adds its offset, and an element its
offset after checking the index slot is below the length (else the trap).""",
"""local's slot holds the address, a field adds its offset, and an element
runs its index's code after its base's, then adds its offset after
checking the index slot is below the length (else the trap).""")
rep("""  | .index base _ slot =>
      match base.code c t with
      | none => none
      | some (code, ty) =>
          match ty.indexInfo with
          | none => none
          | some (length, element) =>
              if 2 ^ 31 ≤ length then none else
              some (.seq code
                (.ite (.compare .u64 .lt (.var slot) (.lit (BitVec.ofNat 64 length)))
                  (elementAddr t slot length element) (refTrap t)), element)""",
"""  | .index base _ indexCode slot =>
      match base.code c t with
      | none => none
      | some (code, ty) =>
          match ty.indexInfo with
          | none => none
          | some (length, element) =>
              if 2 ^ 31 ≤ length then none else
              some (.seq code (.seq indexCode
                (.ite (.compare .u64 .lt (.var slot) (.lit (BitVec.ofNat 64 length)))
                  (elementAddr t slot length element) (refTrap t))), element)""")

# Resolves .. Indexed block
i = s.index("/-- The cell and path a place names in Core's state")
j = s.index("/-- The compile context agrees with Core's state")
s = s[:i] + """/-- The cell and path a place names in Core's state: a home's local's cell,
a reference local's cell and path, then each field, and each element at its
index's value, the index evaluated (with enough fuel, the state unchanged)
once its base has resolved. Out-of-range indices are allowed here; `Traps`
is the place whose resolution traps. -/
inductive RPlace.Resolves (prog : Core.Program) (st : State) :
    RPlace → Lanius.CellId → List ValueProjection → Prop where
  | home {id : Lanius.VarId} {cell : Lanius.CellId} :
      st.cellId? id = some cell → RPlace.Resolves prog st (.home id) cell []
  | deref {id : Lanius.VarId} {T : Core.Ty} {cell : Lanius.CellId} {path : List ValueProjection} :
      coreLocal st id = some (.reference T cell path) → RPlace.Resolves prog st (.deref id) cell path
  | field {base : RPlace} {f : Nat} {cell : Lanius.CellId} {path : List ValueProjection} :
      RPlace.Resolves prog st base cell path → RPlace.Resolves prog st (.field base f) cell (path ++ [.field f])
  | index {base : RPlace} {index : Core.Expr} {code : Stmt} {slot : Nat} {cell : Lanius.CellId}
      {path : List ValueProjection} {iv : Value} {i : Nat} :
      RPlace.Resolves prog st base cell path →
      (∃ N, ∀ fuel, N ≤ fuel → Semantics.evalExpr fuel prog st index = .done iv st) →
      Semantics.integerIndex iv = .ok i →
      RPlace.Resolves prog st (.index base index code slot) cell (path ++ [.index i])

/-- A place whose resolution traps, in Core's order, with this reason and
state: some index's base resolves to an array and then the index itself
traps, or its value is below zero or not below the array's length
(`arrayBounds`). Indices after it are not evaluated. -/
inductive RPlace.Traps (prog : Core.Program) (st : State) : RPlace → Lanius.Trap → State → Prop where
  | field {base : RPlace} {f : Nat} {r : Lanius.Trap} {st' : State} :
      RPlace.Traps prog st base r st' → RPlace.Traps prog st (.field base f) r st'
  | index {base : RPlace} {index : Core.Expr} {code : Stmt} {slot : Nat} {r : Lanius.Trap} {st' : State} :
      RPlace.Traps prog st base r st' → RPlace.Traps prog st (.index base index code slot) r st'
  | indexTraps {base : RPlace} {index : Core.Expr} {code : Stmt} {slot : Nat} {cell : Lanius.CellId}
      {path : List ValueProjection} {elements : List Value} {r : Lanius.Trap} {st' : State} :
      RPlace.Resolves prog st base cell path →
      Semantics.readCellProjection st cell path = .ok (.array elements) →
      (∃ N, ∀ fuel, N ≤ fuel → Semantics.evalExpr fuel prog st index = .trapped r st') →
      RPlace.Traps prog st (.index base index code slot) r st'
  | negative {base : RPlace} {index : Core.Expr} {code : Stmt} {slot : Nat} {cell : Lanius.CellId}
      {path : List ValueProjection} {iv : Value} {elements : List Value} :
      RPlace.Resolves prog st base cell path →
      Semantics.readCellProjection st cell path = .ok (.array elements) →
      (∃ N, ∀ fuel, N ≤ fuel → Semantics.evalExpr fuel prog st index = .done iv st) →
      Semantics.integerIndex iv = .error .arrayBounds →
      RPlace.Traps prog st (.index base index code slot) .arrayBounds st
  | beyond {base : RPlace} {index : Core.Expr} {code : Stmt} {slot : Nat} {cell : Lanius.CellId}
      {path : List ValueProjection} {iv : Value} {i : Nat} {elements : List Value} :
      RPlace.Resolves prog st base cell path →
      Semantics.readCellProjection st cell path = .ok (.array elements) →
      (∃ N, ∀ fuel, N ≤ fuel → Semantics.evalExpr fuel prog st index = .done iv st) →
      Semantics.integerIndex iv = .ok i → elements.length ≤ i →
      RPlace.Traps prog st (.index base index code slot) .arrayBounds st

/-- A word for an index value: the index when Core has one, and at least
`2 ^ 31` (so not below any length) when the value is negative. An `i32`
slot is that (its 32 bits zero-extended), and so are the unsigned. -/
def IndexAt (v : Value) (w : BitVec 64) : Prop :=
  (∀ i, Semantics.integerIndex v = .ok i → w.toNat = i) ∧
    (Semantics.integerIndex v = .error .arrayBounds → 2 ^ 31 ≤ w.toNat)

/-- Each index's code does what Core's index does, run right after its
base's code: from slots that agree with `env` outside `scratch` and `t`
(which holds the base's address then), it ends normally, the heap
unchanged, with the index value's word in the index's slot and the slots
outside `scratch` as they were, when Core's index has a value; and it stops
when Core's index traps. Index slots are scratch slots. Stage 2 proves this
of the code the verified compiler gives an index (its expression lowering's
induction hypothesis). -/
inductive RPlace.IndexRuns (cprog : Core.Program) (st : State) (prog : Program) (depth : Nat)
    (hp : Heap) (env : Env) (t : Nat) (scratch : List Nat) : RPlace → Prop where
  | home {id : Lanius.VarId} : RPlace.IndexRuns cprog st prog depth hp env t scratch (.home id)
  | deref {id : Lanius.VarId} : RPlace.IndexRuns cprog st prog depth hp env t scratch (.deref id)
  | field {base : RPlace} {f : Nat} :
      RPlace.IndexRuns cprog st prog depth hp env t scratch base →
      RPlace.IndexRuns cprog st prog depth hp env t scratch (.field base f)
  | index {base : RPlace} {index : Core.Expr} {code : Stmt} {slot : Nat} :
      RPlace.IndexRuns cprog st prog depth hp env t scratch base → slot ∈ scratch →
      (∀ iv, (∃ N, ∀ fuel, N ≤ fuel → Semantics.evalExpr fuel cprog st index = .done iv st) →
        ∀ env₀ : Env, (∀ k, k ∉ scratch → k ≠ t → env₀ k = env k) →
        ∃ env₁ : Env, Exec prog depth env₀ hp code (.normal env₁ hp) ∧ IndexAt iv (env₁ slot) ∧
          ∀ k, k ∉ scratch → env₁ k = env₀ k) →
      (∀ (r : Lanius.Trap) (st' : State),
        (∃ N, ∀ fuel, N ≤ fuel → Semantics.evalExpr fuel cprog st index = .trapped r st') →
        ∀ env₀ : Env, (∀ k, k ∉ scratch → k ≠ t → env₀ k = env k) →
        ∀ n, Stops prog depth env₀ hp code n) →
      RPlace.IndexRuns cprog st prog depth hp env t scratch (.index base index code slot)

""" + s[j:]
rep("""/-- The slots a place's code reads: the frame slot, reference locals' slots
and index slots. -/
def RPlace.slots (c : RCtx) : RPlace → List Nat
  | .home _ => [c.frame]
  | .deref id => [c.slotOf id]
  | .field base _ => base.slots c
  | .index base _ slot => slot :: base.slots c""",
"""/-- The slots a place's code reads besides its index codes' scratch slots:
the frame slot and reference locals' slots. -/
def RPlace.slots (c : RCtx) : RPlace → List Nat
  | .home _ => [c.frame]
  | .deref id => [c.slotOf id]
  | .field base _ => base.slots c
  | .index base _ _ _ => base.slots c""")
open(p, "w").write(s)
print("ok")
