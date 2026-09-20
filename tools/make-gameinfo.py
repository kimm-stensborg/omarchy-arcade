#!/usr/bin/env python3
"""Build share/arcade-gameinfo.tsv from FinalBurn Neo's driver sources.

The libretro databases name a game, its year and its maker, and stop there.
FBNeo's own driver table also says what kind of game it is, how many play at
once and whether its screen stands on its side -- the facts the panel filters
by. This reads them straight out of the source, once, into a small table that
ships with the plugin:

    rom<TAB>genre<TAB>players<TAB>orientation<TAB>parent<TAB>title<TAB>year<TAB>maker

genre is one or more of the labels below joined with " / ", players a number,
orientation "vertical" or "horizontal", and parent the set this one is a
version of ("bublboblu" is a version of "bublbobl"), empty for a parent.
title, year and maker are FBNeo's own, for the games the libretro database
does not name -- the panel can list every game, not only the ones you have. Run it against a checkout of FBNeo
(only src/burn is needed) when the table should catch up with new drivers:

    git clone --depth 1 --filter=blob:none --sparse https://github.com/libretro/FBNeo.git
    git -C FBNeo sparse-checkout set --no-cone /src/burn/drv/ /src/burn/burn.h
    tools/make-gameinfo.py FBNeo > share/arcade-gameinfo.tsv
"""

import os
import re
import sys

# FBNeo's GBF_* genre flags, as the panel says them.
GENRES = {
    "GBF_HORSHOOT": "Horizontal shooter",
    "GBF_VERSHOOT": "Vertical shooter",
    "GBF_SCRFIGHT": "Beat 'em up",
    "GBF_VSFIGHT": "Fighting",
    "GBF_BREAKOUT": "Breakout",
    "GBF_CASINO": "Casino",
    "GBF_BALLPADDLE": "Ball & paddle",
    "GBF_MAZE": "Maze",
    "GBF_MINIGAMES": "Mini-games",
    "GBF_PINBALL": "Pinball",
    "GBF_PLATFORM": "Platform",
    "GBF_PUZZLE": "Puzzle",
    "GBF_QUIZ": "Quiz",
    "GBF_SPORTSMISC": "Sports",
    "GBF_SPORTSFOOTBALL": "Football",
    "GBF_MISC": "Misc",
    "GBF_MAHJONG": "Mahjong",
    "GBF_RACING": "Racing",
    "GBF_SHOOT": "Shooter",
    "GBF_MULTISHOOT": "Multi-directional shooter",
    "GBF_ACTION": "Action",
    "GBF_RUNGUN": "Run & gun",
    "GBF_STRATEGY": "Strategy",
    "GBF_VECTOR": "Vector",
    "GBF_RPG": "RPG",
    "GBF_SIM": "Simulation",
    "GBF_ADV": "Adventure",
    "GBF_CARD": "Card",
    "GBF_BOARD": "Board",
}

DRIVER = re.compile(r"struct\s+BurnDriver(?:D|X)?\s+BurnDrv\w+\s*=\s*\{(.*?)\};", re.S)


def fields(body):
    """Top-level comma-separated fields of a C initializer, strings kept whole."""
    out, cur, depth, quote, i = [], [], 0, False, 0
    body = re.sub(r"//[^\n]*|/\*.*?\*/", "", body, flags=re.S)
    while i < len(body):
        c = body[i]
        if quote:
            cur.append(c)
            if c == "\\" and i + 1 < len(body):
                cur.append(body[i + 1]); i += 1
            elif c == '"':
                quote = False
        elif c == '"':
            quote = True; cur.append(c)
        elif c in "({":
            depth += 1; cur.append(c)
        elif c in ")}":
            depth -= 1; cur.append(c)
        elif c == "," and depth == 0:
            out.append("".join(cur).strip()); cur = []
        else:
            cur.append(c)
        i += 1
    if "".join(cur).strip():
        out.append("".join(cur).strip())
    return out


def main(root):
    drv = os.path.join(root, "src", "burn", "drv")
    rows = {}
    for dirpath, _, files in os.walk(drv):
        # Consoles and computers live beside the arcade drivers; the arcade
        # plays none of them.
        rel = os.path.relpath(dirpath, drv).split(os.sep)[0]
        if rel in ("channelf", "coleco", "megadrive", "msx", "nes", "pce", "sg1000", "sms", "snes",
                   "spectrum", "cv", "gg", "fds", "ngp", "gba", "atari2600", "atari7800", "lynx"):
            continue
        for name in files:
            if not name.endswith(".cpp"):
                continue
            with open(os.path.join(dirpath, name), encoding="latin-1") as fh:
                text = fh.read()
            for m in DRIVER.finditer(text):
                f = fields(m.group(1))
                if len(f) < 17 or not f[0].startswith('"'):
                    continue
                rom = f[0].strip('"')
                parent = f[1].strip('"') if f[1].startswith('"') else ""
                def text(field):
                    if not field.startswith('"'):
                        return ""
                    # Adjacent literals ("Foo" "Bar") and the trailing \0 FBNeo ends names with.
                    joined = "".join(re.findall(r'"((?:\\.|[^"\\])*)"', field))
                    return joined.replace("\\0", "").replace('\\"', '"').replace("\\'", "'").replace("\t", " ").strip()
                title, year, maker = text(f[5]), text(f[4]), text(f[7])
                flags, players, genre = f[13], f[14], f[16]
                if "BDF_GAME_WORKING" not in flags or "BDF_BOARDROM" in flags:
                    continue
                labels = [GENRES[g] for g in re.findall(r"GBF_\w+", genre) if g in GENRES]
                n = players if players.isdigit() else ""
                orient = "vertical" if "BDF_ORIENTATION_VERTICAL" in flags else "horizontal"
                rows[rom] = (" / ".join(labels), n, orient, parent, title, year, maker)
    sys.stdout.write(
        "# rom\tgenre\tplayers\torientation\tparent\ttitle\tyear\tmaker\n"
        "# Made by tools/make-gameinfo.py from FinalBurn Neo's driver table.\n"
        "# FinalBurn Neo (https://github.com/finalburnneo/FBNeo) is used under its\n"
        "# own licence, kept verbatim in licenses/fbneo-license.txt, which also\n"
        "# carries the MAME licence FBNeo is subject to. Game names belong to their\n"
        "# respective owners.\n")
    for rom in sorted(rows):
        sys.stdout.write("\t".join((rom,) + rows[rom]) + "\n")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: make-gameinfo.py FBNEO_CHECKOUT")
    sys.exit(main(sys.argv[1]))
