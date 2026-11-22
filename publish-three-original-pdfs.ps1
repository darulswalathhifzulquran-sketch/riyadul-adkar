# RIYADUL ADKAR: publish three original PDF files and matching page previews.
# Paste: irm https://raw.githubusercontent.com/darulswalathhifzulquran-sketch/riyadul-adkar/main/publish-three-original-pdfs.ps1 | iex
# No ZIP download, no Flutter build or flutter run.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$repoUrl = 'https://github.com/darulswalathhifzulquran-sketch/riyadul-adkar.git'
$liveUrl = 'https://darulswalathhifzulquran-sketch.github.io/riyadul-adkar/'
$specs = @(
    @{ id='swalath-3'; name='swalathu thaj. pdf.pdf'; sha='2fe34a70ceac80582c3a405d6390f3004ef0aa00c142a1ca5810f0d92daa2185'; pages=3; asset='swalathu_taj.pdf'; category='swalath' },
    @{ id='swalath-4'; name='swalathu nnariyah.pdf'; sha='2277a373a09aa103cbdf008d2ae2503320134220824b17327eae5f907f8ead45'; pages=1; asset='swalathu_nariyath.pdf'; category='swalath' },
    @{ id='dua-8'; name='sayyidul isthia faar.pdf'; sha='768b97cf684ec5d48835d16eeedf086f86d6aeff487643bf0e2e6fb0d218145c'; pages=1; asset='sayyidul_istighfar.pdf'; category='dua' }
)
# Windows PowerShell 5.1 can treat native programs' stderr warnings
# (including Git clone progress and Python FutureWarnings) as terminating
# errors when ErrorActionPreference is Stop. Check exit codes instead.
function Invoke-NativeSafe {
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [switch]$Quiet
    )
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        if ($Quiet) {
            & $Executable @Arguments 2>&1 | Out-Null
        } else {
            & $Executable @Arguments 2>&1 | Out-Host
        }
        return [int]$LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}
