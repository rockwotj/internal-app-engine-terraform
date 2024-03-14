#!/usr/bin/env python3

import subprocess
from pathlib import Path
import time
import getpass

TF_DIR = Path(__file__).resolve().parent
HELLO_APP_DIR = TF_DIR.parent / "hello_app"

subprocess.check_call(["npm", "install"], cwd=HELLO_APP_DIR)
subprocess.check_call(["npm", "run", "build"], cwd=HELLO_APP_DIR)

user = getpass.getuser()
unix_seconds = int(time.time())
deployment_version = f"{user}-{unix_seconds}"

# Deploy the new version
subprocess.check_call(
    [
        "terraform",
        "apply",
        f"-var=deployment_version={deployment_version}",
    ],
    cwd=TF_DIR,
)
