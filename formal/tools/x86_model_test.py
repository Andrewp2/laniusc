#!/usr/bin/env python3
"""Differential test of the Lean x86 model against this CPU.

    python3 -I formal/tools/x86_model_test.py target/claude-work/step14 --per-form 200 --seed 1

For every instruction form the mini compiler emits (the byte patterns of
`Instr.encode`, `prologue` and `epilogue` in `Lanius/Mini/Compiler.lean`), the
tool generates random register, flag and memory states and runs each
instruction twice:

  natively   in this process: a stub in an RWX mapping loads RFLAGS and all
             sixteen registers, executes the instruction bytes, and lands on a
             recorder that stores the registers, RFLAGS and which landing point
             was reached (the fall-through or the branch/call/ret target);
  in Lean    `Lanius.X86.Machine.decode` and `execute`, with `#eval` on a
             generated file `<out>/ModelTest.lean` that reads the same states.

`Step` is a relation; its only freedom is in flags (AF after AND/OR/XOR/TEST,
every flag after IMUL/NEG/shifts/DIV) and `decode` may be applied to any byte list
loaded at rip. `decode` + `execute` is the computable form: `Step.decoded`
says `after = execute instruction size before` for every non-division
instruction, and the other constructors only widen the flags. So the comparison
is exact on the sixteen registers, rip and the 256-byte memory region every
access targets, and on the flag bits the relation fixes (CF PF AF ZF SF OF and
DF, minus AF for the logical forms, none for IMUL/NEG/DIV). Division cases
are ones that succeed on the CPU (a nonzero divisor, a quotient that fits),
where `Step.divided` fixes the quotient and remainder that `execute` writes.
The Lean side also
checks that `decode` returns exactly the instruction's length, that every
shorter prefix decodes to nothing, and that trailing bytes do not change the
result, which is what makes `Step` deterministic on these bytes.

The Lean file also prints `Instr.encode` for every instruction constructor,
`prologue` and `epilogue`; the tool splits those bytes into the forms below and
fails if any byte sequence is not covered, so a new emitted form is noticed.

`--probes` adds byte-store forms outside the compiler's output that exercise a
decoder corner (MOV r/m8, r8 without REX, where reg 4-7 name AH/CH/DH/BH,
which the model must refuse to decode).
Only machine code this tool generates runs, in its own process (UD2 runs in a
forked child).
"""

import argparse
import ctypes
import mmap
import os
import random
import signal
import subprocess
import sys
import time

M64 = (1 << 64) - 1
STATUS = 0x8D5          # CF PF AF ZF SF OF
AF = 0x10
DF = 0x400
ALL_DEFINED = STATUS | DF
REG_NAMES = ['rax', 'rcx', 'rdx', 'rbx', 'rsp', 'rbp', 'rsi', 'rdi',
             'r8', 'r9', 'r10', 'r11', 'r12', 'r13', 'r14', 'r15']
RAX, RCX, RDX, RSP, RBP, R11, R12, R13, R14 = 0, 1, 2, 4, 5, 11, 12, 13, 14

REGION = 256            # memory every access targets, compared byte for byte
REGION_OFFSET = 0x800   # inside the data page
CODE_SIZE = 1 << 20
MAIN = 0x80000          # the per-case stub
RECORDER = 0x40         # the shared recorder
LANDING_LEN = 20


def le(value, n):
    return (value % (1 << (8 * n))).to_bytes(n, 'little')


def sext32(value):
    value &= 0xffffffff
    return value - (1 << 32) if value >> 31 else value


# ---------------------------------------------------------------- forms
#
# Each form: name, the fixed bytes before the variable field, the variable
# field ('imm64', 'imm32', 'disp32', 'rel32' or None), the access kind, and the
# RFLAGS bits the model's Step relation determines.

SETCC = {0x92: 'setb', 0x93: 'setae', 0x94: 'sete', 0x95: 'setne', 0x96: 'setbe',
         0x97: 'seta', 0x9C: 'setl', 0x9D: 'setge', 0x9E: 'setle', 0x9F: 'setg'}


def form(name, prefix, field=None, kind='plain', mask=ALL_DEFINED, base=None, width=0, signed=False):
    return dict(name=name, prefix=bytes(prefix), field=field, kind=kind, mask=mask,
                base=base, width=width, signed=signed)


