import Foundation

@MainActor
@Observable
final class SubscriptionViewModel {
    private(set) var products: [SubscriptionProduct] = []
    private(set) var billingProducts: [BillingProduct] = []
    private(set) var message: String?

    @ObservationIgnored private let apiClient: any APIClienting
    @ObservationIgnored private let storeKitService: any StoreKitSubscriptionServicing
    @ObservationIgnored private let operationState: AppOperationState
    @ObservationIgnored private let accessTokenProvider: () -> String?
    @ObservationIgnored private let userProvider: () -> User?
    @ObservationIgnored private let userUpdateHandler: (User) -> Void
    @ObservationIgnored private var transactionObserverTask: Task<Void, Never>?

    init(
        apiClient: any APIClienting,
        storeKitService: any StoreKitSubscriptionServicing,
        operationState: AppOperationState,
        accessTokenProvider: @escaping () -> String?,
        userProvider: @escaping () -> User?,
        userUpdateHandler: @escaping (User) -> Void
    ) {
        self.apiClient = apiClient
        self.storeKitService = storeKitService
        self.operationState = operationState
        self.accessTokenProvider = accessTokenProvider
        self.userProvider = userProvider
        self.userUpdateHandler = userUpdateHandler
    }

    deinit {
        transactionObserverTask?.cancel()
    }

    var isPro: Bool {
        userProvider()?.entitlements.tier == "pro"
    }

    var paidSubscription: PaidSubscriptionEntitlement? {
        userProvider()?.entitlements.paidSubscription
    }

    var productIDs: [String] {
        billingProducts.map(\.productId)
    }

    func refresh() async {
        guard let accessToken = requireAccessToken() else { return }
        await operationState.withLoading {
            try await refreshProducts(accessToken: accessToken)
        }
    }

    func purchase(_ product: SubscriptionProduct) async {
        guard let accessToken = requireAccessToken() else { return }
        guard let userID = userProvider()?.id, let token = UUID(uuidString: userID) else {
            operationState.alertState = .auth(SubscriptionError.missingUserID.localizedDescription)
            return
        }
        await operationState.withLoading {
            if billingProducts.isEmpty {
                try await refreshProducts(accessToken: accessToken)
            }
            let result = try await storeKitService.purchase(productID: product.productID, appAccountToken: token)
            switch result {
            case .success(let pending):
                try await sync(pending, accessToken: accessToken, finishAfterSync: true)
                message = "Your Pro subscription is active."
            case .pending:
                message = "Purchase pending approval."
            case .cancelled:
                break
            }
        }
    }

    func restore() async {
        guard let accessToken = requireAccessToken() else { return }
        await operationState.withLoading {
            if billingProducts.isEmpty {
                try await refreshProducts(accessToken: accessToken)
            }
            let pending = try await storeKitService.restore(productIDs: productIDs)
            if pending.isEmpty {
                message = "No active RightTrain subscription was found for this Apple ID."
            } else {
                try await sync(pending, accessToken: accessToken, finishAfterSync: true)
                message = "Subscription restored."
            }
        }
    }

    func syncCurrentEntitlementsSilently() async {
        guard let accessToken = accessTokenProvider() else { return }
        do {
            if billingProducts.isEmpty {
                try await refreshProducts(accessToken: accessToken)
            }
            let pending = await storeKitService.currentEntitlements(productIDs: productIDs)
            guard !pending.isEmpty else { return }
            try await sync(pending, accessToken: accessToken, finishAfterSync: false)
        } catch {
            operationState.recordSilentOperationError(error)
        }
    }

    func startTransactionObserver() {
        guard transactionObserverTask == nil else { return }
        transactionObserverTask = Task { [weak self] in
            guard let self else { return }
            for await pending in storeKitService.transactionUpdates(productIDs: productIDs) {
                guard let accessToken = accessTokenProvider() else { continue }
                do {
                    try await sync([pending], accessToken: accessToken, finishAfterSync: true)
                } catch {
                    operationState.recordSilentOperationError(error)
                }
            }
        }
    }

    func stopTransactionObserver() {
        transactionObserverTask?.cancel()
        transactionObserverTask = nil
    }

    func openManageSubscriptions() async {
        await storeKitService.openManageSubscriptions()
    }

    private func refreshProducts(accessToken: String) async throws {
        let response = try await apiClient.billingProducts(accessToken: accessToken)
        billingProducts = response.products
        if var currentUser = userProvider() {
            currentUser.entitlements = response.entitlements
            userUpdateHandler(currentUser)
        }
        products = try await storeKitService.loadProducts(response.products)
    }

    private func sync(_ pending: [PendingStoreKitTransaction], accessToken: String, finishAfterSync: Bool) async throws {
        let signedTransactions = pending.map(\.signedPayload)
        guard !signedTransactions.isEmpty else { return }
        let updatedUser = try await apiClient.syncStoreKitTransactions(
            signedTransactions: signedTransactions,
            accessToken: accessToken
        )
        userUpdateHandler(updatedUser)
        if finishAfterSync {
            await storeKitService.finishTransactions(ids: pending.map(\.transactionID))
        }
    }

    private func requireAccessToken() -> String? {
        guard let accessToken = accessTokenProvider() else {
            operationState.alertState = .auth("Sign in to manage your plan.")
            return nil
        }
        return accessToken
    }
}
