import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "Library.js" as Library
import "Present.js" as Present

// One game on the wall: its title screen, its name and a word about it, the
// pencil into its own settings and the heart that makes it a favourite.
Item {
  id: tile
  property var arcade
  required property int index
  readonly property var entry: index >= 0 && index < arcade.rows.length ? arcade.rows[index] : null
  readonly property bool active: index === arcade.selectedIndex
  readonly property string art: Library.artFor(arcade.artMap, entry)
  readonly property bool pending: Library.artPending(arcade.artMap, entry)
  readonly property string note: Present.tileNote(entry, arcade.now, arcade.sortBy, arcade.gamePaused)
  readonly property bool broken: Library.problemOf(entry).length > 0
  readonly property bool absent: !!entry && entry.installed === false

  Item {
    anchors.fill: parent
    anchors.margins: Math.round(arcade.tileSpacing / 2)

    // The selected tile lifts out of the wall and glows, the way a lit
    // cabinet does in a dark arcade; the rest step back a little.
    scale: tile.active ? 1.05 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    RectangularShadow {
      anchors.fill: frame
      radius: frame.radius
      blur: Style.space(28)
      spread: Style.space(2)
      color: Util.alpha(arcade.accent, 0.55)
      opacity: tile.active ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    Rectangle {
      id: frame
      anchors.fill: parent
      radius: arcade.cornerRadius
      color: tile.active ? Util.alpha(arcade.accent, 0.16) : arcade.tileSurface
      border.width: tile.active ? Math.max(2, Style.space(2)) : Math.max(1, Style.space(1))
      border.color: tile.active ? arcade.accent : arcade.tileBorder
      Behavior on color { ColorAnimation { duration: 140 } }
      Behavior on border.color { ColorAnimation { duration: 140 } }

      // Inset on three sides only: the caption runs to the tile's bottom
      // edge, so it centres between the art and the edge rather than
      // sitting high with the inset stacked under it.
      Column {
        anchors.fill: parent
        anchors.leftMargin: arcade.tileInset
        anchors.rightMargin: arcade.tileInset
        anchors.topMargin: arcade.tileInset
        spacing: 0

        // ---- artwork
        Rectangle {
          id: well
          width: parent.width
          height: arcade.artHeight
          radius: Math.max(2, arcade.cornerRadius - Style.space(3))
          color: arcade.artWell
          clip: true

          Image {
            anchors.fill: parent
            anchors.margins: 1
            source: tile.art ? "file://" + tile.art
              + (tile.entry && arcade.artRevision[tile.entry.rom] ? "?v=" + arcade.artRevision[tile.entry.rom] : "") : ""
            visible: tile.art.length > 0 && status === Image.Ready
            fillMode: Image.PreserveAspectFit
            // Arcade art is 224 lines tall. Smoothing it into a 200px
            // tile turns a title screen into a smear; nearest-neighbour
            // keeps the pixels it was drawn in.
            smooth: false
            mipmap: false
            asynchronous: true
            cache: true
            sourceSize.width: 640
            // A game that won't start steps back further: still there to
            // pick, since a fixed romset may start now, but not inviting.
            opacity: tile.broken || tile.absent ? (tile.active ? 0.6 : 0.35) : (tile.active ? 1 : 0.8)
            Behavior on opacity { NumberAnimation { duration: 140 } }
          }

          // The game on screen right now, marked on its own art so it is
          // found at a glance on a wall of title screens.
          Rectangle {
            visible: !!(tile.entry && tile.entry.playing)
            z: 2
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            height: Style.font.caption + Style.space(8)
            width: playingText.implicitWidth + Style.space(14)
            radius: height / 2
            color: arcade.accent

            Text {
              id: playingText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: arcade.gamePaused ? "PAUSED" : "PLAYING"
              color: arcade.artWell
              font.family: arcade.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: Style.space(1)
            }
          }

          // The last check, or the last try, found it would not start. The
          // reason is the line under the name.
          Rectangle {
            visible: tile.broken || tile.absent
            z: 2
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            height: Style.font.caption + Style.space(8)
            width: brokenText.implicitWidth + Style.space(14)
            radius: height / 2
            color: Util.alpha(arcade.artWell, 0.85)
            border.width: Math.max(1, Style.space(1))
            border.color: tile.absent ? Util.alpha(arcade.foreground, 0.5) : arcade.accent

            Text {
              id: brokenText
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: tile.absent ? "NOT INSTALLED" : "WON'T START"
              color: tile.absent ? arcade.foreground : arcade.accent
              font.family: arcade.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: Style.space(1)
            }
          }

          // No artwork, or none yet: the game's initials set like a
          // marquee, which beats an empty black rectangle.
          Text {
            anchors.centerIn: parent
            visible: tile.art.length === 0
            textFormat: Text.PlainText
            text: Present.initials(tile.entry ? tile.entry.title : "")
            color: Util.alpha(arcade.foreground, tile.pending ? 0.28 : 0.42)
            font.family: arcade.fontFamily
            font.pixelSize: Math.round(well.height * 0.34)
            font.letterSpacing: Style.space(2)
            font.bold: true

            SequentialAnimation on opacity {
              running: tile.pending && arcade.opened
              loops: Animation.Infinite
              NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutQuad }
              NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
            }
          }
        }

        // ---- the caption: the name over a word about it, and on the
        // right a heart, centred on both lines. A favourite's is filled;
        // the selected or hovered tile shows an outline one, which is
        // also where a click makes it a favourite.
        Item {
          id: caption
          width: parent.width
          height: arcade.captionHeight + arcade.tileInset

          Column {
            anchors.left: parent.left
            anchors.leftMargin: arcade.captionPadX
            anchors.right: editBox.visible ? editBox.left : (heartBox.visible ? heartBox.left : parent.right)
            anchors.rightMargin: editBox.visible || heartBox.visible ? Style.space(4) : arcade.captionPadX
            anchors.verticalCenter: parent.verticalCenter
            spacing: arcade.captionGap

            Text {
              width: parent.width
              height: arcade.nameLineHeight
              verticalAlignment: Text.AlignVCenter
              textFormat: Text.PlainText
              // A search lists every version on its own; for games you do not
            // have, the database's full name is what tells them apart.
            text: !tile.entry ? ""
              : (arcade.searching && tile.absent && tile.entry.dbTitle ? tile.entry.dbTitle : tile.entry.title)
              color: tile.active ? arcade.accent : arcade.foreground
              opacity: tile.active ? 1 : 0.9
              font.family: arcade.fontFamily
              font.pixelSize: Style.font.body
              font.bold: tile.active
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              height: arcade.noteLineHeight
              verticalAlignment: Text.AlignVCenter
              textFormat: Text.PlainText
              text: tile.note || " "
              color: tile.entry && tile.entry.playing ? arcade.accent : arcade.foreground
              opacity: tile.entry && tile.entry.playing ? 0.9 : 0.45
              font.family: arcade.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          // The way into this game's own settings, on the tile in hand.
          Item {
            id: editBox
            anchors.right: heartBox.visible ? heartBox.left : parent.right
            anchors.rightMargin: heartBox.visible ? 0 : Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            width: heartBox.width
            height: width
            visible: tile.active || tileMouse.containsMouse

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "󰏫"
              color: arcade.foreground
              opacity: 0.45
              font.family: arcade.fontFamily
              font.pixelSize: Math.round(heartBox.height * 0.5)
            }
          }

          Item {
            id: heartBox
            readonly property bool favourite: Library.isFavourite(tile.entry)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(arcade.captionHeight * 0.8)
            height: width
            visible: favourite || tile.active || tileMouse.containsMouse

            Rectangle {
              anchors.fill: parent
              radius: width / 2
              color: Util.alpha(arcade.accent, heartBox.favourite ? 0.14 : 0.0)
              Behavior on color { ColorAnimation { duration: 140 } }
            }

            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: heartBox.favourite ? "󰋑" : "󰋕"
              color: arcade.accent
              opacity: heartBox.favourite ? 1 : 0.45
              font.family: arcade.fontFamily
              font.pixelSize: Math.round(heartBox.height * 0.58)
            }
          }
        }
      }
    }

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      onEntered: {
        arcade.wake()
        if (arcade.pointerGate.moved) arcade.setSelected(tile.index)
      }
      onClicked: function(mouse) {
        arcade.setSelected(tile.index)
        // The heart is a button of its own; anywhere else plays.
        var p = heartBox.mapFromItem(tileMouse, mouse.x, mouse.y)
        var e = editBox.mapFromItem(tileMouse, mouse.x, mouse.y)
        if (heartBox.visible && heartBox.contains(p)) arcade.toggleFavourite()
        else if (editBox.visible && editBox.contains(e)) arcade.openGame()
        else arcade.activate()
      }
    }
  }
}
