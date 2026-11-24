<p align="center">
  <img src="assets/logo.png" alt="A yellow folder with an undo arrow" width="96" height="96">
</p>

# File Sorter

Give loose Windows downloads a home by file type. Double-click **Sort.bat** to organize them. Double-click **Undo.bat** to put them back, even after several sorting runs.

**[↓ Download Sort.bat](https://github.com/GurnoordeepSingh/File-sorter/raw/refs/heads/main/Sort.bat)** &nbsp;·&nbsp; **[↶ Download Undo.bat](https://github.com/GurnoordeepSingh/File-sorter/raw/refs/heads/main/Undo.bat)**

## Get started

1. Save both batch files in a folder such as `Downloads\file sorter`.
2. Double-click **Sort.bat**. The window shows the Windows Downloads path, how many files moved, and how many were skipped.
3. Open Downloads to see the result. To reverse the moves, double-click **Undo.bat** from the same Windows account.

Each batch file includes its PowerShell source. Windows PowerShell is the only runtime dependency.

## What moves?

| Before | After running Sort |
| --- | --- |
| `Downloads\recording.mp4` | `Downloads\Videos\recording.mp4` |
| `Downloads\photo.png` | `Downloads\Images\photo.png` |
| `Downloads\setup.exe` | `Downloads\Executables\setup.exe` |
| `Downloads\installer.msi` | `Downloads\Apps\installer.msi` |
| `Downloads\notes.txt` | `Downloads\Text\notes.txt` |
| `Downloads\Projects\draft.png` | Stays in its project folder |

The sorter checks loose files at the top of Downloads. It reuses existing category folders and creates new ones as needed. If a destination filename is already taken, the loose file stays where it was. It also skips hidden files, linked items, and common unfinished downloads such as `.crdownload` and `.part`.

## How undo works

Before each move, the sorter saves the original location and Windows file identity under `%LOCALAPPDATA%\DownloadsFileSorter\History-v1`. Keep that history while you want the option to undo. It contains bookkeeping records, not copies of your downloads.

**Undo.bat** restores all recorded moves it can and removes empty category folders that the sorter created. Files you added to those folders stay in place.

| Undo result | What to do |
| --- | --- |
| `Pending: 0` | Every available record has been resolved. |
| The original name is occupied | Move the newer file aside and run Undo again. |
| You moved or renamed a sorted file | Put it back under its sorted name in its category folder, then retry. |
| A different file now occupies the sorted path | Undo skips the replacement. Return the original file to that path before retrying. |

## Test the round trip

On Windows with Python 3 installed, run `py tests\round_trip.py` from the repository root. The test runs both batch files against temporary Downloads and history folders. It checks original paths and contents, duplicate names, and recovery after an undo conflict.
