import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Google Play product IDs — must match exactly what you create in the
/// Play Console under Monetize → Subscriptions.
const kMonthlyProductId = 'workout_ml_premium_monthly';
const kAnnualProductId = 'workout_ml_premium_annual';
const kProductIds = {kMonthlyProductId, kAnnualProductId};

/// Manages the Google Play billing connection, purchase stream, and keeps the
/// Firestore user document in sync with the subscription state.
class SubscriptionService {
  final _iap = InAppPurchase.instance;
  final _firestore = FirebaseFirestore.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  /// Starts listening to the purchase stream. [onUpdate] is called whenever
  /// a purchase is completed, restored, or errored so the ViewModel can react.
  Future<void> initialize(
      void Function(List<PurchaseDetails>) onUpdate) async {
    _purchaseSub = _iap.purchaseStream.listen(onUpdate);
    // Trigger restore so existing subscribers are recognised on fresh install.
    await _iap.restorePurchases();
  }

  /// Returns the available subscription [ProductDetails] from Google Play.
  /// Will be empty on emulators or if the products haven't been created in the
  /// Play Console yet.
  Future<List<ProductDetails>> queryProducts() async {
    final available = await _iap.isAvailable();
    if (!available) return [];
    final response = await _iap.queryProductDetails(kProductIds);
    return response.productDetails;
  }

  /// Initiates the Google Play purchase sheet for [product].
  Future<void> purchase(ProductDetails product) async {
    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  /// Triggers a restore-purchases flow (required by Play Store guidelines).
  Future<void> restore() => _iap.restorePurchases();

  /// Marks the purchase as acknowledged and writes the active subscription
  /// status to Firestore so the backend can verify it server-side.
  Future<void> completePurchase(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final isActive = purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored;
    final plan = purchase.productID == kAnnualProductId ? 'annual' : 'monthly';

    await _firestore.collection('users').doc(uid).update({
      'subscriptionStatus': isActive ? 'active' : 'expired',
      'subscriptionPlan': isActive ? plan : null,
      'subscriptionExpiry': isActive
          ? Timestamp.fromDate(DateTime.now().add(
              plan == 'annual'
                  ? const Duration(days: 365)
                  : const Duration(days: 31),
            ))
          : null,
    });
  }

  /// Reads the user's current subscription status directly from Firestore.
  /// Returns true only if status is 'active' and subscriptionExpiry has not passed.
  Future<bool> fetchPremiumStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final snap = await _firestore.collection('users').doc(uid).get();
    if (!snap.exists) return false;
    final data = snap.data()!;
    if (data['isLifetimePremium'] == true) return true;
    if (data['subscriptionStatus'] != 'active') return false;
    final expiry = data['subscriptionExpiry'];
    if (expiry is Timestamp) {
      if (expiry.toDate().toUtc().isBefore(DateTime.now().toUtc())) return false;
    }
    return true;
  }

  void dispose() => _purchaseSub?.cancel();
}
