"""S3: the front end's copy of SrcEff/SrcStmt gains the F5 forms; its passes keep them as they are.
Run from formal/: s3front.py lani/mini/frontend.lani"""
import re, sys
path = sys.argv[1]
src = open(path).read()
def add_after(text, anchor, new):
    assert text.count(anchor) == 1, anchor
    return text.replace(anchor, anchor + new)
src = add_after(src, "    ELen(usize),\n    EStr(usize, List<usize>),\n",
    "    EBorrow(SrcType, Box<SrcEff>),\n    EDeref(SrcType, Box<SrcEff>),\n    EField(Box<SrcEff>, usize),\n"
    "    EAt(Box<SrcEff>, Box<SrcEff>),\n")
src = add_after(src, "    // core::mem::string_data_ptr(\"chars\"); body\n    LetStr(usize, List<usize>, Box<SrcStmt>),\n",
    "    // place = value and place op= value (the compiler's; the reading never\n    // makes them yet)\n"
    "    SetPlace(SrcEff, SrcEff),\n    SetPlaceOp(SrcAssignOp, SrcEff, SrcEff),\n")
src = add_after(src, "pub enum SrcDivOp { Quotient, Remainder, }\n",
    "\npub enum SrcAssignOp { AAdd, ASub, AMul, AAnd, AOr, AXor, AShl, AShr, }\n")
EFF = [("EBorrow", "bty, bplace"), ("EDeref", "dty, dref"), ("EField", "fbase, fidx"), ("EAt", "abase, aindex")]
STMT = [("SetPlace", "aplace, avalue"), ("SetPlaceOp", "aop, aplace, avalue")]
EFFV = {
  'eff_bytes': {'EBorrow': 'eff_bytes(unbox(bplace))', 'EDeref': 'eff_bytes(unbox(dref))', 'EField': 'eff_bytes(unbox(fbase))',
                'EAt': 'concat(eff_bytes(unbox(abase)), eff_bytes(unbox(aindex)))'},
  'place_eff': {'EBorrow': 'EBorrow(bty, boxed(place_eff(before, unbox(bplace))))',
                'EDeref': 'EDeref(dty, boxed(place_eff(before, unbox(dref))))',
                'EField': 'EField(boxed(place_eff(before, unbox(fbase))), fidx)',
                'EAt': 'EAt(boxed(place_eff(before, unbox(abase))), boxed(place_eff(concat(before, eff_bytes(unbox(abase))), unbox(aindex))))'},
  'lim_eff': {'EBorrow': 'lim_ty(bty) && lim_eff(unbox(bplace))', 'EDeref': 'lim_ty(dty) && lim_eff(unbox(dref))',
              'EField': 'lim_eff(unbox(fbase))', 'EAt': 'lim_eff(unbox(abase)) && lim_eff(unbox(aindex))'},
}
STMTV = {
  'stmt_bytes': {'SetPlace': 'concat(eff_bytes(aplace), eff_bytes(avalue))', 'SetPlaceOp': 'concat(eff_bytes(aplace), eff_bytes(avalue))'},
  'place_stmt': {'SetPlace': 'SetPlace(place_eff(before, aplace), place_eff(concat(before, eff_bytes(aplace)), avalue))',
                 'SetPlaceOp': 'SetPlaceOp(aop, place_eff(before, aplace), place_eff(concat(before, eff_bytes(aplace)), avalue))'},
  'lim_stmt': {'SetPlace': 'lim_leaf(lim_eff(aplace) && lim_eff(avalue))', 'SetPlaceOp': 'lim_leaf(lim_eff(aplace) && lim_eff(avalue))'},
}
lines = src.split('\n'); out = []; fn = ''; done = []
for line in lines:
    out.append(line)
    m = re.match(r'^\s*(pub )?fn (\w+)', line)
    if m: fn = m.group(2)
    m = re.match(r'^(\s*)EStr\(offset, chars\) -> (.*),$', line)
    if m:
        ind = m.group(1)
        for c, b in EFF:
            v = EFFV[fn][c] if fn in EFFV else {'known_eff': 'None', 'lit_eff': f'{c}({b})', 'wide_left_eff': 'false'}[fn]
            out.append(f'{ind}{c}({b}) -> {v},')
        done.append(fn); continue
    m = re.match(r'^(\s*)LetStr\((?:p|pt), cs, body\) -> (.*),$', line)
    if m:
        ind = m.group(1)
        for c, b in STMT:
            v = STMTV[fn][c] if fn in STMTV else {'lit_stmt': f'{c}({b})', 'wide_left_stmt': 'false'}[fn]
            out.append(f'{ind}{c}({b}) -> {v},')
        done.append(fn)
open(path, 'w').write('\n'.join(out))
print(done)