def compiler_forms():
    f = [
        form('mov rax, imm64', [0x48, 0xB8], 'imm64'),
        form('mov r11, imm64', [0x49, 0xBB], 'imm64'),
        form('mov r11d, imm32', [0x41, 0xBB], 'imm32'),
        form('mov rax, [rbp+disp32]', [0x48, 0x8B, 0x85], 'disp32', 'mem', base=RBP, width=8),
        form('mov rcx, [rbp+disp32]', [0x48, 0x8B, 0x8D], 'disp32', 'mem', base=RBP, width=8),
        form('mov [rbp+disp32], rax', [0x48, 0x89, 0x85], 'disp32', 'mem', base=RBP, width=8),
        form('movzx eax, byte [rax+disp32]', [0x0F, 0xB6, 0x80], 'disp32', 'mem', base=RAX, width=1),
        form('mov [rcx+disp32], al', [0x88, 0x81], 'disp32', 'mem', base=RCX, width=1),
        form('mov eax, [rax+disp32]', [0x8B, 0x80], 'disp32', 'mem', base=RAX, width=4),
        form('mov rax, [rax+disp32]', [0x48, 0x8B, 0x80], 'disp32', 'mem', base=RAX, width=8),
        form('mov [rcx+disp32], eax', [0x89, 0x81], 'disp32', 'mem', base=RCX, width=4),
        form('mov [rcx+disp32], rax', [0x48, 0x89, 0x81], 'disp32', 'mem', base=RCX, width=8),
        form('mov rcx, rax', [0x48, 0x89, 0xC1]),
        form('mov rax, rcx', [0x48, 0x89, 0xC8]),
        form('mov rcx, r13', [0x4C, 0x89, 0xE9]),
        form('mov r11, rcx', [0x49, 0x89, 0xCB]),
        form('mov r13, r11', [0x4D, 0x89, 0xDD]),
        form('mov rsp, rbp', [0x48, 0x89, 0xEC]),
        form('mov rbp, rsp', [0x48, 0x89, 0xE5]),
        form('neg eax', [0xF7, 0xD8], mask=0),
        form('add eax, ecx', [0x01, 0xC8]),
        form('sub eax, ecx', [0x29, 0xC8]),
        form('and eax, ecx', [0x21, 0xC8], mask=ALL_DEFINED & ~AF),
        form('or eax, ecx', [0x09, 0xC8], mask=ALL_DEFINED & ~AF),
        form('xor eax, ecx', [0x31, 0xC8], mask=ALL_DEFINED & ~AF),
        form('imul eax, ecx', [0x0F, 0xAF, 0xC1], mask=0),
        form('add rax, rcx', [0x48, 0x01, 0xC8]),
        form('sub rax, rcx', [0x48, 0x29, 0xC8]),
        form('and rax, rcx', [0x48, 0x21, 0xC8], mask=ALL_DEFINED & ~AF),
        form('or rax, rcx', [0x48, 0x09, 0xC8], mask=ALL_DEFINED & ~AF),
        form('xor rax, rcx', [0x48, 0x31, 0xC8], mask=ALL_DEFINED & ~AF),
        form('imul rax, rcx', [0x48, 0x0F, 0xAF, 0xC1], mask=0),
        # Shifts by cl: the model leaves every flag free.
        form('shl eax, cl', [0xD3, 0xE0], mask=0),
        form('shr eax, cl', [0xD3, 0xE8], mask=0),
        form('sar eax, cl', [0xD3, 0xF8], mask=0),
        form('shl rax, cl', [0x48, 0xD3, 0xE0], mask=0),
        form('shr rax, cl', [0x48, 0xD3, 0xE8], mask=0),
        form('sar rax, cl', [0x48, 0xD3, 0xF8], mask=0),
        form('add rcx, r11', [0x4C, 0x01, 0xD9]),
        form('and rcx, r11', [0x4C, 0x21, 0xD9], mask=ALL_DEFINED & ~AF),
        form('add r11, rax', [0x49, 0x01, 0xC3]),
        form('add rax, r12', [0x4C, 0x01, 0xE0]),
        form('add rcx, r12', [0x4C, 0x01, 0xE1]),
        form('sub rsp, r11', [0x4C, 0x29, 0xDC]),
        form('cmp eax, ecx', [0x39, 0xC8]),
        form('cmp rax, rcx', [0x48, 0x39, 0xC8]),
        form('cmp r11, r14', [0x4D, 0x39, 0xF3]),
        form('test rax, rax', [0x48, 0x85, 0xC0], mask=ALL_DEFINED & ~AF),
        form('mov r11, rdx', [0x49, 0x89, 0xD3]),
        form('mov rdx, r11', [0x4C, 0x89, 0xDA]),
        form('mov rax, rdx', [0x48, 0x89, 0xD0]),
        form('xor edx, edx', [0x31, 0xD2], mask=ALL_DEFINED & ~AF),
        form('cdq', [0x99]),
        form('cqo', [0x48, 0x99]),
        # DIV and IDIV leave every status flag undefined.
        form('idiv ecx', [0xF7, 0xF9], kind='div', mask=0, width=4, signed=True),
        form('div ecx', [0xF7, 0xF1], kind='div', mask=0, width=4),
        form('idiv rcx', [0x48, 0xF7, 0xF9], kind='div', mask=0, width=8, signed=True),
        form('div rcx', [0x48, 0xF7, 0xF1], kind='div', mask=0, width=8),
    ]
    for opcode, name in sorted(SETCC.items()):
        f.append(form(f'{name} al', [0x0F, opcode, 0xC0]))
    f += [
        form('movzx eax, al', [0x0F, 0xB6, 0xC0]),
        form('jmp rel32', [0xE9], 'rel32', 'jmp'),
        form('je rel32', [0x0F, 0x84], 'rel32', 'jcc'),
        form('jbe rel32', [0x0F, 0x86], 'rel32', 'jcc'),
        form('call rel32', [0xE8], 'rel32', 'call'),
        form('push rbp', [0x55], kind='push'),
        form('pop rbp', [0x5D], kind='pop'),
        form('ret', [0xC3], kind='ret'),
        form('ud2', [0x0F, 0x0B], kind='fault'),
    ]
    return f


