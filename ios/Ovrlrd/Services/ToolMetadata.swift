import Foundation

/// Metadata for Claude CLI tools - provides display names and icons
enum ToolMetadata {

    /// Returns a user-friendly activity description (e.g., "Reading file...")
    static func activityDescription(for tool: String) -> String {
        switch tool {
        case "Read": return "Reading file..."
        case "Write": return "Writing file..."
        case "Edit": return "Editing file..."
        case "Bash": return "Running command..."
        case "Glob": return "Searching files..."
        case "Grep": return "Searching content..."
        case "WebFetch": return "Fetching webpage..."
        case "WebSearch": return "Searching the web..."
        case "Task": return "Working on subtask..."
        default: return "Using \(tool)..."
        }
    }

    /// Returns an SF Symbol name for the tool
    static func icon(for tool: String) -> String {
        switch tool {
        case "Read": return "doc.text"
        case "Write": return "doc.badge.plus"
        case "Edit": return "pencil"
        case "Bash": return "terminal"
        case "Glob": return "folder.badge.questionmark"
        case "Grep": return "text.magnifyingglass"
        case "WebFetch": return "arrow.down.doc"
        case "WebSearch": return "globe"
        case "Task": return "checklist"
        default: return "wrench.and.screwdriver"
        }
    }
}
