import sys
F='Lanius/Faithful/'
def patch(p, pairs):
    s=open(F+p).read()
    for a,b in pairs:
        n=s.count(a)
        if n!=1:
            print("SKIP",p,repr(a[:70]),n); continue
        s=s.replace(a,b)
    open(F+p,'w').write(s)
E4=['eBorrow','eDeref','eField','eAt']
def after(a,extra): return (a,a+extra)
patch('Safe/Stmt.lean',[after("  | setFieldEval => intro k tenv env st r st' le run ok; simp [stmtOk] at ok\n",
  "  | setPlace => intro k tenv env st r st' le run ok; simp [stmtOk] at ok\n  | setPlaceOp => intro k tenv env st r st' le run ok; simp [stmtOk] at ok\n")])
patch('Safe/Eff.lean',[after("  | setFieldEval => exact exprCase run\n","  | setPlace => exact exprCase run\n  | setPlaceOp => exact exprCase run\n"),
  after("  | eStr => simp [effTy] at ht\n","".join(f"  | {c} => simp [effTy] at ht\n" for c in E4))])
patch('Safe/Func.lean',[("  | returnEval | discard | setIndexEval | setFieldEval | returnUnit | «assert» | «break» | «continue»\n",
  "  | returnEval | discard | setIndexEval | setFieldEval | setPlace | setPlaceOp | returnUnit | «assert» | «break» | «continue»\n")])
patch('BudgetMono.lean',[("  | _, .eLen _ | _, .eStr _ _ => cle_none _\n","  | _, .eLen _ | _, .eStr _ _ | _, .eBorrow _ _ | _, .eDeref _ _ | _, .eField _ _ | _, .eAt _ _ => cle_none _\n"),
  after("  | setFieldEval => intro env; exact cle_none _\n","  | setPlace => intro env; exact cle_none _\n  | setPlaceOp => intro env; exact cle_none _\n")])
patch('BudgetFree.lean',[("  | .eLen _ | .eStr _ _ => true\n","  | .eLen _ | .eStr _ _ => true\n  | .eBorrow _ _ | .eDeref _ _ | .eField _ _ | .eAt _ _ => true\n"),
  after("  | .setFieldEval _ _ _ => true\n","  | .setPlace _ _ => true\n  | .setPlaceOp _ _ _ => true\n"),
  ("  | _, .eLen _, _ | _, .eStr _ _, _ => zle_none\n","  | _, .eLen _, _ | _, .eStr _ _, _ | _, .eBorrow _ _, _ | _, .eDeref _ _, _ | _, .eField _ _, _ | _, .eAt _ _, _ => zle_none\n"),
  after("  | setFieldEval => intro _ env; exact zle_none\n","  | setPlace => intro _ env; exact zle_none\n  | setPlaceOp => intro _ env; exact zle_none\n")])
patch('Fwd/Stmt.lean',[after("  | setFieldEval => intro tenv env st d h ok; simp [stmtOk] at ok\n","  | setPlace => intro tenv env st d h ok; simp [stmtOk] at ok\n  | setPlaceOp => intro tenv env st d h ok; simp [stmtOk] at ok\n")])
patch('Fwd/Eff.lean',[("  | .eLen _, _, _, _, _, _, _, ht, _, _, _, _, _ | .eStr _ _, _, _, _, _, _, _, ht, _, _, _, _, _ => by simp [effTy] at ht\n",
  "  | .eLen _, _, _, _, _, _, _, ht, _, _, _, _, _ | .eStr _ _, _, _, _, _, _, _, ht, _, _, _, _, _ => by simp [effTy] at ht\n"+
  "".join(f"  | .{c} _ _, _, _, _, _, _, _, ht, _, _, _, _, _ => by simp [effTy] at ht\n" for c in E4))])
patch('Sim/QMono.lean',[("  | _, .eLen _, _, h | _, .eStr _ _, _, h => by simp [qeff] at h\n","  | _, .eLen _, _, h | _, .eStr _ _, _, h => by simp [qeff] at h\n"+"".join(f"  | _, .{c} _ _, _, h => by simp [qeff] at h\n" for c in E4)),
  after("  | setFieldEval => intro env d h; simp [qstmt] at h\n","  | setPlace => intro env d h; simp [qstmt] at h\n  | setPlaceOp => intro env d h; simp [qstmt] at h\n")])
patch('Sim/Stmt.lean',[after("  | setFieldEval => intro k tenv env st c st' le run ok; simp [stmtOk] at ok\n","  | setPlace => intro k tenv env st c st' le run ok; simp [stmtOk] at ok\n  | setPlaceOp => intro k tenv env st c st' le run ok; simp [stmtOk] at ok\n")])
patch('Sim/DeclStep.lean',[after("  | .setFieldEval _ _ v, d => by unfold SrcStmt.declare; exact types_grows _ d\n",
  "  | .setPlace p v, d => by unfold SrcStmt.declare; exact types_grows _ d\n  | .setPlaceOp _ p v, d => by unfold SrcStmt.declare; exact types_grows _ d\n")])
patch('Sim/CheckFast.lean',[("  | .eLen _ | .eStr _ _ => none\n","  | .eLen _ | .eStr _ _ | .eBorrow _ _ | .eDeref _ _ | .eField _ _ | .eAt _ _ => none\n"),
  after("  | .setFieldEval _ _ _ => false\n","  | .setPlace _ _ => false\n  | .setPlaceOp _ _ _ => false\n"),
  ("  | .eLen _ | .eStr _ _ => by rw [effTyC, effTy]\n","  | .eLen _ | .eStr _ _ | .eBorrow _ _ | .eDeref _ _ | .eField _ _ | .eAt _ _ => by rw [effTyC, effTy]\n"),
  after("  | setFieldEval => intro tenv; rw [stmtOkC, stmtOk] <;> rfl\n","  | setPlace => intro tenv; rw [stmtOkC, stmtOk] <;> rfl\n  | setPlaceOp => intro tenv; rw [stmtOkC, stmtOk] <;> rfl\n")])
