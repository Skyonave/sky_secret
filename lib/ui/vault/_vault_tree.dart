part of 'vault_panel.dart';

class _VaultDrag {
  final VaultSession session;
  final VaultItem item;

  const _VaultDrag(this.session, this.item);
}

class _VaultInsertion {
  final String? parentId;
  final String? beforeKey;

  const _VaultInsertion(this.parentId, this.beforeKey);

  ({String? parentId, String? beforeKey}) get key => (parentId: parentId, beforeKey: beforeKey);
}

class _VaultTree extends StatefulWidget {
  final VaultSession session;
  final bool busy;
  final Set<String> collapsed;
  final Widget Function(VaultEntry) entryCard;
  final void Function(String?) createFolder;
  final void Function(VaultFolder) renameFolder;
  final void Function(VaultFolder) deleteFolder;
  final void Function(String?) addEntry;
  final void Function(String?) addFile;
  final void Function(String?) addSsh;
  final void Function(String?) createTextFile;
  final Future<void> Function(VaultItem, String?, String?) move;

  const _VaultTree({
    super.key,
    required this.session,
    required this.busy,
    required this.collapsed,
    required this.entryCard,
    required this.createFolder,
    required this.renameFolder,
    required this.deleteFolder,
    required this.addEntry,
    required this.addFile,
    required this.addSsh,
    required this.createTextFile,
    required this.move,
  });

  @override
  State<_VaultTree> createState() => _VaultTreeState();
}

class _VaultTreeState extends State<_VaultTree> {
  Timer? _expandTimer;
  String? _expandId;
  EdgeDraggingAutoScroller? _scroller;
  final _headerKeys = <String, GlobalKey>{};
  String? _nativeFolderId;
  bool _nativeHover = false;
  final _gapKeys = <({String? parentId, String? beforeKey}), GlobalKey>{};
  final _entryKeys = <String, GlobalKey>{};
  _VaultInsertion? _insertion;
  Offset _grabOffset = Offset.zero;
  Offset? _insertionPointer;
  double _dragHeight = 56;

  VaultOrganization get _organization =>
      VaultOrganization(entries: widget.session.entries, folders: widget.session.folders);

  void stopDragging() {
    _expandTimer?.cancel();
    _expandId = null;
    _scroller?.stopAutoScroll();
  }

