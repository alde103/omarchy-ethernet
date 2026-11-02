import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "alde103.ethernet"
  ipcTarget: "alde103.ethernet"

  readonly property string script: Model.fileUrlToPath(Qt.resolvedUrl("ethernet"))

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool showAddress: setting("showAddress", false) === true
  readonly property bool alwaysShow: setting("alwaysShow", false) === true
  readonly property int refreshIntervalSec: Math.max(1, Number(setting("refreshIntervalSec", 3)) || 3)

  property string deviceState: "none"
  property var status: ({ state: "none" })
  property var profiles: []
  property string query: ""
  readonly property var shownProfiles: Model.filterProfiles(profiles, query)
  property int profileIndex: 0
  property bool cursorActive: false

  property bool editing: false
  property string editUuid: "" // empty while creating a new profile
  property string editName: ""
  property string editMethod: "auto"
  property string editAddress: ""
  property string editGateway: ""
  property string editDns: ""

  property string busyText: ""
  property string errorText: ""
  property bool closeEditorOnSuccess: false

  readonly property bool cablePresent: Model.cablePresent(deviceState)
  readonly property bool shown: cablePresent || alwaysShow
  readonly property bool connected: deviceState === "connected"
  readonly property string address: Model.primaryAddress(status.address)
  readonly property bool showsAddressInBar: showAddress && connected && address !== ""
  readonly property bool typing: searchField.activeFocus || nameField.activeFocus || addressField.activeFocus
    || gatewayField.activeFocus || dnsField.activeFocus
  readonly property real rowHeight: Style.spacing.controlHeight + Style.space(4)

  visible: shown
  implicitWidth: shown ? button.implicitWidth : 0
  implicitHeight: shown ? button.implicitHeight : 0

  function close() {
    root.controller.hide()
    editing = false
    query = ""
  }

  function refreshState() {
    if (!stateProc.running) stateProc.running = true
  }

  function refreshDetails() {
    if (!statusProc.running) statusProc.running = true
    if (!profilesProc.running) profilesProc.running = true
  }

  function runAction(args, busy) {
    if (actionProc.running) return
    errorText = ""
    busyText = busy
    actionProc.command = [root.script].concat(args)
    actionProc.running = true
  }

  function activate(profile) {
    if (!profile) return
    if (!cablePresent) {
      errorText = "Plug in a cable first"
      return
    }
    runAction(["up", profile.uuid], "Connecting to " + profile.name)
  }

  function toggleConnection() {
    if (!cablePresent) return
    if (connected) runAction(["disconnect"], "Disconnecting")
    else runAction(["connect"], "Connecting")
  }

  function selectedProfile() {
    if (cursorActive && profileIndex < shownProfiles.length) return shownProfiles[profileIndex]
    for (var i = 0; i < profiles.length; i++) {
      if (profiles[i].active) return profiles[i]
    }
    return null
  }

  function startEdit(profile) {
    if (!profile) return
    editUuid = profile.uuid
    editName = profile.name
    editMethod = profile.method === "manual" ? "manual" : "auto"
    editAddress = profile.addresses.split(",")[0].trim()
    editGateway = profile.gateway
    editDns = profile.dns
    errorText = ""
    editing = true
  }

  function startNew() {
    editUuid = ""
    editName = ""
    editMethod = "manual"
    editAddress = ""
    editGateway = ""
    editDns = ""
    errorText = ""
    editing = true
    Qt.callLater(nameField.forceActiveFocus)
  }

  function cancelEdit() {
    editing = false
    errorText = ""
    keyCatcher.forceActiveFocus()
  }

  function saveEdit() {
    var args = editUuid ? ["set", editUuid, editMethod] : ["new", editName.trim(), editMethod]
    if (editMethod === "manual") args = args.concat([editAddress.trim(), editGateway.trim(), editDns.trim()])
    else args.push(editDns.trim())
    closeEditorOnSuccess = true
    runAction(args, "Saving " + (editName.trim() || "profile"))
  }

  function copy(value) {
    if (!value) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(value) + " | wl-copy"])
  }

  function openNmtui() {
    Quickshell.execDetached(["omarchy-launch-tui", "nmtui"])
    close()
  }

  function moveCursor(delta) {
    if (shownProfiles.length === 0) return
    if (!cursorActive) {
      cursorActive = true
      profileIndex = 0
    } else {
      profileIndex = Math.max(0, Math.min(shownProfiles.length - 1, profileIndex + delta))
    }
    profileList.positionViewAtIndex(profileIndex, ListView.Contain)
  }

  function leaveSearch() {
    keyCatcher.forceActiveFocus()
    cursorActive = shownProfiles.length > 0
    profileIndex = 0
  }

  onOpenedChanged: {
    if (!opened) return
    refreshDetails()
    cursorActive = false
    profileIndex = 0
    errorText = ""
  }

  onDeviceStateChanged: if (opened) refreshDetails()
  onShownProfilesChanged: if (profileIndex >= shownProfiles.length) profileIndex = Math.max(0, shownProfiles.length - 1)

  Process {
    id: stateProc
    command: [root.script, "state"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.deviceState = Model.parseState(text).state }
  }

  Process {
    id: statusProc
    command: [root.script, "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.status = Model.parseStatus(text) }
  }

  Process {
    id: profilesProc
    command: [root.script, "profiles"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.profiles = Model.parseProfiles(text) }
  }

  Process {
    id: actionProc
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.busyText = ""
      if (exitCode === 0) {
        if (root.closeEditorOnSuccess) root.cancelEdit()
      } else {
        root.errorText = String(actionStderr.text || "").trim().split("\n").pop() || "NetworkManager refused the change"
      }
      root.closeEditorOnSuccess = false
      root.refreshState()
      root.refreshDetails()
    }
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshState()
  }

  Timer {
    interval: 2000
    running: root.opened
    repeat: true
    onTriggered: if (!statusProc.running) statusProc.running = true
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showsAddressInBar && !vertical ? root.address + " 󰈀" : "󰈀"
    slotSize: Style.bar.iconSlot * (root.showsAddressInBar && !vertical ? 5.5 : 1)
    opacity: root.connected ? 1 : 0.55
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleConnection()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.typing

      onMoveRequested: function(dx, dy) {
        if (!root.editing && dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: {
        if (!root.editing && root.cursorActive) root.activate(root.shownProfiles[root.profileIndex])
      }
      onCloseRequested: root.editing ? root.cancelEdit() : root.close()
      onTabRequested: function(direction) { if (!root.editing) root.switchPanel(direction) }
      onTextKey: function(t) {
        if (root.editing) return
        if (t === "/") searchField.forceActiveFocus()
        else if (t === "c") root.copy(root.address)
        else if (t === "d") root.toggleConnection()
        else if (t === "e") root.startEdit(root.selectedProfile())
        else if (t === "n") root.startNew()
        else if (t === "t") root.openNmtui()
        else if (t === "r") root.refreshDetails()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Hero: icon · title/status · connect toggle ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, connectButton.implicitHeight)

          Text {
            id: heroIcon
            text: "󰈀"
            color: root.foreground
            opacity: root.connected ? 1 : 0.55
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: connectButton.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: root.status.connection || "Ethernet"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: Model.statusLine(root.status).toUpperCase()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Button {
            id: connectButton
            visible: root.cablePresent
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.connected ? "Disconnect" : "Connect"
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.toggleConnection()
          }
        }

        // ---------- Live link details ----------
        Column {
          visible: root.connected
          width: parent.width
          spacing: Style.spacing.labelGap

          InfoRow { label: "Address"; value: root.status.address || "—"; copyValue: root.address }
          InfoRow { label: "Gateway"; value: root.status.gateway || "—"; copyValue: root.status.gateway || "" }
          InfoRow { label: "DNS"; value: root.status.dns || "—"; copyValue: root.status.dns || "" }
          InfoRow { label: "Method"; value: root.status.method === "manual" ? "Static" : "DHCP" }
          InfoRow { label: "Interface"; value: (root.status.device || "") + (root.status.mac ? "  ·  " + root.status.mac : "") }
        }

        PanelSeparator { foreground: root.foreground }

        // ---------- Profile switcher ----------
        Column {
          visible: !root.editing
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            implicitHeight: Math.max(profilesHeader.implicitHeight, newButton.implicitHeight)

            PanelSectionHeader {
              id: profilesHeader
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "PROFILES · " + root.profiles.length
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              PanelActionButton {
                id: newButton
                iconText: "󰐕"
                tooltipText: "New profile (n)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.startNew()
              }

              PanelActionButton {
                iconText: "󰒓"
                tooltipText: "Advanced: nmtui (t)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.openNmtui()
              }
            }
          }

          TextField {
            id: searchField
            width: parent.width
            placeholderText: "Filter by name or address  ( / )"
            foreground: root.foreground
            text: root.query
            onTextChanged: if (text !== root.query) root.query = text
            onAccepted: root.leaveSearch()
            Keys.onDownPressed: root.leaveSearch()
            Keys.onEscapePressed: {
              if (root.query) root.query = ""
              else keyCatcher.forceActiveFocus()
            }
          }

          ListView {
            id: profileList
            width: parent.width
            height: Math.min(count, 7) * root.rowHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.shownProfiles
            delegate: ProfileRow {}
          }

          Text {
            visible: root.shownProfiles.length === 0
            text: root.profiles.length === 0 ? "No wired profiles yet" : "No profile matches \"" + root.query + "\""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---------- Profile editor ----------
        Column {
          visible: root.editing
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: root.editUuid ? "EDIT · " + root.editName.toUpperCase() : "NEW PROFILE"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          TextField {
            id: nameField
            visible: root.editUuid === ""
            width: parent.width
            placeholderText: "Name, e.g. Bench 192.168.1.x"
            foreground: root.foreground
            text: root.editName
            onTextChanged: if (text !== root.editName) root.editName = text
            onAccepted: root.saveEdit()
            Keys.onEscapePressed: root.cancelEdit()
          }

          ButtonGroup {
            options: [{ value: "auto", label: "DHCP" }, { value: "manual", label: "Static IP" }]
            value: root.editMethod
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            onChanged: function(value) { root.editMethod = value }
          }

          TextField {
            id: addressField
            visible: root.editMethod === "manual"
            width: parent.width
            placeholderText: "Address, e.g. 192.168.1.50/24"
            foreground: root.foreground
            text: root.editAddress
            onTextChanged: if (text !== root.editAddress) root.editAddress = text
            onAccepted: root.saveEdit()
            Keys.onEscapePressed: root.cancelEdit()
          }

          TextField {
            id: gatewayField
            visible: root.editMethod === "manual"
            width: parent.width
            placeholderText: "Gateway (optional)"
            foreground: root.foreground
            text: root.editGateway
            onTextChanged: if (text !== root.editGateway) root.editGateway = text
            onAccepted: root.saveEdit()
            Keys.onEscapePressed: root.cancelEdit()
          }

          TextField {
            id: dnsField
            width: parent.width
            placeholderText: "DNS (optional), e.g. 1.1.1.1, 8.8.8.8"
            foreground: root.foreground
            text: root.editDns
            onTextChanged: if (text !== root.editDns) root.editDns = text
            onAccepted: root.saveEdit()
            Keys.onEscapePressed: root.cancelEdit()
          }

          Row {
            anchors.right: parent.right
            spacing: Style.space(6)

            Button {
              text: "Cancel"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.cancelEdit()
            }

            Button {
              text: "Save"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              active: true
              onClicked: root.saveEdit()
            }
          }
        }

        // ---------- Feedback and key hints ----------
        Text {
          visible: text !== ""
          width: parent.width
          text: root.errorText || root.busyText
          color: root.errorText ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          visible: !root.editing
          width: parent.width
          text: "/ filter · ↵ connect · e edit · n new"
            + (root.cablePresent ? " · d " + (root.connected ? "disconnect" : "connect") : "")
            + (root.connected ? " · c copy IP" : "") + " · t nmtui"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }

  component ProfileRow: CursorSurface {
    id: profileRow
    required property var modelData
    required property int index

    width: ListView.view ? ListView.view.width : 0
    height: root.rowHeight
    foreground: root.foreground
    hasCursor: root.cursorActive && root.profileIndex === index
    current: modelData.active

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.profileIndex = profileRow.index
      }
      onClicked: root.activate(profileRow.modelData)
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(4)
      spacing: Style.space(8)

      Text {
        text: profileRow.modelData.active ? "󰈀" : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.preferredWidth: Style.space(14)
      }

      Text {
        text: profileRow.modelData.name
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: profileRow.modelData.active
        elide: Text.ElideRight
        Layout.fillWidth: true
      }

      Text {
        text: Model.methodSummary(profileRow.modelData)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      PanelActionButton {
        iconText: "󰏫"
        tooltipText: "Edit (e)"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.startEdit(profileRow.modelData)
      }
    }
  }

  component InfoRow: Item {
    property string label: ""
    property string value: ""
    property string copyValue: ""

    width: parent ? parent.width : 0
    implicitHeight: Math.max(infoLabel.implicitHeight, infoValue.implicitHeight)

    Text {
      id: infoLabel
      anchors.left: parent.left
      text: parent.label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      id: infoValue
      anchors.right: parent.right
      anchors.left: infoLabel.right
      anchors.leftMargin: Style.space(12)
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: parent.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideLeft
    }

    MouseArea {
      anchors.fill: parent
      enabled: parent.copyValue !== ""
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.copy(parent.copyValue)
    }
  }
}