def probe_forms():
    # MOV r/m8, r8 (88 /r): without REX, reg 4-7 is AH CH DH BH; with any REX
    # it is SPL BPL SIL DIL. The compiler only emits reg 0 (al).
    return [
        # The model has no AH-BH, so decode must refuse these.
        form('[probe] mov [rcx+disp32], ah', [0x88, 0xA1], 'disp32', 'undecoded', base=RCX, width=1),
        form('[probe] mov [rcx+disp32], bh', [0x88, 0xB9], 'disp32', 'undecoded', base=RCX, width=1),
        form('[probe] mov [rcx+disp32], spl', [0x40, 0x88, 0xA1], 'disp32', 'mem', base=RCX, width=1),
        form('[probe] mov [rcx+disp32], dil', [0x40, 0x88, 0xB9], 'disp32', 'mem', base=RCX, width=1),
    ]


FIELD_LEN = {None: 0, 'imm64': 8, 'imm32': 4, 'disp32': 4, 'rel32': 4}


def form_length(fm):
    return len(fm['prefix']) + FIELD_LEN[fm['field']]


# ---------------------------------------------------------------- native side

class Native:
    """One RWX code mapping, one data page, one save/output page."""

    def __init__(self):
        rwx = mmap.PROT_READ | mmap.PROT_WRITE | mmap.PROT_EXEC
        self.code = mmap.mmap(-1, CODE_SIZE, prot=rwx)
        self.data = mmap.mmap(-1, 4096, prot=mmap.PROT_READ | mmap.PROT_WRITE)
        self.save = mmap.mmap(-1, 4096, prot=mmap.PROT_READ | mmap.PROT_WRITE)
        self.cbase = ctypes.addressof(ctypes.c_char.from_buffer(self.code))
        self.dbase = ctypes.addressof(ctypes.c_char.from_buffer(self.data))
        self.sbase = ctypes.addressof(ctypes.c_char.from_buffer(self.save))
        self.region = self.dbase + REGION_OFFSET
        self.out = self.sbase + 0x100
        rec = self.recorder()
        self.code[RECORDER:RECORDER + len(rec)] = rec
        self.fn = ctypes.CFUNCTYPE(None)(self.cbase + MAIN)
        self.pre_len = len(self.preamble(0, [0] * 16))

    def recorder(self):
        # rax already stored and eax = landing id. Store the id, the other
        # fifteen registers, restore rsp, store RFLAGS, restore callee-saved.
        c = b'\x48\xA3' + le(self.out + 0x88, 8)            # mov [out+0x88], rax
        c += b'\x48\xB8' + le(self.out, 8)                   # mov rax, out
        for r in range(1, 16):
            rex = 0x48 | (4 if r >= 8 else 0)
            c += bytes([rex, 0x89, 0x40 | ((r & 7) << 3), 8 * r])  # mov [rax+8r], r
        c += b'\x48\x8B\xA0' + le(-0x100, 4)                 # mov rsp, [rax-0x100]
        c += b'\x9C\x59'                                     # pushfq; pop rcx
        c += b'\x48\x89\x88' + le(0x80, 4)                   # mov [rax+0x80], rcx
        c += b'\x41\x5F\x41\x5E\x41\x5D\x41\x5C\x5D\x5B'     # pop r15..r12, rbp, rbx
        c += b'\xFC\xC3'                                     # cld; ret
        return c

    def preamble(self, flags, regs):
        c = b'\x53\x55\x41\x54\x41\x55\x41\x56\x41\x57'      # push rbx rbp r12-r15
        c += b'\x48\x89\xE0' + b'\x48\xA3' + le(self.sbase, 8)  # mov rax, rsp; mov [save], rax
        c += b'\x48\xB8' + le(flags, 8) + b'\x50\x9D'        # mov rax, flags; push rax; popfq
        for r in range(16):
            c += bytes([0x48 | (1 if r >= 8 else 0), 0xB8 + (r & 7)]) + le(regs[r], 8)
        return c

    def landing(self, at, ident):
        c = b'\x48\xA3' + le(self.out, 8) + b'\xB8' + le(ident, 4)
        c += b'\xE9' + le(RECORDER - (at + LANDING_LEN), 4)
        assert len(c) == LANDING_LEN
        self.code[at:at + LANDING_LEN] = c

    def run(self, case):
        """Run case natively; return (regs, flags, landing address, region bytes, rest-of-page ok)."""
        code = self.preamble(case['flags'], case['regs'])
        assert len(code) == self.pre_len
        start = MAIN + len(code)
        code += case['bytes']
        self.code[MAIN:MAIN + len(code)] = code
        nxt = MAIN + len(code)
        lands = {}
        for off, ident, jump in case['layout']:
            if jump is not None:
                self.code[off:off + 2] = bytes([0xEB, jump])
            else:
                self.landing(off, ident)
                lands[ident] = self.cbase + off
        if case['form']['kind'] == 'jcc':
            lands[0] = self.cbase + nxt                 # reached through the short jump at nxt
        page = bytearray(os.urandom(4096))
        page[REGION_OFFSET:REGION_OFFSET + REGION] = case['mem']
        self.data[:] = bytes(page)
        self.save[0x100:0x190] = bytes(0x90)
        self.fn()
        out = bytes(self.save[0x100:0x190])
        regs = [int.from_bytes(out[8 * r:8 * r + 8], 'little') for r in range(16)]
        regs[RAX] = int.from_bytes(out[0:8], 'little')
        flags = int.from_bytes(out[0x80:0x88], 'little')
        ident = int.from_bytes(out[0x88:0x90], 'little')
        after = bytes(self.data[:])
        rest_ok = (after[:REGION_OFFSET] == bytes(page[:REGION_OFFSET]) and
                   after[REGION_OFFSET + REGION:] == bytes(page[REGION_OFFSET + REGION:]))
        return regs, flags, lands[ident], after[REGION_OFFSET:REGION_OFFSET + REGION], rest_ok

    def run_fault(self, case):
        """Run in a forked child; return the signal that ended it (0 if it returned)."""
        pid = os.fork()
        if pid == 0:
            try:
                self.run(case)
            finally:
                os._exit(0)
        _, status = os.waitpid(pid, 0)
        return os.WTERMSIG(status) if os.WIFSIGNALED(status) else 0


