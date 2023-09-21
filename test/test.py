import os
import time
import tomllib
from dataclasses import dataclass
from typing import Dict, List

from tqdm import tqdm

from test_util import DocSitePreviewTest

ENV_FILE = ".env"
CONFIG_FILE = "test_config.toml"


@dataclass
class TestReport:
    start_time: float
    end_time: float
    success_tests: List[str]
    failed_tests: List[str]


class TestRunner:
    def __init__(self):
        self.tests = self._load_config()
        self.report = TestReport(
            start_time=time.time(), end_time=time.time(),
            success_tests=[], failed_tests=[])
        self._env = self._load_env()

    @staticmethod
    def _load_config():
        """
        Load test config from test_config.toml.
        """
        with open(CONFIG_FILE, "rb") as f:
            config = tomllib.load(f)
        return config

    @staticmethod
    def _load_env() -> Dict[str, str]:
        """
        Load environment variables from .env file.
        """
        env = os.environ.copy()
        with open(ENV_FILE, "rb") as f:
            for line in f:
                key, value = line.decode("utf-8").strip().split("=")
                env[key] = value
        return env

    def run(self) -> None:
        """
        Run test cases based on given configuration and environment variables.
        """
        print(f"Running Tests...")

        for _, config in self.tests.items():
            script_name = config["test_target"]
            diff_command = config["diff_command"]

            for case in tqdm(config["test_cases"]):
                case_name = case["name"]
                feature_dir = os.path.dirname(case_name)
                test_dir = os.path.abspath(case["directory"])
                script_args = case["args"]

                test = DocSitePreviewTest(test_dir, feature_dir, script_name)

                if test.execute(args=script_args, env=self._env) and test.verify(diff_command):
                    self.report.success_tests.append(case_name)
                else:
                    self.report.failed_tests.append(case_name)

        self.report.end_time = time.time()

    def analyze(self) -> str:
        """
        Analyze test results and generate a report.
        """
        terminal_width = os.get_terminal_size().columns
        hyphens = "-" * ((terminal_width - len("Test Results")) // 2)
        duration = self.report.end_time - self.report.start_time
        result = f"{hyphens}Test Results{hyphens}\n"
        success_count = len(self.report.success_tests)
        failed_count = len(self.report.failed_tests)
        total_count = success_count + failed_count
        for test in self.report.success_tests:
            result += f"✅ Test {test} passed successfully\n"
        for test in self.report.failed_tests:
            result += f"❌ Test {test} failed\n"
        result += f"Tests passed: {success_count} of {total_count} {duration:.2f}s\n"
        result += "-" * terminal_width
        return result


if __name__ == "__main__":
    runner = TestRunner()
    runner.run()
    conclusion = runner.analyze()
    print(conclusion)
