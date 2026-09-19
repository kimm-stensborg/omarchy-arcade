import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "Library.js" as Library

// The body of the panel on the wall: the games in the order the Sort chip
// says, narrowed by the filters; what to do when nothing matched; or what the
// launcher said when it could not list anything.
Item {
  id: wallRoot
  property var arcade
  readonly property alias grid: grid
  anchors.fill: parent

  // The wall: the whole library, in the order the Sort chip says,
  // narrowed by the filters beside it.
  Item {
    id: wall
    anchors.fill: parent
    visible: !arcade.settingsOpen && !arcade.hasProblem && arcade.rows.length > 0

    GridView {
      id: grid
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width
      model: arcade.rows.length
      cellWidth: arcade.cellWidth
      cellHeight: arcade.cellHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      cacheBuffer: arcade.cellHeight * 3
      delegate: GameTile {
        arcade: wallRoot.arcade
        width: grid.cellWidth
        height: grid.cellHeight
        z: index === arcade.selectedIndex ? 2 : 1
      }
    }

    // A slim indicator instead of a scrollbar: the wall scrolls with
    // the selection, so this is a hint about how much library is
    // left, not something to drag.
    Rectangle {
      visible: grid.contentHeight > grid.height
      width: Math.max(2, Style.space(3))
      radius: width / 2
      color: Util.alpha(arcade.foreground, 0.18)
      anchors.right: parent.right
      y: grid.y + grid.visibleArea.yPosition * grid.height
      height: Math.max(Style.space(24), grid.visibleArea.heightRatio * grid.height)
      Behavior on y { NumberAnimation { duration: 90 } }
    }

    // The wall fades out into the info bar rather than being sliced
    // off by it, which is the only cue that there is more below.
    Rectangle {
      visible: grid.contentHeight > grid.height
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Style.space(56)
      gradient: Gradient {
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 1.0; color: arcade.cardColor }
      }
    }
  }

  // Nothing matched what was typed.
  Column {
    anchors.centerIn: parent
    visible: !arcade.settingsOpen && !arcade.hasProblem && arcade.loaded && arcade.rows.length === 0
    spacing: Style.space(6)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: arcade.games.length === 0 ? "No ROMs found"
        : (arcade.searching ? "Nothing matches “" + arcade.filterText + "”" : Library.emptyNote(arcade.filters))
      color: arcade.foreground
      opacity: 0.65
      font.family: arcade.fontFamily
      font.pixelSize: Style.font.heading
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: arcade.games.length === 0 ? "Press + (Alt+A) to add romsets, or drop them here"
        : (Library.filtersActive(arcade.filters) ? (arcade.searching ? "Backspace to widen the search · " : "")
           + "Alt+0 clears the filters" : "Backspace to widen the search")
      color: arcade.foreground
      opacity: 0.4
      font.family: arcade.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Or the launcher could not get as far as a list.
  Flickable {
    anchors.fill: parent
    visible: !arcade.settingsOpen && arcade.hasProblem
    contentHeight: problemText.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Text {
      id: problemText
      width: parent.width
      textFormat: Text.PlainText
      text: arcade.problemReport
      color: arcade.foreground
      wrapMode: Text.WordWrap
      font.family: arcade.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
