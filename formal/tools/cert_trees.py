"""Parse trees for the certificates (the extractions and the self program),
found without laniusc where possible.

    import cert_trees
    accepted = cert_trees.write(bases, workdir)

Each base's tree (base.prods, base.parents, of base.lani) comes from, in
turn: a tree the verified validator accepted before for the same source text
under the same grammar (the run cache's `cert-parse` entries); the CPU parser
(fuzz_oracle.Parser, over the Lean lexer's tokens); laniusc
(stdlib_oracle.parse_stdlib_file, then parse_tree). Every tree, from any of
them, is checked by the verified validator here, and none of them is
trusted: the validator accepts a tree only when it is a parse of the tokens
by the grammar, and `Lanius.Mini.Unique` proves that there is only one, so
an accepted tree is laniusc's whatever found it (TRUSTED_BASE.md, section
4). The key is the source and the text of the extracted definitions
`grammar` uses, not laniusc's digest: a rebuild of laniusc by another branch
does not send every file back through the GPU queue.
"""
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import grammar_cert  # noqa: E402
import run_cache  # noqa: E402
import stdlib_oracle as so  # noqa: E402

LANIUSC = 'target/release/laniusc'
_grammar = []


def grammar_digest():
    """A digest of the extracted definitions `grammar` uses, by name and text."""
    if not _grammar:
        h = hashlib.sha256()
        for name, (_, text) in sorted(grammar_cert.closure(['grammar']).items()):
            h.update(name.encode() + b'\0' + text.encode() + b'\0')
        _grammar.append(h.hexdigest())
    return _grammar[0]


def cpu_trees(bases, workdir):
    """The CPU parser's trees of bases: {base: (prods, parents)} for those it parses."""
    import fuzz_oracle
    for b in bases:
        so.write_tree(b, ([], []))
    manifest = os.path.join(workdir, 'cert_dump.txt')
    open(manifest, 'w').write(''.join(f'dump d{i} {b}\n' for i, b in enumerate(bases)))
    out = run_cache.run_all(manifest).stdout
    lines = {line.split(' ', 1)[0]: line for line in out.split('\n') if ' file ' in line}
    parser = fuzz_oracle.Parser()
    found = {}
    for i, b in enumerate(bases):
        if f'd{i}' in lines:
            tree = parser.parse(parser.tokens(lines[f'd{i}']))
            if tree is not None:
                found[b] = tree
    return found


def write(bases, workdir, laniusc=LANIUSC):
    """Write each base's tree; return the bases whose tree the validator accepts."""
    keys = {b: run_cache.key('cert-parse', grammar_digest(), open(b + '.lani', 'rb').read()) for b in bases}
    trees = {}
    for b in bases:
        hit = run_cache.load('cert-parse', keys[b])
        if hit is not None:
            trees[b] = (hit['prods'], hit['parents'])
    todo = [b for b in bases if b not in trees]
    if todo:
        trees.update(cpu_trees(todo, workdir))
    ok = set()
    # The cached and CPU trees, then laniusc's two ways for those rejected.
    for find in (None, so.parse_stdlib_file, so.parse_tree):
        left = [b for b in bases if b not in ok]
        if find is not None:
            for b in left:
                tree = find(laniusc, b + '.lani', workdir)
                if tree is not None:
                    trees[b] = tree
        for b in left:
            so.write_tree(b, trees.get(b, ([], [])))
        ok |= so.validate_all(left, workdir)
        if len(ok) == len(bases):
            break
    for b in todo:
        if b in ok:
            run_cache.store('cert-parse', keys[b], dict(prods=trees[b][0], parents=trees[b][1]))
    return ok
