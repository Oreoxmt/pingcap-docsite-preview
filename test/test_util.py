import os
import shlex
import shutil
import subprocess


class DocSitePreviewTest:

    def __init__(self, test_dir: str, feature_dir: str, script_name: str):
        self.feature_dir = feature_dir
        self.script_name = script_name
        self.test_dir = test_dir
        self.test_output = os.path.join(self.test_dir, "actual")
        self.test_feature_path = os.path.join(self.test_output, self.script_name)
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
        shutil.copy(os.path.join(self.feature_dir, self.script_name), self.test_feature_path)
        self._make_script_executable(self.test_feature_path)

    @staticmethod
    def _make_script_executable(script: str):
        """
        Make the script executable (chmod +x).
        """
        os.chmod(script, 0o755)

    def execute(self, args: str = "", env: dict | None = None):
        """
        Execute the feature command.
        """
        command_str = self.test_feature_path + " " + args
        command_list = shlex.split(command_str)
        self._execute_command(command_list, self.test_output, env)

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

    def verify(self, command: str = "diff -r data actual"):
        """
        Use diff command to compare the expected output (data) and the actual output.
        """
        args = shlex.split(command)
        self._execute_command(args, self.test_dir)
        print("Test {} passed successfully".format(self.script_name))