# ---------------------------------------------------------------- case generation

SPECIAL = [0, 1, 2, M64, M64 - 1, 0x7fffffff, 0x80000000, 0xffffffff, 0x100000000,
           1 << 63, (1 << 63) - 1, 0xffffffff80000000, 0x7fffffffffffffff, 0x80, 0xff, 0x100,
           0xffffffff00000000, 0x00000000ffffff80]


def rand64(rng):
    roll = rng.random()
    if roll < 0.25:
        return rng.choice(SPECIAL)
    if roll < 0.4:
        return rng.randrange(256)
    if roll < 0.55:
        return rng.randrange(1 << 32)
    return rng.randrange(1 << 64)


def rand_regs(rng):
    regs = [rand64(rng) for _ in range(16)]
    for _ in range(rng.choice([0, 0, 1, 2])):
        a, b = rng.randrange(16), rng.randrange(16)
        if rng.random() < 0.5:
            regs[a] = regs[b]
        else:
            regs[a] = (regs[a] & ~0xffffffff & M64) | (regs[b] & 0xffffffff)
    # the forms' operands: rax, rcx, r11, r14
    pair = rng.random()
    if pair < 0.2:
        regs[RCX] = regs[RAX]
    elif pair < 0.3:
        regs[RCX] = (regs[RCX] & ~0xffffffff & M64) | (regs[RAX] & 0xffffffff)
    elif pair < 0.4:
        regs[R14] = regs[R11]
    elif pair < 0.45:
        regs[RAX] = 0
    return regs


