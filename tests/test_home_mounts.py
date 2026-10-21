"""Exercise launcher state setup without building images or running Docker."""

import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
STATE_DIRS = (
    ".claude",
    ".codex",
    ".local/state/claude",
    ".cache",
    ".cursor",
    ".cursor-server",
)
STATE_FILES = {".claude.json": "{}\n", ".bash_history": ""}


class HomeMountTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="docker-home-mounts-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.host_home = self.root / "home"
        self.host_home.mkdir()
        self.workspace = self.root / "workspace"
        self.workspace.mkdir()
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        docker = bin_dir / "docker"
        docker.write_text(
            "#!/usr/bin/env python3\n"
            "import json, sys\n"
            "print(json.dumps(sys.argv[1:]))\n"
        )
        docker.chmod(0o755)
        self.env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith("DOCKER_")
        }
        self.env.update(
            HOME=str(self.host_home),
            PATH=f"{bin_dir}:{os.environ['PATH']}",
            DOCKER_API_VERSION="1.41",
            AMD_ARCH="gfx950",
            DOCKER_ENABLE_AMD_GPU="0",
            DOCKER_ENABLE_HOST_DOCKER="0",
            DOCKER_ENABLE_BWRAP_SANDBOX="0",
            DOCKER_ENABLE_PEANUT_REVIEW_WEB="0",
        )

    def launch(self, launcher="exec_docker.sh", succeeds=True):
        result = subprocess.run(
            ["bash", str(REPO / launcher)],
            cwd=self.workspace,
            env=self.env,
            capture_output=True,
            text=True,
        )
        if not succeeds:
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, "", "Docker was called after setup failed")
            return
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in result.stdout.splitlines()]
        run = next(args for args in calls if args[0] == "run")
        return {run[i + 1] for i, arg in enumerate(run) if arg == "-v"}

    def mount(self, name, readonly=False):
        path = self.host_home / name
        return f"{path}:{path}" + (":ro" if readonly else "")

    def test_both_local_launchers_prepare_private_mounted_state(self):
        for launcher in ("run_docker.sh", "exec_docker.sh"):
            with self.subTest(launcher=launcher):
                self.host_home = self.root / launcher
                self.host_home.mkdir()
                self.env["HOME"] = str(self.host_home)
                mounts = self.launch(launcher)
                self.assertIn(f"{self.workspace}:{self.workspace}", mounts)
                for name in STATE_DIRS:
                    path = self.host_home / name
                    self.assertTrue(path.is_dir())
                    self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o700)
                    self.assertEqual(path.stat().st_uid, os.getuid())
                    self.assertIn(self.mount(name), mounts)
                for name, content in STATE_FILES.items():
                    path = self.host_home / name
                    self.assertEqual(path.read_text(), content)
                    self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
                    self.assertIn(self.mount(name), mounts)
                self.assertIn(self.mount(".local", readonly=True), mounts)
                self.assertEqual(
                    stat.S_IMODE((self.host_home / ".local/state").stat().st_mode),
                    0o700,
                )
                for name in (
                    ".bashrc",
                    ".ssh",
                    ".config",
                    ".gitconfig",
                    ".gnupg",
                    ".bash_aliases",
                    ".bash_profile",
                ):
                    self.assertFalse((self.host_home / name).exists())

    def test_repeated_launch_preserves_existing_data_and_permissions(self):
        self.launch()
        files = []
        for name in STATE_DIRS:
            path = self.host_home / name
            path.chmod(0o750)
            files.append(path / "saved-state")
        files.extend(self.host_home / name for name in STATE_FILES)
        for path in files:
            path.write_text("saved user state\n")
            path.chmod(0o640)
        before = {path: path.stat() for path in files}
        self.launch()
        self.launch()
        for name in STATE_DIRS:
            self.assertEqual(
                stat.S_IMODE((self.host_home / name).stat().st_mode), 0o750
            )
        for path in files:
            self.assertEqual(path.stat(), before[path])
            self.assertEqual(path.read_text(), "saved user state\n")

    def test_existing_optional_configuration_and_nested_state_mount(self):
        for name in (".ssh", ".config", ".gnupg", ".local"):
            (self.host_home / name).mkdir()
        for name in (".bashrc", ".gitconfig", ".bash_aliases", ".bash_profile"):
            (self.host_home / name).write_text("existing configuration\n")
        mounts = self.launch()
        self.assertIn(self.mount(".bashrc"), mounts)
        self.assertEqual(
            (self.host_home / ".bashrc").read_text(), "existing configuration\n"
        )
        for name in (
            ".ssh",
            ".config",
            ".gnupg",
            ".local",
            ".gitconfig",
            ".bash_aliases",
            ".bash_profile",
        ):
            self.assertIn(self.mount(name, readonly=True), mounts)
        self.assertIn(self.mount(".local/state/claude"), mounts)

    def test_conflicting_path_types_stop_before_docker(self):
        for name in (*STATE_DIRS, *STATE_FILES):
            with self.subTest(path=name):
                self.host_home = self.root / name.replace("/", "-")
                self.host_home.mkdir()
                self.env["HOME"] = str(self.host_home)
                path = self.host_home / name
                path.parent.mkdir(parents=True, exist_ok=True)
                if name in STATE_DIRS:
                    path.write_text("keep this file")
                else:
                    path.mkdir()
                self.launch(succeeds=False)
                if name in STATE_DIRS:
                    self.assertEqual(path.read_text(), "keep this file")
                else:
                    self.assertTrue(path.is_dir())

    def test_existing_symlinks_are_preserved(self):
        state_dir = self.root / "saved-codex"
        state_dir.mkdir()
        state_file = self.root / "saved-claude.json"
        state_file.write_text('{"existing": true}\n')
        (self.host_home / ".codex").symlink_to(state_dir)
        (self.host_home / ".claude.json").symlink_to(state_file)
        self.launch()
        self.assertTrue((self.host_home / ".codex").is_symlink())
        self.assertTrue((self.host_home / ".claude.json").is_symlink())
        self.assertEqual(state_file.read_text(), '{"existing": true}\n')

    def test_dangling_state_symlink_is_not_initialized(self):
        target = self.root / "missing"
        (self.host_home / ".claude.json").symlink_to(target)
        self.launch(succeeds=False)
        self.assertFalse(target.exists())
        self.assertTrue((self.host_home / ".claude.json").is_symlink())

    def test_ci_does_not_prepare_or_mount_home_state(self):
        mounts = self.launch("exec_docker_ci.sh")
        self.assertEqual(mounts, {f"{self.workspace}:/workspace"})
        self.assertEqual(list(self.host_home.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
