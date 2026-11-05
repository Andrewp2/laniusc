import re, sys
path = sys.argv[1]
src = open(path).read().split('\n')
out = []
def fn_of(i):
    for j in range(i, -1, -1):
        m = re.match(r'(pub )?fn (\w+)', src[j])
        if m: return m.group(2)
    return None
vals = {
 'scalar_src': 'None', 'float_typed': 'None', 'field_index': 'None', 'typed_literal': 'None',
 'wide_of': 'None', 'struct_field_tys': 'None', 'slice_elem': 'None', 'index_elem': 'None',
 'array_parts': 'None', 'named_parts': 'None', 'lit_ty': 'false', 'is_ptr_ty': 'false',
 'lower_ty': 'ref_type(lower_ty(minus(fuel, 1), decls, table, unbox(refd)))',
 'ty_insts': 'ty_insts(minus(fuel, 1), decls, unbox(refd))',
 'ty_known': 'ty_known(table, unbox(refd))',
 'ty_weight': 'weight_add_to(1, ty_weight(table, ws, unbox(refd)))',
 'close_ty': 'ref_type(close_ty(minus(fuel, 1), t, unbox(refd)))',
}
done = set()
i = 0
while i < len(src):
    line = src[i]
    out.append(line)
    m = re.match(r'^(\s*)TyStr -> (.*),$', line)
    if m:
        f = fn_of(i)
        ind = m.group(1)
        if f == 'same_ty':
            if m.group(2) == 'match (b) {':
                pass
            else:
                out.append(ind + 'TyRef(f) -> false,')
        elif f in vals:
            out.append(ind + 'TyRef(refd) -> ' + vals[f] + ',')
            done.add(f)
        else:
            print('skip', i+1, f, line)
    if line == '    TyStr,' and fn_of(i) is None:
        out.append('    // a reference to a referent of this type: only a parameter\'s type')
        out.append('    // (`&T` or `&mut T`, param_ty_of)')
        out.append('    TyRef(Box<Ty>),')
    i += 1
missing = set(vals) - done
print('missing', missing)
text = '\n'.join(out)
# same_ty: the outer TyRef arm, after the TyArray arm's inner match
anchor = '''            TyArray(f, m) -> (n == m) && same_ty(unbox(x), unbox(f)),
            TyNamed(e, bs) -> false,
            TySint(v) -> false,
        },
'''
assert text.count(anchor) == 1
arm = '''        TyRef(x) -> match (b) {
            TyI32 -> false,
            TyBool -> false,
            TyUint(v) -> false,
            TyPtr -> false,
            TyIsize -> false,
            TyChar -> false,
            TyStr -> false,
            TyRef(f) -> same_ty(unbox(x), unbox(f)),
            TyFloat(g) -> false,
            TySlice(f) -> false,
            TyArray(f, n) -> false,
            TyNamed(e, bs) -> false,
            TySint(v) -> false,
        },
'''
text = text.replace(anchor, anchor + arm)
# the TyStr inner arm of same_ty's TyStr outer arm
a2 = '''            TyStr -> true,
'''
assert text.count(a2) == 1
text = text.replace(a2, a2 + '            TyRef(f) -> false,\n')
# ref_type after slice_type
a3 = '''pub fn slice_type(element: core::option::Option<SrcType>) -> core::option::Option<SrcType> {
    return match (element) {
        None -> None,
        Some(e) -> Some(Slice(boxed(e))),
    };
}
'''
assert text.count(a3) == 1
text = text.replace(a3, a3 + '''
pub fn ref_type(referent: core::option::Option<SrcType>) -> core::option::Option<SrcType> {
    return match (referent) {
        None -> None,
        Some(e) -> Some(Ref(boxed(e))),
    };
}
''')
open(path, 'w').write(text)
