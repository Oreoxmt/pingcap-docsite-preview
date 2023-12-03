import os
import shlex
import shutil
import subprocess
import time

from typing import Dict, List


class DocSitePreviewTest:

    def __init__(self, test_dir: str, feature_dir: str, script_name: str, test_dependencies: List[str] = None):
        self.test_dir = test_dir
        self.feature_dir = feature_dir
        self.script_name = script_name

        self.test_output = os.path.join(self.test_dir, "actual")
        self.test_script = os.path.join(self.test_output, self.script_name)

        self._setup_test_env()
        if test_dependencies:
            self._load_dependencies(test_dependencies)

    def _setup_test_env(self) -> None:
        """
        Generate the test environment for execution.
        1. Clean up the test environment.
        2. Copy the target script to the test environment.
        """
        self._clean()
        self._copy_setup_script()

    def _clean(self) -> None:
        """
        Clean up the test environment.
        """
        if os.path.exists(self.test_output):
            shutil.rmtree(self.test_output)
        os.makedirs(self.test_output, exist_ok=True)

    def _copy_setup_script(self) -> None:
        """
        Copy the script to the test environment.
        """
        shutil.copy(os.path.join(self.feature_dir, self.script_name), self.test_script)
        self._make_executable(self.test_script)

    def _load_dependencies(self, dependencies: List[str]) -> None:
        """
        Copy the dependencies to the test environment.
        """
        for dependency in dependencies:
            dependency_script = os.path.join(self.feature_dir, dependency)
            test_dependency_script = os.path.join(self.test_output, dependency)
            shutil.copy(dependency_script, test_dependency_script)
            self._make_executable(test_dependency_script)

    @staticmethod
    def _make_executable(script: str) -> None:
        """
        Make the script executable (chmod +x).
        """
        os.chmod(script, 0o755)

    def execute(self, args: str = "", env: Dict[str, str] | None = None) -> bool:
        """
        Execute the feature command.
        """
        command = f"{self.test_script} {args}"
        return self._execute_command(shlex.split(command), self.test_output, "execute", env)

    @staticmethod
    def _execute_command(command: List[str], cwd: str, task: str, env: Dict[str, str] | None = None) -> bool:
        """
        Execute a command and log the output to *.log.
        Returns:
            bool: True if the command is executed successfully, False otherwise.
        """
        log_path = os.path.join(cwd, f"{task}_{int(time.time())}.log")
        with open(log_path, "w") as f:
            result = subprocess.run(command, stdout=f, stderr=f, text=True, cwd=cwd, env=env)
            if result.returncode != 0:
                print(f"🐛 Error detected! Log available at: {log_path}")
                return False
            return True

    def verify(self, command: str = "diff -r data actual") -> bool:
        """
        Use diff command to compare the expected output (data) and the actual output.
        """
        return self._execute_command(shlex.split(command), self.test_dir, "verify")
