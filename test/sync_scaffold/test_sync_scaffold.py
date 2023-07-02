import sys
import os

test_dir: str = os.path.dirname(os.path.abspath(__file__))
feature_dir: str = os.path.dirname(os.path.dirname(test_dir))
sys.path.append(os.path.dirname(test_dir))

from test_util import DocSitePreviewTest

script_name: str = "sync_scaffold.sh"
feature_command: str = "/" + script_name
diff_exclude: list = ["--exclude", "temp", "--exclude", script_name]

test = DocSitePreviewTest(test_dir, feature_dir, feature_command)

test.execute()

test.verify(diff_exclude)
