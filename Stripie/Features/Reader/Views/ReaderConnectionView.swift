import SwiftUI
import StripeTerminal

struct ReaderConnectionView: View {
    @State private var viewModel: ReaderViewModel

    init(viewModel: ReaderViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if case .connected(let reader) = viewModel.connectionState {
                    connectedView(reader: reader)
                } else {
                    discoveryView
                }
            }
            .navigationTitle("Reader")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .overlay {
                // Configuration progress while connecting (App Review 3.9.1):
                // make clear Tap to Pay isn't ready yet.
                if case .connecting = viewModel.connectionState {
                    LoadingOverlay(message: "Preparing Tap to Pay… not ready yet")
                } else if viewModel.isLoading && viewModel.discoveredReaders.isEmpty {
                    LoadingOverlay(message: "Searching for readers…")
                }
            }
            .errorBanner($viewModel.error)
            .task {
                if !viewModel.connectionState.isConnected {
                    await viewModel.startDiscovery()
                }
            }
        }
    }

    // MARK: - Subviews

    private var discoveryView: some View {
        List {
            if viewModel.discoveredReaders.isEmpty && !viewModel.isDiscovering {
                ContentUnavailableView(
                    "No Readers Found",
                    systemImage: "iphone.and.arrow.forward",
                    description: Text("Make sure your iPhone supports Tap to Pay and retry.")
                )
            } else {
                Section("Available Readers") {
                    ForEach(viewModel.discoveredReaders, id: \.stripeId) { reader in
                        ReaderRow(reader: reader) {
                            Task { await viewModel.connect(to: reader) }
                        }
                    }
                }
            }
        }
    }

    private func connectedView(reader: Reader) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            VStack(spacing: 4) {
                Text(reader.label ?? "iPhone (Tap to Pay)")
                    .font(.title2.weight(.semibold))
                Text("Ready to accept payments")
                    .foregroundStyle(.secondary)
            }

            if let progress = viewModel.updateProgress {
                VStack(spacing: 8) {
                    Text("Updating reader…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: progress)
                        .padding(.horizontal)
                }
            }

            Spacer()

            SecondaryButton("Disconnect") {
                Task { await viewModel.disconnect() }
            }
            .padding(.horizontal)
        }
        .padding(.top, 48)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if viewModel.isDiscovering {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Stop") { viewModel.stopDiscovery() }
            }
        } else if !viewModel.connectionState.isConnected {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Search") {
                    Task { await viewModel.startDiscovery() }
                }
            }
        }
    }
}

// MARK: - ReaderRow

private struct ReaderRow: View {
    let reader: Reader
    let onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack {
                Image(systemName: "iphone")
                    .font(.title3)
                    .foregroundStyle(Color.tgkPrimary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(reader.label ?? "iPhone")
                        .foregroundStyle(.primary)
                    Text("Tap to Pay on iPhone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        }
    }
}

// MARK: - Status Badge

struct ReaderStatusBadge: View {
    let state: ReaderConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
            Text(state.displayTitle)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
    }

    private var indicatorColor: Color {
        switch state {
        case .connected:    return .green
        case .connecting,
             .discovering:  return .orange
        case .disconnected: return .red
        }
    }
}

#if DEBUG
#Preview("Disconnected") {
    ReaderConnectionView(viewModel: .preview())
}

#Preview("Status Badge") {
    VStack(spacing: 12) {
        ReaderStatusBadge(state: .disconnected)
        ReaderStatusBadge(state: .discovering)
        ReaderStatusBadge(state: .connecting)
    }
}
#endif
