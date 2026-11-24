"""Run the released batch launchers against disposable Windows folders."""
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory


REPO = Path(__file__).resolve().parents[1]


def ps_literal(path):
    return "'" + str(path).replace("'", "''") + "'"


def stage(batch, target, downloads, history):
    source = (REPO / batch).read_text(encoding="ascii")
    bindings = {
        "$downloads = [SorterPaths]::Downloads()": "$downloads = " + ps_literal(downloads),
        r"Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'DownloadsFileSorter\History-v1'": ps_literal(history),
    }
    for original, replacement in bindings.items():
        if source.count(original) != 1:
            raise RuntimeError(f"Could not isolate {batch}. No batch file was run.")
        source = source.replace(original, replacement)
    with (target / batch).open("w", encoding="ascii", newline="\r\n") as handle:
        handle.write(source)


def run(folder, batch):
    result = subprocess.run(
        ["cmd.exe", "/d", "/c", batch], cwd=folder, input="\n",
        text=True, capture_output=True, check=True,
    )
    return result.stdout


def snapshot(root):
    return {p.relative_to(root): p.read_bytes() if p.is_file() else None
            for p in root.rglob("*")}


def test_round_trip():
    with TemporaryDirectory() as temporary:
        root = Path(temporary)
        downloads = root / "Downloads"
        scripts = downloads / "file sorter"
        history = root / "History"
        scripts.mkdir(parents=True)
        for batch in ("Sort.bat", "Undo.bat"):
            stage(batch, scripts, downloads, history)
        for name in ("clip.mp4", "notes [v2].txt", "Projects/nested.png",
                     "photo.jpg", "Images/photo.jpg", "active.crdownload"):
            file = downloads / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(name.encode())

        original = snapshot(downloads)
        run(scripts, "Sort.bat")
        assert (downloads / "Videos/clip.mp4").read_bytes() == b"clip.mp4"
        assert (downloads / "Text/notes [v2].txt").exists()
        assert (downloads / "photo.jpg").read_bytes() == b"photo.jpg"
        assert (downloads / "Images/photo.jpg").read_bytes() == b"Images/photo.jpg"
        assert (downloads / "Projects/nested.png").exists()
        assert (downloads / "active.crdownload").exists()
        (downloads / "clip.mp4").write_bytes(b"new download")
        assert "Pending: 1" in run(scripts, "Undo.bat")
        assert (downloads / "clip.mp4").read_bytes() == b"new download"
        assert (downloads / "Videos/clip.mp4").read_bytes() == b"clip.mp4"
        (downloads / "clip.mp4").rename(root / "new download.mp4")
        assert "Pending: 0" in run(scripts, "Undo.bat")
        assert original == snapshot(downloads)


if __name__ == "__main__":
    test_round_trip()
    print("Passed: sorting, filename conflicts, and a complete undo round trip.")
