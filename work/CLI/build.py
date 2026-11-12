#!/usr/bin/env python3
"""Build the native CLI and install its file-store entry point."""
from pathlib import Path
import json
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.project_tools.support import toolchain


def main():
    subprocess.run([sys.executable, str(ROOT/'work/CLI/generate_reference.py')], check=True)
    cjc, env, version = toolchain(ROOT)
    sources = [ROOT/'work/code/tracker.cj', ROOT/'work/code/working_time.cj', ROOT/'work/CLI/working_time_bridge.cj', *[ROOT/'work/CLI'/name for name in ('bridge.cj', 'main.cj', 'help.cj')]]
    command = [str(cjc), '-O2', '--set-runtime-rpath', *map(str, sources), '-o', str(ROOT/'work/CLI/bin/tracker-core')]
    print('+', ' '.join(command), flush=True)
    subprocess.run(command, env=env, check=True)
    entry = ROOT/'work/CLI/bin/tracker'
    entry.write_text('#!/usr/bin/env python3\nfrom pathlib import Path\nimport runpy\nrunpy.run_path(str(Path(__file__).resolve().parents[1]/"file_store.py"), run_name="__main__")\n')
    entry.chmod(0o755)
    (ROOT/'work/CLI/build-record.json').write_text(json.dumps({'compiler': version, 'command': command, 'entry': str(entry)}, indent=2)+'\n')


if __name__ == '__main__':
    main()