def rand_disp(rng, fm):
    roll = rng.random()
    if fm['base'] == RBP and roll < 0.5:
        return -8 * (rng.randrange(1 << 20) + 1)       # a frame slot, as emitted
    if fm['base'] in (RAX, RCX) and roll < 0.3:
        return 0                                        # as emitted
    if roll < 0.7:
        return sext32(rng.randrange(1 << 32))
    return rng.choice([0, 1, -1, 0x7fffffff, -0x80000000, 8, -8])


def make_case(rng, fm, native, ident):
    regs = rand_regs(rng)
    flags = rng.randrange(1 << 12) & (STATUS | DF)
    flags |= 0x202                                      # reserved bit 1; IF stays set in user mode
    mem = bytearray(rng.randrange(256) for _ in range(REGION))
    region = native.region
    rip = native.cbase + MAIN + native.pre_len
    length = form_length(fm)
    nxt = MAIN + native.pre_len + length                # code offsets
    field = fm['field']
    value = None
    layout = [(nxt, 0, None)]                           # (offset, landing id, short jump)

    if field in ('imm64', 'imm32'):
        value = rand64(rng) & ((1 << (8 * FIELD_LEN[field])) - 1)
    elif field == 'disp32':
        value = rand_disp(rng, fm)
        ea = region + rng.randrange(0, REGION - fm['width'] + 1)
        regs[fm['base']] = (ea - value) & M64
    elif field == 'rel32':
        roll = rng.random()
        if roll < 0.35:
            value = rng.choice([2, 2, 3, 5, 21, 22, 40, 63, 100, 200, 0x1ff])
        elif roll < 0.7:
            value = rng.randrange(0x200, CODE_SIZE - 0x1000 - nxt)
        else:
            value = -rng.randrange(nxt - (MAIN - 0x1000) + 0x100, nxt - 0x1000)
        if fm['kind'] == 'jcc':
            if value < 22:
                layout = [(nxt, None, 42), (nxt + 44, 0, None)]
            else:
                layout = [(nxt, None, 0), (nxt + 2, 0, None)]
            layout.append((nxt + value, 1, None))
        else:
            layout = [] if 0 <= value < LANDING_LEN else layout
            layout.append((nxt + value, 1, None))
    if fm['kind'] in ('push', 'call'):
        regs[RSP] = region + 8 + rng.randrange(0, REGION - 8 + 1)
    elif fm['kind'] in ('pop', 'ret'):
        regs[RSP] = region + rng.randrange(0, REGION - 8 + 1)
    if fm['kind'] == 'ret':
        if rng.random() < 0.5:
            target = rng.randrange(0x1000, MAIN - 0x1000)
        else:
            target = rng.randrange(nxt + 0x100, CODE_SIZE - 0x100)
        layout.append((target, 1, None))
        at = regs[RSP] - region
        mem[at:at + 8] = le(native.cbase + target, 8)
    if fm['kind'] == 'div':
        # A division that succeeds: a nonzero divisor, and a quotient that fits,
        # as the compiled code sets up rdx (the sign of rax, or zero) or with any
        # high half below the divisor for an unsigned one.
        bits = 8 * fm['width']
        mask = (1 << bits) - 1
        while regs[RCX] & mask == 0:
            regs[RCX] = rand64(rng)
        divisor = regs[RCX] & mask
        high_bits = regs[RDX] & ~mask & M64           # ignored by a 32-bit divide
        if fm['signed']:
            if regs[RAX] & mask == 1 << (bits - 1) and divisor == mask:
                regs[RAX] ^= 1                           # the least value by -1 overflows
            sign = mask if regs[RAX] >> (bits - 1) & 1 else 0
            regs[RDX] = high_bits | sign
        elif rng.random() < 0.5:
            regs[RDX] = high_bits
        else:
            regs[RDX] = high_bits | rng.randrange(divisor)
    # alignment probes: unaligned stack and slot addresses happen naturally

    data = fm['prefix'] + (le(value, FIELD_LEN[field]) if field else b'')
    tail = bytes(rng.randrange(256) for _ in range(16))
    return dict(id=ident, form=fm, bytes=data, regs=regs, flags=flags, mem=bytes(mem),
                rip=rip, region=region, tail=tail, layout=layout)


# ---------------------------------------------------------------- Lean side

