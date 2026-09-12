part of 'manager_window.dart';

class _GeneratorPanel extends StatelessWidget {
  final bool compact;
  final String password;
  final int length;
  final bool symbols;
  final bool copied;
  final bool copying;
  final VoidCallback onCopy;
  final VoidCallback onRegenerate;
  final ValueChanged<double> onLengthChanged;
  final ValueChanged<bool> onSymbolsChanged;

  const _GeneratorPanel({
    required this.compact,
    required this.password,
    required this.length,
    required this.symbols,
    required this.copied,
    required this.copying,
    required this.onCopy,
    required this.onRegenerate,
    required this.onLengthChanged,
    required this.onSymbolsChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!compact)
        Text(
          t.newPassword,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.7,
          ),
        ),
      if (!compact) const SizedBox(height: 4),
      Text(t.generatedLocally, style: TextStyle(color: AppColors.muted, fontSize: 13)),
      SizedBox(height: compact ? 4 : 12),
      Container(
        key: const Key('password-panel'),
        height: compact ? 64 : 100,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: _GeneratedPasswordPreview(password: password),
      ),
      SizedBox(height: compact ? 4 : 12),
      Row(
        children: [
          Text(t.length, style: TextStyle(fontSize: 14)),
          Expanded(
            child: Slider(
              key: const Key('length-slider'),
              value: length.toDouble(),
              min: 12,
              max: 64,
              divisions: 52,
              label: '$length',
              onChanged: onLengthChanged,
              onChangeEnd: (_) => onRegenerate(),
            ),
          ),
          SizedBox(
            width: 24,
            child: Text(
              '$length',
              textAlign: TextAlign.end,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
        ],
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(t.symbols, style: TextStyle(fontSize: 14))),
          Switch(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            value: symbols,
            onChanged: onSymbolsChanged,
          ),
        ],
      ),
      SizedBox(height: compact ? 4 : 12),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              key: const Key('copy-password'),
              onPressed: copying ? null : onCopy,
              icon: Icon(
                copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 17,
              ),
              label: Text(copied ? t.copied : t.copy),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filledTonal(
            tooltip: t.regenerate,
            onPressed: onRegenerate,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        t.clipboardHelp,
        key: const Key('clipboard-help'),
        style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.5),
      ),
    ],
  );
}

class _GeneratedPasswordPreview extends StatelessWidget {
  final String password;

  const _GeneratedPasswordPreview({
    required this.password,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final baseStyle = DefaultTextStyle.of(context).style.merge(
        const TextStyle(
          fontFamily: 'Consolas',
          fontSize: 21,
          height: 1.4,
          color: AppColors.accent,
          letterSpacing: 1,
        ),
      );
      final scaler = MediaQuery.textScalerOf(context);
      final painter = TextPainter(
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      );
      bool fits(double fontSize) {
        painter.text = TextSpan(
          text: password,
          style: baseStyle.copyWith(fontSize: fontSize),
        );
        painter.layout(maxWidth: constraints.maxWidth);
        return painter.height <= constraints.maxHeight &&
            painter.computeLineMetrics().every(
              (line) => line.width <= constraints.maxWidth,
            );
      }

      var fontSize = 21.0;
      if (!fits(fontSize)) {
        var lower = 0.0;
        var upper = fontSize;
        for (var step = 0; step < 12; step++) {
          final middle = (lower + upper) / 2;
          if (fits(middle)) {
            lower = middle;
          } else {
            upper = middle;
          }
        }
        fontSize = lower;
      }
      painter.dispose();
      return Center(
        child: Text(
          password,
          key: const Key('generated-password'),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          textScaler: scaler,
          style: baseStyle.copyWith(fontSize: fontSize),
        ),
      );
    },
  );
}
