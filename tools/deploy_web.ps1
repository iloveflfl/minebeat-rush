# MineBeat Rush - build the web version and publish it to GitHub Pages.
#
#   .\tools\deploy_web.ps1            # rebuild and publish at the current version
#   .\tools\deploy_web.ps1 patch      # 0.2.0 -> 0.2.1, then publish
#   .\tools\deploy_web.ps1 minor      # 0.2.0 -> 0.3.0
#   .\tools\deploy_web.ps1 major      # 0.2.0 -> 1.0.0
#
# The main branch keeps the project; the built page lives on the gh-pages
# branch, which is what Pages serves. Nothing is written to C:.

param([ValidateSet('none', 'patch', 'minor', 'major')][string]$Bump = 'none')

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Godot = 'S:\GameDev\Godot\Godot_v4.7-stable_win64_console.exe'
$Build = Join-Path $Root 'build\web'
$Worktree = 'S:\GameDev\_minebeat_pages'

Set-Location $Root

# --- version ---------------------------------------------------------------
$verFile = Join-Path $Root 'VERSION'
if (-not (Test-Path $verFile)) { '0.1.0' | Set-Content $verFile -Encoding utf8 -NoNewline }
$parts = (Get-Content $verFile -Raw).Trim().Split('.')
[int]$maj, [int]$min, [int]$pat = $parts[0], $parts[1], $parts[2]
switch ($Bump) {
    'patch' { $pat++ }
    'minor' { $min++; $pat = 0 }
    'major' { $maj++; $min = 0; $pat = 0 }
}
$version = "$maj.$min.$pat"
$version | Set-Content $verFile -Encoding utf8 -NoNewline
Write-Host "== MineBeat Rush v$version ==" -ForegroundColor Cyan

# --- tests must pass before anything ships ---------------------------------
Write-Host "-- tests" -ForegroundColor Yellow
$testOut = & $Godot --headless --path $Root --script res://tests/run_tests.gd 2>&1 | Out-String
$summary = ($testOut -split "`n" | Select-String '=== \d+ passed').Line
if (-not $summary -or $summary -match ' [1-9]\d* failed') {
    Write-Host $testOut
    throw "tests failed - refusing to deploy"
}
Write-Host "   $($summary.Trim())"

# --- build -----------------------------------------------------------------
Write-Host "-- export web" -ForegroundColor Yellow
if (Test-Path $Build) { Remove-Item -Recurse -Force $Build -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force $Build | Out-Null
& $Godot --headless --path $Root --export-release 'Web' (Join-Path $Build 'index.html') | Out-Null
if (-not (Test-Path (Join-Path $Build 'index.wasm'))) { throw "export produced no wasm" }
$mb = [math]::Round(((Get-ChildItem $Build | Measure-Object Length -Sum).Sum / 1MB), 1)
Write-Host "   $mb MB"

# GitHub Pages serves from Jekyll by default, which silently drops files it
# does not recognise. .nojekyll turns that off.
New-Item -ItemType File -Force (Join-Path $Build '.nojekyll') | Out-Null

# --- commit the source -----------------------------------------------------
Write-Host "-- commit + tag" -ForegroundColor Yellow
git add -A
if (git status --porcelain) {
    git commit -q -m "Release v$version"
}
if (-not (git tag -l "v$version")) { git tag "v$version" }
git push -q origin HEAD --tags

# --- publish the build to gh-pages ----------------------------------------
Write-Host "-- publish gh-pages" -ForegroundColor Yellow
if (Test-Path $Worktree) { git worktree remove --force $Worktree 2>$null | Out-Null }
if (git ls-remote --heads origin gh-pages) {
    git worktree add -f $Worktree gh-pages | Out-Null
} else {
    git worktree add -f --detach $Worktree | Out-Null
    git -C $Worktree checkout --orphan gh-pages | Out-Null
    git -C $Worktree rm -rq --cached . 2>$null | Out-Null
}
Get-ChildItem $Worktree -Exclude '.git' -Force | Remove-Item -Recurse -Force
Copy-Item "$Build\*" $Worktree -Recurse -Force
git -C $Worktree add -A
git -C $Worktree commit -q -m "Deploy v$version" --allow-empty
git -C $Worktree push -q -f origin gh-pages
git worktree remove --force $Worktree

$url = "https://$((git remote get-url origin) -replace '.*github\.com[:/]([^/]+)/(.+?)(\.git)?$', '$1.github.io/$2')/"
Write-Host ""
Write-Host "published v$version" -ForegroundColor Green
Write-Host "  $url"
Write-Host "  (first deploy can take a minute or two to go live)"

