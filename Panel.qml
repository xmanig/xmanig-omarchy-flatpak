import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "xmanig.flatpak"
  ipcTarget: "xmanig.flatpak"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property var installed: []
  property var searchResults: []
  property string searchText: ""
  property string searchError: ""
  property string installStatus: ""
  property var pendingInstall: null
  property bool installing: false
  property int searchGeneration: 0

  readonly property string scriptPath: Model.urlToPath(Qt.resolvedUrl("Model.js"))
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color surface: Qt.lighter(Color.background, 1.08)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool searchActive: searchText.trim().length >= 2
  readonly property string barLabel: "Flatpaks " + installed.length
  readonly property string barTooltip: installed.length + " installed Flatpak applications"

  function refresh() {
    if (!installedProc.running) installedProc.running = true
    runSearch()
  }

  function openFromHotkey() {
    open()
    refresh()
  }

  function runSearch() {
    var query = searchText.trim()
    searchGeneration++
    root.searchError = ""
    if (query.length < 2) {
      searchResults = []
      searchProc.running = false
      return
    }

    if (searchProc.running) searchProc.running = false
    searchProc.requestId = searchGeneration
    searchProc.command = [
      "flatpak", "search", "--json",
      "--columns=application,name,description,version,branch,remotes",
      query
    ]
    searchProc.running = true
  }

  function isInstalled(id) {
    return Model.containsApp(installed, id)
  }

  function launch(app) {
    if (!app || !/^[A-Za-z0-9_.-]+$/.test(app.id) || !bar) return
    bar.run("flatpak run " + Util.shellQuote(app.id))
    close()
  }

  function requestInstall(app) {
    if (!app || isInstalled(app.id) || !/^[A-Za-z0-9_.-]+$/.test(app.id)) return
    pendingInstall = app
    installStatus = ""
  }

  function cancelInstall() {
    if (installing) return
    pendingInstall = null
  }

  function confirmInstall() {
    if (!pendingInstall || installing) return
    var id = pendingInstall.id
    if (!/^[A-Za-z0-9_.-]+$/.test(id)) return
    installing = true
    installStatus = "Installing " + pendingInstall.name + "…"
    installProc.command = ["flatpak", "install", "--user", "--noninteractive", "flathub", id]
    installProc.running = true
  }

  onOpenedChanged: {
    if (!opened) return
    refresh()
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  onSearchTextChanged: searchTimer.restart()

  Timer {
    id: searchTimer
    interval: 350
    repeat: false
    onTriggered: root.runSearch()
  }

  Process {
    id: installedProc
    command: ["flatpak", "list", "--app", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.installed = Model.installedApps(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
    }
  }

  Process {
    id: searchProc
    property int requestId: 0
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (searchProc.requestId !== root.searchGeneration) return
        root.searchResults = Model.searchApps(text)
      }
    }
    stderr: StdioCollector {
      id: searchError
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (requestId !== root.searchGeneration) return
      if (exitCode !== 0) {
        root.searchResults = []
        root.searchError = "Flathub search failed"
      }
    }
  }

  Process {
    id: installProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: installError
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var name = root.pendingInstall ? root.pendingInstall.name : "Flatpak"
      root.installing = false
      root.pendingInstall = null
      if (exitCode === 0) {
        root.installStatus = "Installed " + name
        root.refresh()
      } else {
        root.installStatus = "Could not install " + name
          + (String(installError.text || "").trim() !== "" ? ": " + String(installError.text).trim().split("\n").pop() : "")
      }
    }
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r") root.refresh()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(10)

        PanelHero {
          width: parent.width
          title: "Flatpak"
          meta: root.installed.length + " installed · Search Flathub to discover more"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: ""
              color: root.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.display
            }
          }
          trailingControl: refreshButton
        }

        TextField {
          id: searchField
          width: parent.width
          foreground: root.foreground
          accent: root.accent
          placeholderText: "Search Flathub…"
          selectByMouse: true
          onTextChanged: root.searchText = text
          Keys.onEscapePressed: {
            if (text !== "") text = ""
            else root.close()
          }
        }

        Rectangle {
          visible: root.pendingInstall !== null || root.installing
          width: parent.width
          color: root.surface
          radius: Style.cornerRadius
          implicitHeight: confirmColumn.implicitHeight + Style.space(20)

          Column {
            id: confirmColumn
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(6)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.installing
                ? root.installStatus
              : (root.pendingInstall ? "Install “" + root.pendingInstall.name + "” from Flathub?" : "")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              visible: !root.installing
              width: parent.width
              textFormat: Text.PlainText
              text: root.pendingInstall ? root.pendingInstall.id : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            RowLayout {
              visible: !root.installing
              width: parent.width
              spacing: Style.space(6)

              Item { Layout.fillWidth: true }

              PanelActionButton {
                iconText: ""
                tooltipText: "Cancel installation"
                foreground: root.foreground
                hoverColor: root.accent
                onClicked: root.cancelInstall()
              }

              PanelActionButton {
                iconText: ""
                tooltipText: "Install from Flathub"
                foreground: root.foreground
                hoverColor: root.accent
                onClicked: root.confirmInstall()
              }
            }
          }
        }

        Text {
          visible: root.installStatus !== "" && root.pendingInstall === null && !root.installing
          width: parent.width
          textFormat: Text.PlainText
          text: root.installStatus
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PanelSectionHeader {
          width: parent.width
          text: root.searchActive ? "Flathub results" : "Installed applications"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        Text {
          visible: root.searchText.trim().length === 1
          width: parent.width
          textFormat: Text.PlainText
          text: "Type at least 2 characters to search Flathub."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: root.searchError !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.searchError
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          visible: root.searchActive && root.searchResults.length === 0 && root.searchError === ""
          width: parent.width
          textFormat: Text.PlainText
          text: "No Flathub applications found."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: !root.searchActive && root.installed.length === 0
          width: parent.width
          textFormat: Text.PlainText
          text: "No installed Flatpak applications found."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        ListView {
          id: installedList
          width: parent.width
          height: root.searchActive ? 0 : Math.min(contentHeight, Style.space(360))
          visible: !root.searchActive && count > 0
          clip: true
          spacing: Style.space(3)
          interactive: contentHeight > height
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          model: root.installed

          delegate: Item {
            required property var modelData
            width: ListView.view.width
            height: installedRow.implicitHeight + Style.space(8)

            CursorSurface {
              anchors.fill: parent
              foreground: root.foreground
              fill: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              currentFill: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)

              RowLayout {
                id: installedRow
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(8)

                Column {
                  Layout.fillWidth: true
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: modelData.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: modelData.id + (modelData.version !== "" ? " · " + modelData.version : "")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                PanelActionButton {
                  iconText: ""
                  tooltipText: "Launch " + modelData.name
                  foreground: root.foreground
                  hoverColor: root.accent
                  onClicked: root.launch(modelData)
                }
              }
            }
          }
        }

        ListView {
          id: searchList
          width: parent.width
          height: root.searchActive ? Math.min(contentHeight, Style.space(390)) : 0
          visible: root.searchActive && count > 0
          clip: true
          spacing: Style.space(3)
          interactive: contentHeight > height
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          model: root.searchResults

          delegate: Item {
            required property var modelData
            width: ListView.view.width
            height: searchRow.implicitHeight + Style.space(8)

            CursorSurface {
              anchors.fill: parent
              foreground: root.foreground
              fill: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              currentFill: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)

              RowLayout {
                id: searchRow
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(8)

                Column {
                  Layout.fillWidth: true
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: modelData.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: modelData.id + (modelData.version !== "" ? " · " + modelData.version : "")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    visible: modelData.description !== ""
                    textFormat: Text.PlainText
                    text: modelData.description
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    wrapMode: Text.WordWrap
                  }
                }

                Text {
                  visible: root.isInstalled(modelData.id)
                  textFormat: Text.PlainText
                  text: "Installed"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                PanelActionButton {
                  visible: !root.isInstalled(modelData.id)
                  iconText: ""
                  tooltipText: "Install " + modelData.name
                  foreground: root.foreground
                  hoverColor: root.accent
                  onClicked: root.requestInstall(modelData)
                }
              }
            }
          }
        }
      }

      Component {
        id: refreshButton
        PanelActionButton {
          iconText: ""
          tooltipText: "Refresh Flatpak applications"
          foreground: root.foreground
          hoverColor: root.accent
          onClicked: root.refresh()
        }
      }
    }
  }

  IpcHandler {
    target: "xmanig.flatpak-refresh"
    function refresh(): string {
      root.refresh()
      return "ok"
    }
  }
}
