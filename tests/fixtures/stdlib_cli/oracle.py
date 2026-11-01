"""Oracle for std::cli against Python's getopt (GNU getopt_long semantics).

usage: python3 -I oracle.py BATCH_EXE [--seed N] [--cases N]

BATCH_EXE is tests/fixtures/stdlib_cli/batch.lani compiled. Three layers:

- getopt: for option sets without optional values, getopt.gnu_getopt
  (permuting) or getopt.getopt (stop at the first operand, and the root of
  a command with subcommands) gives the occurrences, operands and the
  error. The model below must agree with it on every such case.
- model: a small Python model of getopt_long with optional values,
  operand counts and subcommands, and the glibc error messages
  ("unrecognized option '--x'", "option '--a' is ambiguous;
  possibilities: ...", ...) that were confirmed against GNU coreutils 9.4
  binaries on this machine. std::cli must agree with the model on every
  case: occurrences, values, operands, command, error kind, argument index,
  offset and message bytes.
- help: hand-written expected --help texts.

Prints `group agree/total` lines and exits 1 on any disagreement.
"""

import getopt
import random
import subprocess
import sys


class Spec:
    def __init__(self, kind, scope, id, short, long, value='', help=''):
        self.kind, self.scope, self.id, self.short, self.long, self.value, self.help = kind, scope, id, short, long, value, help


class Sub:
    def __init__(self, id, name, help='', operand='', minimum=0, maximum=-1):
        self.id, self.name, self.help, self.operand, self.minimum, self.maximum = id, name, help, operand, minimum, maximum


class Cli:
    def __init__(self, specs, subs=(), name='prog', about='', operand='', minimum=0, maximum=-1, stop=False):
        self.specs, self.subs, self.name, self.about = list(specs), list(subs), name, about
        self.operand, self.minimum, self.maximum, self.stop = operand, minimum, maximum, stop

    def help_id(self):
        return any(s.kind == 'H' and s.scope == -1 for s in self.specs)

    def scoped(self, scope):
        out = []
        for s in self.specs:
            if s.scope == scope:
                if s.kind == 'H':
                    out.append(Spec('F', scope, s.id, 'h', 'help', '', 'display this help and exit'))
                else:
                    out.append(s)
        return out


# Model ------------------------------------------------------------------------

class Fail(Exception):
    def __init__(self, kind, argument, offset, spec=None, scope=-1):
        self.kind, self.argument, self.offset, self.spec, self.scope = kind, argument, offset, spec, scope


