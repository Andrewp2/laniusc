# Generates formal/Lanius/Faithful/SelfPre/LimitsNums.lean (by hand-run script; output is checked in as source).
import sys
EFF = [("ePure",["e"]),("eCall",["n","xs"]),("eApply",["o","x","x"]),("eNeg",["x"]),("eNot",["x"]),
 ("eCast",["t","x"]),("eIndex",["n","x"]),("eStruct",["t","xs"]),("eVariant",["t","n","xs"]),
 ("eMatch",["x","t","t","idss","xs"]),("eDivide",["o","x","x"]),("eStride",["n"]),("arraySlice",["t","n"]),
 ("eIf",["x","t","x","x"]),("eLet",["n","t","x","t","x"]),("eLen",["n"]),("eStr",["n","ids"]),
 ("eBorrow",["t","x"]),("eDeref",["t","x"]),("eField",["x","n"]),("eAt",["x","x"])]
STMT = [("nop",[]),("let",["n","t","e","s"]),("letStruct",["n","t","es","s"]),("letCall",["n","t","n","es","s"]),
 ("letEnum",["n","t","n","es","s"]),("letMatch",["n","t","n","n","arms","s"]),("set",["n","e"]),
 ("setField",["n","n","e"]),("setCall",["n","n","es"]),("then",["s","s"]),("if",["e","s","s"]),
 ("while",["e","s"]),("return",["e"]),("letAlloc",["n","e","n","s"]),("letLoad",["n","e","e","s"]),
 ("setByte",["e","e","e"]),("free",["e","e","n"]),("letSlice",["n","t","e","e","s"]),
 ("letIndex",["n","t","n","e","s"]),("setIndex",["n","e","e"]),("letEval",["n","t","x","s"]),
 ("setEval",["n","x"]),("ifEval",["x","s","s"]),("whileEval",["x","s"]),("returnEval",["x"]),
 ("discard",["x"]),("setIndexEval",["n","x","x"]),("setFieldEval",["n","n","x"]),("returnUnit",[]),
 ("assert",["x"]),("break",[]),("continue",[]),("matchArm",["n","n","n","o","n","t","s","s"]),
 ("unreachable",["n","t"]),("letView",["n","n","es","n","s"]),("letStr",["n","ids","s"]),
 ("setPlace",["x","x"]),("setPlaceOp",["o","x","x"])]
TY = [("i32",[]),("bool",[]),("uint",["o"]),("struct",["n","tys"]),("enum",["n","vs"]),("ptr",[]),
 ("slice",["t"]),("array",["t","n"]),("unit",[]),("isize",[]),("char",[]),("float",["o"]),("sint",["o"]),
 ("view",["n"]),("str",[]),("ref",["t"])]
EXPR = [("int",["o"]),("boolean",["o"]),("unsigned",["o","o"]),("local",["n"]),("field",["n","n"]),
 ("negate",["e"]),("not",["e"]),("apply",["o","e","e"]),("cast",["t","e"]),("null",[]),("char",["o"]),("float",["o","o"])]
LEM = {"t":"limNumsTy_ok","tys":"limNumsTys_ok","vs":"limNumsVariants_ok","e":"limNumsExpr_ok","es":"limNumsExprs_ok",
 "x":"limNumsEff_ok","xs":"limNumsEffs_ok","s":"limNumsStmt_ok","ids":"limNumsIds_ok","idss":"limNumsIdss_ok","arms":"limNumsArms_ok"}
SIMP = "simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, {f}]"
def cases(ctor_list, typ, fname):
    out=[]
    for c,args in ctor_list:
        names=[f"a{i}" for i in range(len(args))]
        pat=" ".join(["."+c]+[("_" if k=="o" else nm) for k,nm in zip(args,names)])
        haves=[f"have h{i} := {LEM[k]} {nm}" for i,(k,nm) in enumerate(zip(args,names)) if k in LEM]
        body="; ".join(haves+[SIMP.format(f=fname)])
        out.append(f"  | {pat}, h => by {body}")
    return out
def thm(name, typ, fn, ctors, struct=True):
    lines=[f"theorem {name} : ∀ (v : {typ}), {fn} v = true → nb v ≤ depthLimit"]
    lines+=cases(ctors,typ,fn)
    return lines
