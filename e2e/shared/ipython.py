import os
import tempfile

from IPython import start_ipython

with tempfile.TemporaryDirectory() as d:
    os.environ["IPYTHONDIR"] = str(d)
    start_ipython()
