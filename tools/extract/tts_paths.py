"""Where Tabletop Simulator keeps its files on this machine.

Its own module so the tools that only need a path -- importing track edits
from a save, say -- do not have to pull in OpenCV with it.
"""
import os
import pathlib


def documents_dir():
    """The user's Documents folder, wherever Windows has put it.

    Often redirected (OneDrive), so ask the registry rather than assume
    ~/Documents.
    """
    try:
        import winreg
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                             r"Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders")
        value, _ = winreg.QueryValueEx(key, "Personal")
        return pathlib.Path(os.path.expandvars(value))
    except (ImportError, OSError):
        return pathlib.Path(os.path.expanduser("~")) / "Documents"


TTS_DIR = documents_dir() / "My Games" / "Tabletop Simulator"
MODS = pathlib.Path(os.environ.get("TTS_MODS", TTS_DIR / "Mods"))