def model(cli, args):
    """(command, [(id, value|None)], [operands]) or raises Fail."""
    state = {'i': 0, 'occ': [], 'ops': [], 'opi': [], 'help': False}

    def find_long(specs, name):
        found = None
        for s in specs:
            if s.long and s.long.startswith(name):
                if s.long == name:
                    return s
                found = s if found is None else 'ambiguous'
        return found

    def scan(scope, stop, root_with_subs):
        specs = cli.scoped(scope)
        ended = False
        while state['i'] < len(args):
            word = args[state['i']]
            if ended or len(word) < 2 or word[0] != '-':
                if root_with_subs:
                    return
                if stop:
                    ended = True
                state['ops'].append(word)
                state['opi'].append(state['i'])
                state['i'] += 1
                continue
            if word[1] == '-':
                if word == '--':
                    ended = True
                    state['i'] += 1
                    if root_with_subs:
                        return
                    continue
                name, eq, value = word[2:].partition('=')
                s = find_long(specs, name)
                if s is None:
                    raise Fail('UnknownOption', state['i'], 0, scope=scope)
                if s == 'ambiguous':
                    raise Fail('AmbiguousOption', state['i'], 0, scope=scope)
                argument = state['i']
                state['i'] += 1
                if eq:
                    if s.kind == 'F':
                        raise Fail('UnexpectedValue', argument, 2 + len(name), s, scope)
                    state['occ'].append((s.id, value))
                elif s.kind == 'R':
                    if state['i'] >= len(args):
                        raise Fail('MissingValue', argument, 0, s, scope)
                    state['occ'].append((s.id, args[state['i']]))
                    state['i'] += 1
                else:
                    state['occ'].append((s.id, None))
                    state['help'] = state['help'] or s.long == 'help' and any(x.kind == 'H' and x.id == s.id for x in cli.specs)
                continue
            argument = state['i']
            state['i'] += 1
            offset = 1
            while offset < len(word):
                s = next((x for x in specs if x.short == word[offset]), None)
                if s is None:
                    raise Fail('InvalidOption', argument, offset, scope=scope)
                if s.kind == 'F':
                    state['occ'].append((s.id, None))
                    state['help'] = state['help'] or s.short == 'h' and any(x.kind == 'H' and x.id == s.id for x in cli.specs)
                    offset += 1
                    continue
                if offset + 1 < len(word):
                    state['occ'].append((s.id, word[offset + 1:]))
                elif s.kind == 'R':
                    if state['i'] >= len(args):
                        raise Fail('MissingValue', argument, offset, s, scope)
                    state['occ'].append((s.id, args[state['i']]))
                    state['i'] += 1
                else:
                    state['occ'].append((s.id, None))
                break

    command, scope = -1, -1
    scan(-1, cli.stop or bool(cli.subs), bool(cli.subs))
    minimum, maximum = cli.minimum, cli.maximum
    if state['help']:
        return command, state['occ'], state['ops']
    if cli.subs:
        if state['i'] >= len(args):
            raise Fail('MissingCommand', -1, -1)
        word = args[state['i']]
        index = next((k for k, s in enumerate(cli.subs) if s.name == word), None)
        if index is None:
            raise Fail('UnknownCommand', state['i'], 0)
        state['i'] += 1
        command, scope = cli.subs[index].id, index
        scan(index, cli.stop, False)
        minimum, maximum = cli.subs[index].minimum, cli.subs[index].maximum
        if state['help']:
            return command, state['occ'], state['ops']
    if len(state['ops']) < minimum:
        raise Fail('MissingOperand', -1, -1, scope=scope)
    if maximum >= 0 and len(state['ops']) > maximum:
        raise Fail('ExtraOperand', state['opi'][maximum], 0, scope=scope)
    return command, state['occ'], state['ops']


def message(cli, fail, args):
    word = args[fail.argument] if 0 <= fail.argument < len(args) else ''
    k = fail.kind
    if k == 'UnknownOption':
        text = "unrecognized option '%s'" % word
    elif k == 'InvalidOption':
        text = "invalid option -- '%s'" % word[fail.offset]
    elif k == 'AmbiguousOption':
        name = word[2:].partition('=')[0]
        text = "option '%s' is ambiguous; possibilities:" % word + ''.join(
            " '--%s'" % s.long for s in cli.scoped(fail.scope) if s.long and s.long.startswith(name))
    elif k == 'UnexpectedValue':
        text = "option '--%s' doesn't allow an argument" % fail.spec.long
    elif k == 'MissingValue':
        if fail.offset == 0:
            text = "option '--%s' requires an argument" % fail.spec.long
        else:
            text = "option requires an argument -- '%s'" % fail.spec.short
    elif k == 'MissingCommand':
        text = 'missing command'
    elif k == 'UnknownCommand':
        text = "unknown command '%s'" % word
    elif k == 'MissingOperand':
        text = 'missing operand'
    elif k == 'ExtraOperand':
        text = "extra operand '%s'" % word
    out = '%s: %s\n' % (cli.name, text)
    if cli.help_id():
        out += "Try '%s --help' for more information.\n" % cli.name
    return out


# getopt cross-check -----------------------------------------------------------

