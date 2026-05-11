param(
  [string]$PythonExe = "",
  [string]$RscriptExe = "",
  [switch]$CreateVenv,
  [switch]$SkipPython,
  [switch]$SkipR
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

function Find-FirstCommand {
  param([string[]]$Names)
  foreach ($Name in $Names) {
    $Cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($Cmd) {
      return $Cmd.Source
    }
  }
  return ""
}

Write-Host "Project root: $Root"

if (-not $SkipPython) {
  if ([string]::IsNullOrWhiteSpace($PythonExe)) {
    $PythonExe = Find-FirstCommand @("python", "py")
  }
  if ([string]::IsNullOrWhiteSpace($PythonExe)) {
    throw "Cannot find python or py. Install Python first, or pass -PythonExe <path>."
  }

  if ($CreateVenv) {
    if (-not (Test-Path ".venv")) {
      Write-Host "Creating Python virtual environment: .venv"
      & $PythonExe -m venv .venv
    }
    $PythonExe = Join-Path $Root ".venv\Scripts\python.exe"
  }

  Write-Host "Using Python: $PythonExe"
  & $PythonExe -m pip install --upgrade pip
  & $PythonExe -m pip install -r requirements.txt
}

if (-not $SkipR) {
  if ([string]::IsNullOrWhiteSpace($RscriptExe)) {
    $RscriptExe = Find-FirstCommand @("Rscript", "Rscript.exe")
  }
  if ([string]::IsNullOrWhiteSpace($RscriptExe)) {
    throw "Cannot find Rscript. Install R first, or pass -RscriptExe <path>."
  }

  Write-Host "Using Rscript: $RscriptExe"
  & $RscriptExe scripts/install_r_packages.R
}

Write-Host "Environment setup complete."
