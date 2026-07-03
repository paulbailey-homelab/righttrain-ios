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
        PinnedObjectHeader(
            kind: .journey,
            showsKindBadge: false,
            showsActionMenu: recoveryFromCrs != nil,
            title: presentation.routeTitle,
            summary: presentation.subtitleText,
            statusText: presentation.headerStatusText,
            statusTone: presentation.headerStatusTone,
            primaryAction: PinnedHeaderPrimaryAction(
                title: "Unpin",
                systemImage: "pin.slash",
                role: .destructive,
                accessibilityHint: "Removes this Journey Pin.",
                isDisabled: isDeleting,
                action: { confirmation = .unpin }
            )
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
    var borderColor = Color.rightTrainInkFaint
    var borderWidth: CGFloat = 1
    private let content: () -> Content

    init(
        borderColor: Color = Color.rightTrainInkFaint,
        borderWidth: CGFloat = 1,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(RTSpacing.cardPadding)
        .background(Color.rightTrainPaperCream, in: RoundedRectangle(cornerRadius: RTRadius.card))
        .lightSurfaceForeground()
        .overlay {
            RoundedRectangle(cornerRadius: RTRadius.card)
                .stroke(borderColor, lineWidth: borderWidth)
        }
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
