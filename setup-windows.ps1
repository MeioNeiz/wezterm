# Points WezTerm on Windows at this repo's wezterm.lua. No symlinks: those need admin or
# developer mode, and WEZTERM_CONFIG_FILE outranks every other config location.
# The cc-* fleet layer is bash and stays off here; wezterm.lua gates it on POSIX.
# Run: powershell -ExecutionPolicy Bypass -File setup-windows.ps1
# WezTerm itself: the nightly, as on the Mac (the config is tested against it). winget's
# wez.wezterm.nightly fails its hash check (the installer is rebuilt daily at one URL), so
# run github.com/wezterm/wezterm/releases/download/nightly/WezTerm-nightly-setup.exe
# (/VERYSILENT for no prompts) with WezTerm closed; rerun it to update

$config = Join-Path $PSScriptRoot 'wezterm.lua'
[Environment]::SetEnvironmentVariable('WEZTERM_CONFIG_FILE', $config, 'User')
Write-Host "WEZTERM_CONFIG_FILE = $config"

Write-Host 'Restart WezTerm (quit it fully) to pick this up.'
