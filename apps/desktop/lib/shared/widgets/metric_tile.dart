import 'package:material_ui/material_ui.dart';

class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 360),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        // Avoid EditableText semantics for read-only values. On macOS the
        // Flutter accessibility bridge can send startEditing to a static node.
        SelectionArea(
          child: Text(value, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    ),
  );
}
