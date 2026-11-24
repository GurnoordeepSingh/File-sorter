@echo off
setlocal DisableDelayedExpansion
set "DOWNLOAD_SORTER_BATCH=%~f0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -Command "$body=[IO.File]::ReadAllText($env:DOWNLOAD_SORTER_BATCH); $marker='# POWERSHELL SOURCE'; & ([scriptblock]::Create($body.Substring($body.LastIndexOf($marker)+$marker.Length))) -Mode Sort"
set "result=%errorlevel%"
pause
exit /b %result%
# POWERSHELL SOURCE
param([Parameter(Mandatory)][ValidateSet('Sort','Undo')][string]$Mode)
$ErrorActionPreference = 'Stop'

# Ask Windows for Downloads, including a Downloads folder redirected to another drive.
# File IDs follow local moves, so undo can recognize an edited file and skip a replacement.
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class SorterPaths {
    [DllImport("shell32.dll")]
    static extern int SHGetKnownFolderPath(ref Guid folder, uint flags, IntPtr token, out IntPtr path);
    public static string Downloads() {
        Guid folder = new Guid("374DE290-123F-4565-9164-39C4925E467B");
        IntPtr path;
        Marshal.ThrowExceptionForHR(SHGetKnownFolderPath(ref folder, 0, IntPtr.Zero, out path));
        try { return Marshal.PtrToStringUni(path); }
        finally { Marshal.FreeCoTaskMem(path); }
    }
    [StructLayout(LayoutKind.Sequential)]
    struct Info {
        public uint attributes, createdLow, createdHigh, accessLow, accessHigh,
                    writeLow, writeHigh, volume, sizeHigh, sizeLow, links, indexHigh, indexLow;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security,
                                            uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool GetFileInformationByHandle(SafeFileHandle handle, out Info info);
    public static string Identity(string path) {
        using (var handle = CreateFile(path, 0, 7, IntPtr.Zero, 3, 0x02200000, IntPtr.Zero)) {
            if (handle.IsInvalid) throw new Win32Exception();
            Info info;
            if (!GetFileInformationByHandle(handle, out info)) throw new Win32Exception();
            if ((info.attributes & 1024) != 0 || (info.indexHigh == 0 && info.indexLow == 0))
                throw new InvalidOperationException("Linked item or unsupported file identity: " + path);
            return String.Format("{0:X8}-{1:X8}{2:X8}-{3:X8}{4:X8}", info.volume,
                info.indexHigh, info.indexLow, info.createdHigh, info.createdLow);
        }
    }
}
'@

$groups = [ordered]@{
    Images = 'jpg jpeg jfif png gif bmp webp avif heic heif tif tiff svg ico raw cr2 cr3 nef dng arw'
    Videos = 'mp4 mkv mov avi m4v webm flv wmv mpg mpeg ts mts m2ts 3gp'
    Audio = 'mp3 wav flac aac m4a wma ogg oga opus aiff mid midi'
    Executables = 'exe com scr'
    Apps = 'msi msp msix msixbundle appx appxbundle appinstaller apk aab ipa dmg pkg deb rpm appimage'
    Text = 'txt md markdown log nfo rst'
    Documents = 'doc docx odt rtf pages tex'
    PDFs = 'pdf'
    Spreadsheets = 'xls xlsx xlsm ods csv tsv numbers'
    Presentations = 'ppt pptx pptm odp key'
    Archives = 'zip 7z rar tar gz bz2 xz tgz cab zst'
    Code = 'py ipynb java c cpp cc h hpp cs js jsx tsx mjs html htm css scss lua luau go rs rb php swift kt sql ps1 bat cmd sh vbs'
    Data = 'json jsonl xml yaml yml toml ini db sqlite parquet'
    Design = 'psd ai indd fig kra xcf aep prproj'
    '3D Models' = 'blend fbx obj stl gltf glb dae usd usdz'
    Fonts = 'ttf otf woff woff2'
    Books = 'epub mobi azw azw3 cbz cbr'
    Subtitles = 'srt vtt ass sub'
    'Disk Images' = 'iso img vhd vhdx'
}
$categories = @{}
foreach ($group in $groups.Keys) {
    foreach ($ext in $groups[$group].Split(' ')) { $categories[$ext] = $group }
}
function Get-Category([string]$name) {
    $ext = [IO.Path]::GetExtension($name).TrimStart('.').ToLowerInvariant()
    if (!$ext) { return 'No Extension' }
    if ($categories.ContainsKey($ext)) { return $categories[$ext] }
    if ($ext -match '^[a-z0-9_-]{1,40}$') { return ($ext.ToUpperInvariant() + ' Files') }
    return 'Other Files'
}
function Test-Leaf([string]$name) {
    return ($name -and $name -notin '.', '..' -and
            $name.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -lt 0 -and
            $name -eq $name.TrimEnd(' ', '.'))
}
function Save-Intent([string]$kind, [string]$category, [string]$name, [string]$identity, [string]$folderID) {
    $record = [ordered]@{ Root = $downloads; RootID = $rootID; Kind = $kind; Category = $category
                           Name = $name; Identity = $identity; FolderID = $folderID }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($record | ConvertTo-Json -Compress))
    $base = Join-Path $state ([Guid]::NewGuid().ToString('N'))
    $stream = [IO.File]::Open($base + '.tmp', 'CreateNew', 'Write', 'None')
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
    [IO.File]::Move($base + '.tmp', $base + '.json')
    return ($base + '.json')
}
function Invoke-Sort {
    $moved = 0
    $skipped = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $downloads -Force -File)) {
        try {
            # Keep category names available for an unambiguous one-click undo across runs.
            if ($groups.Contains($file.Name) -or $file.Name -in 'No Extension','Other Files' -or
                $file.Name -match '^[a-z0-9_-]{1,40} Files$') {
                $skipped++; Write-Host ("Skipped category name conflict: " + $file.Name); continue
            }
            if ($file.FullName -eq $env:DOWNLOAD_SORTER_BATCH -or $file.Name -in 'Sort.bat','Undo.bat' -or
                ($file.Attributes -band 1030) -or $file.Name -in 'desktop.ini','thumbs.db' -or
                $file.Extension -in '.crdownload','.part','.partial','.download','.tmp','.aria2','.opdownload' -or
                [IO.File]::Exists($file.FullName + '.aria2') -or !(Test-Leaf $file.Name)) {
                $skipped++; continue
            }
            $category = Get-Category $file.Name
            $folder = Join-Path $downloads $category
            if (![IO.Directory]::Exists($folder)) {
                # New-Item without -Force fails if another process created the folder first.
                $null = New-Item -Path $folder -ItemType Directory
                $id = [SorterPaths]::Identity($folder)
                $null = Save-Intent 'Directory' $category '' $id $id
            }
            $folderID = [SorterPaths]::Identity($folder)
            $target = Join-Path $folder $file.Name
            if (Test-Path -LiteralPath $target) { throw "Name already in $category." }
            $id = [SorterPaths]::Identity($file.FullName)
            $null = Save-Intent 'File' $category $file.Name $id $folderID
            [IO.File]::Move($file.FullName, $target)
            $moved++
        } catch { $skipped++; Write-Host ("Skipped {0} - {1}" -f $file.Name, $_.Exception.Message) }
    }
    Write-Host "Moved $moved file(s). Skipped $skipped. Run Undo.bat to restore your files."
}
function Restore-File($record) {
    if (!(Test-Leaf $record.Name) -or (Get-Category $record.Name) -ne $record.Category) {
        throw 'Invalid file record.'
    }
    $original = Join-Path $downloads $record.Name
    if (Test-Path -LiteralPath $original) {
        if ([SorterPaths]::Identity($original) -eq $record.Identity) { return $false }
        throw 'The original name is occupied. Free it and run Undo again.'
    }
    $folder = Join-Path $downloads $record.Category
    if ([SorterPaths]::Identity($folder) -ne $record.FolderID) { throw 'Category folder changed.' }
    $sorted = Join-Path $folder $record.Name
    if ([SorterPaths]::Identity($sorted) -ne $record.Identity) { throw 'This is a different file.' }
    [IO.File]::Move($sorted, $original)
    return $true
}
function Invoke-Undo {
    $restored = 0
    $pending = 0
    $dirs = @()
    $blocked = @{}
    foreach ($entry in @(Get-ChildItem -LiteralPath $state -Filter '*.json' -File)) {
        $record = $null
        try {
            $record = [IO.File]::ReadAllText($entry.FullName) | ConvertFrom-Json
            if ($record.Root -ne $downloads -or $record.RootID -ne $rootID) { throw 'Downloads location changed.' }
            if (!(Test-Leaf $record.Category)) { throw 'Invalid category.' }
            if ($record.Kind -eq 'Directory') {
                $dirs += @{ Log = $entry.FullName; Data = $record }
                continue
            }
            if ($record.Kind -ne 'File') { throw 'Invalid record.' }
            if (Restore-File $record) { $restored++ }
            [IO.File]::Delete($entry.FullName) # Only our own completed undo record.
        } catch {
            $pending++
            if ($record -and $record.Category) { $blocked[$record.Category] = $true }
            Write-Host ("Pending {0} - {1}" -f $record.Name, $_.Exception.Message)
        }
    }
    foreach ($entry in $dirs) {
        $record = $entry.Data
        if ($blocked.ContainsKey($record.Category)) { continue }
        try {
            $folder = Join-Path $downloads $record.Category
            if ([IO.Directory]::Exists($folder) -and [SorterPaths]::Identity($folder) -eq $record.Identity) {
                if ([IO.Directory]::GetFileSystemEntries($folder).Length -eq 0) {
                    [IO.Directory]::Delete($folder, $false) # Empty sorter-created directory only.
                }
            }
            [IO.File]::Delete($entry.Log)
        } catch { $pending++; Write-Host ("Pending {0} - {1}" -f $record.Category, $_.Exception.Message) }
    }
    Write-Host "Restored $restored file(s). Pending: $pending."
}
$lock = $null
try {
    $downloads = [SorterPaths]::Downloads()
    if (![IO.Directory]::Exists($downloads)) { throw 'Windows Downloads folder is unavailable.' }
    $rootID = [SorterPaths]::Identity($downloads)
    $state = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'DownloadsFileSorter\History-v1'
    $null = [IO.Directory]::CreateDirectory($state)
    $lock = [IO.File]::Open((Join-Path $state 'session.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    Write-Host "Downloads folder: $downloads"
    if ($Mode -eq 'Sort') { Invoke-Sort } else { Invoke-Undo }
} catch {
    Write-Host ("Stopped - " + $_.Exception.Message)
    exit 1
} finally { if ($lock) { $lock.Dispose() } }
