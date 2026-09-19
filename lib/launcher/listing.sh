# shellcheck shell=bash
# arcade-launcher: finding romsets and listing the library.
# Sourced by bin/arcade-launcher, in the order it lists; not run on its own.

# --------------------------------------------------------------------------
# ROM listing
# --------------------------------------------------------------------------

find_roms() {
  local -a find_args=()
  local ext first=1

  for ext in $ROM_EXTS; do
    if ((first)); then
      find_args+=(-iname "*.${ext}")
      first=0
    else
      find_args+=(-o -iname "*.${ext}")
    fi
  done

  find "$ROM_DIR" -maxdepth 2 -type f \( "${find_args[@]}" \) -print
}

# BIOS and device sets have to sit next to the games that need them, but are
# not games: launching one boots to nothing. Most say so in their database
# title ("PGM (Polygame Master) System BIOS", "NMK004 Internal ROM"); these are
# the common ones whose title does not.
readonly BIOS_SETS=(
  neogeo neocdz qsound cpzn1 cpzn2 coh1000a coh1000c coh1000t coh1000w
  coh1001l coh1002e coh1002m coh1002v coh3002c coh3002t tps taitofx1
  konamigx naomi naomi2 awbios hod2bios hng64 chihiro triforce segasp
  galgbios
)

# Emit "Display title<TAB>/path/to/rom.zip", sorted case-insensitively by title.
# ROMs with no mapping keep their bare filename rather than a guessed title.
# BIOS sets are left out; a title of your own in arcade-titles.tsv that does
# not end in "BIOS" brings one back.
#
# More columns ride along for the panel: when the game was last played (an
# epoch, empty if never), "playing" for the one running right now, the
# database's own title (which may differ from the one shown), and its year and
# maker. A dmenu only ever sees the first.
# The library as lines, installed games first. `catalogue` adds the games
# FinalBurn Neo knows that are not in ROM_DIR, marked "missing" in the last
# column with the bare ROM name for a path: "wishlist" only the ones you made
# favourites, "all" every one. The menu passes nothing -- it can only launch.
build_menu_lines() {
  local catalogue="${1-}" playing=""
  playing="$(running_game | cut -f2)"
  seed_history
  {
    [[ -r "$FAVOURITES_FILE" ]] && sed 's/^/\x1d\t/' -- "$FAVOURITES_FILE"
    [[ -r "$GAMEINFO_FILE" ]] && grep -v '^#' -- "$GAMEINFO_FILE" | sed 's/^/\x1b\t/'
    check_lines | sed 's/^/\x1a\t/' 
    [[ -r "$HISTORY_FILE" ]] && cat -- "$HISTORY_FILE"
    printf '\036\n'
    title_sources
    printf '\034\n'
    find_roms
  } | awk -F'\t' -v bios_sets="${BIOS_SETS[*]}" -v playing="$playing" -v catalogue="$catalogue" '
    BEGIN {
      n_bios = split(bios_sets, names, " ")
      for (i = 1; i <= n_bios; i++) listed[names[i]] = 1
      section = -1
    }
    section < 0 && $0 == "\036" { section = 0; next }
    section < 0 && $1 == "\035" { if ($2 != "") starred[$2] = 1; next }
    section < 0 && $1 == "\033" {
      genre[$2] = $3; players[$2] = $4; orient[$2] = $5; parent[$2] = $6; known[$2] = 1
      fbtitle[$2] = $7; fbyear[$2] = $8; fbmaker[$2] = $9
      next
    }
    section < 0 && $1 == "\032" { if ($3 == "broken") problem[$2] = $4; next }
    section < 0 {
      if (NF < 2) next
      if ($1 + 0 > played[$2] + 0) played[$2] = $1
      plays[$2] += (NF >= 3 && $3 + 0 > 0) ? $3 : 1
      next
    }
    section < 2 && $0 == "\035" { section = 1; next }
    section < 2 && $0 == "\037" { database = 1; next }
    section < 2 && $0 == "\034" { section = 2; next }
    section < 2 {
      if (database && NF >= 2 && !($1 in dbtitle)) { dbtitle[$1] = $2; dbyear[$1] = $3; dbmaker[$1] = $4 }
      # First source wins, so a title of your own decides for the database.
      if (NF >= 2 && !($1 in title)) {
        title[$1] = $2
        if (section == 0) own[$1] = 1
        low = tolower($2)
        if (low ~ /bios\)?$/ || low ~ /internal p?rom$/) bios[$1] = 1
      }
      next
    }
    {
      path = $0
      base = path
      sub(/.*\//, "", base)
      rom = base
      sub(/\.[^.]*$/, "", rom)
      if ((rom in bios) || ((rom in listed) && !(rom in own))) next
      label = (rom in title) ? title[rom] : rom
      # The MAME database writes "&" as "_", which is not how the game spells it.
      gsub(/ _ /, " \\& ", label)

      n++
      labels[n] = label
      roms[n] = rom
      paths[n] = path
      seen[label]++
    }
    END {
      for (i = 1; i <= n; i++) {
        # Two ROMs can share a title (a parent and its clone). Tag both with the
        # ROM name so the menu stays unambiguous and the right file gets launched.
        label = (seen[labels[i]] > 1) ? labels[i] " (" roms[i] ")" : labels[i]
        emit(label, paths[i], roms[i], played[paths[i]], (paths[i] == playing ? "playing" : ""), \
             plays[paths[i]], problem[paths[i]], "")
        installed[roms[i]] = 1
      }
      if (catalogue == "") exit
      # The rest of what FBNeo knows. A title of your own or a shipped one
      # first, as for an installed game; otherwise the database title with its
      # brackets off -- versions group into one tile, and the full name with
      # its region is the facts line.
      for (r in known) {
        if (r in installed) continue
        if (catalogue != "all" && !(r in starred)) continue
        label = (r in title) ? title[r] : (dbtitle[r] != "" ? dbtitle[r] : fbtitle[r])
        if (!(r in own)) { while (sub(/ *[\(\[][^\(\)\[\]]*[\)\]] *$/, "", label)) {} }
        gsub(/ _ /, " \\& ", label)
        if (label == "") label = r
        emit(label, r, r, "", "", "", "", "missing")
      }
    }
    function emit(label, path, rom, last, running, count, trouble, missing) {
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", label, path, last, running, \
        (dbtitle[rom] != "" ? dbtitle[rom] : fbtitle[rom]), (dbyear[rom] != "" ? dbyear[rom] : fbyear[rom]), \
        (dbmaker[rom] != "" ? dbmaker[rom] : fbmaker[rom]), ((rom in starred) ? "favourite" : ""), count, \
        genre[rom], players[rom], orient[rom], trouble, \
        ((rom in known) ? (parent[rom] != "" ? parent[rom] : rom) : ""), missing
    }
  ' | sort -f -t $'\t' -k1,1
}
