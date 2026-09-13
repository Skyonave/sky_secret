part of '../vault_panel.dart';

class _VaultEntryCard extends StatelessWidget {
  final VaultEntry entry;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool lifted;
  final bool copied;

  const _VaultEntryCard({
    super.key,
    required this.entry,
    this.onTap,
    this.trailing,
    this.lifted = false,
    this.copied = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = entry.conflictOf == null
        ? entry.title
        : '${entry.title} · ${t.syncVariant(id: entry.id.substring(0, entry.id.length < 10 ? entry.id.length : 10))}';
    final subtitle = entry.isFile
        ? '${(entry.attachments.single.size / 1024).toStringAsFixed(1)} KiB'
        : entry.isSsh
        ? lifted
              ? t.sshConnect
              : '${entry.username}@${entry.ssh!.host}:${entry.ssh!.port}'
        : entry.username.isEmpty || lifted
        ? t.vaultSecretKind
        : entry.username;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: lifted || copied ? colors.primary.withValues(alpha: 0.35) : colors.outlineVariant),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: lifted ? colors.surfaceContainerHigh : colors.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        elevation: lifted ? 6 : 0,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: copied ? 0.18 : 0.10),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      copied
                          ? Icons.check_rounded
                          : entry.isFile
                          ? Icons.insert_drive_file_outlined
                          : entry.isSsh
                          ? Icons.terminal_rounded
                          : Icons.lock_outline_rounded,
                      color: colors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Semantics(
                          liveRegion: copied,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 160),
                            layoutBuilder: (currentChild, previousChildren) => Stack(
                              alignment: Alignment.centerLeft,
                              children: [...previousChildren, ?currentChild],
                            ),
                            child: Text(
                              copied ? t.copied : subtitle,
                              key: ValueKey(copied),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: copied ? colors.primary : colors.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (trailing == null)
                    const SizedBox(width: 76)
                  else
                    IconTheme(
                      data: IconThemeData(color: colors.onSurfaceVariant),
                      child: trailing!,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
