import Foundation
import SwiftUI

// MARK: - AI Agent Registry

/// Central registry for all AI agent plugins
/// Add new agents by registering them in the `allPlugins` array
enum AIAgentRegistry {
    
    // MARK: - Registered Plugins
    
    /// All registered AI agent plugins
    /// Add new plugins here to enable them throughout the app
    static let allPlugins: [AIAgentPlugin.Type] = [
        ClaudeAgent.self,
        KimiAgent.self,
        OpenCodeAgent.self
    ]
    
    // MARK: - Plugin Lookup
    
    /// Get a plugin by its agent ID
    static func plugin(for agentID: String) -> AIAgentPlugin.Type? {
        allPlugins.first { $0.agentID == agentID }
    }
    
    /// Get display name for an agent ID
    static func displayName(for agentID: String) -> String {
        plugin(for: agentID)?.displayName ?? agentID.capitalized
    }
    
    /// Get icon name for an agent ID
    static func iconName(for agentID: String) -> String {
        plugin(for: agentID)?.iconName ?? "sparkles"
    }
    
    /// Check if the icon is a custom image asset (not an SF Symbol)
    /// Custom assets are identified by PascalCase naming (e.g., "KimiIcon", "ClaudeIcon")
    /// SF Symbols are lowercase with dots (e.g., "sparkles", "moon.stars", "brain")
    static func isCustomIcon(_ iconName: String) -> Bool {
        // Custom asset names start with uppercase letter (PascalCase)
        // SF Symbols are all lowercase
        if let firstChar = iconName.first {
            return firstChar.isUppercase
        }
        return false
    }
    
    /// Get theme color for an agent ID
    static func themeColor(for agentID: String) -> Color {
        let colorName = plugin(for: agentID)?.themeColor ?? "purple"
        return colorFromName(colorName)
    }
    
    /// Get all installed agents on a server
    static func detectInstalledAgents(over session: SSHSession) async -> [AIAgentPlugin.Type] {
        var installed: [AIAgentPlugin.Type] = []
        
        for plugin in allPlugins {
            if let result = try? await plugin.isInstalled(over: session), result {
                installed.append(plugin)
            }
        }
        
        return installed
    }
    
    // MARK: - Combined Operations
    
    /// Detect all running AI agents across all tmux sessions
    static func detectAllRunningSessions(
        over session: SSHSession,
        tmuxSessions: [TmuxSession]
    ) async -> [String: Set<String>] {
        var results: [String: Set<String>] = [:]
        
        await withTaskGroup(of: (String, Set<String>).self) { group in
            for plugin in allPlugins {
                group.addTask {
                    let running = (try? await plugin.detectRunningSessions(
                        over: session,
                        tmuxSessions: tmuxSessions
                    )) ?? []
                    return (plugin.agentID, running)
                }
            }
            
            for await (agentID, running) in group {
                if !running.isEmpty {
                    results[agentID] = running
                }
            }
        }
        
        return results
    }
    
    /// Get sessions from all installed agents
    static func listAllSessions(over session: SSHSession) async -> [AIAgentSession] {
        await listAllSessions(over: session, installedAgents: allPlugins)
    }

    /// Get sessions from a known set of installed agents (skips redundant isInstalled checks)
    static func listAllSessions(over session: SSHSession, installedAgents: [AIAgentPlugin.Type]) async -> [AIAgentSession] {
        var allSessions: [AIAgentSession] = []

        await withTaskGroup(of: [AIAgentSession].self) { group in
            for plugin in installedAgents {
                group.addTask {
                    return (try? await plugin.listSessions(over: session)) ?? []
                }
            }

            for await sessions in group {
                allSessions.append(contentsOf: sessions)
            }
        }

        return allSessions.sorted { ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast) }
    }
    
    // MARK: - Helper
    
    private static func colorFromName(_ name: String) -> Color {
        switch name.lowercased() {
        case "purple": return .purple
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "pink": return .pink
        case "cyan", "teal": return .cyan
        case "indigo": return .indigo
        case "mint": return .mint
        case "yellow": return .yellow
        case "gray", "grey": return .gray
        case "black": return .black
        default: return .purple
        }
    }
}

// MARK: - Running Agent Info

/// Information about an AI agent running in a tmux session
struct RunningAgentInfo {
    let agentID: String
    let tmuxSessionName: String
    let windowIndex: Int?
    
    var displayName: String {
        AIAgentRegistry.displayName(for: agentID)
    }
    
    var iconName: String {
        AIAgentRegistry.iconName(for: agentID)
    }
    
    var themeColor: Color {
        AIAgentRegistry.themeColor(for: agentID)
    }
}
