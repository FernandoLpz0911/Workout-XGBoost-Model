import 'package:flutter/material.dart';

/// A colored circular icon badge — the shared visual language for leading
/// icons across every list-style screen (Settings, Log, Progress, History,
/// Calendar), so the app reads as one cohesive system.
class IconAvatar extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double radius;
  const IconAvatar({
    super.key,
    required this.icon,
    required this.color,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Icon(icon, color: color, size: radius),
    );
  }
}

/// Uppercase section label used above a [GroupedCard] or other card group.
class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Colors.grey,
        ),
      ),
    );
  }
}

/// Card that lays out its [children] as rows separated by thin dividers, so
/// every multi-row group looks identical regardless of what the rows
/// contain. Used to group related controls (Settings sections, Log's
/// recommendation + inputs, Progress's filters, ...) the same way.
class GroupedCard extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final double dividerIndent;
  const GroupedCard({
    super.key,
    required this.children,
    this.padding,
    this.dividerIndent = 72,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i != 0) Divider(height: 1, indent: dividerIndent),
          children[i],
        ],
      ],
    );
    return Card(
      child: padding == null
          ? content
          : Padding(padding: padding!, child: content),
    );
  }
}

/// One row within a [GroupedCard]: icon avatar, title, optional subtitle,
/// and either a chevron (tappable navigation), a custom [trailing] control,
/// or a loading spinner in place of the icon.
class AppListRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool loading;
  final bool enabled;
  final VoidCallback? onTap;

  const AppListRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.loading = false,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: loading
          ? const SizedBox(
              width: 40,
              height: 40,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : IconAvatar(icon: icon, color: iconColor),
      title: Text(title),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : const Icon(Icons.chevron_right, color: Colors.grey)),
      enabled: enabled && !loading,
      onTap: onTap == null || loading ? null : onTap,
    );
  }
}
