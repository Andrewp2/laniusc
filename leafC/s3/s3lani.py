"""S3: add Source's borrow, deref, field, element (SrcEff) and assignment through a
place (SrcStmt) to compiler.lani, every case rejecting. Run from formal/: s3lani.py lani/mini/compiler.lani"""
import re, sys
path = sys.argv[1]
src = open(path).read()

# the types
def add_after(text, anchor, new):
    assert text.count(anchor) == 1, anchor
    return text.replace(anchor, anchor + new)

src = add_after(src, "    EStr(usize, List<usize>),\n", """    // &place, of the place's type: Core's borrow of the place
    // (SrcEff.toPlace: a local, a field or element of a place, else the
    // place a reference names). F5: nothing accepts it yet.
    EBorrow(SrcType, Box<SrcEff>),
    // *reference, of the referent's type: Core's dereference
    EDeref(SrcType, Box<SrcEff>),
    // base.field of any struct value (Core's field of a value)
    EField(Box<SrcEff>, usize),
    // base[index] of any array value (Core's index of a value)
    EAt(Box<SrcEff>, Box<SrcEff>),
""")
src = add_after(src, "    LetStr(usize, List<usize>, Box<SrcStmt>),\n", """    // place = value, place op= value: Core's assignment to the place
    // (SrcEff.toPlace), the compound one reading the old value before value
    // (F5: nothing accepts them yet)
    SetPlace(SrcEff, SrcEff),
    SetPlaceOp(SrcAssignOp, SrcEff, SrcEff),
""")
src = add_after(src, "pub enum SrcDivOp { Quotient, Remainder, }\n", """
// The operator of a compound assignment through a place: Core's assignment
// operators add, subtract, multiply, bitAnd, bitOr, bitXor, shiftLeft and
// shiftRight (F5).
pub enum SrcAssignOp { AAdd, ASub, AMul, AAnd, AOr, AXor, AShl, AShr, }
""")

eff_arms = {
    'types': ["EBorrow(bty, bplace) -> unbox(bplace).types(),", "EDeref(dty, dref) -> unbox(dref).types(),",
              "EField(fbase, fidx) -> unbox(fbase).types(),",
              "EAt(abase, aindex) -> concat(unbox(abase).types(), unbox(aindex).types()),"],
    'slice_uses': ["EBorrow(bty, bplace) -> unbox(bplace).slice_uses(),", "EDeref(dty, dref) -> unbox(dref).slice_uses(),",
                   "EField(fbase, fidx) -> unbox(fbase).slice_uses(),",
                   "EAt(abase, aindex) -> concat(unbox(abase).slice_uses(), unbox(aindex).slice_uses()),"],
    'callee_need': ["EBorrow(bty, bplace) -> unbox(bplace).callee_need(needs),",
                    "EDeref(dty, dref) -> unbox(dref).callee_need(needs),",
                    "EField(fbase, fidx) -> unbox(fbase).callee_need(needs),",
                    "EAt(abase, aindex) -> max_of(unbox(abase).callee_need(needs), unbox(aindex).callee_need(needs)),"],
}
def eff_const(v):
    return [f"EBorrow(bty, bplace) -> {v},", f"EDeref(dty, dref) -> {v},", f"EField(fbase, fidx) -> {v},",
            f"EAt(abase, aindex) -> {v},"]
stmt_arms = {
    'lower': ["SetPlace(aplace, avalue) -> None,", "SetPlaceOp(aop, aplace, avalue) -> None,"],
    'breaks_out': ["SetPlace(aplace, avalue) -> false,", "SetPlaceOp(aop, aplace, avalue) -> false,"],
    'depth': ["SetPlace(aplace, avalue) -> 0,", "SetPlaceOp(aop, aplace, avalue) -> 0,"],
    'slice_uses': ["SetPlace(aplace, avalue) -> concat(aplace.slice_uses(), avalue.slice_uses()),",
                   "SetPlaceOp(aop, aplace, avalue) -> concat(aplace.slice_uses(), avalue.slice_uses()),"],
    'array_bytes': ["SetPlace(aplace, avalue) -> 0,", "SetPlaceOp(aop, aplace, avalue) -> 0,"],
    'callee_need': ["SetPlace(aplace, avalue) -> max_of(aplace.callee_need(needs), avalue.callee_need(needs)),",
                    "SetPlaceOp(aop, aplace, avalue) -> max_of(aplace.callee_need(needs), avalue.callee_need(needs)),"],
    'declare': ["SetPlace(aplace, avalue) -> declare_types(concat(aplace.types(), avalue.types()), decls),",
                "SetPlaceOp(aop, aplace, avalue) -> declare_types(concat(aplace.types(), avalue.types()), decls),"],
    'returns': ["SetPlace(aplace, avalue) -> false,", "SetPlaceOp(aop, aplace, avalue) -> false,"],
}
lines = src.split('\n'); out = []; fn = ''; done = []
for line in lines:
    out.append(line)
    m = re.match(r'^\s*(pub )?fn (\w+)', line)
    if m: fn = m.group(2)
    m = re.match(r'^(\s*)EStr\(offset, chars\) -> (.*),$', line)
    if m:
        ind, val = m.group(1), m.group(2)
        if fn in eff_arms: new = eff_arms[fn]
        elif val in ('empty()', 'None', '0', 'false'): new = eff_const(val)
        elif fn == 'eval': new = eff_const('None')
        else: raise SystemExit(f'SrcEff arm in {fn}: {val}')
        out += [ind + a for a in new]; done.append('eff:' + fn); continue
    m = re.match(r'^(\s*)LetStr\(pointer, chars, body\) -> (.*),$', line)
    if m:
        ind = m.group(1)
        if fn not in stmt_arms: raise SystemExit(f'SrcStmt arm in {fn}')
        out += [ind + a for a in stmt_arms[fn]]; done.append('stmt:' + fn)
open(path, 'w').write('\n'.join(out))
print(done)
