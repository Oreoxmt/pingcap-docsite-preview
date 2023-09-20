import os
import time
import tomllib

from tqdm import tqdm

from test_util import DocSitePreviewTest

ENV_FILE = ".env"
CONFIG_FILE = "test_config.toml"


class TestRunner:
    def __init__(self):
        self.tests = self._load_config()
        self._env = self._load_env()
        self._start = time.time()
        self._end = None

    @staticmethod
    def _load_config():

        """
        Load test config from test_config.toml.
        """
        with open(CONFIG_FILE, "rb") as f:
            config = tomllib.load(f)
        return config

    @staticmethod
    def _load_env() -> dict:
        """
        Load environment variables from .env file.
        """
        env = os.environ.copy()
        with open(ENV_FILE, "rb") as f:
            for line in f:
                key, value = line.decode("utf-8").strip().split("=")
                env[key] = value
        return env

    def run(self) -> str:
        """
        Run test cases based on given configuration and environment variables.
        """
        test_count = 0
        success_test = 0
        terminal_width = os.get_terminal_size().columns
        hyphens = "-" * ((terminal_width - len("Test Results")) // 2)
        result = f"{hyphens}Test Results{hyphens}\n"
        print(f"Running Tests...")

        for feature, config in self.tests.items():
            script_name = config["test_target"]
            diff_command = config["diff_command"]

            for case in tqdm(config["test_cases"]):
                test_count += 1
                case_name = case["name"]
                feature_dir = os.path.dirname(case_name)
                test_dir = os.path.abspath(case["directory"])
                script_args = case["args"]

                test = DocSitePreviewTest(test_dir, feature_dir, script_name)

                if test.execute(args=script_args, env=self._env) and test.verify(diff_command):
                    result += f"✅ Test {case_name} passed successfully\n"
                    success_test += 1
                else:
                    result += f"❌ Test {case_name} failed\n"

        result += f"\nTests passed: {success_test} of {test_count}"
        self._end = time.time()
        result += f" {self._end - self._start:.2f}s\n"
        result += "-" * terminal_width
        return result


if __name__ == "__main__":
    runner = TestRunner()
    conclusion = runner.run()
    print(conclusion)

