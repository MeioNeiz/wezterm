# Points WezTerm on Windows at this repo's wezterm.lua. No symlinks: those need admin or
# developer mode, and WEZTERM_CONFIG_FILE outranks every other config location.
# The cc-* fleet layer is bash and stays off here; wezterm.lua gates it on POSIX.
# Run: powershell -ExecutionPolicy Bypass -File setup-windows.ps1

$config = Join-Path $PSScriptRoot 'wezterm.lua'
[Environment]::SetEnvironmentVariable('WEZTERM_CONFIG_FILE', $config, 'User')
Write-Host "WEZTERM_CONFIG_FILE = $config"

Write-Host 'Restart WezTerm (quit it fully) to pick this up.'
