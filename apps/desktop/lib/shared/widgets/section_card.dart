import 'package:material_ui/material_ui.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.warning = false});
  final Widget child;
  final bool warning;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: warning
          ? const Color(0xfffff4df)
          : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xffe3e5e8)),
    ),
    child: child,
  );
}
