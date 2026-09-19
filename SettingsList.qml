import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "Settings.js" as Settings
import "Pad.js" as Pad

// the editor
//
// One row per key in arcade.conf. A row shows what is in effect and
// where it came from, so a value nobody chose reads as a default
// rather than as a setting, and Delete puts a chosen one back.
ListView {
  property var arcade
  id: settingsList
  // A column of label-and-value reads badly across a panel this
  // wide: the value ends up an arm's length from its name. The
  // wall gets the whole card, the editor takes a page width.
  anchors.top: parent.top
  anchors.bottom: parent.bottom
  anchors.horizontalCenter: parent.horizontalCenter
  width: Math.min(parent.width, Style.space(900))
  visible: arcade.settingsOpen && !arcade.padTesting
  model: arcade.settingsRows.length
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  spacing: Style.space(2)

  delegate: Column {
    id: settingRow
    required property int index
    readonly property var entry: arcade.settingsRows[index]
    readonly property bool active: index === arcade.settingsIndex
    readonly property bool editingThis: index === arcade.editingIndex
    readonly property bool capturingThis: index === arcade.capturingIndex
    readonly property bool newGroup: index === 0
      || arcade.settingsRows[index - 1].group !== entry.group

    width: settingsList.width
    spacing: Style.space(4)

    Item {
      width: parent.width
      height: settingRow.newGroup ? Style.font.caption + Style.space(16) : 0
      visible: settingRow.newGroup

      Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(3)
        textFormat: Text.PlainText
        text: settingRow.entry ? String(settingRow.entry.group).toUpperCase() : ""
        color: arcade.foreground
        opacity: 0.35
        font.family: arcade.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: Style.space(2)
      }
    }

    Rectangle {
      width: parent.width
      height: Math.max(Style.space(42), Style.font.body + Style.space(20))
      radius: arcade.cornerRadius
      color: settingRow.active ? Util.alpha(arcade.accent, 0.12) : "transparent"
      border.width: settingRow.active ? Math.max(1, Style.space(1)) : 0
      border.color: Util.alpha(arcade.accent, 0.45)
      Behavior on color { ColorAnimation { duration: 120 } }

      // A settings row is a claim about what the panel does, so the
      // one thing it must never hide is that a value is merely the
      // default. The dot marks the rows that are the user's own.
      Rectangle {
        id: overrideDot
        anchors.left: parent.left
        anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(4, Style.space(6))
        height: width
        radius: width / 2
        color: arcade.accent
        opacity: Settings.isOverridden(settingRow.entry) ? 0.9 : 0
      }

      Text {
        id: settingLabel
        anchors.left: overrideDot.right
        anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(parent.width * 0.32)
        textFormat: Text.PlainText
        text: settingRow.entry ? settingRow.entry.label : ""
        color: settingRow.active ? arcade.accent : arcade.foreground
        opacity: settingRow.active ? 1 : 0.85
        font.family: arcade.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      // The value, or the buffer being typed into it. Editing is
      // drawn rather than focused: the overlay owns the keyboard
      // exclusively, so a real text field would have to take it
      // back from the panel and hand it over again.
      Text {
        id: settingValue
        anchors.left: settingLabel.right
        anchors.leftMargin: Style.space(12)
        anchors.right: stepHint.left
        anchors.rightMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: settingRow.capturingThis
          ? "press a key…"
          : (settingRow.editingThis
             ? arcade.editText
             : (settingRow.entry && (settingRow.entry.kind === "bind" || settingRow.entry.layout)
                ? Pad.controlDisplay(settingRow.entry)
                  + (settingRow.entry.kind === "bind" && Pad.controlPadLabel(arcade.controllerParsed, settingRow.entry.id)
                     ? "   ·   stick: " + Pad.controlPadLabel(arcade.controllerParsed, settingRow.entry.id) : "")
                : Settings.displayValue(settingRow.entry, arcade.home)
                  + (settingRow.entry && settingRow.entry.unit && settingRow.entry.value
                     ? " " + settingRow.entry.unit : "")))
        color: settingRow.capturingThis
          || (!settingRow.editingThis && settingRow.entry && settingRow.entry.state === "missing")
          ? arcade.accent : arcade.foreground
        opacity: settingRow.capturingThis || settingRow.editingThis
          || Settings.isOverridden(settingRow.entry) ? 1 : 0.55
        font.family: arcade.fontFamily
        font.pixelSize: Style.font.body
        elide: settingRow.editingThis ? Text.ElideLeft : Text.ElideMiddle
      }

      Rectangle {
        id: settingCaret
        visible: settingRow.editingThis && !settingRow.capturingThis
        anchors.left: settingValue.left
        anchors.leftMargin: Math.min(settingValue.contentWidth + Style.space(3), settingValue.width)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(2, Style.space(2))
        height: Style.font.body
        radius: width / 2
        color: arcade.accent
        opacity: arcade.caretOn ? 0.9 : 0
      }

      // Arrow keys change a choice or a number in place; only the
      // typed rows need Enter, so only they are told about it.
      Text {
        id: stepHint
        anchors.right: parent.right
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        visible: settingRow.active && !settingRow.editingThis
        text: settingRow.entry && settingRow.entry.kind === "bind"
          ? "Enter to bind"
          : settingRow.entry && (settingRow.entry.kind === "padtest" || settingRow.entry.kind === "check")
          ? (settingRow.entry.kind === "check" && arcade.checkState.running ? "" : "Enter to start")
          : settingRow.entry && settingRow.entry.kind === "padinfo"
          ? "F5 re-checks"
          : (settingRow.entry && (settingRow.entry.kind === "choice" || settingRow.entry.kind === "number")
             ? "← →" : (settingRow.entry && settingRow.entry.kind === "image" ? "Enter to choose" : "Enter to edit"))
        color: arcade.foreground
        opacity: 0.35
        font.family: arcade.fontFamily
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: if (arcade.pointerGate.moved && !arcade.editing) arcade.settingsIndex = settingRow.index
        onClicked: {
          if (arcade.editing && !settingRow.editingThis) arcade.cancelEdit()
          arcade.settingsIndex = settingRow.index
          if (settingRow.entry && settingRow.entry.kind === "choice") arcade.stepSetting(1)
          else if (settingRow.entry && settingRow.entry.kind === "bind") arcade.beginCapture()
          else if (settingRow.entry && settingRow.entry.kind === "padtest") arcade.startPadTest()
          else if (settingRow.entry && settingRow.entry.kind === "check") arcade.startCheck()
          else if (settingRow.entry && settingRow.entry.kind === "padinfo") {}
          else if (!settingRow.editingThis) arcade.beginEdit()
        }
      }
    }
  }
}
