# Application documentation on GitHub Pages

Public landing page: https://danghica.github.io/cjr-shift/

- Application docs: https://danghica.github.io/cjr-shift/work/docs/
- CLI reference: https://danghica.github.io/cjr-shift/work/CLI/doc/

The `Publish documentation` workflow runs when generated docs or their linked
public reports change on `main`. It can also be run manually from GitHub Actions.
It packages existing HTML, CSS, SVG and four explicitly selected public JSON
reports/examples. It does not compile the core, extract code or validate proofs.

To check the same publication locally:

```sh
python3 scripts/package_docs.py
```

The staging directory is `build/pages-site/` (ignored by Git). The script checks
local file links and HTML anchors before deployment. The directory hierarchy is
preserved so links between CLI docs, specifications and reports keep working.
The artifact contains a landing page and `.nojekyll`; prompts, browser snapshots,
private stores and executables are excluded. GitHub Pages settings must use
**GitHub Actions** as the publishing source. The Railway app is a separate service.
