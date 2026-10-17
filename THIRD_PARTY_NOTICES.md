# Third-party notices

pypackaging.bzl is licensed under the Apache License, Version 2.0 (see
[`LICENSE`](LICENSE)). It contains Starlark ports of code from the projects
below. Their copyright notices and license texts are reproduced here and in
[`LICENSES/`](LICENSES), as their licenses require.

## pypa/packaging

- Project: <https://github.com/pypa/packaging>
- Version: 26.2
- Used in: `pypackaging/private/` (versions, specifiers, markers,
  requirements, tags, utils)
- Copyright: Copyright (c) Donald Stufft and individual contributors.
- License: dual-licensed under the Apache License, Version 2.0 **or** the BSD
  2-Clause License, at your option. The upstream license files are reproduced
  verbatim:
  - [`LICENSES/packaging/LICENSE`](LICENSES/packaging/LICENSE)
  - [`LICENSES/packaging/LICENSE.APACHE`](LICENSES/packaging/LICENSE.APACHE)
  - [`LICENSES/packaging/LICENSE.BSD`](LICENSES/packaging/LICENSE.BSD)

## pypa/pip

- Project: <https://github.com/pypa/pip>
- Used in: `pypackaging/private/tags/tags.bzl` (handling of custom platform
  strings and legacy platform aliases when generating tags)
- Copyright: Copyright (c) 2008-present The pip developers (see
  <https://github.com/pypa/pip/blob/main/AUTHORS.txt>).
- License: MIT. The upstream license file is reproduced verbatim:
  [`LICENSES/pip/LICENSE.txt`](LICENSES/pip/LICENSE.txt)
