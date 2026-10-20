# Installs Cadex on this Windows 11 (docs/adr/0007-one-step-install.md):
#
#   irm https://github.com/c4duZ/cadex/releases/latest/download/install.ps1 | iex
#
# Downloads the latest Cadex-windows-<arch>.zip and its checksum from the
# GitHub release, checks it, and puts Cadex in %LOCALAPPDATA%\Programs\Cadex
# with a Start menu shortcut and an entry in Settings > Apps for removing it.
# No administrator, nothing else is downloaded. CADEX_DOWNLOAD (a URL or a
# folder) and CADEX_INSTALL_DIR override the source and the destination, for
# testing this script.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # the progress bar makes Invoke-WebRequest many times slower

# throw, not exit: under `irm | iex` an exit closes the user's window.
function Fail($message) {
    throw "cadex: $message"
}

$base = if ($env:CADEX_DOWNLOAD) { $env:CADEX_DOWNLOAD } else { 'https://github.com/c4duZ/cadex/releases/latest/download' }
$dest = if ($env:CADEX_INSTALL_DIR) { $env:CADEX_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'Programs\Cadex' }

if ([Environment]::OSVersion.Version.Build -lt 22000) { Fail 'o Cadex precisa do Windows 11' }
# An x64 PowerShell on an ARM machine says AMD64; PROCESSOR_ARCHITEW6432 has the real one.
$machine = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
$arch = switch ($machine) {
    'ARM64' { 'arm64' }
    'AMD64' { 'x64' }
    default { Fail "processador sem build do Cadex: $machine" }
}
$zipName = "Cadex-windows-$arch.zip"

$work = Join-Path ([IO.Path]::GetTempPath()) ("cadex-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $work | Out-Null
try {
    function Fetch($name) {
        $to = Join-Path $work $name
        if ($base -match '^https?://') {
            try { Invoke-WebRequest -UseBasicParsing -Uri "$base/$name" -OutFile $to } catch { Fail "não consegui baixar $base/$name" }
        } else {
            try { Copy-Item (Join-Path $base $name) $to } catch { Fail "não achei $base\$name" }
        }
        $to
    }

    Write-Host 'Baixando o Cadex...'
    $zip = Fetch $zipName
    $sums = Fetch "$zipName.sha256"
    $expected = ((Get-Content $sums -Raw).Trim() -split '\s+')[0].ToLower()
    $actual = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
    if ($expected -ne $actual) { Fail 'o download veio diferente do publicado (checksum não confere); nada foi instalado' }

    Expand-Archive -Path $zip -DestinationPath (Join-Path $work 'app')
    $unpacked = Join-Path $work 'app\Cadex'
    if (-not (Test-Path (Join-Path $unpacked 'Cadex.exe'))) { Fail 'o arquivo baixado não tem o Cadex.exe' }

    if (Get-Process -Name Cadex -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$dest\*" }) {
        Fail 'feche o Cadex antes de atualizar'
    }
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
    Move-Item $unpacked $dest
    # Downloaded files carry the internet mark; only Cadex's lose it, so it
    # opens without the SmartScreen question for files from the browser.
    Get-ChildItem -Recurse $dest | Unblock-File
    $exe = Join-Path $dest 'Cadex.exe'

    if (-not $env:CADEX_INSTALL_DIR) {
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'Cadex.lnk'))
        $link.TargetPath = $exe
        $link.WorkingDirectory = $env:USERPROFILE
        $link.IconLocation = "$exe,0"
        $link.Save()

        # Settings > Apps lists it for this user, with a way out that removes
        # the folder, the shortcut and this entry (the user's files in
        # %APPDATA%\Cadex stay).
        $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Cadex'
        $remove = "Stop-Process -Name Cadex -ErrorAction SilentlyContinue; Remove-Item -Recurse -Force '$dest'; Remove-Item -Force '$([Environment]::GetFolderPath('Programs'))\Cadex.lnk' -ErrorAction SilentlyContinue; Remove-Item -Recurse -Force '$key'"
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($remove))
        New-Item -Path $key -Force | Out-Null
        $version = (Get-Item $exe).VersionInfo.ProductVersion
        Set-ItemProperty -Path $key -Name DisplayName -Value 'Cadex'
        Set-ItemProperty -Path $key -Name DisplayVersion -Value $version
        Set-ItemProperty -Path $key -Name Publisher -Value 'Cadex'
        Set-ItemProperty -Path $key -Name DisplayIcon -Value "$exe,0"
        Set-ItemProperty -Path $key -Name InstallLocation -Value $dest
        Set-ItemProperty -Path $key -Name UninstallString -Value "powershell.exe -NoProfile -WindowStyle Hidden -EncodedCommand $encoded"
        Set-ItemProperty -Path $key -Name NoModify -Value 1 -Type DWord
        Set-ItemProperty -Path $key -Name NoRepair -Value 1 -Type DWord
        Set-ItemProperty -Path $key -Name EstimatedSize -Value ([int]((Get-ChildItem -Recurse $dest | Measure-Object Length -Sum).Sum / 1KB)) -Type DWord
    }

    Write-Host "Cadex instalado em $dest"
    Write-Host 'Para abrir: Menu Iniciar > Cadex, ou'
    Write-Host "  & `"$exe`""
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
