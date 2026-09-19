import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "Library.js" as Library
import "Present.js" as Present
import "Settings.js" as Settings
import "Pad.js" as Pad

// The foot of the panel: on the wall, the selected game's name, its facts and
// keycaps; in the editors and the stick test, the plain line of hints.
Item {
  property var arcade
  width: parent.width
  height: arcade.footerHeight

  Rectangle {
    anchors.top: parent.top
    width: parent.width
    height: 1
    color: Util.alpha(arcade.foreground, 0.10)
  }

  // ---- the info bar
  Column {
    id: infoText
    visible: arcade.infoBarShown
    anchors.left: parent.left
    anchors.right: keycaps.left
    anchors.rightMargin: Style.space(20)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: arcade.statusMessage || (arcade.selected ? arcade.selected.title : "")
      color: arcade.statusMessage ? arcade.accent : arcade.foreground
      font.family: arcade.fontFamily
      font.pixelSize: Math.round(Style.font.title * 1.5)
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      // A game that won't start says why here, where there is room for all
      // of it; its tile only has room to say that it won't.
      readonly property string problem: Present.problemNote(arcade.selected)
      readonly property bool urgent: (arcade.addNote && !arcade.addOk) || !!arcade.launchNote || !!problem
      text: arcade.addNote || arcade.launchNote || problem || Present.gameFacts(arcade.selected, arcade.now)
      color: urgent ? arcade.accent : arcade.foreground
      opacity: urgent ? 1 : 0.55
      font.family: arcade.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  Row {
    id: keycaps
    visible: arcade.infoBarShown
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(18)

    Repeater {
      model: Present.wallHints(arcade.stickLast && !!arcade.controllerParsed.pad,
                             Library.versionCount(arcade.selected) > 1,
                             arcade.selected ? { on: Library.isFavourite(arcade.selected),
                                               stickKey: Pad.favouriteStickKey(arcade.controllerParsed) } : null)

      Row {
        required property var modelData
        spacing: Style.space(6)

        Repeater {
          model: modelData.keys

          Rectangle {
            required property string modelData
            anchors.verticalCenter: parent.verticalCenter
            height: Style.font.caption + Style.space(10)
            width: Math.max(height, capText.implicitWidth + Style.space(12))
            radius: Math.max(3, arcade.cornerRadius / 2)
            color: Util.alpha(arcade.foreground, 0.07)
            border.width: Math.max(1, Style.space(1))
            border.color: Util.alpha(arcade.foreground, 0.22)

            Text {
              id: capText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: modelData
              color: arcade.foreground
              opacity: 0.85
              font.family: arcade.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: modelData.label
          color: arcade.foreground
          opacity: 0.55
          font.family: arcade.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // ---- the plain footer: settings, the stick test, setup problems
  Column {
    visible: !arcade.infoBarShown
    anchors.left: parent.left
    anchors.right: hintText.left
    anchors.rightMargin: Style.space(16)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: arcade.padTesting
        ? "Controller test" + (arcade.controllerParsed.pad ? " · " + arcade.controllerParsed.pad.name : "")
        : arcade.settingsOpen
        ? (arcade.settingsRow ? arcade.settingsRow.label : "Settings")
        : (arcade.statusMessage
           || (arcade.selected ? arcade.selected.title : (arcade.hasProblem ? "Setup needed" : "")))
      color: arcade.statusMessage && !arcade.settingsOpen ? arcade.accent : arcade.foreground
      font.family: arcade.fontFamily
      font.pixelSize: Style.font.heading
      elide: Text.ElideRight
    }

    // Under the name: what the setting does and where its value came
    // from, or the problem with what was just typed.
    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: arcade.padTesting
        ? Pad.controllerStatus(arcade.controllerParsed).text
        : arcade.settingsOpen
        ? (arcade.settingsError
           || (arcade.capturing ? "press the key for this control — Esc cancels" : "")
           || Settings.describeState(arcade.settingsRow)
           || (arcade.settingsRow
               ? [arcade.settingsRow.help || "", Settings.describeSource(arcade.settingsRow)]
                   .filter(function(part) { return part.length > 0 }).join("  ·  ")
               : ""))
        : (arcade.selected
           ? arcade.selected.rom + "  ·  "
             + (arcade.launchNote || Present.versionNote(arcade.selected)
                || Present.shortenPath(arcade.selected.path, arcade.home))
           : "")
      color: (arcade.settingsOpen
              && (arcade.settingsError || arcade.capturing || Settings.describeState(arcade.settingsRow)))
        || (!arcade.settingsOpen && arcade.launchNote)
        ? arcade.accent : arcade.foreground
      opacity: (arcade.settingsOpen
                && (arcade.settingsError || arcade.capturing || Settings.describeState(arcade.settingsRow)))
        || (!arcade.settingsOpen && arcade.launchNote)
        ? 1 : 0.45
      font.family: arcade.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideMiddle
    }
  }

  Text {
    id: hintText
    visible: !arcade.infoBarShown
    textFormat: Text.PlainText
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(implicitWidth, parent.width * 0.42)
    horizontalAlignment: Text.AlignRight
    text: arcade.padTesting
      ? "press buttons on the stick\nEsc or hold Home ends the test"
      : arcade.stickLast && arcade.controllerParsed.pad && !arcade.editing && !arcade.capturing
      ? Pad.stickHint(arcade.stickView)
      : arcade.settingsOpen
      ? (arcade.capturing
         ? "press a key · Esc cancels"
         : (arcade.editing
            ? "Enter saves · Esc cancels"
            : "←→ changes · Enter edits\nDel resets · Esc goes back"))
      : (arcade.hasProblem
         ? "Enter re-checks · Alt+S settings · Esc closes"
         : "Enter plays · ←↑↓→ selects\nAlt+S settings · F5 rescans · Esc closes")
    color: arcade.foreground
    opacity: 0.4
    font.family: arcade.fontFamily
    font.pixelSize: Style.font.caption
    lineHeight: 1.25
  }
}
