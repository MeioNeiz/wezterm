# Points WezTerm on Windows at this repo's wezterm.lua. No symlinks: those need admin or
# developer mode, and WEZTERM_CONFIG_FILE outranks every other config location.
# The cc-* fleet layer is bash and stays off here; wezterm.lua gates it on POSIX.
# Run: powershell -ExecutionPolicy Bypass -File setup-windows.ps1

$config = Join-Path $PSScriptRoot 'wezterm.lua'
[Environment]::SetEnvironmentVariable('WEZTERM_CONFIG_FILE', $config, 'User')
Write-Host "WEZTERM_CONFIG_FILE = $config"

# JetBrains Mono ships inside WezTerm; the tab bar font does not
$fontDirs = "$env:WINDIR\Fonts", "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
if (-not (Get-ChildItem $fontDirs -Filter 'Roboto*' -ErrorAction SilentlyContinue)) {
	Write-Host 'Roboto missing, tab bar falls back until installed: https://fonts.google.com/specimen/Roboto'
}

Write-Host 'Restart WezTerm (quit it fully) to pick this up.'