LEAN = r'''import Lanius.X86.Machine.Scalar
import Lanius.Mini.Compiler

/-! Generated by formal/tools/x86_model_test.py. Runs the x86 model's
`decode` and `execute` on the states in `cases.txt` and prints the results,
then prints the bytes of every mini compiler instruction form. -/

namespace X86ModelTest
open Lanius.X86.Machine

def digit (c : Char) : Nat :=
  if c.isDigit then c.toNat - 48 else c.toLower.toNat - 87

def hexNat (s : String) : Nat :=
  s.foldl (fun acc c => acc * 16 + digit c) 0

def hexBytes (s : String) : ByteArray := Id.run do
  let cs := s.toList.toArray
  let mut out := ByteArray.empty
  for i in [0:cs.size / 2] do
    out := out.push (UInt8.ofNat (digit cs[2 * i]! * 16 + digit cs[2 * i + 1]!))
  return out

def hexChar (n : Nat) : Char :=
  if n < 10 then Char.ofNat (48 + n) else Char.ofNat (87 + n)

def showByte (b : UInt8) : String :=
  String.mk [hexChar (b.toNat / 16), hexChar (b.toNat % 16)]

def showNat (n : Nat) : String :=
  String.mk (Nat.toDigits 16 n)

def initial (regs : Array Nat) (rip flags base : Nat) (mem : ByteArray) : State :=
  { registers := fun r => BitVec.ofNat 64 (regs.getD r.val 0)
    rip := BitVec.ofNat 64 rip
    memory := fun a =>
      let n := a.toNat
      if base ≤ n ∧ n - base < mem.size then mem.get! (n - base) else 0
    flags := BitVec.ofNat 64 flags }

/-- `id bytes rip flags base mem tail r0 .. r15`, all hex. -/
def runCase (line : String) : String :=
  let f := (line.splitOn " ").toArray
  let ident := f[0]!
  let bytes := (hexBytes f[1]!).toList
  let rip := hexNat f[2]!
  let flags := hexNat f[3]!
  let base := hexNat f[4]!
  let mem := hexBytes f[5]!
  let tail := (hexBytes f[6]!).toList
  let regs := (f.extract 7 23).map hexNat
  let s := initial regs rip flags base mem
  match decode bytes with
  | none => ident ++ " none"
  | some (instruction, size) =>
    let prefixes := (List.range bytes.length).all fun k => decode (bytes.take k) == none
    let tailed := decode (bytes ++ tail) == some (instruction, size)
    let after := execute instruction size s
    let regsOut := (List.range 16).map fun r =>
      if h : r < 16 then showNat (after.registers ⟨r, h⟩).toNat else "0"
    let memOut := String.join ((List.range mem.size).map fun i =>
      showByte (after.memory (BitVec.ofNat 64 (base + i))))
    let shown := (toString (repr instruction)).replace "\n" " "
    ident ++ " some " ++ toString size ++ " " ++ toString prefixes ++ " " ++ toString tailed ++ " " ++
      toString instruction.isDivision ++ " " ++ " ".intercalate regsOut ++ " " ++
      showNat after.rip.toNat ++ " " ++ showNat after.flags.toNat ++ " " ++ memOut ++ " | " ++ shown

def bytesHex (bytes : List UInt8) : String := String.join (bytes.map showByte)

open Lanius.Mini in
def encodings : List (String × List UInt8) :=
  let place : Place := { body := 4096, slots := 9, entries := [0, 2000, 3000] }
  let words := [Word.s32, Word.u64]
  let binops := [BinOp.add, BinOp.sub, BinOp.mul, BinOp.and, BinOp.or, BinOp.xor, BinOp.shl, BinOp.shr, BinOp.sar]
  let cmpops := [CmpOp.eq, CmpOp.ne, CmpOp.lt, CmpOp.le, CmpOp.gt, CmpOp.ge]
  let ops := words.flatMap fun w => binops.map fun o => (s!"op {repr w} {repr o}", Instr.op w o 3)
  let cmps := words.flatMap fun w => cmpops.map fun o => (s!"cmp {repr w} {repr o}", Instr.cmp w o 1048575)
  let divops := [DivOp.sDiv, DivOp.sRem, DivOp.uDiv, DivOp.uRem]
  let divs := words.flatMap fun w => divops.map fun o => (s!"div {repr w} {repr o}", Instr.div w o 5)
  let rest : List (String × Instr) :=
    [("imm", .imm 0x123456789abcdef0), ("load", .load 0), ("load far", .load 1048575),
     ("store", .store 7), ("neg", .neg), ("jmp back", .jmp 0), ("jmp", .jmp 900),
     ("jz", .jz 50), ("call", .call 1 [0, 1, 2] 3 2), ("ret", .ret [0, 1]),
     ("bump 0", .bump 0), ("bump 3", .bump 3), ("bump 31", .bump 31),
     ("loadAt", .loadAt), ("storeAt", .storeAt 4),
     ("loadWordAt m32", .loadWordAt .m32), ("loadWordAt m64", .loadWordAt .m64),
     ("storeWordAt m32", .storeWordAt .m32 4), ("storeWordAt m64", .storeWordAt .m64 4)]
  (ops ++ cmps ++ divs ++ rest).map (fun (n, i) => (n, Instr.encode i place 100)) ++
    [("prologue", prologue 5), ("prologue big", prologue 1048576), ("epilogue", epilogue)]

def main : IO Unit := do
  let text ← IO.FS.readFile "CASES"
  let lines := (text.splitOn "\n").filter (· ≠ "")
  let out := lines.map runCase
  let enc := encodings.map fun (n, b) => "enc " ++ n.replace " " "_" ++ " " ++ bytesHex b
  IO.FS.writeFile "RESULTS" ("\n".intercalate (out ++ enc) ++ "\n")

#eval main

end X86ModelTest
'''


