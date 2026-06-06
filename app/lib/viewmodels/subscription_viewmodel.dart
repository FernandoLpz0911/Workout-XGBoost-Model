import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:repiq/services/subscription_service.dart';

/// Manages subscription state and exposes [isPremium] to the widget tree.
///
/// Premium status is cached in SharedPreferences so the app works offline for
/// paying users. Firestore is the authoritative source — checked on every
/// cold start.
class SubscriptionViewModel extends ChangeNotifier {
  final _service = SubscriptionService();
  static const _premiumCacheKey = 'subscription_premium_v1';

  bool _isPremium = false;
  bool _isLoading = false;
  List<ProductDetails> _products = [];
  String? _error;
  SharedPreferences? _prefs;

  bool get isPremium => _isPremium;
  bool get isLoading => _isLoading;
  List<ProductDetails> get products => _products;
  String? get error => _error;

  /// Initialises the billing connection, restores purchases, and verifies
  /// subscription status with Firestore. Must be called after Firebase is
  /// ready and the user is signed in.
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    // Load cached value immediately so premium users see the right UI
    // before the async Firestore check completes.
    _prefs = await SharedPreferences.getInstance();
    _isPremium = _prefs!.getBool(_premiumCacheKey) ?? false;
    notifyListeners();

    try {
      await _service.initialize(_onPurchaseUpdate);
      _products = await _service.queryProducts();

      // Authoritative check from Firestore
      final premium = await _service.fetchPremiumStatus();
      await _setPremium(premium);
    } catch (e) {
      _error = 'Could not verify subscription.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Launches the Google Play purchase sheet for [product].
  Future<void> subscribe(ProductDetails product) async {
    _error = null;
    notifyListeners();
    try {
      await _service.purchase(product);
    } catch (e) {
      _error = 'Purchase failed. Please try again.';
      notifyListeners();
    }
  }

  /// Restores previous purchases — required by Play Store guidelines.
  Future<void> restore() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _service.restore();
    } catch (e) {
      _error = 'Restore failed. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        await _service.completePurchase(purchase);
        await _setPremium(true);
      } else if (purchase.status == PurchaseStatus.error) {
        _error = purchase.error?.message ?? 'Purchase error.';
        notifyListeners();
      }
    }
  }

  Future<void> _setPremium(bool value) async {
    _isPremium = value;
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    await prefs.setBool(_premiumCacheKey, value);
    notifyListeners();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
