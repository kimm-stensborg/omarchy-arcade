import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Arcade launcher. A wall of title screens, one per ROM, with a line to type
// in above it; Enter boots the selection into RetroArch. The panel knows
// nothing about ROMs or cores: bin/arcade-launcher lists and launches,
// bin/arcade-artwork fetches the art, and when the launcher finds something
// missing its report is shown here in place of the wall.
Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "io.github.kimm-stensborg.arcade"
  // The registry hands every plugin its own source directory, so the scripts
  // are found wherever the plugin was installed rather than at a path
  // hardcoded from the id.
  readonly property string pluginDir: root.manifest && root.manifest.__sourceDir
    ? String(root.manifest.__sourceDir)
    : Quickshell.env("HOME") + "/.config/omarchy/plugins/" + root.pluginId
  readonly property string launcher: root.pluginDir + "/bin/arcade-launcher"
  readonly property string artworkTool: root.pluginDir + "/bin/arcade-artwork"
  readonly property string home: Quickshell.env("HOME")

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property var games: []
  property bool loaded: false
  property bool loading: false
  // rom -> image path, or "" for a game the thumbnail server has nothing for.
  // Filled in as arcade-artwork reports, so tiles dress themselves while the
  // grid is already on screen.
  property var artMap: ({})
  // What the launcher said when it could not produce a list: no core, no ROMs,
  // no RetroArch. Shown in place of the wall, because an empty panel would be
  // a worse lie than the problem itself.
  property string problemReport: ""
  property string statusMessage: ""

  readonly property var rows: Model.filterGames(root.games, root.filterText)
  readonly property var selected: root.selectedIndex >= 0 && root.selectedIndex < root.rows.length
    ? root.rows[root.selectedIndex]
    : null
  readonly property bool hasProblem: root.problemReport.length > 0

  // Theme: shares the [menu] surface tokens, so a theme that styles the
  // Omarchy menu styles this panel too.
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color borderColor: Color.menu.border
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", borderColor, Math.max(1, Style.space(2)))
  readonly property color scrim: Color.menu.scrim
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property color accent: Color.accent
  readonly property color tileSurface: Util.alpha(root.foreground, 0.06)
  readonly property color tileBorder: Util.alpha(root.foreground, 0.10)
  // Arcade art is a CRT picture: it wants a black surround in any theme, the
  // way a cabinet bezel does.
  readonly property color artWell: "#07070b"
  readonly property int cornerRadius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily
  // The panel is mostly artwork, so it gets room to breathe: a tight margin
  // makes a wall of screenshots look like a contact sheet.
  readonly property int contentMargin: Math.max(Style.spacing.panelPadding, Style.space(20))
  readonly property int contentSpacing: Math.max(Style.spacing.md, Style.space(14))
  readonly property int headerHeight: Math.max(Style.space(44), Style.font.title + Style.spacing.controlPaddingY * 2)
  readonly property int footerHeight: Math.max(Style.space(60), Style.font.heading + Style.font.caption + Style.space(18))

  readonly property int tileSpacing: Style.space(16)
  // Title screens want room. The panel takes most of the screen and the tiles
  // aim for roughly 300px each, capped at six across so a wide monitor gets
  // bigger art rather than more of it.
  readonly property int targetTileWidth: Math.max(Style.space(300), 240)
  readonly property int cardWidth: Math.min(panel.width - Style.gapsOut * 2,
    Math.max(Style.space(1180), Math.round(panel.width * 0.72)))
  readonly property int cardHeight: Math.min(panel.height - Style.gapsOut * 2,
    Math.max(Style.space(760), Math.round(panel.height * 0.78)))
  readonly property int columns: Model.columnsFor(grid.width, root.targetTileWidth, root.tileSpacing, 6)
  readonly property int cellWidth: root.columns > 0 ? Math.floor(grid.width / root.columns) : root.targetTileWidth
  // 4:3 for the art, plus two lines of label underneath. Arcade screens are
  // that shape, so anything else would letterbox every tile.
  readonly property int cellHeight: Math.round((root.cellWidth - root.tileSpacing) * 0.75)
    + Style.font.body + Style.font.caption + Style.space(22) + root.tileSpacing

  // ------------------------------------------------------------- lifecycle

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    root.opened = true
    root.filterText = payload.filter ? String(payload.filter) : ""
    root.selectedIndex = 0
    root.statusMessage = ""
    root.refresh()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  // The library is re-read on every open: ROMs get added between sessions, and
  // a stale list would offer a game that is no longer there.
  function refresh() {
    if (listProc.running) return "busy"
    root.loading = true
    listProc.running = true
    return "ok"
  }

  function ping() { return "ok" }

  // ---------------------------------------------------------------- artwork

  // Ask about what is on screen first, then the rest of the library. Cached
  // images come back in the same breath as the request, so a second open is
  // dressed before it is drawn.
  function requestArt() {
    if (artProc.running || root.games.length === 0) return
    var wanted = Model.artWanted(root.artMap, root.rows, 24)
    if (wanted.length === 0) wanted = Model.artWanted(root.artMap, root.games, 24)
    if (wanted.length === 0) return
    artProc.command = [root.artworkTool].concat(wanted)
    artProc.running = true
  }

  onGamesChanged: root.requestArt()
  onRowsChanged: root.requestArt()

  // ------------------------------------------------------------- navigation

  function moveBy(delta) {
    if (root.rows.length === 0) return
    pointerGate.reset()
    root.setSelected(Model.gridTarget(root.selectedIndex, delta, root.rows.length))
  }

  function setSelected(index) {
    root.selectedIndex = Model.clampIndex(index, root.rows.length)
    Qt.callLater(function() { grid.positionViewAtIndex(root.selectedIndex, GridView.Contain) })
  }

  function setFilter(next) {
    root.filterText = next
    // Any edit re-aims at the best match rather than keeping a tile that the
    // new filter may have pushed somewhere else entirely.
    root.selectedIndex = 0
    pointerGate.reset()
    Qt.callLater(function() { grid.positionViewAtIndex(0, GridView.Beginning) })
  }

  // ---------------------------------------------------------------- actions

  function launch(game) {
    if (!game) return
    launchProc.command = [root.launcher, game.path]
    launchProc.running = true
    root.statusMessage = "Starting " + game.title + "…"
    // Close immediately: RetroArch takes a second or two to appear, and a
    // panel sitting on top of a game that is about to go fullscreen is worse
    // than one that got out of the way.
    root.close()
  }

  function activate() {
    if (root.hasProblem) { root.refresh(); return }
    root.launch(root.selected)
  }

  // --------------------------------------------------------------- backends

  Process {
    id: listProc
    command: [root.launcher, "--list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.games = Model.parseList(text)
        root.loaded = true
        root.selectedIndex = 0
      }
    }
    // --list reports problems on stderr: the same text `arcade-launcher
    // --doctor` prints, already written for a human to read.
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.problemReport = text ? text.trim() : ""
    }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode === 0) root.problemReport = ""
      else if (root.problemReport.length === 0) root.problemReport = "arcade-launcher exited with code " + exitCode
    }
  }

  Process {
    id: artProc
    stdout: SplitParser {
      onRead: function(line) {
        var next = Model.withArt(root.artMap, line)
        if (next) root.artMap = next
      }
    }
    // Why a tile stayed blank -- an unreachable thumbnail server, most often --
    // belongs in the shell log rather than nowhere.
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text && text.trim().length > 0) console.warn(root.pluginId + ":", text.trim())
    }
    // Keep going until every game has either an image or a recorded miss.
    onExited: Qt.callLater(function() { root.requestArt() })
  }

  Process {
    id: launchProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text && text.trim().length > 0) console.warn(root.pluginId + ":", text.trim())
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  // ------------------------------------------------------------------- view

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-arcade"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        // BorderSurface exposes its padding as insets rather than applying it,
        // so the content inset is anchored here. Without this the wordmark sits
        // flush against the border.
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate()
            event.accepted = true
          } else if (event.key === Qt.Key_Right || (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier))) {
            root.moveBy(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Left || (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier))) {
            root.moveBy(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.moveBy(root.columns)
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.moveBy(-root.columns)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.moveBy(root.columns * 2)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.moveBy(-root.columns * 2)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.setSelected(0)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.setSelected(root.rows.length - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_F5) {
            root.refresh()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        Column {
          anchors.fill: parent
          spacing: root.contentSpacing

          // ------------------------------------------------------------ header
          Item {
            width: parent.width
            height: root.headerHeight

            Text {
              id: wordmark
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "ARCADE"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: Style.space(3)
            }

            // The search line is a field rather than loose text: it is the one
            // thing in the panel you are meant to type into, and it should look
            // like it before anything is typed.
            Rectangle {
              id: searchField
              anchors.left: wordmark.right
              anchors.leftMargin: Style.space(16)
              anchors.right: countPill.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              height: parent.height
              radius: height / 2
              color: Util.alpha(root.foreground, 0.06)
              border.width: Math.max(1, Style.space(1))
              border.color: root.filterText ? Util.alpha(root.accent, 0.45) : Util.alpha(root.foreground, 0.10)
              Behavior on border.color { ColorAnimation { duration: 130 } }

              Text {
                id: searchGlyph
                anchors.left: parent.left
                anchors.leftMargin: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "󰍉"
                color: root.filterText ? root.accent : root.foreground
                opacity: root.filterText ? 0.9 : 0.4
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
              }

              Text {
                id: searchLine
                textFormat: Text.PlainText
                anchors.left: searchGlyph.right
                anchors.leftMargin: Style.space(10)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter
                text: root.filterText || "Search games…"
                color: root.foreground
                opacity: root.filterText ? 1 : 0.42
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                elide: Text.ElideRight
              }

              // A caret, so an empty field still looks like something you type
              // in rather than a label.
              Rectangle {
                anchors.left: searchLine.left
                anchors.leftMargin: root.filterText ? Math.min(searchLine.contentWidth + Style.space(3), searchLine.width) : 0
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(2, Style.space(2))
                height: Style.font.heading
                radius: width / 2
                color: root.accent
                opacity: caretBlink.on ? 0.9 : 0
                Behavior on opacity { NumberAnimation { duration: 90 } }
              }
            }

            Rectangle {
              id: countPill
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              height: Style.font.caption + Style.space(12)
              width: countText.implicitWidth + Style.space(20)
              radius: height / 2
              color: root.hasProblem ? Util.alpha(root.accent, 0.18) : Util.alpha(root.foreground, 0.08)

              Text {
                id: countText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: root.loading ? "reading library…"
                  : (root.hasProblem ? "setup needed" : Model.describeCount(root.rows.length, root.games.length))
                color: root.hasProblem ? root.accent : root.foreground
                opacity: root.hasProblem ? 1 : 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // -------------------------------------------------------------- body
          Item {
            width: parent.width
            height: parent.height - root.headerHeight - root.footerHeight - root.contentSpacing * 2

            // The wall.
            GridView {
              id: grid
              anchors.fill: parent
              visible: !root.hasProblem && root.rows.length > 0
              model: root.rows.length
              cellWidth: root.cellWidth
              cellHeight: root.cellHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              cacheBuffer: root.cellHeight * 3

              delegate: Item {
                id: tile
                required property int index
                readonly property var entry: root.rows[index]
                readonly property bool active: index === root.selectedIndex
                readonly property string art: Model.artFor(root.artMap, entry)
                readonly property bool pending: Model.artPending(root.artMap, entry)

                width: grid.cellWidth
                height: grid.cellHeight
                z: active ? 2 : 1

                Item {
                  anchors.fill: parent
                  anchors.margins: Math.round(root.tileSpacing / 2)

                  // The selected tile lifts out of the wall rather than merely
                  // changing colour: at this size a border alone is easy to
                  // lose track of while arrowing around.
                  scale: tile.active ? 1.04 : 1
                  Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

                  // A halo around the selection, so the accent border reads as
                  // a lit cabinet rather than a hairline.
                  Rectangle {
                    anchors.fill: frame
                    anchors.margins: -Math.round(root.tileSpacing / 3)
                    radius: root.cornerRadius + Style.space(3)
                    color: "transparent"
                    border.width: Math.max(1, Style.space(2))
                    border.color: Util.alpha(root.accent, 0.45)
                    opacity: tile.active ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 130 } }
                  }

                  Rectangle {
                    id: frame
                    anchors.fill: parent
                    radius: root.cornerRadius
                    color: tile.active ? Util.alpha(root.accent, 0.14) : root.tileSurface
                    border.width: tile.active ? Math.max(2, Style.space(3)) : Math.max(1, Style.space(1))
                    border.color: tile.active ? root.accent : root.tileBorder
                    Behavior on color { ColorAnimation { duration: 130 } }
                    Behavior on border.color { ColorAnimation { duration: 130 } }

                    Column {
                      anchors.fill: parent
                      anchors.margins: Style.space(6)
                      spacing: Style.space(6)

                      // ---- artwork
                      Rectangle {
                        id: well
                        width: parent.width
                        height: Math.round(width * 0.75)
                        radius: Math.max(2, root.cornerRadius - Style.space(3))
                        color: root.artWell
                        clip: true

                        Image {
                          anchors.fill: parent
                          anchors.margins: 1
                          source: tile.art ? "file://" + tile.art : ""
                          visible: tile.art.length > 0 && status === Image.Ready
                          fillMode: Image.PreserveAspectFit
                          // Arcade art is 224 lines tall. Smoothing it into a
                          // 200px tile turns a title screen into a smear;
                          // nearest-neighbour keeps the pixels it was drawn in.
                          smooth: false
                          mipmap: false
                          asynchronous: true
                          cache: true
                          sourceSize.width: 640
                        }

                        // No artwork, or none yet: the game's initials set like
                        // a marquee, which beats an empty black rectangle.
                        Text {
                          anchors.centerIn: parent
                          visible: tile.art.length === 0
                          textFormat: Text.PlainText
                          text: Model.initials(tile.entry ? tile.entry.title : "")
                          color: Util.alpha(root.foreground, tile.pending ? 0.28 : 0.42)
                          font.family: root.fontFamily
                          font.pixelSize: Math.round(well.height * 0.34)
                          font.letterSpacing: Style.space(2)
                          font.bold: true

                          SequentialAnimation on opacity {
                            running: tile.pending && root.opened
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutQuad }
                            NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
                          }
                        }
                      }

                      // ---- label
                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: tile.entry ? tile.entry.title : ""
                        color: tile.active ? root.accent : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: tile.active
                        elide: Text.ElideRight
                      }

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: tile.entry ? tile.entry.rom : ""
                        color: root.foreground
                        opacity: 0.45
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: if (pointerGate.moved) root.setSelected(tile.index)
                    onClicked: {
                      root.setSelected(tile.index)
                      root.activate()
                    }
                  }
                }
              }
            }

            // A slim indicator instead of a scrollbar: the wall scrolls with
            // the selection, so this is a hint about how much library is left,
            // not something to drag.
            Rectangle {
              visible: grid.visible && grid.contentHeight > grid.height
              width: Math.max(2, Style.space(3))
              radius: width / 2
              color: Util.alpha(root.foreground, 0.18)
              anchors.right: parent.right
              y: grid.visibleArea.yPosition * parent.height
              height: Math.max(Style.space(24), grid.visibleArea.heightRatio * parent.height)
              Behavior on y { NumberAnimation { duration: 90 } }
            }

            // The wall fades out into the footer rather than being sliced off
            // by it, which is the only cue that there is more below.
            Rectangle {
              visible: grid.visible && grid.contentHeight > grid.height
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: Style.space(72)
              gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.55; color: Util.alpha(root.background, 0.75) }
                GradientStop { position: 1.0; color: root.background }
              }
            }

            // Nothing matched what was typed.
            Column {
              anchors.centerIn: parent
              visible: !root.hasProblem && root.loaded && root.rows.length === 0
              spacing: Style.space(6)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: root.games.length === 0 ? "No ROMs found" : "Nothing matches “" + root.filterText + "”"
                color: root.foreground
                opacity: 0.65
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: root.games.length === 0 ? "Put romsets in your ROM directory, then press F5"
                                              : "Backspace to widen the search"
                color: root.foreground
                opacity: 0.4
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            // Or the launcher could not get as far as a list.
            Flickable {
              anchors.fill: parent
              visible: root.hasProblem
              contentHeight: problemText.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Text {
                id: problemText
                width: parent.width
                textFormat: Text.PlainText
                text: root.problemReport
                color: root.foreground
                wrapMode: Text.WordWrap
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // ------------------------------------------------------------ footer
          Item {
            width: parent.width
            height: root.footerHeight

            Rectangle {
              anchors.top: parent.top
              width: parent.width
              height: 1
              color: Util.alpha(root.foreground, 0.10)
            }

            Column {
              anchors.left: parent.left
              anchors.right: hintText.left
              anchors.rightMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.statusMessage
                  || (root.selected ? root.selected.title : (root.hasProblem ? "Setup needed" : ""))
                color: root.statusMessage ? root.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.selected
                  ? root.selected.rom + "  ·  " + Model.shortenPath(root.selected.path, root.home)
                  : ""
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
              }
            }

            Text {
              id: hintText
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, parent.width * 0.42)
              horizontalAlignment: Text.AlignRight
              text: root.hasProblem
                ? "Enter re-checks · Esc closes"
                : "Enter plays · ←↑↓→ selects\nF5 rescans · Esc closes"
              color: root.foreground
              opacity: 0.4
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              lineHeight: 1.25
            }
          }
        }
      }
    }
  }

  // The caret blink, kept out of the layout so nothing above re-lays out twice
  // a second.
  Timer {
    id: caretBlink
    property bool on: true
    running: root.opened
    interval: 560
    repeat: true
    onTriggered: on = !on
    onRunningChanged: if (!running) on = true
  }
}
