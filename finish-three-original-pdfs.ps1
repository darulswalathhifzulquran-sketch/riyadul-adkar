# RIYADUL ADKAR — finish the previous successfully rendered and staged
# three-original-PDF deployment. No PDF rerender, download, ZIP or Flutter run.
# This script searches temporary output from the prior publisher and resumes
# at the failed Git author-identity step.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$owner = 'darulswalathhifzulquran-sketch'
$noReply = '316104416+darulswalathhifzulquran-sketch@users.noreply.github.com'
$expectedFiles = @(
    @{path='assets/assets/books/swalathu_taj.pdf'; hash='2fe34a70ceac80582c3a405d6390f3004ef0aa00c142a1ca5810f0d92daa2185'; id='swalath-3'},
    @{path='assets/assets/books/swalathu_nariyath.pdf'; hash='2277a373a09aa103cbdf008d2ae2503320134220824b17327eae5f907f8ead45'; id='swalath-4'},
    @{path='assets/assets/books/sayyidul_istighfar.pdf'; hash='768b97cf684ec5d48835d16eeedf086f86d6aeff487643bf0e2e6fb0d218145c'; id='dua-8'}
)
$pageNames = @(
  'swalath-3_page_0001.jpg', 'swalath-3_page_0002.jpg',
  'swalath-3_page_0003.jpg', 'swalath-4_page_0001.jpg',
  'dua-8_page_0001.jpg'
)
function Git-Run {
    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $quoted = @(
            foreach ($value in $args) {
                '"' + ([string]$value).Replace('"', '\"') + '"'
            }
        ) -join ' '
        $p = Start-Process -FilePath 'git' -ArgumentList $quoted -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
        foreach ($file in @($stdout,$stderr)) {
            if ((Test-Path -LiteralPath $file) -and (Get-Item -LiteralPath $file).Length -gt 0) {
                Get-Content -LiteralPath $file -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
            }
        }
        if ($p.ExitCode -ne 0) { throw ('Git command failed (exit ' + $p.ExitCode + '): git ' + ($args -join ' ')) }
    } finally {
        Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
    }
}
function Valid-Checkout([string]$path) {
    if (-not (Test-Path -LiteralPath (Join-Path $path '.git') -PathType Container)) { return $false }
    foreach ($spec in $expectedFiles) {
        $full = Join-Path $path $spec.path
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $false }
        if ((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant() -ne $spec.hash) { return $false }
    }
    foreach ($page in $pageNames) {
        if (-not (Test-Path -LiteralPath (Join-Path $path ('assets/assets/web_books/' + $page)) -PathType Leaf)) { return $false }
    }
    $catalogPath = Join-Path $path 'assets/assets/data/library.json'
    if (-not (Test-Path -LiteralPath $catalogPath)) { return $false }
    try {
        $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($spec in $expectedFiles) {
            $items = @($catalog.items | Where-Object { $_.id -eq $spec.id })
            if ($items.Count -ne 1 -or $items[0].pdfAsset -ne ('assets/books/' + (Split-Path $spec.path -Leaf))) { return $false }
        }
    } catch { return $false }
    return $true
}
try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git for Windows is not available.' }
    $candidateFolders = @(Get-ChildItem -LiteralPath $env:TEMP -Directory -Filter 'riyadul-adkar-original-pdfs-*' -ErrorAction Stop | Sort-Object LastWriteTime -Descending)
    $checkout = $null
    foreach ($folder in $candidateFolders) {
        $candidate = Join-Path $folder.FullName 'published-repo'
        if (Valid-Checkout $candidate) { $checkout = $candidate; break }
    }
    if (-not $checkout) {
        throw 'Cannot find the previous verified temporary checkout. Run the updated publish-three-original-pdfs.ps1 command instead.'
    }
    Write-Host 'FOUND: All 3 original PDFs, all 5 page images, and catalog were verified.' -ForegroundColor Green
    Write-Host 'Finishing the previously prepared GitHub Pages update...' -ForegroundColor Cyan

    # Only configure the temporary checkout. Do not modify global Git identity.
    Git-Run -C $checkout config --local user.name $owner
    Git-Run -C $checkout config --local user.email $noReply
    $paths = @('assets/assets/data/library.json')
    $paths += @($expectedFiles | ForEach-Object { $_.path })
    $paths += @($pageNames | ForEach-Object { 'assets/assets/web_books/' + $_ })
    Git-Run -C $checkout add -f -- @paths
    Git-Run -C $checkout diff --cached --check
    Git-Run -C $checkout commit -m 'Publish original Nariyyath, Taj and Sayyidul Istighfar PDFs'

    # The publisher script itself was updated on main while this temporary
    # checkout was waiting. Rebase to keep those newer changes intact.
    Git-Run -C $checkout pull --rebase origin main
    Git-Run -C $checkout push origin main

    Write-Host 'SUCCESS: Changes pushed to GitHub Pages repository.' -ForegroundColor Green
    Write-Host 'https://darulswalathhifzulquran-sketch.github.io/riyadul-adkar/'
} catch {
    Write-Host ('PUBLISH NOT COMPLETED: ' + $_.Exception.Message) -ForegroundColor Red
}
