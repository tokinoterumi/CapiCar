import SwiftUI

struct SyncStatusWidget: View {
    @EnvironmentObject private var syncManager: SyncManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Connection status indicator
            connectionStatusIcon
            
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(statusColor)
                
                Text(statusDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Sync actions
            syncActionButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(statusBackgroundColor)
        .cornerRadius(10)
        .animation(.easeInOut(duration: 0.3), value: syncManager.isOnline)
        .animation(.easeInOut(duration: 0.3), value: syncManager.isSyncing)
    }
    
    // MARK: - Subviews
    
    private var connectionStatusIcon: some View {
        Group {
            if syncManager.isSyncing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(0.8)
            } else {
                Image(systemName: syncManager.isOnline ? "wifi" : "wifi.slash")
                    .font(.title3)
                    .foregroundColor(statusColor)
            }
        }
        .frame(width: 24, height: 24)
    }
    
    private var syncActionButton: some View {
        Group {
            if syncManager.pendingChangesCount > 0 {
                Button(action: {
                    Task {
                        await syncManager.forceSyncNow()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                        Text("\(syncManager.pendingChangesCount)")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange)
                    .cornerRadius(6)
                }
                .disabled(syncManager.isSyncing || !syncManager.isReady)
            } else if let lastSync = syncManager.lastSyncDate {
                Text(formatLastSyncTime(lastSync))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("Ready")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var statusTitle: String {
        if !syncManager.isReady {
            return "Initializing..."
        } else if syncManager.isSyncing {
            return "Syncing..."
        } else if syncManager.isOnline {
            if syncManager.syncError != nil {
                return "Sync Error"
            } else {
                return "Online"
            }
        } else {
            return "Offline"
        }
    }
    
    private var statusDescription: String {
        if !syncManager.isReady {
            return "Setting up offline sync"
        } else if syncManager.isSyncing {
            return "Updating data"
        } else if syncManager.isOnline {
            if let error = syncManager.syncError {
                return error
            } else if syncManager.pendingChangesCount > 0 {
                return "\(syncManager.pendingChangesCount) pending changes"
            } else {
                return "All data synced"
            }
        } else {
            if syncManager.pendingChangesCount > 0 {
                return "\(syncManager.pendingChangesCount) changes will sync when online"
            } else {
                return "Working offline"
            }
        }
    }
    
    private var statusColor: Color {
        if !syncManager.isReady {
            return .gray
        } else if syncManager.isSyncing {
            return .blue
        } else if syncManager.isOnline {
            if syncManager.syncError != nil {
                return .red
            } else {
                return .green
            }
        } else {
            return .orange
        }
    }
    
    private var statusBackgroundColor: Color {
        if syncManager.syncError != nil {
            return Color.red.opacity(0.1)
        } else if !syncManager.isOnline {
            return Color.orange.opacity(0.1)
        } else if syncManager.pendingChangesCount > 0 {
            return Color.orange.opacity(0.05)
        } else {
            return Color(.secondarySystemGroupedBackground)
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatLastSyncTime(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
}

// MARK: - Preview
#if DEBUG
struct SyncStatusWidget_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            SyncStatusWidget()
                .environmentObject(SyncManager.shared)
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
