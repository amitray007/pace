import PaceCore

extension RailActivationMode {
    var label: String {
        switch self {
        case .modifierHover:
            "Modifier + hover"
        case .clickHandle:
            "Click handle"
        case .dwellHover:
            "Dwell hover"
        }
    }
}

extension RailActivationModifier {
    var label: String {
        switch self {
        case .shift:
            "Shift"
        case .option:
            "Option"
        case .control:
            "Control"
        case .command:
            "Command"
        }
    }
}

extension RailEdge {
    var label: String {
        switch self {
        case .left:
            "Left"
        case .right:
            "Right"
        }
    }
}

extension RailVerticalPosition {
    var label: String {
        switch self {
        case .top:
            "Top"
        case .center:
            "Center"
        case .bottom:
            "Bottom"
        }
    }
}
