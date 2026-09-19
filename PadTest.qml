import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "Pad.js" as Pad

// the stick test
//
// Every press on the stick, read as RetroArch will read it: the big
// line says what the last button does in a game, and the board
// below lights each cabinet control while it is held -- so a
// button that lights nothing, or the wrong thing, shows at once.
Item {
  property var arcade
  id: padBoard
  visible: arcade.settingsOpen && arcade.padTesting
  anchors.top: parent.top
  anchors.bottom: parent.bottom
  anchors.horizontalCenter: parent.horizontalCenter
  width: Math.min(parent.width, Style.space(900))

  Column {
    id: padHeadline
    anchors.top: parent.top
    anchors.topMargin: Style.space(24)
    width: parent.width
    spacing: Style.space(8)

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: arcade.padState.last
        ? arcade.padState.last.label + "  →  " + arcade.padState.last.meaning
        : "Press a button on the stick"
      color: arcade.padState.last && !arcade.padState.last.ok ? arcade.accent : arcade.foreground
      opacity: arcade.padState.last ? 1 : 0.6
      font.family: arcade.fontFamily
      font.pixelSize: Style.font.title
      font.bold: !!arcade.padState.last
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: arcade.padState.last
        ? (arcade.padState.last.note || " ")
        : (arcade.controllerParsed.profile ? "Read as " + arcade.controllerParsed.profile.name
           + ", the way RetroArch will read it in a game." : " ")
      color: arcade.foreground
      opacity: 0.5
      font.family: arcade.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
  }

  Grid {
    id: padGrid
    anchors.top: padHeadline.bottom
    anchors.topMargin: Style.space(28)
    anchors.horizontalCenter: parent.horizontalCenter
    columns: 6
    spacing: Style.space(10)
    readonly property int cell: Math.floor((padBoard.width - spacing * 5) / 6)

    Repeater {
      model: Pad.testControls()

      Rectangle {
        required property string modelData
        readonly property bool lit: Pad.controlHeld(arcade.padState, modelData)
        readonly property string stick: Pad.controlPadLabel(arcade.controllerParsed, modelData)
        width: padGrid.cell
        height: Math.round(padGrid.cell * 0.62)
        radius: arcade.cornerRadius
        color: lit ? arcade.accent : arcade.tileSurface
        border.width: Math.max(1, Style.space(1))
        border.color: lit ? arcade.accent : (stick ? arcade.tileBorder : Util.alpha(arcade.accent, 0.5))
        Behavior on color { ColorAnimation { duration: 60 } }

        Column {
          anchors.centerIn: parent
          spacing: Style.space(4)

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: Pad.controlName(modelData)
            color: lit ? arcade.background : arcade.foreground
            font.family: arcade.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: stick || "not on the stick"
            color: lit ? arcade.background : (stick ? arcade.foreground : arcade.accent)
            opacity: lit ? 0.85 : 0.55
            font.family: arcade.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
