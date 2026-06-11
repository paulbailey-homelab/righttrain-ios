import Foundation
import StoreKit
import UIKit

struct SubscriptionProduct: Identifiable, Equatable {
    var productID: String
    var displayName: String
    var displayPrice: String
    var period: String

    var id: String { productID }
}

struct PendingStoreKitTransaction: Equatable {
    var transactionID: UInt64
    var signedPayload: String
}

enum StoreKitPurchaseOutcome: Equatable {
    case success([PendingStoreKitTransaction])
    case pending
    case cancelled
}

@MainActor
protocol StoreKitSubscriptionServicing {
    func loadProducts(_ billingProducts: [BillingProduct]) async throws -> [SubscriptionProduct]
    func purchase(productID: String, appAccountToken: UUID) async throws -> StoreKitPurchaseOutcome
    func restore(productIDs: [String]) async throws -> [PendingStoreKitTransaction]
    func currentEntitlements(productIDs: [String]) async -> [PendingStoreKitTransaction]
    func transactionUpdates(productIDs: [String]) -> AsyncStream<PendingStoreKitTransaction>
    func finishTransactions(ids: [UInt64]) async
    func openManageSubscriptions() async
}

@MainActor
final class StoreKitSubscriptionService: StoreKitSubscriptionServicing {
    private var productsByID: [String: Product] = [:]
    private var pendingTransactions: [UInt64: Transaction] = [:]

    func loadProducts(_ billingProducts: [BillingProduct]) async throws -> [SubscriptionProduct] {
        let productIDs = billingProducts.map(\.productId)
        let products = try await Product.products(for: productIDs)
        productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        let periodsByID = Dictionary(uniqueKeysWithValues: billingProducts.map { ($0.productId, $0.period) })
        return products
            .sorted { lhs, rhs in
                (productIDs.firstIndex(of: lhs.id) ?? productIDs.count) < (productIDs.firstIndex(of: rhs.id) ?? productIDs.count)
            }
            .map {
                SubscriptionProduct(
                    productID: $0.id,
                    displayName: $0.displayName,
                    displayPrice: $0.displayPrice,
                    period: periodsByID[$0.id] ?? "unknown"
                )
            }
    }

    func purchase(productID: String, appAccountToken: UUID) async throws -> StoreKitPurchaseOutcome {
        guard let product = productsByID[productID] else {
            throw SubscriptionError.productUnavailable
        }
        let result = try await product.purchase(options: [.appAccountToken(appAccountToken)])
        switch result {
        case .success(let verification):
            let result = try verifiedTransaction(verification)
            return .success([remember(result.transaction, signedPayload: result.signedPayload)])
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .pending
        }
    }

    func restore(productIDs: [String]) async throws -> [PendingStoreKitTransaction] {
        try await AppStore.sync()
        return await currentEntitlements(productIDs: productIDs)
    }

    func currentEntitlements(productIDs: [String]) async -> [PendingStoreKitTransaction] {
        var pending: [PendingStoreKitTransaction] = []
        let allowed = Set(productIDs)
        for await verification in Transaction.currentEntitlements {
            guard let result = try? verifiedTransaction(verification),
                  allowed.contains(result.transaction.productID) else {
                continue
            }
            pending.append(remember(result.transaction, signedPayload: result.signedPayload))
        }
        return pending
    }

    func transactionUpdates(productIDs: [String]) -> AsyncStream<PendingStoreKitTransaction> {
        let allowed = Set(productIDs)
        return AsyncStream { continuation in
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                for await verification in Transaction.updates {
                    guard let result = try? verifiedTransaction(verification),
                          allowed.contains(result.transaction.productID) else {
                        continue
                    }
                    continuation.yield(remember(result.transaction, signedPayload: result.signedPayload))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func finishTransactions(ids: [UInt64]) async {
        for id in ids {
            guard let transaction = pendingTransactions[id] else { continue }
            await transaction.finish()
            pendingTransactions[id] = nil
        }
    }

    func openManageSubscriptions() async {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return
        }
        try? await AppStore.showManageSubscriptions(in: scene)
    }

    private func remember(_ transaction: Transaction, signedPayload: String) -> PendingStoreKitTransaction {
        pendingTransactions[transaction.id] = transaction
        return PendingStoreKitTransaction(transactionID: transaction.id, signedPayload: signedPayload)
    }

    private func verifiedTransaction(_ result: VerificationResult<Transaction>) throws -> (transaction: Transaction, signedPayload: String) {
        switch result {
        case .verified(let value):
            return (value, result.jwsRepresentation)
        case .unverified(_, let error):
            throw error
        }
    }
}

enum SubscriptionError: LocalizedError {
    case productUnavailable
    case missingUserID

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return "This subscription is not available right now."
        case .missingUserID:
            return "Sign in again before upgrading."
        }
    }
}
