import os
import shutil
import subprocess


class DocSitePreviewTest:

    def __init__(self, test_dir: str, feature_dir: str, feature_command: str):
        self.feature_dir = feature_dir
        self.feature_command = feature_command
        self.test_dir = test_dir
        self.test_output = os.path.join(self.test_dir, "actual")
        self.test_feature_path = self.test_output + self.feature_command
        self._setup_test_env()

    def _setup_test_env(self):
        """
        Generate the test environment for execution.
        1. Clean up the test environment.
        2. Copy the target script to the test environment.
        """
        self._clean_up()
        self._copy_and_setup_script()

    def _clean_up(self):
        """
        Clean up the test environment.
        """
        if os.path.exists(self.test_output):
            shutil.rmtree(self.test_output)
        os.makedirs(self.test_output, exist_ok=True)

    def _copy_and_setup_script(self):
        """
        Copy the script to the test environment.
        """
        shutil.copy(self.feature_dir + self.feature_command,
                    self.test_feature_path)
        self._make_script_executable(self.test_feature_path)

    @staticmethod
    def _make_script_executable(script: str):
        """
        Make the script executable (chmod +x).
        """
        os.chmod(script, 0o755)

    def execute(self, env: dict | None = None):
        """
        Execute the feature command.
        """

        self._execute_command(self.test_feature_path, self.test_output, env)

    @staticmethod
    def _execute_command(command, cwd, env=None):
        """
        Execute a command and check its exit code.
        Raise an exception if the command does not return 0.
        """
        process = subprocess.Popen(command, cwd=cwd, env=env)
        code = process.wait()
        if code != 0:
            raise Exception("Error: command returned code {}".format(code))

    def verify(self, command: list | None = None):
        """
        Use diff command to compare the expected output (data) and the actual output.
        """
        diff_command = ["diff", "-r", "data", "actual"] + (command or [])
        self._execute_command(diff_command, self.test_dir)
        print("Test {} passed successfully".format(self.feature_command))
