import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("audit_port", Path(__file__).parents[1] / "audit_port.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AuditPortTests(unittest.TestCase):
    def test_classifies_real_git_tree_changes_including_spaces_and_deletions(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            def git(*args):
                return subprocess.check_output(["git", "-C", str(repo), *args], stderr=subprocess.DEVNULL).decode().strip()
            def write(name, value):
                (repo / name).write_text(value)
            def commit(message):
                git("add", "-A")
                git("commit", "-m", message)
                return git("rev-parse", "HEAD")
            git("init", "--initial-branch=main")
            git("config", "user.name", "Fixture")
            git("config", "user.email", "fixture@example.invalid")
            for name in ("unchanged.txt", "changed.txt", "removed.txt", "applied.txt", "delete.txt", "with spaces.txt"):
                write(name, "original")
            original = commit("base")
            for name in ("unchanged.txt", "changed.txt", "removed.txt", "applied.txt", "with spaces.txt"):
                write(name, "legacy")
            write("added.txt", "legacy addition")
            (repo / "delete.txt").unlink()
            legacy = commit("legacy")
            git("checkout", "--detach", original)
            write("changed.txt", "modern")
            write("applied.txt", "legacy")
            (repo / "removed.txt").unlink()
            target = commit("modern")
            report = module.audit(repo, {"legacy_base": {"revision": original}, "legacy_port": {"revision": legacy}, "target": {"revision": target}})
            actual = {item["path"]: item["disposition"] for item in report["files"]}
            self.assertEqual(actual, {"unchanged.txt": "upstream_unchanged", "changed.txt": "upstream_changed", "removed.txt": "upstream_removed", "applied.txt": "already_in_target", "delete.txt": "upstream_unchanged", "with spaces.txt": "upstream_unchanged", "added.txt": "legacy_addition"})
            self.assertEqual(report["total_files"], 7)

    def test_rejects_moving_branch_names_in_revision_lock(self):
        with self.assertRaisesRegex(ValueError, "full SHA-1"):
            module.audit(Path("."), {"legacy_base": {"revision": "main"}})


if __name__ == "__main__":
    unittest.main()
