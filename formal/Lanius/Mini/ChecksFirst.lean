import Lanius.Mini.Compiler

/-! Checks moved before the work they guard (F14), each giving the compiler's old result:
`SrcStmt.lower` of a `letView` checks the view's length (as `lowerView` does) before it
lowers the body under the view's binding (`lower_let_view`), and `evalStr` checks the
string's offset before `strPlaced` and the end's sum count from it. Only the order of the
checks changed, so the compiler accepts the same programs with the same code
(`lower_letView_eq`, `evalStr_eq`). -/

namespace Lanius.Mini

/-- A view's lowering is as before the length was checked first. -/
theorem lower_letView_eq (id length : Nat) (fields : List SrcExpr) (pointer : Nat) (body : SrcStmt)
    (sigs : List Sig) (decls : SrcDecls) (ret : SrcType) (scope : List Binding) (next : Nat) :
    SrcStmt.lower (.letView id length fields pointer body) sigs decls ret scope next =
      guarded next (guardAll scope fields)
        (lowerView next length (lowerLiteral scope (SrcType.array SrcType.i32 length) fields)
          (SrcStmt.lower body sigs decls ret
            (({ id := pointer, slot := next + length, ty := SrcType.ptr, home := none } : Binding) ::
              ({ id := id, slot := next, ty := SrcType.view length, home := none } : Binding) :: scope)
            (next + length + 1))) := by
  rw [SrcStmt.lower]
  split
  · rename_i h
    simp only [lowerView, h, if_true, guarded]
  · rfl

/-- A string literal's evaluation is as before its offset was checked first. -/
theorem evalStr_eq (decls : SrcDecls) (offset : Nat) (chars : List Nat) (slot : Nat) :
    evalStr decls offset chars slot =
      if strPlaced decls.statics offset chars && decide (offset + chars.length < 2147483648) &&
          decide (offset + chars.length ≤ decls.statics.length) then
        some ({ stmt := Stmt.seq (Stmt.static slot offset) (Stmt.assign (slot + 1) (Expr.lit (BitVec.ofNat 64 chars.length))),
                ty := SrcType.str } : Evaluated)
      else
        none := by
  rw [evalStr]
  split
  · rename_i h
    have : ¬ offset + chars.length < 2147483648 := by omega
    simp [this]
  · rfl

end Lanius.Mini