def getopt_parse(cli, args):
    """Like model() via Python getopt, or raises Fail with argument -1 (getopt
    does not report positions); None when getopt cannot express the case."""
    if any(s.kind == 'O' for s in cli.specs):
        return None

    def run(scope, argv, stop):
        specs = cli.scoped(scope)
        shorts = ''.join(s.short + (':' if s.kind == 'R' else '') for s in specs if s.short)
        longs = [s.long + ('=' if s.kind == 'R' else '') for s in specs if s.long]
        try:
            if stop:
                opts, rest = getopt.getopt(argv, shorts, longs)
            else:
                opts, rest = getopt.gnu_getopt(argv, shorts, longs)
        except getopt.GetoptError as error:
            msg, opt = error.msg, error.opt
            if 'not recognized' in msg:
                raise Fail('UnknownOption' if msg.startswith('option --') else 'InvalidOption', -1, -1, opt)
            if 'not a unique prefix' in msg:
                raise Fail('AmbiguousOption', -1, -1, opt)
            if 'must not have an argument' in msg:
                raise Fail('UnexpectedValue', -1, -1, opt)
            if 'requires argument' in msg:
                raise Fail('MissingValue', -1, -1, opt)
            raise
        occ = []
        for name, value in opts:
            if name.startswith('--'):
                s = next(x for x in specs if x.long == name[2:])
            else:
                s = next(x for x in specs if x.short == name[1:])
            occ.append((s.id, value if s.kind == 'R' else None))
        return occ, rest

    def helped(occ):
        return any(x.kind == 'H' and x.id == id for id, _ in occ for x in cli.specs)

    if not cli.subs:
        occ, rest = run(-1, args, cli.stop)
        return -1, occ, rest
    occ, rest = run(-1, args, True)
    if helped(occ):
        return -1, occ, rest[:0]
    if not rest:
        raise Fail('MissingCommand', -1, -1)
    index = next((k for k, s in enumerate(cli.subs) if s.name == rest[0]), None)
    if index is None:
        raise Fail('UnknownCommand', -1, -1, rest[0])
    more, ops = run(index, rest[1:], cli.stop)
    return cli.subs[index].id, occ + more, ops


def fail_name(fail, args):
    """The option name getopt reports for a model failure."""
    word = args[fail.argument] if fail.argument >= 0 else ''
    if fail.kind in ('UnknownOption', 'AmbiguousOption'):
        return word[2:].partition('=')[0]
    if fail.kind == 'InvalidOption':
        return word[fail.offset]
    if fail.kind == 'UnexpectedValue':
        return fail.spec.long
    if fail.kind == 'MissingValue':
        return fail.spec.long if fail.offset == 0 else fail.spec.short
    if fail.kind == 'UnknownCommand':
        return word
    return None


# Generation -------------------------------------------------------------------

LONGS = ['all', 'almost-all', 'author', 'file', 'files', 'filter', 'verbose', 'version', 'color', 'colour', 'c',
         'x-y', 'level', 'output', 'out', 'quiet', 'q2']
SHORTS = list('abcfvqxo1Z')
VALUES = ['x', '', '-', '--', '-x', '--all', 'a=b', '=', 'two words', 'é', '-1']
WORDS = ['file1', 'dir/x', '-', 'é', 'a=b', 'add', 'rm', 'list', 'x']
SUBS = ['add', 'rm', 'list', 'remote']


def gen_specs(rng, scope, start_id, allow_optional):
    specs, shorts, longs = [], set(), set()
    for k in range(rng.randrange(1, 7)):
        kind = rng.choice(['F', 'F', 'R', 'O'] if allow_optional else ['F', 'F', 'R'])
        short = rng.choice(SHORTS) if rng.random() < 0.7 else ''
        long = rng.choice(LONGS) if (rng.random() < 0.7 or not short) else ''
        if short in shorts:
            short = ''
        if long in longs:
            long = ''
        if not short and not long:
            continue
        shorts.add(short)
        longs.add(long)
        specs.append(Spec(kind, scope, start_id + k, short, long, rng.choice(['FILE', 'N', 'WHEN']), 'help for %d' % (start_id + k)))
    if rng.random() < 0.2 and 'h' not in shorts and 'help' not in longs:
        specs.append(Spec('H', scope, start_id + 50, '', ''))
    return specs


