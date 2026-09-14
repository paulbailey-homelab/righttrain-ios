import SwiftUI

private enum ActiveItineraryConfirmation {
    case recovery
    case unpin

    var title: String {
        switch self {
        case .recovery:
            return "Not on this journey?"
        case .unpin:
            return "Unpin this journey?"
        }
    }

    var message: String {
        switch self {
        case .recovery:
            return "RightTrain will look for a replacement journey from your current interchange."
        case .unpin:
            return "This removes the current Journey Pin from RightTrain."
        }
    }
}

/// connection to make.

struct ActiveItineraryHeader: View {
    @Environment(ActiveWindowViewModel.self) private var activeWindowViewModel
    @State private var confirmation: ActiveItineraryConfirmation?
    @State private var isDeleting = false
    var presentation: ActiveItineraryPresentation
    var recoveryFromCrs: String?

    var body: some View {
        // The live glance panel above the card already shows route, status
        // and freshness, so this header contributes only the navigation-bar
        // actions and their confirmations. Attach it with `.background`.
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .pinnedActionsToolbar(
                primaryAction: PinnedHeaderPrimaryAction(
                    title: "Unpin Journey",
                    systemImage: "pin.slash",
                    role: .destructive,
                    accessibilityHint: "Removes this Journey Pin.",
                    isDisabled: isDeleting,
                    action: { confirmation = .unpin }
                ),
                showsMenu: recoveryFromCrs != nil
            ) {
                menuActions
            }
        .disabled(isDeleting)
        .confirmationDialog("Not on this journey?", isPresented: recoveryConfirmationPresented, titleVisibility: .visible) {
            Button("Replan from current station", role: .destructive) {
                replanFromCurrentStation()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ActiveItineraryConfirmation.recovery.message)
        }
        .alert("Unpin this journey?", isPresented: unpinAlertPresented) {
            Button("Unpin Journey", role: .destructive) {
                unpinJourney()
            }
            Button("Keep Pin", role: .cancel) {}
        } message: {
            Text(ActiveItineraryConfirmation.unpin.message)
        }
    }

    @ViewBuilder
    private var menuActions: some View {
        if recoveryFromCrs != nil {
            Button(role: .destructive) {
                confirmation = .recovery
            } label: {
                Label("Not on this journey", systemImage: "arrow.triangle.2.circlepath")
            }
        }
    }

    private var recoveryConfirmationPresented: Binding<Bool> {
        Binding {
            confirmation == .recovery
        } set: { isPresented in
            if !isPresented {
                confirmation = nil
            }
        }
    }

    private var unpinAlertPresented: Binding<Bool> {
        Binding {
            confirmation == .unpin
        } set: { isPresented in
            if !isPresented {
                confirmation = nil
            }
        }
    }

    private func replanFromCurrentStation() {
        guard let recoveryFromCrs else { return }
        Task {
            await activeWindowViewModel.replanItineraryFromCurrentStation(
                fromCrs: recoveryFromCrs,
                itineraryID: presentation.itinerary.id
            )
        }
    }

    private func unpinJourney() {
        guard !isDeleting else { return }
        isDeleting = true
        Task {
            await activeWindowViewModel.deleteActiveItinerary()
            await MainActor.run {
                isDeleting = false
            }
        }
    }
}

struct ActiveItineraryCard<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(RTSpacing.cardPadding)
        .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card, style: .continuous))
        .lightSurfaceForeground()
    }
}

#Preview("Pinned Itinerary - Planning") {
    PreviewAppContainer {
        ScrollView {
            PerspectiveActiveItineraryView(
                itinerary: PreviewFixtures.activeItinerary(phase: .planning),
                loadDetail: { _ in }
            )
            .padding(RTSpacing.pageHorizontal)
        }
        .background(Color.rightTrainSurfaceCream)
    }
}

#Preview("Pinned Itinerary - Change") {
    PreviewAppContainer {
        ScrollView {
            PerspectiveActiveItineraryView(
                itinerary: PreviewFixtures.activeItinerary(phase: .approachingInterchange, currentLegIndex: 0),
                loadDetail: { _ in }
            )
            .padding(RTSpacing.pageHorizontal)
        }
        .background(Color.rightTrainSurfaceCream)
    }
}

#Preview("Pinned Itinerary - Final") {
    PreviewAppContainer {
        ScrollView {
            PerspectiveActiveItineraryView(
                itinerary: PreviewFixtures.activeItinerary(phase: .onFinalLeg, currentLegIndex: 1),
                loadDetail: { _ in }
            )
            .padding(RTSpacing.pageHorizontal)
        }
        .background(Color.rightTrainSurfaceCream)
    }
}
