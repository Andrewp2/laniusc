#!/usr/bin/env python3
"""CPU authority mutations; no compiler, assembler, linker or native run."""
import copy
import struct
from pathlib import Path
import unittest
from unittest.mock import patch

import source_allocations as SOURCE


class SourceAllocationAuthority(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.runtime = SOURCE.runtime_bytes()
        cls.crt = SOURCE.crt_bytes()

    def image(self, flags=0x22, both=False):
        base, image = 0x401000, bytearray()
        functions, symbols, runtime_starts, crt_starts = [], [], [], []
        tails = SOURCE.RUNTIME.RUNTIME.replace(bytes.fromhex("41ba62000000"), bytes.fromhex("41ba22000000"))
        for unit, selected in enumerate((flags, 0x22) if both else (flags,)):
            raw = base + len(image)
            entry = raw + 17 if unit == 0 else raw + 16
            wrapper = bytearray.fromhex("4989e7e80000000089c7b83c0000000f05")
            struct.pack_into("<i", wrapper, 4, entry - (raw + 8))
            image.extend(wrapper)
            functions.append((f"__lanius_0_{unit}_0", raw + 17, 16))
            symbols.append(functions[-1])
            image.extend(b"\x90" * 16)
            runtime = self.runtime
            if selected == 0x62:
                at = runtime.index(tails)
                runtime = runtime[:at] + SOURCE.RUNTIME.RUNTIME + runtime[at + len(tails):]
            runtime_starts.append(base + len(image))
            image.extend(runtime)
            crt_start = base + len(image)
            crt_starts.append(crt_start)
            crt = bytearray(self.crt)
            struct.pack_into("<i", crt, 182, entry - (crt_start + 186))
            image.extend(crt)
            if unit == 0:
                functions.append(("main", crt_start, len(crt)))
                symbols.append(functions[-1])
            image.extend(b"\x90" * 16)
        image.extend(b"\x90" * 32)
        instructions = {base + at: ("nop", []) for at in range(len(image))}
        ends = {point: point + 1 for point in instructions}
        # Model a complete decoder map; production obtains real extents from
        # objdump. Both raw and CRT displacement fields are single instructions.
        for at in range(len(image) - 1):
            if image[at:at + 2] == b"\x0f\x05":
                instructions[base + at] = ("syscall", [])
                ends[base + at] = base + at + 2
                del instructions[base + at + 1], ends[base + at + 1]
        for crt_start in crt_starts:
            call = crt_start + 181
            ends[call] = call + 5
            for point in range(call + 1, call + 5):
                instructions.pop(point, None)
                ends.pop(point, None)
        for unit in range(2 if both else 1):
            raw = runtime_starts[unit] - 33
            call = raw + 3
            ends[call] = call + 5
            for point in range(call + 1, call + 5):
                instructions.pop(point, None)
                ends.pop(point, None)
        return dict(image=bytes(image), loads=[(1, 5, 0, base, base, len(image), len(image), 4096)],
                    functions=functions, symbols=symbols,
                    instructions=instructions, instruction_ends=ends,
                    runtime_instructions=instructions, runtime_instruction_ends=ends, branches=0,
                    runtime_starts=runtime_starts, crt_starts=crt_starts)

    def profile(self, inspected):
        return SOURCE._profile(inspected, self.runtime)

    def test_each_exact_profile_full_width_and_mixed_keep_per_site_flags(self):
        for flags in (0x22, 0x62):
            with self.subTest(flags=flags):
                inspected = self.image(flags)
                pairs, named = self.profile(inspected)
                self.assertFalse(named)
                self.assertEqual(len(pairs), 1)
                self.assertEqual(pairs.mmap_flags, {pairs[0][0]: flags})
                self.assertIn((inspected["runtime_starts"][0], inspected["runtime_starts"][0] + len(self.runtime)), pairs.executable_ranges)
                self.assertIn((0x401011, 0x401021), pairs.executable_ranges)
                self.assertNotIn((0x401000, 0x401000 + len(inspected["image"])), pairs.executable_ranges)
                self.assertFalse(any(low <= inspected["crt_starts"][0] < high for low, high in pairs.executable_ranges))
                self.assertEqual(len(pairs.bootstrap_sites), 3)
        pairs, _ = self.profile(self.image(flags=0x62, both=True))
        self.assertEqual(set(pairs.mmap_flags.values()), {0x22, 0x62})
        self.assertEqual(len(pairs), 2)

    def test_each_runtime_byte_mutation_rejects_including_nonallocation_thunks(self):
        baseline = self.image()
        for position in range(len(self.runtime)):
            with self.subTest(position=position):
                inspected = dict(baseline)
                changed = bytearray(inspected["image"])
                changed[baseline["runtime_starts"][0] - 0x401000 + position] ^= 1
                inspected["image"] = bytes(changed)
                with self.assertRaisesRegex(ValueError, "no exact supported"):
                    self.profile(inspected)

    def test_start_interior_continuity_extent_and_syscall_boundaries(self):
        runtime_start = self.image()["runtime_starts"][0]
        baseline = self.image()
        pair, _ = self.profile(baseline)
        cases = [
            lambda item: item["instructions"].pop(runtime_start),
            lambda item: item["instructions"].pop(runtime_start + 1),
            lambda item: item["instruction_ends"].update({runtime_start: runtime_start + len(self.runtime) + 1}),
            lambda item: item["instruction_ends"].update({runtime_start: runtime_start}),
            lambda item: item["instructions"].update({pair[0][0] - 2: ("nop", [])}),
            lambda item: item["instructions"].update({pair[0][1] - 2: ("nop", [])}),
            lambda item: item["instructions"].update({pair[0][0] - 1: ("nop", [])}),
        ]
        for change in cases:
            with self.subTest(change=change):
                inspected = copy.deepcopy(baseline)
                change(inspected)
                with self.assertRaises(ValueError):
                    self.profile(inspected)

    def test_literal_pattern_inside_crt_or_source_symbol_is_not_a_runtime(self):
        for name in ("main", "_start", "__lanius_3_4_5"):
            with self.subTest(name=name):
                inspected = self.image()
                inspected["symbols"] = [*inspected["symbols"], (name, inspected["runtime_starts"][0], len(self.runtime))]
                with self.assertRaisesRegex(ValueError, "overlaps"):
                    self.profile(inspected)

    def test_nonexec_truncated_bad_ranges_missing_source_and_tail_only_reject(self):
        changes = [
            lambda item: item.update(loads=[(1, 4, 0, 0x401000, 0x401000, len(item["image"]), len(item["image"]), 4096)]),
            lambda item: item.update(loads=[(1, 7, 0, 0x401000, 0x401000, len(item["image"]), len(item["image"]), 4096)]),
            lambda item: item.update(image=item["image"][:30]),
            lambda item: item.update(functions=[("main", 0x401000, 1)]),
            lambda item: item.update(functions=[("__lanius_0_0_0", 0x401000, 0)]),
            lambda item: item.update(functions=[("__lanius_0_0_0", 0x400000, 1)]),
            lambda item: item["instructions"].pop(0x401011),
        ]
        for change in changes:
            with self.subTest(change=change):
                inspected = self.image()
                change(inspected)
                with self.assertRaises(ValueError):
                    self.profile(inspected)
        inspected = self.image()
        inspected["image"] = inspected["image"].replace(self.runtime[:4], b"\x90" * 4)
        with self.assertRaisesRegex(ValueError, "no exact supported"):
            self.profile(inspected)

    def test_unchanged_live_ledger_rejects_unknown_source_mmap_and_free(self):
        ledger = SOURCE.load("native_source_control_live_ledger", SOURCE.HERE.parent / "extended/archive_source/ledger.py")
        pairs, named = self.profile(self.image())
        profile = pairs, named
        pointer, amount = 0x7fff10000000, 37
        def line(ip, operation):
            return f"[{ip:016x}] {operation}\n"
        allocate = line(pairs[0][0], f"mmap(NULL, {amount}, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = {pointer:#x}")
        release = line(pairs[0][1], f"munmap({pointer:#x}, {amount}) = 0")
        self.assertEqual(ledger.source(allocate, profile)["live"], {pointer: amount})
        self.assertFalse(ledger.source(allocate + release, profile)["live"])
        with self.assertRaises(AssertionError):
            ledger.source(allocate.replace(f"{pairs[0][0]:016x}", "0000000000401011"), profile)
        with self.assertRaises(AssertionError):
            ledger.source(allocate + release.replace(f"{pairs[0][1]:016x}", "0000000000401011"), profile)
        bootstrap_ip = next(ip for ip, kind in pairs.bootstrap_sites.items() if kind == "bootstrap-mmap")
        bootstrap = line(bootstrap_ip, "mmap(NULL, 8388608, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff20000000")
        self.assertEqual(SOURCE.classify(profile, bootstrap_ip), "bootstrap-mmap")
        self.assertEqual(SOURCE.classify(profile, pairs[0][0]), "source")
        self.assertEqual(SOURCE.classify(profile, 0x7fff00000000), "native")
        with self.assertRaisesRegex(ValueError, "unverified executable-image"):
            SOURCE.classify(profile, 0x401001)
        self.assertEqual(ledger.source(bootstrap + allocate, profile)["peak"], amount)

    def test_global_partition_rejects_unknown_unsized_or_disguised_bootstrap_sites(self):
        baseline = self.image(both=True)
        unknown = 0x401000 + len(baseline["image"]) - 2
        item = copy.deepcopy(baseline)
        image = bytearray(item["image"])
        image[-2:] = b"\x0f\x05"
        item["image"] = bytes(image)
        item["runtime_instructions"][unknown] = ("syscall", [])
        item["runtime_instruction_ends"][unknown] = unknown + 2
        item["runtime_instructions"].pop(unknown + 1, None)
        with self.assertRaisesRegex(ValueError, "unknown unsized"):
            self.profile(item)
        for position in (0, 129, 199):
            with self.subTest(bridge_byte=position):
                item = copy.deepcopy(baseline)
                image = bytearray(item["image"])
                image[item["crt_starts"][0] - 0x401000 + position] ^= 1
                item["image"] = bytes(image)
                with self.assertRaises(ValueError):
                    self.profile(item)
        # A dormant bridge must target exactly its paired raw+16 sentinel,
        # not an arbitrary instruction inside a sized source function.
        item = copy.deepcopy(baseline)
        image = bytearray(item["image"])
        raw = item["runtime_starts"][1] - 33
        destination = raw + 18
        struct.pack_into("<i", image, raw - 0x401000 + 4, destination - raw - 8)
        crt = item["crt_starts"][1]
        struct.pack_into("<i", image, crt - 0x401000 + 182, destination - crt - 186)
        item["image"] = bytes(image)
        with self.assertRaisesRegex(ValueError, "dormant"):
            self.profile(item)

    def test_raw_wrapper_native_overlap_and_image_end_postips_reject(self):
        inspected = self.image()
        inspected["symbols"] = [*inspected["symbols"], ("_start", 0x401000, 17)]
        with self.assertRaisesRegex(ValueError, "raw entry overlaps"):
            self.profile(inspected)
        profile = self.profile(self.image())
        end = profile[0].image_ranges[-1][1]
        for post_ip in (end, end + 1):
            with self.subTest(post_ip=post_ip), self.assertRaisesRegex(ValueError, "unverified executable-image"):
                SOURCE.classify(profile, post_ip)
        self.assertEqual(SOURCE.classify(profile, end + 2), "native")

    def test_public_entry_requires_validator_admission_and_legacy_result_is_same(self):
        with patch.object(SOURCE.ELF, "inspect", side_effect=ValueError("rejected ELF")):
            with self.assertRaisesRegex(ValueError, "rejected ELF"):
                SOURCE.verified_sites("invalid")
        with patch.object(SOURCE.ELF, "inspect", return_value=self.image()) as inspect:
            pairs, named = SOURCE.verified_sites("not-executed")
            self.assertEqual(len(pairs), 1)
            self.assertEqual(named, [])
            inspect.assert_called_once()
        with patch.object(SOURCE.ELF, "inspect", return_value=dict(functions=[1, 2], branches=7)):
            self.assertEqual(SOURCE.ELF.validate("unused"), (2, 7))


if __name__ == "__main__":
    unittest.main()
