part of '../vault_panel.dart';

class _VaultEntryCard extends StatelessWidget {
  final VaultEntry entry;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool lifted;
  final bool copied;
  final String? status;

  const _VaultEntryCard({
    super.key,
    required this.entry,
    this.onTap,
    this.trailing,
    this.lifted = false,
    this.copied = false,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = entry.conflictOf == null
        ? entry.title
        : '${entry.title} · ${t.syncVariant(id: entry.id.substring(0, entry.id.length < 10 ? entry.id.length : 10))}';
    final subtitle = entry.isTotp
        ? t.totpKind
        : entry.isFile
        ? '${(entry.attachments.single.size / 1024).toStringAsFixed(1)} KiB'
        : entry.isSsh
        ? lifted
              ? t.sshConnect
              : '${entry.username}@${entry.ssh!.host}:${entry.ssh!.port}'
        : entry.username.isEmpty || lifted
        ? t.vaultSecretKind
        : entry.username;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: BorderSide(color: lifted || copied ? colors.primary.withValues(alpha: 0.35) : Colors.transparent),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
      child: Material(
        color: lifted || copied ? colors.surfaceContainerHigh : Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: lifted ? 6 : 0,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 24,
                    height: 28,
                    decoration: BoxDecoration(
                      color: copied ? colors.primary.withValues(alpha: 0.18) : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      copied
                          ? Icons.check_rounded
                          : entry.isTotp
                          ? Icons.timer_outlined
                          : entry.isFile
                          ? Icons.insert_drive_file_outlined
                          : entry.isSsh
                          ? Icons.terminal_rounded
                          : Icons.lock_outline_rounded,
                      color: colors.primary,
                      size: 17,
                    ),
                  ),
                  const SizedBox(width: 8),
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
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Semantics(
                          liveRegion: copied,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 160),
                            layoutBuilder: (currentChild, previousChildren) => Stack(
                              alignment: Alignment.centerLeft,
                              children: [...previousChildren, ?currentChild],
                            ),
                            child: Text(
                              status ?? (copied ? t.copied : subtitle),
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
                    const SizedBox(width: 32)
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
