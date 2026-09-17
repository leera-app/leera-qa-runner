# Installs the QA runner on Windows and, optionally, connects it and starts it at logon.
#
#   irm https://raw.githubusercontent.com/leera-app/leera-qa-runner/main/install/install.ps1 | iex
#   & ([scriptblock]::Create((irm .../install.ps1))) -Url https://app.example.com -Service
#
# The token for -Url comes from -Token or the RUNNER_TOKEN environment variable.
# -Portable installs the .zip bundle instead of running the installer (no Apps & features entry).
# Every download is checked against the release's SHA256SUMS.
[CmdletBinding()]
param(
  [string]$Version = '',
  [string]$Url = '',
  [string]$Token = $env:RUNNER_TOKEN,
  [string]$Name = '',
  [switch]$Service,
  [switch]$NoBrowsers,
  [switch]$Portable,
  [string]$BaseUrl = $env:QA_RUNNER_DOWNLOAD_BASE
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Releases = 'https://github.com/leera-app/leera-qa-runner/releases'

# throw, not exit: under `irm | iex` exit would close the user's PowerShell window.
function Fail([string]$Message) {
  throw "install: $Message"
}

if (-not [Environment]::Is64BitOperatingSystem) { Fail 'a 64-bit Windows is required' }
if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
  Write-Warning 'No ARM64 build yet; installing the x64 build, which runs under emulation.'
}

$asset = if ($Portable) { 'leera-qa-runner-windows-x64.zip' } else { 'leera-qa-runner-windows-x64.exe' }
$appDir = Join-Path $env:LOCALAPPDATA 'Programs\leera-qa-runner'
$Version = $Version.TrimStart('v')
if ($Version) {
  $base = if ($BaseUrl) { $BaseUrl.TrimEnd('/') } else { "$Releases/download" }
  $from = "$base/v$Version"
} elseif ($BaseUrl) {
  Fail '-Version is required with a custom download base'
} else {
  $from = "$Releases/latest/download"
}

$work = Join-Path ([IO.Path]::GetTempPath()) ("leera-qa-runner-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $work | Out-Null
try {
  Write-Host "Downloading $asset from $from"
  $installer = Join-Path $work $asset
  $sums = Join-Path $work 'SHA256SUMS'
  Invoke-WebRequest -UseBasicParsing -Uri "$from/$asset" -OutFile $installer
  Invoke-WebRequest -UseBasicParsing -Uri "$from/SHA256SUMS" -OutFile $sums

  $expected = $null
  foreach ($line in Get-Content $sums) {
    $parts = $line -split '\s+', 2
    if ($parts.Count -eq 2 -and $parts[1].TrimStart('*') -eq $asset) { $expected = $parts[0].ToLower(); break }
  }
  if (-not $expected) { Fail "SHA256SUMS does not list $asset" }
  $actual = (Get-FileHash -Algorithm SHA256 -Path $installer).Hash.ToLower()
  if ($expected -ne $actual) { Fail "checksum mismatch for $asset (expected $expected, got $actual)" }
  Write-Host 'Checksum verified.'

  if ($Portable) {
    # The zip holds leera-qa-runner-windows-x64\; bsdtar (tar.exe) ships with Windows 10 1803 and later.
    $unpacked = Join-Path $work 'unpacked'
    New-Item -ItemType Directory -Path $unpacked | Out-Null
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    & $tar -xf $installer -C $unpacked
    if ($LASTEXITCODE -ne 0) { Fail "could not unpack $asset (tar exited with $LASTEXITCODE)" }
    $bundle = Join-Path $unpacked 'leera-qa-runner-windows-x64'
    if (-not (Test-Path (Join-Path $bundle 'build-info.json'))) { Fail "$asset does not contain leera-qa-runner-windows-x64\" }
    if (Test-Path $appDir) { Remove-Item -Recurse -Force $appDir }
    New-Item -ItemType Directory -Force -Path (Split-Path $appDir) | Out-Null
    Move-Item -Path $bundle -Destination $appDir
    $binDir = Join-Path $appDir 'bin'
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (($userPath -split ';') -contains $binDir)) {
      [Environment]::SetEnvironmentVariable('Path', ((@($userPath, $binDir) | Where-Object { $_ }) -join ';'), 'User')
    }
  } else {
    $process = Start-Process -FilePath $installer -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
    if ($process.ExitCode -ne 0) { Fail "the installer exited with $($process.ExitCode)" }
  }
} finally {
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}

$bin = Join-Path $appDir 'bin\leera-qa-runner.cmd'
if (-not (Test-Path $bin)) { Fail "the installer did not create $bin" }
# The installer added bin\ to the user's PATH; make it usable in this session too.
$env:Path = "$env:Path;$(Join-Path $appDir 'bin')"

$installedVersion = ((& $bin version) -split ' ')[-1]
$runnerHome = if ($env:LEERA_RUNNER_HOME) { $env:LEERA_RUNNER_HOME } else { Join-Path $HOME '.leera-qa-runner' }
New-Item -ItemType Directory -Force -Path $runnerHome | Out-Null
# install.json tells `leera-qa-runner update` how this copy was installed (the zip counts as a tarball install).
$method = if ($Portable) { 'tar' } else { 'exe' }
$installJson = @{ method = $method; version = $installedVersion; installed_at = (Get-Date).ToUniversalTime().ToString('o'); prefix = $appDir; path = $bin } |
  ConvertTo-Json -Compress
# UTF-8 without a byte order mark (Set-Content -Encoding UTF8 adds one in Windows PowerShell).
[IO.File]::WriteAllText((Join-Path $runnerHome 'install.json'), $installJson, (New-Object Text.UTF8Encoding $false))
Write-Host "Installed leera-qa-runner $installedVersion at $bin"

if (-not $NoBrowsers) {
  & $bin setup browsers
  if ($LASTEXITCODE -ne 0) { Fail 'Chromium could not be installed' }
}

if ($Url) {
  if (-not $Token) { Fail '-Url needs a token: set RUNNER_TOKEN or pass -Token' }
  $connectArgs = @('connect', '--url', $Url, '--token-stdin')
  if ($Name) { $connectArgs += @('--name', $Name) }
  $Token | & $bin @connectArgs
  if ($LASTEXITCODE -ne 0) { Fail "connect failed with exit code $LASTEXITCODE" }
}

if ($Service) {
  & $bin service install
  if ($LASTEXITCODE -ne 0) { Fail "service install failed with exit code $LASTEXITCODE" }
}

Write-Host "Done. Run 'leera-qa-runner doctor' in a new terminal to check this machine."