def write_lean(out_dir, cases):
    path_cases = os.path.join(out_dir, 'cases.txt')
    path_results = os.path.join(out_dir, 'results.txt')
    with open(path_cases, 'w') as fh:
        for c in cases:
            fields = [str(c['id']), c['bytes'].hex(), f"{c['rip']:x}", f"{c['flags']:x}",
                      f"{c['region']:x}", c['mem'].hex(), c['tail'].hex()]
            fields += [f'{r:x}' for r in c['regs']]
            fh.write(' '.join(fields) + '\n')
    lean = LEAN.replace('"CASES"', '"' + path_cases + '"').replace('"RESULTS"', '"' + path_results + '"')
    path_lean = os.path.join(out_dir, 'ModelTest.lean')
    with open(path_lean, 'w') as fh:
        fh.write(lean)
    return path_lean, path_results


def run_lean(formal, path_lean):
    lake = os.path.expanduser('~/.elan/bin/lake')
    if not os.path.exists(lake):
        lake = 'lake'
    proc = subprocess.run([lake, 'env', 'lean', path_lean], cwd=formal,
                          capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout + proc.stderr)
        raise SystemExit('lean failed')


# ---------------------------------------------------------------- coverage

def split_forms(data, forms):
    """Split emitted bytes into known forms; return (names, None) or (names, bad offset)."""
    names, i = [], 0
    while i < len(data):
        match = None
        for fm in forms:
            if data[i:i + len(fm['prefix'])] == fm['prefix'] and i + form_length(fm) <= len(data):
                match = fm
                break
        if match is None:
            return names, i
        names.append(match['name'])
        i += form_length(match)
    return names, None


# ---------------------------------------------------------------- main

