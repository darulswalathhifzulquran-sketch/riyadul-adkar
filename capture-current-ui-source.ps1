# Capture current local Flutter UI source to a separate review branch.
# Does not run Flutter, build, or change live app.
$ErrorActionPreference='Stop'
$root=(Get-Location).Path
if (-not (Test-Path -LiteralPath (Join-Path $root 'lib/main.dart'))) {
  $nested=Join-Path $root 'al_auradu'
  if (Test-Path -LiteralPath (Join-Path $nested 'lib/main.dart')) { $root=$nested }
}
if (-not (Test-Path -LiteralPath (Join-Path $root 'lib/main.dart'))) {
  Write-Host 'Open VS Code in the current al_auradu Flutter source folder and retry.' -ForegroundColor Red
  return
}
$files=@(Get-ChildItem -LiteralPath (Join-Path $root 'lib') -File -Filter '*.dart' -Recurse)
$sourceText=($files | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue }) -join [char]10
$matched=@('Other sections','About Jamia','About JAMIA','POWERED BY','P O W E R E D B Y','Powered by') | Where-Object { $sourceText.Contains($_) }
Write-Host ('Flutter source files: '+$files.Count+', UI markers: '+($matched -join ' / ')) -ForegroundColor Cyan
if (@($matched).Count -lt 2) {
  Write-Host 'This local Flutter source appears older than your live app. Nothing changed or uploaded.' -ForegroundColor Yellow
  return
}
$branch='assistant/riyadul-ui-'+(Get-Date -Format 'yyyyMMdd-HHmmss')
$temp=Join-Path $env:TEMP ('riyadul-ui-'+[guid]::NewGuid().ToString('N'))
function Git([string[]]$a) {
  $old=$ErrorActionPreference
  try {
    $ErrorActionPreference='Continue'
    & git @a 2>&1 | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw ('Git exit '+$LASTEXITCODE+': '+($a -join ' ')) }
  } finally { $ErrorActionPreference=$old }
}
try {
  Git @('clone','--depth','1','--filter=blob:none','--sparse','https://github.com/darulswalathhifzulquran-sketch/aurad.git',$temp)
  Git @('-C',$temp,'sparse-checkout','set','--no-cone','/al_auradu/lib/**','/al_auradu/web/**','/al_auradu/pubspec.yaml')
  Git @('-C',$temp,'switch','-c',$branch)
  $target=Join-Path $temp 'al_auradu'
  $lib=Join-Path $target 'lib'
  foreach($file in $files) {
    $rel=$file.FullName.Substring((Join-Path $root 'lib').Length).TrimStart('\','/')
    $dest=Join-Path $lib $rel
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $dest -Force
  }
  Copy-Item -LiteralPath (Join-Path $root 'pubspec.yaml') -Destination (Join-Path $target 'pubspec.yaml') -Force
  $webRoot=Join-Path $root 'web'
  if(Test-Path -LiteralPath $webRoot) {
    $destWeb=Join-Path $target 'web'
    New-Item -ItemType Directory -Force -Path $destWeb | Out-Null
    foreach($name in @('index.html','manifest.json')){
      $src=Join-Path $webRoot $name
      if(Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $destWeb $name) -Force }
    }
  }
  Git @('-C',$temp,'config','--local','user.name','darulswalathhifzulquran-sketch')
  Git @('-C',$temp,'config','--local','user.email','316104416+darulswalathhifzulquran-sketch@users.noreply.github.com')
  Git @('-C',$temp,'add','-A','--','al_auradu/lib','al_auradu/pubspec.yaml','al_auradu/web')
  Git @('-C',$temp,'diff','--cached','--check')
  Git @('-C',$temp,'commit','--allow-empty','-m','Capture current Riyadul Adkar Flutter UI for requested updates')
  Git @('-C',$temp,'push','-u','origin',$branch)
  Write-Host 'SUCCESS: Latest UI source copied to a separate GitHub branch.' -ForegroundColor Green
  Write-Host ('BRANCH: '+$branch)
  Write-Host ('https://github.com/darulswalathhifzulquran-sketch/aurad/tree/'+$branch)
  Write-Host 'Published website and main branch are unchanged.'
} catch {
  Write-Host ('SOURCE SNAPSHOT FAILED: '+$_.Exception.Message) -ForegroundColor Red
}
