import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';
import 'package:repiq/services/subscription_service.dart';
import 'package:repiq/viewmodels/subscription_viewmodel.dart';

/// Subscription paywall — shown when a user taps a premium-locked feature.
class PaywallView extends StatelessWidget {
  const PaywallView({super.key});

  /// Push-navigates to the paywall and returns when dismissed.
  static Future<void> show(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaywallView()));

  @override
  Widget build(BuildContext context) {
    final sub = context.watch<SubscriptionViewModel>();
    return Scaffold(
      backgroundColor: const Color(0xFF0E1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1117),
        surfaceTintColor: Colors.transparent,
        leading: const CloseButton(),
        title: const Text('Upgrade to Premium'),
      ),
      body: sub.isLoading && sub.products.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PremiumHeader(),
                  const SizedBox(height: 28),
                  _FeatureList(),
                  const SizedBox(height: 28),
                  if (sub.products.isEmpty)
                    _BillingUnavailable()
                  else
                    _PricingCards(products: sub.products),
                  const SizedBox(height: 16),
                  if (sub.error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        sub.error!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  TextButton(
                    onPressed: () => context.read<SubscriptionViewModel>().restore(),
                    child: const Text('Restore Purchases',
                        style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    children: const [
                      Text('Privacy Policy',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('·',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('Terms of Service',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}

class _PremiumHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.redAccent.withValues(alpha: 0.25),
            Colors.blueAccent.withValues(alpha: 0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome,
                color: Colors.redAccent, size: 32),
          ),
          const SizedBox(height: 12),
          const Text(
            'Unlock the full AI experience',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'Get smarter recommendations, progress analytics,\nand advanced training modes.',
            style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FeatureList extends StatelessWidget {
  static const _features = [
    (Icons.bolt, 'Hypertrophy & Strength modes',
        'Tailored rep ranges and weight increments per goal'),
    (Icons.show_chart, 'Progress charts',
        '1RM trends, max weight, and volume over time'),
    (Icons.notes, 'Form & fatigue analysis',
        'AI reads your logged notes to catch issues'),
    (Icons.cloud_sync, 'Cloud model retraining',
        'Sync your data to retrain the XGBoost model'),
    (Icons.auto_awesome, 'Advanced AI recommendations',
        'Safety overrides, momentum tracking, and more'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _features
          .map((f) => _FeatureRow(icon: f.$1, title: f.$2, subtitle: f.$3))
          .toList(),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _FeatureRow(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.blueAccent, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
        ],
      ),
    );
  }
}

class _PricingCards extends StatefulWidget {
  final List<ProductDetails> products;
  const _PricingCards({required this.products});

  @override
  State<_PricingCards> createState() => _PricingCardsState();
}

class _PricingCardsState extends State<_PricingCards> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    // Default to annual if available (best value)
    final hasAnnual =
        widget.products.any((p) => p.id == kAnnualProductId);
    _selected =
        hasAnnual ? kAnnualProductId : widget.products.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final sub = context.read<SubscriptionViewModel>();
    return Column(
      children: [
        Row(
          children: widget.products
              .map((p) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _PlanCard(
                        product: p,
                        isSelected: _selected == p.id,
                        isBestValue: p.id == kAnnualProductId,
                        onTap: () => setState(() => _selected = p.id),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _selected == null
                ? null
                : () {
                    final product = widget.products
                        .firstWhere((p) => p.id == _selected);
                    sub.subscribe(product);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Subscribe',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Cancel anytime from Google Play',
          style: TextStyle(color: Colors.grey, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final ProductDetails product;
  final bool isSelected;
  final bool isBestValue;
  final VoidCallback onTap;
  const _PlanCard({
    required this.product,
    required this.isSelected,
    required this.isBestValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor =
        isSelected ? Colors.redAccent : Colors.white12;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.redAccent.withValues(alpha: 0.1)
              : const Color(0xFF262730),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isBestValue)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('Best Value',
                    style: TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            Text(
              product.id == kAnnualProductId ? 'Annual' : 'Monthly',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              product.price,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.redAccent : Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              product.id == kAnnualProductId ? 'per year' : 'per month',
              style:
                  const TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _BillingUnavailable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        children: [
          Icon(Icons.store_outlined, color: Colors.grey, size: 36),
          SizedBox(height: 12),
          Text(
            'Google Play billing is not available on this device.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          SizedBox(height: 6),
          Text(
            'Ensure you are signed into a Google account and that '
            'the subscription products are published in Play Console.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