def gen_args(rng, cli, scope_specs):
    longs = [s.long for s in scope_specs if s.long] or ['all']
    shorts = [s.short for s in scope_specs if s.short] or ['a']
    args = []
    for _ in range(rng.randrange(0, 8)):
        r = rng.random()
        if r < 0.2:
            args.append('--' + rng.choice(longs))
        elif r < 0.3:
            name = rng.choice(longs)
            args.append('--' + name[:rng.randrange(1, len(name) + 1)])
        elif r < 0.4:
            args.append('--' + rng.choice(longs * 3 + LONGS) + '=' + rng.choice(VALUES))
        elif r < 0.41:
            args.append('--' + rng.choice(['nope', 'zz', 'alll']))
        elif r < 0.65:
            chars = [rng.choice(shorts) if rng.random() < 0.92 else rng.choice(SHORTS) for _ in range(rng.randrange(1, 4))]
            args.append('-' + ''.join(chars) + ('val' if rng.random() < 0.1 else ''))
        elif r < 0.7:
            args.append('--')
        elif r < 0.8:
            args.append(rng.choice(VALUES))
        else:
            args.append(rng.choice(WORDS))
    return args


def gen_case(rng):
    allow_optional = rng.random() < 0.5
    specs = gen_specs(rng, -1, 0, allow_optional)
    subs = []
    if rng.random() < 0.25:
        for k, name in enumerate(rng.sample(SUBS, rng.randrange(1, 4))):
            mx = rng.choice([-1, 0, 1, 2])
            mn = rng.choice([0, 0, 1]) if mx != 0 else 0
            if mx >= 0:
                mn = min(mn, mx)
            subs.append(Sub(100 + k, name, 'sub %s' % name, 'ARG', mn, mx))
            specs += gen_specs(rng, k, 200 + 20 * k, allow_optional)
    maximum = rng.choice([-1, -1, 0, 1, 2, 3])
    minimum = min(rng.choice([0, 0, 1, 2]), maximum if maximum >= 0 else 9)
    cli = Cli(specs, subs, operand='FILE', minimum=minimum, maximum=maximum, stop=rng.random() < 0.2)
    root = cli.scoped(-1)
    args = gen_args(rng, cli, root)
    if subs:
        if rng.random() < 0.85:
            at = rng.randrange(0, len(args) + 1)
            name = rng.choice([s.name for s in subs] + ['bogus'])
            args.insert(at, name)
            scope = next((k for k, s in enumerate(subs) if s.name == name), None)
            if scope is not None:
                args += gen_args(rng, cli, cli.scoped(scope))
    return cli, args


# Batch --------------------------------------------------------------------------

def field(value):
    data = value.encode('utf-8') if isinstance(value, str) else value
    return b'%d:' % len(data) + data


def number(value):
    return field(str(value))


def record(cli, args, mode='P', help_sub=-1):
    out = [field(mode), number(help_sub), field(cli.name), field(cli.about), field(cli.operand), number(cli.minimum),
           number(cli.maximum), number(1 if cli.stop else 0), number(len(cli.specs)), number(len(cli.subs)), number(len(args))]
    for s in cli.specs:
        out += [field(s.kind), number(s.scope), number(s.id), number(ord(s.short) if s.short else 0), field(s.long),
                field(s.value), field(s.help)]
    for s in cli.subs:
        out += [number(s.id), field(s.name), field(s.help), field(s.operand), number(s.minimum), number(s.maximum)]
    out += [field(a) for a in args]
    return b''.join(out)


def run(exe, records):
    result = subprocess.run([exe], input=b''.join(records), capture_output=True, timeout=240)
    if result.returncode != 0:
        raise SystemExit('batch exited %d %r' % (result.returncode, result.stderr[:300]))
    data, at, out = result.stdout, 0, []
    while at < len(data):
        end = data.index(b'\n', at)
        line = data[at:end].decode('utf-8')
        at = end + 1
        if line.startswith('ok '):
            out.append(('ok', parse_ok(line[3:])))
        else:
            head = line.split(' ')
            size = int(head[-1])
            text = data[at:at + size].decode('utf-8')
            at += size
            out.append((head[0], head[1:-1], text))
    return out