function Git-Run {
    $code = Invoke-NativeSafe -Executable 'git' -Arguments $args
    if ($code -ne 0) { throw ('Git failed (exit ' + $code + '): git ' + ($args -join ' ')) }
}
function Find-Original([hashtable]$spec) {
    $roots = New-Object 'System.Collections.Generic.List[string]'
    $roots.Add((Get-Location).Path)
    foreach ($homePath in @($env:USERPROFILE, $env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)) {
        if ([string]::IsNullOrWhiteSpace($homePath)) { continue }
        foreach ($sub in @('Downloads','Desktop','Documents','')) {
            $folder = if ($sub) { Join-Path $homePath $sub } else { $homePath }
            if (Test-Path -LiteralPath $folder -PathType Container) { $roots.Add($folder) }
        }
    }
    $seen = @{}
    foreach ($root in $roots) {
        if ($seen.ContainsKey($root)) { continue }
        $seen[$root] = $true
        $candidate = Join-Path $root $spec.name
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            if ((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant() -eq $spec.sha) { return $candidate }
        }
    }
    foreach ($root in $roots) {
        # Search a few levels down (including project folders and PDFs inside Downloads).
        try {
            $found = @(Get-ChildItem -LiteralPath $root -Filter $spec.name -File -Recurse -Depth 3 -ErrorAction SilentlyContinue)
            foreach ($candidate in $found) {
                if ((Get-FileHash -LiteralPath $candidate.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -eq $spec.sha) {
                    return $candidate.FullName
                }
            }
        } catch {}
    }
    return $null
}
function Set-Value($object, [string]$name, $value) {
    if ($null -eq $object.PSObject.Properties[$name]) {
        $object | Add-Member -MemberType NoteProperty -Name $name -Value $value
    } else {
        $object.$name = $value
    }
}
$base = Join-Path $env:TEMP ('riyadul-adkar-original-pdfs-' + [guid]::NewGuid().ToString('N'))
$checkout = Join-Path $base 'published-repo'
$thumbs = Join-Path $base 'page-previews'
try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git for Windows is missing.' }
    Write-Host 'RIYADUL ADKAR: Checking the three original PDFs...' -ForegroundColor Cyan
    foreach ($spec in $specs) {
        $file = Find-Original $spec
        if (-not $file) {
            throw ('Cannot find this original PDF on your computer: ' + $spec.name + '. Save the original uploaded PDF to Downloads and paste the SAME command again.')
        }
        $spec.source = $file
        Write-Host ('Found verified original: ' + $spec.name) -ForegroundColor Green
    }
    $python = @(Get-Command py, python -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($python.Count -eq 0) { throw 'Python is needed to prepare the five identical-layout PDF page previews. Install Python, then paste the same command again.' }
    New-Item -ItemType Directory -Force -Path $base, $thumbs | Out-Null
    $renderPython = $python[0].Source
    # Use the current non-deprecated PyMuPDF API.
    # A missing module is detected from its exit code, not warning text.
    $importExit = Invoke-NativeSafe -Executable $renderPython -Arguments @('-c', 'import pymupdf') -Quiet
    if ($importExit -ne 0) {
        Write-Host 'Preparing the PDF renderer (in a temporary isolated environment)...'
        $venv = Join-Path $base 'python-env'
        $venvExit = Invoke-NativeSafe -Executable $renderPython -Arguments @('-m', 'venv', $venv)
        if ($venvExit -ne 0) { throw 'Python virtual environment setup failed.' }
        $renderPython = Join-Path $venv 'Scripts\python.exe'
        $installExit = Invoke-NativeSafe -Executable $renderPython -Arguments @('-m', 'pip', 'install', '--disable-pip-version-check', '--quiet', 'pymupdf')
        if ($installExit -ne 0) { throw 'Could not install the PDF rendering dependency.' }
    }
    $renderCode = @'
import pymupdf as fitz
import os
import sys
dest=sys.argv[1]
for source,key,expected in [(sys.argv[2],'swalath-3',3),(sys.argv[3],'swalath-4',1),(sys.argv[4],'dua-8',1)]:
    doc=fitz.open(source)
    if len(doc)!=expected:
        raise ValueError(f'{key}: expected {expected} pages, found {len(doc)}')
    for i,page in enumerate(doc):
        pix=page.get_pixmap(matrix=fitz.Matrix(0.78,0.78),alpha=False)
        pix.save(os.path.join(dest, f'{key}_page_{i+1:04d}.jpg'), jpg_quality=93)
'@
    Write-Host 'Rendering exact PDF page layouts (3 + 1 + 1 pages)...'
    $renderExit = Invoke-NativeSafe -Executable $renderPython -Arguments @('-c', $renderCode, $thumbs, $specs[0].source, $specs[1].source, $specs[2].source)
    if ($renderExit -ne 0) { throw 'Could not render original PDF pages.' }
    $imagePaths = @(Get-ChildItem -LiteralPath $thumbs -Filter '*.jpg' -File)
    if ($imagePaths.Count -ne 5) { throw 'Five PDF page preview images were expected.' }
    Write-Host 'Preparing existing published website, not Flutter source...'
    Git-Run clone --depth 1 --filter=blob:none --sparse --branch main $repoUrl $checkout
    Git-Run -C $checkout sparse-checkout set --no-cone '/assets/assets/data/library.json' '/assets/assets/books/swalathu_taj.pdf' '/assets/assets/books/swalathu_nariyath.pdf' '/assets/assets/books/sayyidul_istighfar.pdf' '/assets/assets/web_books/swalath-3_page_0001.jpg' '/assets/assets/web_books/swalath-3_page_0002.jpg' '/assets/assets/web_books/swalath-3_page_0003.jpg' '/assets/assets/web_books/swalath-4_page_0001.jpg' '/assets/assets/web_books/dua-8_page_0001.jpg'
    $catalogPath = Join-Path $checkout 'assets\assets\data\library.json'
    $catalog = Get-Content -LiteralPath $catalogPath -Encoding UTF8 -Raw | ConvertFrom-Json
    foreach ($spec in $specs) {
        $matches = @($catalog.items | Where-Object { $_.id -eq $spec.id -and $_.category -eq $spec.category })
        if ($matches.Count -ne 1) { throw ('Catalog item not found exactly once: ' + $spec.id) }
        $item = $matches[0]
        Set-Value $item 'pdfAsset' ('assets/books/' + $spec.asset)
        Set-Value $item 'flow' $false
        $item.pages = @()
    }
    $json = ConvertTo-Json -InputObject $catalog -Depth 100
    [System.IO.File]::WriteAllText($catalogPath, $json + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    foreach ($spec in $specs) {
        $dest = Join-Path $checkout ('assets\assets\books\' + $spec.asset)
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
        Copy-Item -LiteralPath $spec.source -Destination $dest -Force
        if ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant() -ne $spec.sha) {
            throw ('Published PDF does not match uploaded original: ' + $spec.name)
        }
    }
    $webBooks = Join-Path $checkout 'assets\assets\web_books'
    New-Item -ItemType Directory -Force -Path $webBooks | Out-Null
    foreach ($img in $imagePaths) { Copy-Item -LiteralPath $img.FullName -Destination (Join-Path $webBooks $img.Name) -Force }
    Git-Run -C $checkout add -f -- 'assets/assets/data/library.json' 'assets/assets/books/swalathu_taj.pdf' 'assets/assets/books/swalathu_nariyath.pdf' 'assets/assets/books/sayyidul_istighfar.pdf' 'assets/assets/web_books/swalath-3_page_0001.jpg' 'assets/assets/web_books/swalath-3_page_0002.jpg' 'assets/assets/web_books/swalath-3_page_0003.jpg' 'assets/assets/web_books/swalath-4_page_0001.jpg' 'assets/assets/web_books/dua-8_page_0001.jpg'
    Git-Run -C $checkout diff --cached --check
    Git-Run -C $checkout commit -m 'Replace Nariyyath and Taj originals and add Sayyidul Istighfar PDF'
    Git-Run -C $checkout push origin main
    Write-Host 'SUCCESS: Changes pushed to GitHub Pages repository.' -ForegroundColor Green
    Write-Host ('App: ' + $liveUrl)
    Write-Host 'No flutter run or flutter build needed.'
} catch {
    Write-Host ('PUBLISH NOT COMPLETED: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ('Temporary folder: ' + $base)
    return
}
