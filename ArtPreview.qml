import Quickshell
import QtQuick
import qs.Commons
import qs.Ui
import "Present.js" as Present

// The picture a kind of artwork would put on the game's tile, shown beside
// the editor while one of the Artwork rows is the row in hand. The panel says
// which kind to show (Arcade.previewKind) and where its file is.
Item {
  id: preview
  property var arcade

  anchors.fill: parent
  visible: opacity > 0
  opacity: arcade.previewKind ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: 160 } }

  // The editor is a page in the middle of the card; the preview takes the
  // room beside it.
  readonly property real side: Math.max(0, (width - Math.min(width, Style.space(900))) / 2)

  Column {
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(Style.space(220), preview.side - Style.space(24))
    spacing: Style.space(10)

    Rectangle {
      width: parent.width
      height: Math.round(width * 0.75)
      radius: arcade.cornerRadius
      color: arcade.artWell
      border.width: Math.max(1, Style.space(1))
      border.color: Util.alpha(arcade.foreground, 0.12)
      clip: true

      Image {
        anchors.fill: parent
        anchors.margins: Style.space(6)
        source: arcade.previewPath ? "file://" + arcade.previewPath : ""
        visible: arcade.previewPath.length > 0 && status === Image.Ready
        fillMode: Image.PreserveAspectFit
        smooth: false
        mipmap: false
        asynchronous: true
        sourceSize.width: 900
      }

      // Being fetched, or this game has none of that kind.
      Text {
        anchors.centerIn: parent
        width: parent.width - Style.space(24)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        visible: arcade.previewPath.length === 0
        text: arcade.previewKind ? "looking for a " + Present.artKindLabel(arcade.previewKind) + "…" : ""
        color: arcade.foreground
        opacity: 0.45
        font.family: arcade.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: Present.artKindLabel(arcade.previewKind)
      color: arcade.foreground
      opacity: 0.55
      font.family: arcade.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