  @override
  void didUpdateWidget(_VaultTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session || widget.busy || widget.session.isLocked) {
      stopDragging();
      _nativeFolderId = null;
      _nativeHover = false;
      _insertion = null;
      _insertionPointer = null;
    }
  }

  @override
  void dispose() {
    stopDragging();
    super.dispose();
  }

  void _hoverFolder(String? id) {
    if (id == _expandId) return;
    _expandTimer?.cancel();
    _expandId = id;
    if (id == null || !widget.collapsed.contains(id)) return;
    _expandTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted && !widget.busy && !widget.session.isLocked) {
        setState(() => widget.collapsed.remove(id));
      }
    });
  }

  void _scroll(Offset position) {
    _scroller ??= EdgeDraggingAutoScroller(Scrollable.of(context), velocityScalar: 12);
    _scroller!.startAutoScrollIfNecessary(Rect.fromCenter(center: position, width: 1, height: 1));
  }

  String? get nativeFolderId => _nativeFolderId;

  void nativeHover(Offset? position) {
    String? folderId;
    if (position != null && !widget.busy && !widget.session.isLocked) {
      for (final folder in widget.session.folders) {
        final box = _headerKeys[folder.id]?.currentContext?.findRenderObject();
        if (box is RenderBox && box.hasSize && (box.localToGlobal(Offset.zero) & box.size).contains(position)) {
          folderId = folder.id;
          break;
        }
      }
      _scroll(position);
    } else {
      stopDragging();
    }
    _hoverFolder(folderId);
    if (_nativeFolderId != folderId || _nativeHover != (position != null)) {
      setState(() {
        _nativeFolderId = folderId;
        _nativeHover = position != null;
      });
    }
  }

  bool _accept(_VaultDrag drag, String? parentId) =>
      !widget.busy &&
      !widget.session.isLocked &&
      identical(drag.session, widget.session) &&
      _organization.canMove(drag.item, parentId);

  void _hoverInsertion(_VaultInsertion insertion, DragTargetDetails<_VaultDrag> details) {
    if (!_accept(details.data, insertion.parentId) || insertion.beforeKey == details.data.item.key) return;
    if (_insertion?.key == insertion.key) return;
    final pointer = details.offset + _grabOffset;
    if (_keepInsertion(details)) return;
    _hoverFolder(null);
    setState(() {
      _insertion = insertion;
      _insertionPointer = pointer;
    });
  }

  bool _keepInsertion(DragTargetDetails<_VaultDrag> details) {
    if (_insertion == null) return false;
    final pointer = details.offset + _grabOffset;
    final gap = _gapKeys[_insertion!.key]?.currentContext?.findRenderObject();
    if (gap is RenderBox && gap.hasSize) {
      final bounds = (gap.localToGlobal(Offset.zero) & gap.size).inflate(6);
      if (bounds.contains(pointer)) return true;
    }
    return _insertionPointer != null && (pointer - _insertionPointer!).distance < 8;
  }

  void _hoverDestination(String? parentId, DragTargetDetails<_VaultDrag> details) {
    if (!_accept(details.data, parentId)) return;
    if (_keepInsertion(details)) return;
    _clearInsertion();
    _hoverFolder(parentId);
  }

  void _clearInsertion() {
    if (_insertion == null) return;
    setState(() {
      _insertion = null;
      _insertionPointer = null;
    });
  }

  void _dropInsertion(_VaultDrag drag) {
    final insertion = _insertion;
    if (insertion != null && _accept(drag, insertion.parentId)) {
      unawaited(widget.move(drag.item, insertion.parentId, insertion.beforeKey));
    }
    _finishDrag();
  }

  Widget _target({
    required String? parentId,
    String? beforeKey,
    required Widget child,
    bool insertion = false,
  }) => DragTarget<_VaultDrag>(
    key: ValueKey((parentId: parentId, beforeKey: beforeKey, insertion: insertion)),
    onWillAcceptWithDetails: (details) {
      final accepted = _accept(details.data, parentId) && beforeKey != details.data.item.key;
      if (accepted) {
        if (insertion) {
          _hoverInsertion(_VaultInsertion(parentId, beforeKey), details);
        } else {
          _hoverDestination(parentId, details);
        }
      }
      return accepted;
    },
    onMove: (details) {
      if (insertion) {
        _hoverInsertion(_VaultInsertion(parentId, beforeKey), details);
      } else {
        _hoverDestination(parentId, details);
      }
    },
    onLeave: (_) => _hoverFolder(null),
    onAcceptWithDetails: (details) {
      if (insertion || _keepInsertion(details)) {
        _dropInsertion(details.data);
        return;
      }
      if (_accept(details.data, parentId)) unawaited(widget.move(details.data.item, parentId, beforeKey));
      _finishDrag();
    },
    builder: (context, candidates, rejected) {
      final active =
          (candidates.isNotEmpty && _insertion == null) || (!insertion && _nativeHover && _nativeFolderId == parentId);
      final colors = Theme.of(context).colorScheme;
      if (insertion) {
        final slot = _VaultInsertion(parentId, beforeKey);
        final opened = _insertion?.key == slot.key;
        return AnimatedContainer(
          key: _gapKeys.putIfAbsent(slot.key, GlobalKey.new),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: opened ? _dragHeight + 8 : 8,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: opened ? colors.primary.withValues(alpha: 0.045) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: opened ? colors.primary.withValues(alpha: 0.22) : Colors.transparent),
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Stack(
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: active ? colors.primary.withValues(alpha: 0.08) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: active ? colors.primary.withValues(alpha: 0.55) : Colors.transparent),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _draggable(VaultItem item, Widget child) => LayoutBuilder(
    builder: (context, constraints) => Draggable<_VaultDrag>(
      key: ValueKey('drag-${item.key}'),
      data: _VaultDrag(widget.session, item),
      maxSimultaneousDrags: widget.busy ? 0 : 1,
      dragAnchorStrategy: (draggable, context, position) {
        _grabOffset = childDragAnchorStrategy(draggable, context, position);
        _dragHeight = context.size!.height;
        return _grabOffset;
      },
      onDragUpdate: (details) => _scroll(details.globalPosition),
      onDragEnd: (_) {
        _finishDrag();
      },
      onDragCompleted: _finishDrag,
      onDraggableCanceled: (_, _) => _finishDrag(),
      feedback: Builder(
        builder: (context) => SizedBox(
          width: constraints.maxWidth,
          height: _dragHeight,
          child: _VaultDragPreview(item: item),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.5, child: child),
      child: child,
    ),
  );

  void _finishDrag() {
    stopDragging();
    if (mounted) _clearInsertion();
  }

  Widget _entryTarget(VaultItem item, String? nextKey) {
    void hover(DragTargetDetails<_VaultDrag> details) {
      if (details.data.item.key == item.key || !_accept(details.data, item.parentId)) return;
      final box = _entryKeys[item.key]?.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final pointer = box.globalToLocal(details.offset + _grabOffset);
        final before = pointer.dy < box.size.height / 2 ? item.key : nextKey;
        _hoverInsertion(_VaultInsertion(item.parentId, before), details);
      }
    }

    return DragTarget<_VaultDrag>(
      key: _entryKeys.putIfAbsent(item.key, GlobalKey.new),
      onWillAcceptWithDetails: (details) {
        if (details.data.item.key == item.key || !_accept(details.data, item.parentId)) return false;
        hover(details);
        return true;
      },
      onMove: hover,
      onAcceptWithDetails: (details) => _dropInsertion(details.data),
      builder: (context, candidates, rejected) => _draggable(item, widget.entryCard(item.entry!)),
    );
  }

  List<PopupMenuEntry<String>> _menu(VaultFolder? folder) => [
    InsetMenuItem(value: 'entry', label: t.vaultAddEntry, icon: Icons.add_rounded),
    InsetMenuItem(value: 'ssh', label: t.sshAdd, icon: Icons.terminal_rounded),
    InsetMenuItem(value: 'file', label: t.vaultAddFile, icon: Icons.upload_file_outlined),
    InsetMenuItem(value: 'text', label: t.vaultCreateTextFile, icon: Icons.note_add_outlined),
    if (folder == null || folder.isSection)
      InsetMenuItem(
        value: 'folder',
        label: folder == null ? t.vaultNewFolder : t.vaultNewSubfolder,
        icon: Icons.create_new_folder_outlined,
      ),
    if (folder != null) ...[
      InsetMenuItem(
        value: 'rename',
        label: folder.isSection ? t.vaultRenameFolder : t.vaultRenameSubfolder,
        icon: Icons.edit_outlined,
      ),
      InsetMenuItem(
        value: 'delete',
        label: folder.isSection ? t.vaultDeleteFolder : t.vaultDeleteSubfolder,
        icon: Icons.delete_outline_rounded,
      ),
    ],
  ];

  void _action(String action, VaultFolder? folder) {
    if (widget.busy || widget.session.isLocked) return;
    switch (action) {
      case 'entry':
        widget.addEntry(folder?.id);
      case 'ssh':
        widget.addSsh(folder?.id);
      case 'file':
        widget.addFile(folder?.id);
      case 'text':
        widget.createTextFile(folder?.id);
      case 'folder':
        widget.createFolder(folder?.id);
      case 'rename':
        if (folder != null) widget.renameFolder(folder);
      case 'delete':
        if (folder != null) widget.deleteFolder(folder);
    }
  }

  Future<void> _contextMenu(Offset position, VaultFolder? folder) async {
    if (widget.busy || widget.session.isLocked) return;
    final session = widget.session;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
      items: _menu(folder),
    );
    if (mounted && identical(session, widget.session) && action != null) _action(action, folder);
  }

  Widget _children(String? parentId) {
    final items = _organization.children(parentId);
    return Column(
      key: ValueKey('children-$parentId'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < items.length; index++) ...[
          _target(parentId: parentId, beforeKey: items[index].key, insertion: true, child: const SizedBox.shrink()),
          if (items[index].folder case final folder?)
            _folder(folder)
          else
            _entryTarget(items[index], index + 1 < items.length ? items[index + 1].key : null),
        ],
        _target(
          parentId: parentId,
          insertion: items.isNotEmpty,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              parentId == null ? t.vaultRootDropHint : t.vaultFolderDropHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }

  Widget _folder(VaultFolder folder) {
    final expanded = !widget.collapsed.contains(folder.id);
    final header = GestureDetector(
      key: _headerKeys.putIfAbsent(folder.id, GlobalKey.new),
      onSecondaryTapDown: (details) => _contextMenu(details.globalPosition, folder),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: ValueKey('folder-header-${folder.id}'),
                onTap: widget.busy
                    ? null
                    : () => setState(() {
                        if (expanded) {
                          widget.collapsed.add(folder.id);
                        } else {
                          widget.collapsed.remove(folder.id);
                        }
                      }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Row(
                    children: [
                      Icon(expanded ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 20),
                      const SizedBox(width: 4),
                      Icon(folder.isSection ? Icons.segment_rounded : Icons.folder_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 4),
                      Text(
                        '${_organization.children(folder.id).length}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            key: ValueKey('folder-actions-${folder.id}'),
            enabled: !widget.busy,
            tooltip: t.vaultLocationActions,
            padding: const EdgeInsets.all(10),
            iconSize: 20,
            itemBuilder: (_) => _menu(folder),
            onSelected: (action) => _action(action, folder),
          ),
        ],
      ),
    );
    return Column(
      key: ValueKey('node-${folder.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _target(parentId: folder.id, child: _draggable(VaultItem.folder(folder), header)),
        if (expanded)
          Container(
            margin: const EdgeInsets.only(left: 12, bottom: 6),
            padding: const EdgeInsets.only(left: 6),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
            ),
            child: _children(folder.id),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _target(
        parentId: null,
        child: GestureDetector(
          onSecondaryTapDown: (details) => _contextMenu(details.globalPosition, null),
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: t.vaultMoveToRoot,
                  child: Text(t.vaultContents, style: Theme.of(context).textTheme.labelLarge),
                ),
              ),
              IconButton(
                key: const Key('add-folder'),
                tooltip: t.vaultNewFolder,
                padding: const EdgeInsets.all(12),
                onPressed: widget.busy ? null : () => widget.createFolder(null),
                icon: const Icon(Icons.create_new_folder_outlined, size: 20),
              ),
            ],
          ),
        ),
      ),
      _children(null),
    ],
  );
}

class _VaultDragPreview extends StatelessWidget {
  final VaultItem item;

  const _VaultDragPreview({required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.entry case final entry?) {
      return _VaultEntryCard(entry: entry, lifted: true);
    }
    final colors = Theme.of(context).colorScheme;
    final icon = item.folder == null
        ? (item.entry!.isFile ? Icons.insert_drive_file_outlined : Icons.key_outlined)
        : (item.folder!.isSection ? Icons.segment_rounded : Icons.folder_outlined);
    return Material(
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      color: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: colors.onSurfaceVariant),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