def parse_ok(text):
    b = text.encode('utf-8')
    i = b.index(b' ') if b' ' in b else len(b)
    command = int(b[:i])
    occ, ops = [], []
    while i < len(b):
        assert b[i:i + 1] == b' '
        tag = b[i + 1:i + 2]
        i += 2
        if tag == b'o':
            j = i
            while j < len(b) and b[j:j + 1] not in (b' ', b'='):
                j += 1
            id = int(b[i:j])
            i = j
            value = None
            if i < len(b) and b[i:i + 1] == b'=':
                value, i = take(b, i + 1)
            occ.append((id, value))
        else:
            value, i = take(b, i)
            ops.append(value)
    return command, occ, ops


def take(b, i):
    j = b.index(b':', i)
    n = int(b[i:j])
    return b[j + 1:j + 1 + n].decode('utf-8'), j + 1 + n


HELP_CASES = [
    (Cli([Spec('F', -1, 1, 'a', 'all', '', 'do not ignore entries starting with .'),
          Spec('R', -1, 2, 'f', 'file', 'ARCHIVE', 'use archive file ARCHIVE'),
          Spec('O', -1, 3, '', 'color', 'WHEN', 'colorize the output;\nWHEN is always, never or auto'),
          Spec('R', -1, 4, 'C', '', 'DIR', 'change to DIR first'),
          Spec('O', -1, 5, 'z', '', 'N', ''),
          Spec('H', -1, 6, '', '')], name='tool', about='List things.', operand='FILE', minimum=0, maximum=-1), -1,
     'Usage: tool [OPTION]... [FILE]...\nList things.\n\nOptions:\n'
     '  -a, --all           do not ignore entries starting with .\n'
     '  -f, --file=ARCHIVE  use archive file ARCHIVE\n'
     '      --color[=WHEN]  colorize the output;\n'
     '                      WHEN is always, never or auto\n'
     '  -C DIR              change to DIR first\n'
     '  -z[N]\n'
     '  -h, --help          display this help and exit\n'),
    (Cli([Spec('F', -1, 1, 'v', 'verbose', '', 'say more'),
          Spec('F', 0, 2, 'n', 'dry-run', '', 'only show what would happen'),
          Spec('R', 1, 3, '', 'reason-for-removing-this-file-now', 'TEXT', 'why')],
         [Sub(10, 'add', 'Add file contents', 'PATH', 1, -1), Sub(11, 'rm', 'Remove files', 'PATH', 1, 1)],
         name='vc', about='A version tool.'), -1,
     'Usage: vc [OPTION]... COMMAND [ARG]...\nA version tool.\n\nOptions:\n'
     '  -v, --verbose  say more\n\nCommands:\n'
     '  add            Add file contents\n'
     '  rm             Remove files\n'),
    (None, 10, 'Usage: vc add [OPTION]... PATH...\nAdd file contents\n\nOptions:\n'
     '  -n, --dry-run  only show what would happen\n'),
    (None, 11, 'Usage: vc rm [OPTION]... PATH\nRemove files\n\nOptions:\n'
     '      --reason-for-removing-this-file-now=TEXT\n'
     '                              why\n'),
    (Cli([], name='bare', operand='X Y', minimum=2, maximum=2), -1, 'Usage: bare X Y\n'),
    (Cli([], name='opt', operand='X', minimum=0, maximum=1), -1, 'Usage: opt [X]\n'),
    (Cli([], name='many', operand='X', minimum=1, maximum=-1), -1, 'Usage: many X...\n'),
]

