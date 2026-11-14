"""Exercise the interactive build menu with a fake Flutter executable."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


PROJECT = Path(__file__).resolve().parents[1]


def device(identifier, *, emulator=False, platform="ios", supported=True):
    return dict(id=identifier, name=identifier, emulator=emulator,
                targetPlatform=platform, isSupported=supported)


class IosReleaseMenuTest(unittest.TestCase):
    def run_menu(self, devices, menu_input="8\nq\n", fail=""):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "pubspec.yaml").write_text("version: 1.0.0+1\n")
            (root / "ios").mkdir()
            (root / "ios/Podfile").touch()
            native_assets = root / "build/native_assets"
            (native_assets / "ios").mkdir(parents=True)
            (native_assets / "macos").mkdir()
            build_cache = root / ".dart_tool/flutter_build/previous-build"
            build_cache.mkdir(parents=True)
            (build_cache / "install_code_assets.stamp").touch()
            log = root / "calls.jsonl"
            flutter = root / "flutter"
            flutter.write_text(f"#!{sys.executable}\n" + '''
import json, os, sys
args = sys.argv[1:]
with open(os.environ["CALL_LOG"], "a") as log:
    log.write(json.dumps(args) + "\\n")
if args[0] == os.environ.get("FAIL_COMMAND"):
    sys.exit(1)
if args == ["devices", "--machine"]:
    print(os.environ["FAKE_DEVICES"])
if args[:2] == ["build", "ios"]:
    from pathlib import Path
    assert not Path("build/native_assets/ios").exists()
    assert Path("build/native_assets/macos").is_dir()
    assert not list(Path(".dart_tool/flutter_build").glob("*/install_code_assets.stamp"))
''')
            flutter.chmod(0o755)
            pod = root / "pod"
            pod.write_text("#!/bin/sh\nexit 0\n")
            pod.chmod(0o755)
            result = subprocess.run(
                ["bash", str(PROJECT / "build_app.sh")], cwd=root,
                input=menu_input, text=True, capture_output=True, timeout=10,
                env={**os.environ, "PATH": f"{root}:{os.environ['PATH']}",
                     "CALL_LOG": str(log), "FAKE_DEVICES": json.dumps(devices),
                     "FAIL_COMMAND": fail},
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            return [json.loads(line) for line in log.read_text().splitlines()], result.stdout

    def test_only_simulator_stops_before_build(self):
        calls, output = self.run_menu([device("simulator", emulator=True)])
        self.assertEqual(calls, [["devices", "--machine"]])
        self.assertIn("找不到可用的 iOS 實機", output)

    def test_one_physical_device_is_explicitly_selected(self):
        calls, _ = self.run_menu([
            device("simulator", emulator=True), device("iphone"),
            device("macos", platform="darwin"), device("unsupported", supported=False),
        ])
        self.assertEqual(calls[1], ["build", "ios", "--release",
                                    "--dart-define=ENABLE_IOS_CLOUD_SYNC=false"])
        self.assertEqual(calls[2], ["run", "-d", "iphone", "--release",
                                    "--use-application-binary=build/ios/iphoneos/YunxuLearn.app"])

    def test_multiple_physical_devices_use_selected_id(self):
        calls, _ = self.run_menu([device("first"), device("second")], "8\n2\nq\n")
        self.assertEqual(calls[-1][1:3], ["-d", "second"])

    def test_invalid_selection_stops_before_build(self):
        for selection in ["0", "3", "abc", "01", "999999999999999999999999"]:
            with self.subTest(selection=selection):
                calls, _ = self.run_menu([device("a"), device("b")],
                                         f"8\n{selection}\nq\n")
                self.assertEqual(calls, [["devices", "--machine"]])

    def test_failed_build_does_not_run(self):
        calls, _ = self.run_menu([device("iphone")], fail="build")
        self.assertEqual([call[0] for call in calls], ["devices", "build"])

    def test_discovery_failure_stops_before_build(self):
        calls, _ = self.run_menu([], fail="devices")
        self.assertEqual(calls, [["devices", "--machine"]])

    def test_clean_option_checks_device_before_cleaning(self):
        calls, _ = self.run_menu([], "17\nq\n")
        self.assertEqual(calls, [["devices", "--machine"]])

    def test_clean_option_preserves_selected_device(self):
        calls, _ = self.run_menu([device("iphone")], "17\nq\n")
        self.assertEqual([call[0] for call in calls],
                         ["devices", "clean", "pub", "build", "run"])
        self.assertEqual(calls[-1][1:3], ["-d", "iphone"])


if __name__ == "__main__":
    unittest.main()
