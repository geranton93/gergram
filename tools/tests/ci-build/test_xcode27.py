import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/xcode27.sh"
MTPROTO_PROJECT = "core-xprojects/mtproto-engine/MTProtoEngine.xcodeproj/project.pbxproj"
SPARKLE_PROJECT = "submodules/Sparkle/Sparkle.xcodeproj/project.pbxproj"
PROJECT = "Telegram.xcodeproj/project.pbxproj"
SETTINGS = """\t\tAAAAAAAAAAAAAAAAAAAAAAAA /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 10.13;
\t\t\t};
\t\t};
"""


class Xcode27PreparationTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="gergram-xcode27-")
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.script = self.root / "scripts/xcode27.sh"
        self.script.parent.mkdir()
        shutil.copyfile(SCRIPT, self.script)
        source = SCRIPT.read_text()
        projects = re.search(r"^PROJECTS=\((.*?)\)", source, re.M | re.S).group(1).split()
        shader_paths = re.search(r"^SHADER_MANIFESTS=\((.*?)\)", source, re.M | re.S).group(1).split()
        core_path = re.search(r"^TELEGRAM_CORE_MANIFEST=(.+)$", source, re.M).group(1)
        self.inputs = projects + shader_paths + [core_path]
        for project in projects:
            self.write(project, SETTINGS)
        for shader in shader_paths:
            self.write(shader, 'target(path: "Sources", resources: [.copy("Shader.metal")])\n')
        self.write(core_path, 'target(swiftSettings: [.unsafeFlags(["-warnings-as-errors"])])\n')
        self.xcodebuild = self.write("bin/xcodebuild", "#!/bin/sh\nexit 0\n")
        self.xcodebuild.chmod(0o755)
        self.environment = dict(os.environ, PATH=f"{self.xcodebuild.parent}:{os.environ['PATH']}")
        self.git("init", "-q")
        self.git("add", ".")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "Fixture")

    def write(self, relative, contents):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)
        return path

    def git(self, *args):
        subprocess.run(["git", "-C", self.root, *args], check=True, capture_output=True, text=True)

    def run_prepare(self, action):
        return subprocess.run(["/bin/bash", self.script, action], env=self.environment, capture_output=True, text=True)

    def snapshot(self):
        return {path: (self.root / path).read_bytes() for path in self.inputs if (self.root / path).exists()}

    def test_missing_submodule_leaves_every_other_input_untouched(self):
        (self.root / SPARKLE_PROJECT).unlink()
        before = self.snapshot()
        result = self.run_prepare("apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(SPARKLE_PROJECT, result.stderr)
        self.assertEqual(self.snapshot(), before)

    def test_unsupported_project_layout_leaves_every_input_untouched(self):
        self.write(MTPROTO_PROJECT, SETTINGS.replace("= XCBuildConfiguration;", "= PBXProject;"))
        before = self.snapshot()
        result = self.run_prepare("apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(MTPROTO_PROJECT, result.stderr)
        self.assertEqual(self.snapshot(), before)

    def test_quoted_value_round_trips(self):
        self.write(MTPROTO_PROJECT, SETTINGS.replace("10.13;", '"10.13";'))
        self.git("add", MTPROTO_PROJECT)
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "Quoted baseline")
        before = self.snapshot()
        result = self.run_prepare("apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(b'MACOSX_DEPLOYMENT_TARGET = "12.0";', self.snapshot()[MTPROTO_PROJECT])
        result = self.run_prepare("revert")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.snapshot(), before)

    def test_local_deployment_changes_are_preserved(self):
        for edit in (SETTINGS.replace("10.13;", "11.0;"), SETTINGS + SETTINGS.replace("A" * 24, "B" * 24, 1)):
            with self.subTest(edit=edit):
                self.write(MTPROTO_PROJECT, edit)
                before = self.snapshot()
                result = self.run_prepare("apply")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("local deployment target differs from HEAD", result.stderr)
                self.assertEqual(self.snapshot(), before)

    def test_complete_prepare_is_idempotent_and_revert_keeps_unrelated_edits(self):
        self.write(PROJECT, SETTINGS + "// My local edit\n")
        original = self.snapshot()
        result = self.run_prepare("apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(b"MACOSX_DEPLOYMENT_TARGET = 12.0;", self.snapshot()[MTPROTO_PROJECT])
        applied = self.snapshot()
        self.assertEqual(self.run_prepare("apply").returncode, 0)
        self.assertEqual(self.snapshot(), applied)
        result = self.run_prepare("revert")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.snapshot(), original)

    def test_metal_query_failure_is_advisory(self):
        self.xcodebuild.write_text("#!/bin/sh\nexit 70\n")
        result = self.run_prepare("apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Could not verify the Metal toolchain", result.stderr)
        self.assertIn("xcodebuild -downloadComponent MetalToolchain", result.stderr)

    def test_revert_recovers_an_earlier_partial_apply(self):
        self.write(PROJECT, SETTINGS.replace("10.13;", "12.0;") + "// Keep this change\n")
        (self.root / SPARKLE_PROJECT).unlink()
        result = self.run_prepare("revert")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(SPARKLE_PROJECT, result.stderr)
        self.assertEqual((self.root / PROJECT).read_text(), SETTINGS + "// Keep this change\n")


if __name__ == "__main__":
    unittest.main()
