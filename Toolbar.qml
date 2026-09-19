import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "Library.js" as Library

// The order and the filters, each a chip showing what it is set to and the
// key that steps it. A click steps it on, a right click back; a filter that is
// doing something is lit.
Row {
  property var arcade
  visible: arcade.toolbarShown
  height: visible ? arcade.toolbarHeight : 0
  width: parent.width
  spacing: Style.space(8)

  Repeater {
    model: [
      { id: "sort", label: "Sort: " + Library.sortLabel(arcade.sortBy), key: "O", lit: false },
      { id: "show", label: Library.showLabel(arcade.filters.show), key: "V", lit: arcade.filters.show !== "all" },
      { id: "decade", label: arcade.filters.decade || "Any decade", key: "D", lit: !!arcade.filters.decade,
        hidden: arcade.decadeChoices.length < 2 },
      { id: "maker", label: arcade.filters.maker || "Any maker", key: "M", lit: !!arcade.filters.maker,
        hidden: arcade.makerChoices.length < 2 },
      { id: "clear", label: "Clear filters", key: "0", lit: false,
        hidden: !Library.filtersActive(arcade.filters) }
    ]

    Rectangle {
      id: chip
      required property var modelData
      visible: !modelData.hidden
      height: arcade.toolbarHeight
      width: visible ? chipRow.implicitWidth + Style.space(20) : 0
      radius: height / 2
      color: modelData.lit ? Util.alpha(arcade.accent, 0.18)
        : (chipArea.containsMouse ? Util.alpha(arcade.foreground, 0.10) : Util.alpha(arcade.foreground, 0.05))
      border.width: Math.max(1, Style.space(1))
      border.color: modelData.lit ? Util.alpha(arcade.accent, 0.6) : Util.alpha(arcade.foreground, 0.12)
      Behavior on color { ColorAnimation { duration: 130 } }

      Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: Style.space(8)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: chip.modelData.label
          color: chip.modelData.lit ? arcade.accent : arcade.foreground
          opacity: chip.modelData.lit ? 1 : 0.75
          font.family: arcade.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Alt+" + chip.modelData.key
          color: arcade.foreground
          opacity: 0.35
          font.family: arcade.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      MouseArea {
        id: chipArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
          var delta = mouse.button === Qt.RightButton ? -1 : 1
          var id = chip.modelData.id
          if (id === "sort") arcade.stepSort(delta)
          else if (id === "clear") arcade.clearFilters()
          else arcade.stepFilter(id, delta)
          arcade.focusKeys()
        }
      }
    }
  }
}
