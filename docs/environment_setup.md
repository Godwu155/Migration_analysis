# Environment Setup

This project now includes setup scripts for installing the R and Python dependencies used by the migration analysis, prediction apps, and the multi-species framework.

## Windows PowerShell

From the project root:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/setup_env.ps1
```

Create and use a local Python virtual environment:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/setup_env.ps1 -CreateVenv
```

If Python or R are not on `PATH`, pass explicit executables:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/setup_env.ps1 `
  -PythonExe "C:\Path\To\python.exe" `
  -RscriptExe "C:\Path\To\Rscript.exe"
```

## macOS/Linux/Git Bash

```bash
bash scripts/setup_env.sh
```

Create and use a local Python virtual environment:

```bash
CREATE_VENV=1 bash scripts/setup_env.sh
```

Override executable names:

```bash
PYTHON_BIN=python RSCRIPT_BIN=Rscript bash scripts/setup_env.sh
```

## What Gets Installed

Python dependencies are listed in `requirements.txt`.

R dependencies are listed in `scripts/install_r_packages.R`.

The R installer uses `CRAN_REPO` when set, otherwise it defaults to `https://cloud.r-project.org`:

```powershell
$env:CRAN_REPO = "https://cloud.r-project.org"
powershell -ExecutionPolicy Bypass -File scripts/setup_env.ps1
```

## Notes

- The setup scripts are explicit: analysis scripts do not install packages automatically.
- The optional `maps` R package is included so static longitude/latitude figures can draw a world map background.
- The `sf` R package may require system libraries on some Linux machines. If `sf` fails to install, install GDAL, GEOS, PROJ, and udunits development packages with your system package manager, then rerun the setup script.
