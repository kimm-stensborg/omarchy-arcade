# shellcheck shell=bash
# arcade-launcher: the menu, a direct launch, --list, --help.
# Sourced by bin/arcade-launcher, in the order it lists; not run on its own.

# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------

usage() {
  cat <<EOF
$PROGRAM $VERSION - arcade quick-launcher for RetroArch

Usage:
  $PROGRAM                  Show the menu and launch the selected game
  $PROGRAM <romname>        Launch a game directly, e.g. "$PROGRAM bublbobl"
  $PROGRAM --list           Print "title<TAB>path<TAB>played<TAB>playing<TAB>db title<TAB>year<TAB>maker
                            <TAB>favourite<TAB>plays<TAB>genre<TAB>players<TAB>orientation<TAB>problem
                            <TAB>family (the parent set, when FinalBurn Neo knows the game)<TAB>missing"
                            Favourites you do not have yet are listed too, marked "missing"
  $PROGRAM --list --all     The same, with every game FinalBurn Neo knows that you do not have
  $PROGRAM --check [--all] [ROM...]
                            Test-load the games (all of ROM_DIR by default) and remember
                            which start; --all checks again ones already checked
  $PROGRAM --game ROM       Print one game's own settings: title, artwork, picture, controls
  $PROGRAM --game-set ROM KEY=VALUE...
                            Change them (empty = back to the shared setting). Keys:
                            TITLE, ART (titles snaps boxarts custom), SHADER (none or a
                            preset), SMOOTH (smooth sharp), ASPECT (core 4:3 full square),
                            INTEGER (on off), ROTATE (0 90 180 270), or a control id
  $PROGRAM --game-image ROM FILE
                            Use a PNG or JPEG of your own for the game's tile
  $PROGRAM --pick-image     Choose a picture in a file chooser; prints its path
  $PROGRAM --favourite ROM...   Make games favourites, e.g. "--favourite bublbobl"
  $PROGRAM --unfavourite ROM... Take them off the favourites again
  $PROGRAM --doctor         Check the setup and print what is missing
  $PROGRAM --rebuild-titles Rebuild the title cache from the libretro databases
  $PROGRAM --config         Print the resolved configuration
  $PROGRAM --settings       Print "KEY<TAB>value<TAB>source" for every setting
  $PROGRAM --set KEY=VALUE  Write a setting to the config file (empty = unset)
  $PROGRAM --controls       Print "control<TAB>key<TAB>source" for the cabinet binds
  $PROGRAM --set-control ID=KEY
                            Bind one control, e.g. coin1=num5 (empty = unbind)
  $PROGRAM --add FILE...    Copy romsets into ROM_DIR, test that each runs, keep
                            the ones that do, fetch their artwork. A folder
                            stands for the romsets in it
  $PROGRAM --pick           Choose romsets in a file chooser; prints their paths
  $PROGRAM --stop           Close the game this launcher started (1: none running,
                            72: a RetroArch started some other way is left alone)
  $PROGRAM --controller     Print the game controller RetroArch will use, its
                            profile, and which of its buttons does what
  $PROGRAM --controller --follow
                            Stream its presses, through unplugging and replugging
  $PROGRAM --controls-preset mame|retroarch
                            Write a whole control layout
  $PROGRAM --help           Show this help
  $PROGRAM --version        Show the version

Configuration ($CONFIG_FILE, or the environment):
  ROM_DIR           Directory scanned for ROMs (default: ~/Games/roms)
  ROM_EXTS          Space-separated extensions to look for (default: zip 7z chd)
  CORE_PATH         libretro core .so (default: autodetected, FBNeo then MAME)
  RETROARCH_CONFIG  Optional retroarch.cfg passed as --config
  MENU_CMD          dmenu-style command (default: wofi, then rofi, then fuzzel)
  TITLES_FILE       TSV of "romname<TAB>Title" overrides
  CACHE_FILE        Generated title cache
  LOG_FILE          RetroArch output log (default: ~/.cache/omarchy/arcade.log)
  ARTWORK           on | off - whether tiles may be fetched from the network
  ART_KINDS         Artwork preference order (default: titles snaps boxarts)
  ART_DIR           Where artwork is cached
  TILE_SIZE         Overlay only: width a game tile aims for, in pixels
  MAX_COLUMNS       Overlay only: most tiles the wall puts in a row
  SORT_BY           Overlay only: last played | favourites | most played | name | year
  ATTRACT_AFTER     Overlay only: seconds of no input before title screens cycle (off = never)
  GROUP_VERSIONS    Overlay only: on | off - one tile per game, Tab for its versions

Controls are kept in ~/.config/omarchy/arcade-retroarch.cfg, which RetroArch
loads on top of its own config for arcade games only (--appendconfig), so your
everyday RetroArch keeps its own binds and the arcade keeps up with the rest.
EOF
}

show_config() {
  cat <<EOF
CONFIG_FILE=$CONFIG_FILE $([[ -r "$CONFIG_FILE" ]] && echo "(loaded)" || echo "(absent)")
ROM_DIR=$ROM_DIR
ROM_EXTS=$ROM_EXTS
CORE_PATH=${CORE_PATH:-<none found>}
RETROARCH_CONFIG=${RETROARCH_CONFIG:-<retroarch default>}
MENU_CMD=${MENU_CMD:-<none found>}
TITLES_FILE=$TITLES_FILE
CACHE_FILE=$CACHE_FILE
LOG_FILE=$LOG_FILE
ARTWORK=$ARTWORK ($(find "$ART_DIR" -maxdepth 1 -name '*.png' 2>/dev/null | wc -l) images cached in $ART_DIR)
EOF
}
