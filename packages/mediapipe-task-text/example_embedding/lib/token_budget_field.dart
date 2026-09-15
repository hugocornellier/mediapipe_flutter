import 'package:flutter/material.dart';

/// Presets passed to the official task's combined input/output token budget.
class TokenBudgetField extends StatelessWidget {
  const TokenBudgetField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int? value;
  final ValueChanged<int?>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: DropdownButtonFormField<int>(
      initialValue: value ?? 0,
      decoration: const InputDecoration(
        labelText: 'Token budget',
        helperText:
            'Input + output combined. Small budgets can reject input or truncate output.',
        helperMaxLines: 2,
        border: OutlineInputBorder(),
      ),
      items: [
        const DropdownMenuItem(value: 0, child: Text('Model default (8k)')),
        for (final tokens in [64, 256, 1024, 4096, 8192])
          DropdownMenuItem(value: tokens, child: Text('$tokens tokens')),
      ],
      onChanged: onChanged == null
          ? null
          : (value) => onChanged!(value == 0 ? null : value),
    ),
  );
}