def describe(c):
    regs = ' '.join(f'{REG_NAMES[r]}={c["regs"][r]:#x}' for r in range(16))
    return (f'  bytes {c["bytes"].hex(" ")}\n  rip {c["rip"]:#x} flags {c["flags"]:#x}\n  {regs}\n'
            f'  region {c["region"]:#x}: {c["mem"].hex()}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out', help='directory for the generated Lean file, cases and results')
    ap.add_argument('--per-form', type=int, default=200)
    ap.add_argument('--seed', type=int, default=1)
    ap.add_argument('--probes', action='store_true', help='also test decoder corner forms')
    ap.add_argument('--formal', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
    args = ap.parse_args()
    out_dir = os.path.abspath(args.out)
    os.makedirs(out_dir, exist_ok=True)
    rng = random.Random(args.seed)
    native = Native()
    forms = compiler_forms() + (probe_forms() if args.probes else [])
    cases = []
    for fm in forms:
        count = 3 if fm['kind'] == 'fault' else args.per_form
        for _ in range(count):
            cases.append(make_case(rng, fm, native, len(cases)))

    t0 = time.time()
    native_results = {}
    for c in cases:
        if c['form']['kind'] == 'fault':
            native_results[c['id']] = ('signal', native.run_fault(c))
        else:
            native_results[c['id']] = native.run(c)
    t1 = time.time()
    path_lean, path_results = write_lean(out_dir, cases)
    run_lean(os.path.abspath(args.formal), path_lean)
    t2 = time.time()

    model, encodings = {}, []
    for line in open(path_results):
        parts = line.rstrip('\n').split(' ')
        if parts[0] == 'enc':
            encodings.append((parts[1], bytes.fromhex(parts[2])))
        else:
            model[int(parts[0])] = line.rstrip('\n')

    problems = []
    per_form = {}
    representative = 0
    for c in cases:
        fm = c['form']
        line = model[c['id']]
        head, _, shown = line.partition(' | ')
        p = head.split(' ')
        bad = []
        if fm['kind'] == 'fault':
            sig = native_results[c['id']][1]
            if p[1] != 'none':
                bad.append(f'model decodes a fault instruction: {shown}')
            if sig != signal.SIGILL:
                bad.append(f'CPU: expected SIGILL, got signal {sig}')
        elif fm['kind'] == 'undecoded':
            if p[1] != 'none':
                bad.append(f'model decodes an instruction it lacks: {shown}')
        elif p[1] != 'some':
            bad.append('model does not decode the bytes')
        else:
            size, prefixes, tailed, division = int(p[2]), p[3], p[4], p[5]
            m_regs = [int(x, 16) for x in p[6:22]]
            m_rip, m_flags, m_mem = int(p[22], 16), int(p[23], 16), bytes.fromhex(p[24])
            n_regs, n_flags, n_rip, n_mem, rest_ok = native_results[c['id']]
            if size != len(c['bytes']):
                bad.append(f'decoded size {size}, instruction is {len(c["bytes"])} bytes')
            if prefixes != 'true':
                bad.append('a shorter prefix decodes')
            if tailed != 'true':
                bad.append('trailing bytes change the decoding')
            if division != ('true' if fm['kind'] == 'div' else 'false'):
                bad.append('decoded as a division' if division == 'true' else 'not decoded as a division')
            for r in range(16):
                if m_regs[r] != n_regs[r]:
                    bad.append(f'{REG_NAMES[r]}: model {m_regs[r]:#x} CPU {n_regs[r]:#x}')
            if m_rip != n_rip:
                bad.append(f'rip: model {m_rip:#x} CPU {n_rip:#x}')
            if (m_flags ^ n_flags) & fm['mask']:
                bad.append(f'flags (mask {fm["mask"]:#x}): model {m_flags:#x} CPU {n_flags:#x}')
            elif (m_flags ^ n_flags) & ALL_DEFINED:
                representative += 1                     # execute's choice of a free flag differs
            if m_mem != n_mem:
                diffs = [i for i in range(REGION) if m_mem[i] != n_mem[i]]
                bad.append('memory at region+' + ','.join(f'{i:#x}' for i in diffs[:16]) +
                           ': model ' + ' '.join(f'{m_mem[i]:02x}' for i in diffs[:16]) +
                           ' CPU ' + ' '.join(f'{n_mem[i]:02x}' for i in diffs[:16]))
            if not rest_ok:
                bad.append('CPU wrote outside the compared region')
        stats = per_form.setdefault(fm['name'], [0, 0, shown])
        stats[0] += 1
        if bad:
            stats[1] += 1
            problems.append((c, bad, shown))

    # coverage: every emitted byte sequence splits into tested forms
    uncovered = []
    used = set()
    for name, data in encodings:
        names, at = split_forms(data, compiler_forms())
        used.update(names)
        if at is not None:
            uncovered.append(f'{name}: unknown form at byte {at}: {data[at:at + 8].hex(" ")}')

    print(f'{len(forms)} forms, {len(cases)} cases ({t1 - t0:.1f} s native, {t2 - t1:.1f} s Lean)')
    for name, (n, failed, shown) in per_form.items():
        print(f'  {"FAIL" if failed else "ok  "} {n:5d}  {name:32s} {shown[:70]}')
    print(f'coverage: {len(encodings)} emitted encodings split into {len(used)} forms; '
          f'{len(uncovered)} uncovered')
    unused = [fm['name'] for fm in compiler_forms() if fm['name'] not in used]
    if unused:
        print('  forms in the table that no encoding used:', ', '.join(unused))
    for u in uncovered:
        print('  ' + u)
    shown_problems = {}
    for c, bad, shown in problems:
        k = c['form']['name']
        shown_problems[k] = shown_problems.get(k, 0) + 1
        if shown_problems[k] <= 3:
            print(f'DISAGREEMENT {k} (case {c["id"]}): model {shown}')
            print(describe(c))
            for b in bad:
                print('  ' + b)
    print(f'{representative} cases where the CPU picked a different value than execute for a flag '
          f'the Step relation leaves free (AF after AND/OR/XOR/TEST, all flags after IMUL/NEG/DIV)')
    print(f'{len(problems)} disagreeing cases')
    sys.exit(1 if problems or uncovered else 0)


if __name__ == '__main__':
    main()
