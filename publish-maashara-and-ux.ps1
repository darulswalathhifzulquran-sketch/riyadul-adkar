# RIYADUL ADKAR: publish the exact Maashar PDF and activate the prepared live UX release.
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$expected='d8a8479d3c7be60bbb00d94c7f8ea95f708f6ce8fee9cf6d22670b31f101aef4'
$repo='https://github.com/darulswalathhifzulquran-sketch/riyadul-adkar.git'
$old='flutter_bootstrap-82B43C711C73272E.js'
$new='flutter_bootstrap-RIYAD20261123-UX1.js'
$tmp=Join-Path $env:TEMP ('riyad-maashara-'+[guid]::NewGuid().ToString('N'))
$work=Join-Path $tmp 'published'
function Native([string]$exe,[string[]]$arguments,[switch]$quiet) {
  $stdout=[System.IO.Path]::GetTempFileName()
  $stderr=[System.IO.Path]::GetTempFileName()
  try {
    $line=(@(foreach($arg in $arguments){'"'+([string]$arg).Replace('"','\"')+'"'}) -join ' ')
    $p=Start-Process -FilePath $exe -ArgumentList $line -PassThru -Wait -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
    if(-not $quiet -or $p.ExitCode -ne 0){
      foreach($file in @($stdout,$stderr)){
        if((Test-Path -LiteralPath $file) -and (Get-Item -LiteralPath $file).Length -gt 0){
          Get-Content -LiteralPath $file -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
        }
      }
    }
    return [int]$p.ExitCode
  } finally {
    Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
  }
}
function Must([string]$exe,[string[]]$arguments) {
  $result=Native $exe $arguments
  if($result -ne 0){throw ($exe+' failed, exit '+$result)}
}
try {
  if(-not(Get-Command git -ErrorAction SilentlyContinue)){throw 'Git is missing.'}
  Write-Host 'Checking your uploaded original Maashar PDF...' -ForegroundColor Cyan
  $roots=@((Get-Location).Path)
  foreach($homePath in @($env:USERPROFILE,$env:OneDrive,$env:OneDriveConsumer)){
    if($homePath){
      $roots+=@((Join-Path $homePath 'Downloads'),(Join-Path $homePath 'Desktop'),(Join-Path $homePath 'Documents'))
    }
  }
  $source=$null
  foreach($root in ($roots|Select-Object -Unique)){
    if(-not(Test-Path -LiteralPath $root -PathType Container)){continue}
    foreach($f in @(Get-ChildItem -LiteralPath $root -Filter '*ashara*.pdf' -Recurse -File -Depth 3 -ErrorAction SilentlyContinue)){
      if((Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -eq $expected){$source=$f.FullName;break}
    }
    if($source){break}
  }
  if(-not $source){throw 'The exact original Maashar PDF was not found. Place the previously uploaded file in Downloads and try this same command.'}
  Write-Host ('Verified original: '+$source) -ForegroundColor Green
  $pyCmd=Get-Command py,python -ErrorAction SilentlyContinue|Select-Object -First 1
  if(-not $pyCmd){throw 'Python not found.'}
  $python=$pyCmd.Source
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $ok=Native $python @('-c','import pymupdf') -quiet
  if($ok -ne 0){
    $venv=Join-Path $tmp 'venv'
    Must $python @('-m','venv',$venv)
    $python=Join-Path $venv 'Scripts\python.exe'
    Must $python @('-m','pip','install','--quiet','pymupdf')
  }
  $preview=Join-Path $tmp 'maashara_page_0001.jpg'
  $code=@'
import pymupdf as fitz
import sys
doc=fitz.open(sys.argv[1])
assert len(doc)==1, 'Expected exactly one PDF page'
doc[0].get_pixmap(matrix=fitz.Matrix(0.78,0.78),alpha=False).save(sys.argv[2],jpg_quality=94)
print('Preserved original PDF page layout')
'@
  $render=Join-Path $tmp 'render.py'
  [System.IO.File]::WriteAllText($render,$code,(New-Object System.Text.UTF8Encoding($false)))
  Must $python @($render,$source,$preview)
  Write-Host 'Preparing current published site...' -ForegroundColor Cyan
  Must 'git' @('clone','--depth','1','--filter=blob:none','--sparse','--branch','main',$repo,$work)
  Must 'git' @('-C',$work,'sparse-checkout','set','--no-cone','/index.html','/flutter_bootstrap-RIYAD20261123-UX1.js','/main-RIYAD20261123-UX1.dart.js','/assets/assets/web_books/dua-8_page_0001.jpg','/assets/assets/web_books/swalath-3_page_0003.jpg','/assets/assets/web_books/maashara_page_0001.jpg','/assets/assets/books/maashara.pdf')
  if(-not(Test-Path -LiteralPath (Join-Path $work $new)) -or -not(Test-Path -LiteralPath (Join-Path $work 'main-RIYAD20261123-UX1.dart.js'))){throw 'Prepared UX release is missing; site was not changed.'}
  foreach($f in @('assets/assets/web_books/dua-8_page_0001.jpg','assets/assets/web_books/swalath-3_page_0003.jpg')){
    if(-not(Test-Path -LiteralPath (Join-Path $work $f))){throw ('Previous book image missing: '+$f)}
  }
  $pdfDest=Join-Path $work 'assets\assets\books\maashara.pdf'
  $imageDest=Join-Path $work 'assets\assets\web_books\maashara_page_0001.jpg'
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $pdfDest),(Split-Path -Parent $imageDest)|Out-Null
  Copy-Item -LiteralPath $source -Destination $pdfDest -Force
  Copy-Item -LiteralPath $preview -Destination $imageDest -Force
  if((Get-FileHash -LiteralPath $pdfDest -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected){throw 'PDF verification failed.'}
  $indexFile=Join-Path $work 'index.html'
  $html=Get-Content -LiteralPath $indexFile -Encoding UTF8 -Raw
  if($html.Contains($old)){
    [System.IO.File]::WriteAllText($indexFile,$html.Replace($old,$new),(New-Object System.Text.UTF8Encoding($false)))
  } elseif(-not $html.Contains($new)){throw 'Unexpected homepage version; changes not published.'}
  Must 'git' @('-C',$work,'config','--local','user.name','darulswalathhifzulquran-sketch')
  Must 'git' @('-C',$work,'config','--local','user.email','316104416+darulswalathhifzulquran-sketch@users.noreply.github.com')
  Must 'git' @('-C',$work,'add','-f','--','index.html','assets/assets/books/maashara.pdf','assets/assets/web_books/maashara_page_0001.jpg')
  Must 'git' @('-C',$work,'diff','--cached','--check')
  $diff=Native 'git' @('-C',$work,'diff','--cached','--quiet') -quiet
  if($diff -eq 1){
    Must 'git' @('-C',$work,'commit','-m','Publish original Maashar PDF and activate Riyadul Adkar UX updates')
    Must 'git' @('-C',$work,'pull','--rebase','origin','main')
    Must 'git' @('-C',$work,'push','origin','main')
  } elseif($diff -ne 0){throw 'Unable to verify staged changes.'}
  Write-Host 'SUCCESS: GitHub Pages update pushed.' -ForegroundColor Green
  Write-Host 'https://darulswalathhifzulquran-sketch.github.io/riyadul-adkar/'
  Write-Host 'No Flutter build or run required.'
} catch {
  Write-Host ('PUBLISH NOT COMPLETED: '+$_.Exception.Message) -ForegroundColor Red
  Write-Host ('Temporary folder: '+$tmp)
}
