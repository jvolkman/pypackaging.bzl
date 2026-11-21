"""Tests that the Starlark code does not get slower without us noticing."""

import unittest

import starlark_shim
from workloads import workloads

# The number of steps that each workload takes, see the README.md. Update the
# numbers with the output of `bazel run //:benchmark`.
_STEPS = {
    # keep sorted
    "evaluate_long": 2018,
    "evaluate_long_parsed": 659,
    "evaluate_partial": 306,
    "evaluate_string": 121,
    "evaluate_two_strings": 250,
    "evaluate_version": 211,
    "evaluate_version_parsed": 120,
    "parse_long": 1360,
    "requirement_parse": 381,
    "specifier_set_contains": 66,
    "specifier_set_parse": 146,
    "tags_get_supported": 1227,
    "version_is_compatible": 29,
    "version_is_eq_prefix": 24,
    "version_is_ge": 21,
    "version_is_lt": 24,
    "version_normalize": 46,
    "version_parse_all_segments": 201,
    "version_parse_invalid": 20,
    "version_parse_pre_release": 96,
    "version_parse_release": 30,
    "wheel_filename_parse": 190,
}

# The number of the steps slightly depends on the Python version.
_TOLERANCE = 0.05


class StepsTest(unittest.TestCase):
    def test_all_workloads_are_measured(self):
        self.assertEqual(sorted(_STEPS), sorted(workloads()))

    def test_steps(self):
        for name, fn in workloads().items():
            with self.subTest(name):
                want = _STEPS[name]
                self.assertAlmostEqual(
                    starlark_shim.count_steps(fn),
                    want,
                    delta=want * _TOLERANCE,
                    msg="The number of steps has changed, see perf/README.md",
                )


if __name__ == "__main__":
    unittest.main()
