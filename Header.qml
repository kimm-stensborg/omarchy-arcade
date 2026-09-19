import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "Library.js" as Library

// The top of the panel: the wordmark, the search line (or, in an editor, the
// file it writes), and the add, settings and count buttons.
Item {
  property var arcade
  width: parent.width
  height: arcade.headerHeight

  Text {
    id: wordmark
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: arcade.settingsOpen ? (arcade.gameRom ? "GAME" : "SETTINGS") : "ARCADE"
    color: arcade.accent
    font.family: arcade.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: Style.space(3)
  }

  // The search line is a field rather than loose text: it is the one
  // thing in the panel you are meant to type into, and it should look
  // like it before anything is typed.
  Rectangle {
    id: searchField
    visible: !arcade.settingsOpen
    anchors.left: wordmark.right
    anchors.leftMargin: Style.space(16)
    anchors.right: addButton.left
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    height: parent.height
    radius: height / 2
    color: Util.alpha(arcade.foreground, 0.06)
    border.width: Math.max(1, Style.space(1))
    border.color: arcade.filterText ? Util.alpha(arcade.accent, 0.45) : Util.alpha(arcade.foreground, 0.10)
    Behavior on border.color { ColorAnimation { duration: 130 } }

    Text {
      id: searchGlyph
      anchors.left: parent.left
      anchors.leftMargin: Style.space(14)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "󰍉"
      color: arcade.filterText ? arcade.accent : arcade.foreground
      opacity: arcade.filterText ? 0.9 : 0.4
      font.family: arcade.fontFamily
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
      text: arcade.filterText || "Search games…"
      color: arcade.foreground
      opacity: arcade.filterText ? 1 : 0.42
      font.family: arcade.fontFamily
      font.pixelSize: Style.font.heading
      elide: Text.ElideRight
    }

    // A caret, so an empty field still looks like something you type
    // in rather than a label.
    Rectangle {
      anchors.left: searchLine.left
      anchors.leftMargin: arcade.filterText ? Math.min(searchLine.contentWidth + Style.space(3), searchLine.width) : 0
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(2, Style.space(2))
      height: Style.font.heading
      radius: width / 2
      color: arcade.accent
      opacity: arcade.caretOn ? 0.9 : 0
      Behavior on opacity { NumberAnimation { duration: 90 } }
    }
  }

  // Which file is being edited, in the search line's place: every row
  // below is a line in it, and a person who would rather edit it by
  // hand should be told where it is.
  Text {
    id: configPath
    visible: arcade.settingsOpen
    anchors.left: wordmark.right
    anchors.leftMargin: Style.space(16)
    anchors.right: gearButton.left
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    // The file this editor writes: the game's own in the game editor.
    text: arcade.gameRom
      ? Library.shortenPath(arcade.gameParsed.file, arcade.home)
        + (arcade.gameParsed.present ? "" : "  ·  made when you change something")
      : Library.shortenPath(arcade.settingsParsed.configFile, arcade.home)
        + (arcade.settingsParsed.configPresent ? "" : "  ·  not created yet")
    color: arcade.foreground
    opacity: 0.45
    font.family: arcade.fontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideMiddle
  }

  // Adding games: the file chooser. (Dropping files anywhere on the
  // panel works too.)
  Rectangle {
    id: addButton
    visible: !arcade.settingsOpen
    anchors.right: gearButton.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    width: parent.height
    height: parent.height
    radius: height / 2
    color: addArea.containsMouse ? Util.alpha(arcade.accent, 0.16) : Util.alpha(arcade.foreground, 0.06)
    Behavior on color { ColorAnimation { duration: 130 } }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: "󰐕"
      color: addArea.containsMouse ? arcade.accent : arcade.foreground
      opacity: addArea.containsMouse ? 1 : 0.5
      font.family: arcade.fontFamily
      font.pixelSize: Style.font.heading
    }

    MouseArea {
      id: addArea
      anchors.fill: parent
      hoverEnabled: true
      onClicked: arcade.pickGames()
    }
  }

  // The wall's way in and out of the editor, for the half of the time
  // a pointer is already in hand.
  Rectangle {
    id: gearButton
    anchors.right: countPill.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    width: parent.height
    height: parent.height
    radius: height / 2
    color: gearArea.containsMouse || arcade.settingsOpen
      ? Util.alpha(arcade.accent, 0.16) : Util.alpha(arcade.foreground, 0.06)
    Behavior on color { ColorAnimation { duration: 130 } }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: arcade.settingsOpen ? "󰅖" : "󰒓"
      color: arcade.settingsOpen || gearArea.containsMouse ? arcade.accent : arcade.foreground
      opacity: arcade.settingsOpen || gearArea.containsMouse ? 1 : 0.5
      font.family: arcade.fontFamily
      font.pixelSize: Style.font.heading
    }

    MouseArea {
      id: gearArea
      anchors.fill: parent
      hoverEnabled: true
      onClicked: arcade.settingsOpen ? arcade.closeSettings() : arcade.openSettings()
    }
  }

  Rectangle {
    id: countPill
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: Style.font.caption + Style.space(12)
    width: countText.implicitWidth + Style.space(20)
    radius: height / 2
    color: arcade.hasProblem ? Util.alpha(arcade.accent, 0.18) : Util.alpha(arcade.foreground, 0.08)

    Text {
      id: countText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: arcade.settingsOpen ? (arcade.gameRom ? arcade.gameTitle + "  ·  Esc goes back" : "Esc goes back")
        : (arcade.loading ? "reading library…"
        : (arcade.hasProblem ? "setup needed" : (arcade.filterText.trim().length > 0
        ? Library.describeCount(arcade.rows.length, arcade.searchPool)
        : Library.describeCount(arcade.rows.length, arcade.scoped.length))))
      color: arcade.hasProblem && !arcade.settingsOpen ? arcade.accent : arcade.foreground
      opacity: arcade.hasProblem && !arcade.settingsOpen ? 1 : 0.7
      font.family: arcade.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