FIXED = [
    # GNU message forms confirmed with coreutils ls, sort and head on this machine.
    (Cli([Spec('F', -1, 1, 'a', 'all'), Spec('F', -1, 2, 'A', 'almost-all'), Spec('F', -1, 3, '', 'author'),
          Spec('O', -1, 4, '', 'color', 'WHEN'), Spec('F', -1, 5, '', 'context'), Spec('H', -1, 6, '', '')], name='ls'),
     [['--co'], ['--colr=x'], ['--all=3'], ['--al=3'], ['-j'], ['-aj'], ['--hel=x'], ['--a'], ['--all', '--al'],
      ['--color'], ['--color=never', '-aA', 'x', '--', '-a'], ['--col', 'x']]),
    (Cli([Spec('R', -1, 1, 't', 'field-separator', 'SEP'), Spec('F', -1, 2, '', 'version'), Spec('F', -1, 3, 'V', 'version-sort')],
         name='sort'),
     [['--field-separator'], ['--field'], ['-t'], ['--ver=1'], ['-t', ','], ['-t,'], ['--field', '--'], ['--version']]),
    (Cli([Spec('R', -1, 1, 'n', 'lines', 'NUM'), Spec('R', -1, 2, 'c', 'bytes', 'NUM')], name='head', operand='FILE', maximum=1),
     [['-n'], ['--lin'], ['--bytes=', 'f'], ['-ckk'], ['a', 'b'], ['-n3', '--', '-x']]),
]


def main():
    args = sys.argv[1:]
    seed, count = 11, 6000
    if '--seed' in args:
        seed = int(args[args.index('--seed') + 1])
    if '--cases' in args:
        count = int(args[args.index('--cases') + 1])
    exe = args[0]
    rng = random.Random(seed)
    cases = [(cli, a) for cli, argvs in FIXED for a in argvs] + [gen_case(rng) for _ in range(count)]
    help_records = []
    last = None
    for cli, sub, text in HELP_CASES:
        last = cli or last
        help_records.append((last, sub, text))
    records = [record(cli, a) for cli, a in cases] + [record(cli, [], 'H', sub) for cli, sub, _ in help_records]
    results = run(exe, records)
    failed = 0

    def show(*parts):
        if failed <= 12:
            print('DIFF', *parts)

    agree = checked = model_ok = 0
    kinds = {}
    for (cli, argv), got in zip(cases, results):
        try:
            expected = ('ok', model(cli, argv))
        except Fail as fail:
            expected = ('err', [fail.kind, str(fail.argument), str(fail.offset)], message(cli, fail, argv))
        kind = expected[1][0] if expected[0] == 'err' else 'ok'
        kinds[kind] = kinds.get(kind, 0) + 1
        try:
            reference = getopt_parse(cli, argv)
            reference = None if reference is None else ('ok', reference)
        except Fail as fail:
            reference = ('err', fail.kind, fail.spec)
        if reference is not None:
            checked += 1
            if expected[0] == 'ok':
                good = reference == expected
            else:
                f = None
                try:
                    model(cli, argv)
                except Fail as error:
                    f = error
                good = reference[0] == 'err' and reference[1] == f.kind and (
                    reference[2] is None or reference[2] == fail_name(f, argv))
                if f.kind in ('MissingOperand', 'ExtraOperand'):
                    good = reference[0] == 'ok'  # getopt does not count operands
            model_ok += good
            if not good:
                failed += 1
                show('model vs getopt', argv, '\n  model', expected, '\n  getopt', reference)
        if got == expected:
            agree += 1
        else:
            failed += 1
            show('std::cli vs model', argv, [(s.kind, s.scope, s.short, s.long) for s in cli.specs],
                 [(s.name, s.minimum, s.maximum) for s in cli.subs], (cli.minimum, cli.maximum, cli.stop),
                 '\n  got     ', got, '\n  expected', expected)
    print('model vs getopt %d/%d' % (model_ok, checked))
    print('std::cli vs model %d/%d' % (agree, len(cases)))
    print('outcomes', ' '.join('%s=%d' % kv for kv in sorted(kinds.items())))

    ok = 0
    for (cli, sub, text), got in zip(help_records, results[len(cases):]):
        good = got[0] == 'help' and got[2] == text
        ok += good
        if not good:
            failed += 1
            show('help', sub, '\n' + (got[2] if len(got) > 2 else str(got)), '\nexpected\n' + text)
    print('help %d/%d' % (ok, len(help_records)))
    print('disagreements', failed)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
