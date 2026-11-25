import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "release.sh"


class ReleaseTests(unittest.TestCase):
    def run_release(self, failure, upload=True):
        with tempfile.TemporaryDirectory(prefix="pihole-release-test-") as directory:
            root = Path(directory)
            test_build = root / "build/local-test/keep.txt"
            test_build.parent.mkdir(parents=True)
            test_build.write_text("running test build")
            (root / "PiHoleControls.xcodeproj").mkdir()
            (root / "PiHoleControls.xcodeproj/project.pbxproj").touch()
            binary = root / "bin"
            binary.mkdir()
            app = root / "fixture/PiHoleControls.app/Contents"
            (app / "MacOS").mkdir(parents=True)
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "PiHoleControls"}))
            executable = app / "MacOS/PiHoleControls"
            executable.write_text("#!/bin/sh\nexit 0\n")
            executable.chmod(0o755)
            (root / "fixture/ArchiveInfo.plist").write_bytes(plistlib.dumps({
                "ApplicationProperties": {"ApplicationPath": "Applications/PiHoleControls.app"}
            }))
            stubs = {
                "xcodebuild": '''#!/bin/bash
case " $* " in
  *" -showBuildSettings "*)
    [ "$FAILURE" = version ] && exit 65
    echo '    MARKETING_VERSION = 0.7'; exit 0 ;;
  *" -exportArchive "*)
    touch export-attempted
    [ "$FAILURE" = export ] && exit 70
    cp -R fixture/PiHoleControls.app build/release/
    [ "$FAILURE" = empty ] && rm build/release/PiHoleControls.app/Contents/MacOS/PiHoleControls
    exit 0 ;;
  *" archive "*)
    [[ " $* " = *" SKIP_INSTALL=NO "* ]] && exit 66
    mkdir -p build/PiHoleControls.xcarchive/Products/Applications
    cp -R fixture/PiHoleControls.app build/PiHoleControls.xcarchive/Products/Applications/
    cp fixture/ArchiveInfo.plist build/PiHoleControls.xcarchive/Info.plist
    [ "$FAILURE" = generic ] && cp fixture/PiHoleControls.app/Contents/Info.plist build/PiHoleControls.xcarchive/Info.plist
    [ "$FAILURE" = archive ] && exit 65
    exit 0 ;;
esac
exit 1
''',
                "codesign": '#!/bin/sh\ntouch signature-checked\n[ "$FAILURE" != signature ]\n',
                "git": '''#!/bin/sh
case "$1" in
  status) [ "$FAILURE" = dirty ] && echo ' M source.swift'; exit 0 ;;
  rev-parse)
    if [ "$FAILURE" = tag ] && [ "$2" = --verify ]; then echo other; else echo head; fi
    exit 0 ;;
esac
exit 1
''',
                "gh": '''#!/bin/sh
touch github-called
printf '%s\\n' "$*" >> github-args
[ "$FAILURE" = publish ]
''',
            }
            for name, source in stubs.items():
                path = binary / name
                path.write_text(source)
                path.chmod(0o755)
            environment = dict(os.environ, PATH=f"{binary}:{os.environ['PATH']}", FAILURE=failure)
            result = subprocess.run(["bash", str(SCRIPT)] + (["--upload"] if upload else []), cwd=root, env=environment,
                                    capture_output=True, text=True, timeout=30)
            self.assertTrue(test_build.exists(), "Release must not delete other build products")
            if failure == "publish":
                self.assertIn("release create v0.7 build/release/PiHoleControls.zip --verify-tag", (root / "github-args").read_text())
            return (result, (root / "build/release/PiHoleControls.zip").exists(),
                    (root / "export-attempted").exists(), (root / "signature-checked").exists(),
                    (root / "github-called").exists())

    def test_archive_failure_cannot_export_or_package(self):
        result, zipped, exported, _, github = self.run_release("archive")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(zipped or exported or github)

    def test_export_failure_cannot_copy_archive_fallback(self):
        result, zipped, _, _, github = self.run_release("export")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(zipped or github)

    def test_generic_archive_cannot_export_or_package(self):
        result, zipped, exported, _, github = self.run_release("generic")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(zipped or exported or github)

    def test_missing_executable_cannot_package(self):
        result, zipped, _, _, _ = self.run_release("empty")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(zipped)

    def test_invalid_signature_cannot_package(self):
        result, zipped, _, checked, _ = self.run_release("signature")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertTrue(checked)
        self.assertFalse(zipped)

    def test_missing_version_is_fatal(self):
        result, zipped, _, _, _ = self.run_release("version")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertFalse(zipped)

    def test_success_validates_and_packages_without_publishing(self):
        result, zipped, exported, checked, github = self.run_release("none", upload=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(zipped and exported and checked)
        self.assertFalse(github)

    def test_dirty_tree_cannot_publish(self):
        result, zipped, exported, _, github = self.run_release("dirty")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(zipped or exported or github)

    def test_wrong_tag_cannot_publish(self):
        result, zipped, exported, _, github = self.run_release("tag")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(zipped or exported or github)

    def test_upload_requires_existing_remote_tag(self):
        result, zipped, exported, checked, github = self.run_release("publish")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(zipped and exported and checked and github)


if __name__ == "__main__":
    unittest.main()