o=[]
o.append("""import Lanius.Faithful.SelfPre.NB
import Lanius.Faithful.SelfPre.EvalSlots
import Lanius.Mini.Frontend

/-! # The front end's number and nesting limits (F14)

`limFuncs` checks every function's numbers against `depthLimit` (`limNums*`,
the largest number as `nb` counts it) and its expressions' unchecked slot
steps (`limNest`, which is `SrcStmt.slotNest`). Generated once by
target/claude-work/leafA/lims/gen.py from the constructors; edited by hand since. -/

open Lanius.Mini
open Lanius.Faithful.SelfPre

namespace Lanius.Faithful.SelfPre.Limits

theorem limNumsIds_ok : ∀ (v : List Nat), limNumsIds v = true → nb v ≤ depthLimit
  | [], _ => by simp
  | a :: rest, h => by have h1 := limNumsIds_ok rest; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsIds]

theorem limNumsIdss_ok : ∀ (v : List (List Nat)), limNumsIdss v = true → nb v ≤ depthLimit
  | [], _ => by simp
  | a :: rest, h => by have h0 := limNumsIds_ok a; have h1 := limNumsIdss_ok rest; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsIdss]
""")
o.append("mutual")
o+=thm("limNumsTy_ok","SrcType","limNumsTy",TY)
o.append("termination_by structural v => v\n")
o.append("""theorem limNumsTys_ok : ∀ (v : List SrcType), limNumsTys v = true → nb v ≤ depthLimit
  | [], _ => by simp
  | a :: rest, h => by have h0 := limNumsTy_ok a; have h1 := limNumsTys_ok rest; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsTys]
termination_by structural v => v

theorem limNumsVariants_ok : ∀ (v : List (List SrcType)), limNumsVariants v = true → nb v ≤ depthLimit
  | [], _ => by simp
  | a :: rest, h => by have h0 := limNumsTys_ok a; have h1 := limNumsVariants_ok rest; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsVariants]
termination_by structural v => v
end
""")
o+=thm("limNumsExpr_ok","SrcExpr","limNumsExpr",EXPR)
o.append("""
theorem limNumsExprs_ok : ∀ (v : List SrcExpr), limNumsExprs v = true → nb v ≤ depthLimit
  | [], _ => by simp
  | a :: rest, h => by have h0 := limNumsExpr_ok a; have h1 := limNumsExprs_ok rest; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsExprs]

theorem limNumsArms_ok : ∀ (v : List SrcArm), limNumsArms v = true → nb v ≤ depthLimit
  | [], _ => by simp
  | ⟨bs, e⟩ :: rest, h => by
    have h0 := limNumsIds_ok bs; have h2 := limNumsExpr_ok e; have h1 := limNumsArms_ok rest
    simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsArms]
""")
o.append("mutual")
o+=thm("limNumsEff_ok","SrcEff","limNumsEff",EFF)
o.append("termination_by structural v => v\n")
o.append("""theorem limNumsEffs_ok : ∀ (v : List SrcEff), limNumsEffs v = true → nb v ≤ depthLimit
  | [], _ => by simp
  | a :: rest, h => by have h0 := limNumsEff_ok a; have h1 := limNumsEffs_ok rest; simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsEffs]
termination_by structural v => v
end
""")
o+=thm("limNumsStmt_ok","SrcStmt","limNumsStmt",STMT)
o.append("""
theorem limNumsParams_ok : ∀ (v : List SrcParam), limNumsParams v = true → nb v ≤ depthLimit
  | [], _ => by simp
  | ⟨id, t⟩ :: rest, h => by
    have h0 := limNumsTy_ok t; have h1 := limNumsParams_ok rest
    simp_all [nb_simp, Nat.max_le, Bool.and_eq_true, limNum, decide_eq_true_eq, limNumsParams]
""")
# nest: the count is slotNest when it is within the limit
def nle(name, typ, fn, ref, ctors, kinds):
    lines=[f"theorem {name} : ∀ (v : {typ}), {fn} v ≤ depthLimit → {ref} v = {fn} v"]
    for c,args in ctors:
        names=[f"a{i}" for i in range(len(args))]
        pat=" ".join(["."+c]+[("_" if k not in kinds else nm) for k,nm in zip(args,names)])
        if typ=="SrcEff" and c in ("eApply","eDivide"):
            lines.append(f"  | {pat}, h => by")
            lines.append(f"    have ha := limNestEff_le a1; have hb := limNestEff_le a2")
            lines.append(f"    simp only [limNestEff, Nat.max_le] at h")
            lines.append(f"    obtain ⟨h1, h2⟩ := h")
            lines.append(f"    have st := limNestStep_le h2")
            lines.append(f"    simp only [SrcEff.slotNest, limNestEff, st.1, ha h1, hb (by omega)]")
            continue
        haves=[f"have h{i} := {kinds[k]} {nm}" for i,(k,nm) in enumerate(zip(args,names)) if k in kinds]
        body="; ".join(haves+[f"simp_all [{fn}, {ref}, Nat.max_le]"])
        lines.append(f"  | {pat}, h => by {body}")
    return lines
o.append("""theorem limNestStep_le {n : Nat} (h : limNestStep n ≤ depthLimit) : limNestStep n = n + 1 ∧ n + 1 ≤ depthLimit := by
  unfold limNestStep at h ⊢
  split at h <;> simp_all <;> omega
""")
o.append("mutual")
o+=nle("limNestEff_le","SrcEff","limNestEff","SrcEff.slotNest",EFF,{"x":"limNestEff_le","xs":"limNestEffs_le"})
o.append("termination_by structural v => v\n")
o.append("""theorem limNestEffs_le : ∀ (v : List SrcEff), limNestEffs v ≤ depthLimit → effsSlotNest v = limNestEffs v
  | [], _ => by simp only [limNestEffs, effsSlotNest]
  | a :: rest, h => by have h0 := limNestEff_le a; have h1 := limNestEffs_le rest; simp_all [limNestEffs, effsSlotNest, Nat.max_le]
termination_by structural v => v
end
""")
o+=nle("limNest_le","SrcStmt","limNest","SrcStmt.slotNest",STMT,{"x":"limNestEff_le","s":"limNest_le"})
o.append("\nend Lanius.Faithful.SelfPre.Limits\n")
open(sys.argv[1],"w").write("\n".join(o))
