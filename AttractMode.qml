import Quickshell
import QtQuick
import qs.Commons
import qs.Ui
import "Library.js" as Library

// Attract mode: the panel left alone shows one game's title screen after
// another across the screen, big and pixel-sharp, with its name under it --
// the way a cabinet waits for coins. The blurred backdrop behind follows the
// game shown. Any key, button or mouse movement wakes the wall (Arcade.wake).
Item {
  id: attractView
  property var arcade

  visible: opacity > 0
  opacity: arcade.attract ? 1 : 0
  Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }

  // The game on screen; it changes only once the last one has faded out, so
  // a name never sits under the wrong picture.
  property var shown: null
  readonly property var wanted: arcade.attractGame
  onWantedChanged: {
    if (!wanted) return
    if (!shown) { shown = wanted; return }
    swap.restart()
  }
  onVisibleChanged: if (!visible) shown = null

  SequentialAnimation {
    id: swap
    NumberAnimation { target: stage; property: "opacity"; to: 0; duration: 450; easing.type: Easing.InQuad }
    ScriptAction { script: attractView.shown = attractView.wanted }
    NumberAnimation { target: stage; property: "opacity"; to: 1; duration: 650; easing.type: Easing.OutQuad }
  }

  Column {
    id: stage
    anchors.centerIn: parent
    spacing: Style.space(26)

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      // 4:3 or 3:4 as the game is, at most two-thirds of the screen high.
      readonly property bool tall: !!(attractView.shown && attractView.shown.vertical)
      height: Math.round(attractView.height * 0.62)
      width: Math.round(height * (tall ? 0.75 : 4 / 3))
      color: arcade.artWell
      radius: arcade.cornerRadius
      border.width: Math.max(2, Style.space(2))
      border.color: Util.alpha(arcade.accent, 0.5)
      clip: true

      Image {
        anchors.fill: parent
        anchors.margins: Style.space(6)
        source: attractView.shown ? "file://" + Library.artFor(arcade.artMap, attractView.shown) : ""
        fillMode: Image.PreserveAspectFit
        smooth: false
        mipmap: false
        asynchronous: true
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: attractView.shown ? attractView.shown.title : ""
      color: arcade.foreground
      font.family: arcade.fontFamily
      font.pixelSize: Math.round(Style.font.title * 1.6)
      font.bold: true
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      textFormat: Text.PlainText
      text: attractView.shown ? [attractView.shown.maker, attractView.shown.year].filter(function(x) { return x }).join("  ·  ") : ""
      color: arcade.foreground
      opacity: 0.55
      font.family: arcade.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  // The cabinet's own invitation, blinking the way they did.
  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Math.round(parent.height * 0.08)
    textFormat: Text.PlainText
    text: "PRESS ANY BUTTON"
    color: arcade.accent
    font.family: arcade.fontFamily
    font.pixelSize: Style.font.heading
    font.bold: true
    font.letterSpacing: Style.space(4)
    opacity: blink.on ? 1 : 0.15
    Behavior on opacity { NumberAnimation { duration: 200 } }

    Timer {
      id: blink
      property bool on: true
      running: attractView.visible
      interval: 800
      repeat: true
      onTriggered: on = !on
    }
  }

  // A mouse moved or clicked wakes the wall too. The first position is where
  // the pointer already rests, not a movement.
  MouseArea {
    anchors.fill: parent
    enabled: arcade.attract
    hoverEnabled: true
    property point first: Qt.point(-1, -1)
    onEnabledChanged: first = Qt.point(-1, -1)
    onPositionChanged: function(mouse) {
      if (first.x < 0) { first = Qt.point(mouse.x, mouse.y); return }
      if (Math.abs(mouse.x - first.x) + Math.abs(mouse.y - first.y) > 6) arcade.wake()
    }
    onClicked: arcade.wake()
  }
}
