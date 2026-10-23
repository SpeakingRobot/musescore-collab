// StyledField.qml
// Reusable styled TextField for MuseCollab plugin
// Theme: Catppuccin Mocha

import QtQuick 2.9
import QtQuick.Controls 2.2

TextField {
    id: control
    color:                "#cdd6f4"
    placeholderTextColor: "#585b70"
    font.pixelSize:       13
    leftPadding:          10
    rightPadding:         10
    background: Rectangle {
        color:        "#313244"
        radius:       4
        border.color: control.activeFocus ? "#89b4fa" : "#45475a"
        border.width: 1
    }
}
