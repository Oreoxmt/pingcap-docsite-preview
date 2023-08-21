import sys
import os

test_dir: str = os.path.dirname(os.path.abspath(__file__))
feature_dir: str = os.path.dirname(os.path.dirname(test_dir))
sys.path.append(os.path.dirname(test_dir))

from test_util import DocSitePreviewTest

script_name: str = "sync_scaffold.sh"
diff_command_line: str = f"diff -r data actual --exclude temp --exclude {script_name}"

script_env = os.environ.copy()
script_env["TEST"] = str(1)

test = DocSitePreviewTest(test_dir, feature_dir, script_name)

test.execute(env=script_env)

test.verify(diff_command_line)
