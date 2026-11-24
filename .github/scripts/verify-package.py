"""Verify distribution archives/staging only; does not simulate the WoW client."""

import argparse
import os
from pathlib import Path, PurePosixPath
import subprocess
import zipfile


def git(*args):
    return subprocess.check_output(["git", *args], text=True, stderr=subprocess.PIPE).strip()


def expected_version():
    # Follow BigWigs Packager's tag selection and untagged build naming.
    tags = git("tag", "--points-at", "HEAD", "--sort=-committerdate",
               "--sort=-v:refname", "--sort=-taggerdate").splitlines()
    if tags:
        ref = os.environ.get("GITHUB_REF", "")
        selected = ref.removeprefix("refs/tags/")
        return selected if ref.startswith("refs/tags/") and selected in tags else tags[0]
    try:
        return git("describe", "--tags", "--abbrev=7",
                   "--exclude=*[Aa][Ll][Pp][Hh][Aa]*")
    except subprocess.CalledProcessError:
        return git("describe", "--tags", "--always", "--abbrev=7")


def verify(files, read):
    assert files, "Package is empty"
    assert len(files) <= 2048, f"Too many entries: {len(files)}"
    for name in files:
        path = PurePosixPath(name)
        assert not path.is_absolute() and ".." not in path.parts, name
        assert path.parts[0] == "Merlin", f"Unexpected top-level entry: {name}"
        assert path.suffix.lower() != ".zip", f"Nested ZIP: {name}"
        assert not any(part.startswith(".") for part in path.parts), f"Dotfile: {name}"
        assert len(name) <= 240 and all(len(part) <= 120 for part in path.parts), f"Path too long: {name}"
    lowered = [name.lower() for name in files]
    assert len(lowered) == len(set(lowered)), "Paths differ only in letter case"
    toc = read("Merlin/Merlin.toc").decode("utf-8-sig")
    lines = toc.splitlines()
    version = args.version or expected_version()
    assert f"## Version: {version}" in lines, f"Incorrect TOC version; expected {version}"
    assert "@project-version@" not in toc, "Unsubstituted version keyword"
    assert "## Interface: 16001" in lines, "Incorrect Forever interface"
    assert "## AllowLoadGameType: standard, camelot" in lines, "Load types changed"

    # Every tracked runtime file, library, asset and license must ship unchanged in name.
    tracked = git("ls-files").splitlines()
    for name in tracked:
        if name.startswith(".") or name.endswith(".md"):
            continue
        packaged = "Merlin/" + name
        assert packaged in files, f"Missing runtime file or license: {packaged}"
        if name.startswith(("Media/", "Libs/")) or name.startswith("LICENSE"):
            assert read(packaged) == Path(name).read_bytes(), f"Modified bundled file: {name}"
    forbidden = ("AGENTS.md", "worker.js", "index.html", "stylua.toml")
    for name in files:
        assert PurePosixPath(name).name not in forbidden, f"Development file: {name}"
    print(f"Verified Merlin/ layout, Forever TOC version {version}, runtime files and licenses.")


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--version", help="Expected explicit build version; defaults to BigWigs Git-derived version")
source = parser.add_mutually_exclusive_group(required=True)
source.add_argument("--archive", nargs="?", const="auto")
source.add_argument("--directory", type=Path)
args = parser.parse_args()
if args.directory:
    files = {p.relative_to(args.directory).as_posix() for p in args.directory.rglob("*")}
    verify(files, lambda name: (args.directory / name).read_bytes())
else:
    if args.archive == "auto":
        archives = list(Path(".release").glob("*.zip"))
        assert len(archives) == 1, f"Expected one addon ZIP, found {len(archives)}"
        archive = archives[0]
    else:
        archive = Path(args.archive)
    with zipfile.ZipFile(archive) as zipped:
        files = {entry.filename.rstrip("/") for entry in zipped.infolist()}
        verify(files, zipped.read)
