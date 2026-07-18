import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_models/shared_models.dart';
import 'package:uuid/uuid.dart';

import '../../services/device_service.dart';
import '../../services/playback_service.dart';
import '../../services/session_controller.dart';
import '../widgets/track_search_sheet.dart';

class HostListsScreen extends ConsumerWidget {
  const HostListsScreen({super.key});

  /// Opens track search and optionally autoplays the first song.
  static Future<void> showAddTrackSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final hostBefore = ref.read(hostSessionProvider).state;
    final shouldAutoplay =
        hostBefore.playlist.isEmpty || hostBefore.nowPlayingIndex < 0;

    final track = await showModalBottomSheet<Track>(
      context: context,
      isScrollControlled: true,
      builder: (context) => TrackSearchSheet(
        provider: ref.read(hostSessionProvider.notifier).musicProvider,
      ),
    );
    if (track == null) return;

    ref.read(hostSessionProvider.notifier).addTrack(track);
    if (!shouldAutoplay) return;

    final playlist = ref.read(hostSessionProvider).state.playlist;
    final index = playlist.indexWhere((item) => item.id == track.id);
    if (index >= 0) {
      await ref.read(playbackProvider.notifier).playIndex(index);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(hostSessionProvider);
    final playlist = host.state.playlist;

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.45,
              ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Load playlist',
                  onPressed: () => _loadPlaylist(context, ref),
                  icon: const Icon(Icons.file_open_outlined),
                ),
                IconButton(
                  tooltip: 'Share playlist',
                  onPressed: playlist.isEmpty
                      ? null
                      : () => _sharePlaylist(context, host.state),
                  icon: const Icon(Icons.share_outlined),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Save playlist',
                  onPressed: playlist.isEmpty
                      ? null
                      : () => _savePlaylist(context, ref),
                  icon: const Icon(Icons.file_download_outlined),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: playlist.isEmpty
              ? const Center(child: Text('Playlist is empty'))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: playlist.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    ref
                        .read(hostSessionProvider.notifier)
                        .moveTrack(oldIndex, newIndex);
                  },
                  itemBuilder: (context, index) {
                    final track = playlist[index];
                    final playback = ref.read(playbackProvider.notifier);
                    final isNowPlaying = track.id == playback.activeTrackId ||
                        (playback.activeTrackId == null &&
                            index == host.state.nowPlayingIndex);
                    return _PlaylistTile(
                      key: ValueKey(track.id),
                      track: track,
                      index: index,
                      isNowPlaying: isNowPlaying,
                      voteScore: host.state.voteScores[track.id] ?? 0,
                      onPlay: () =>
                          ref.read(playbackProvider.notifier).playIndex(index),
                      onRemove: () => ref
                          .read(hostSessionProvider.notifier)
                          .removeTrackAt(index),
                      onMoveTop: () => ref
                          .read(hostSessionProvider.notifier)
                          .moveTrackToTop(index),
                      onMoveBottom: () => ref
                          .read(hostSessionProvider.notifier)
                          .moveTrackToBottom(index),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _savePlaylist(BuildContext context, WidgetRef ref) async {
    final playlist = ref.read(hostSessionProvider).state.playlist;
    if (playlist.isEmpty) return;

    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save playlist'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Playlist name',
            hintText: 'Friday night',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(nameController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.isEmpty) return;
    if (!context.mounted) return;

    final persistence = await ref.read(sessionPersistenceProvider.future);
    await persistence.savePlaylist(
      SavedPlaylist(
        id: const Uuid().v4(),
        name: name,
        tracks: List<Track>.from(playlist),
        savedAt: DateTime.now(),
      ),
    );
    ref.invalidate(savedPlaylistsProvider);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved “$name”')),
    );
  }

  Future<void> _loadPlaylist(BuildContext context, WidgetRef ref) async {
    final playlists = await ref.read(savedPlaylistsProvider.future);
    if (!context.mounted) return;

    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No saved playlists yet')),
      );
      return;
    }

    final selected = await showModalBottomSheet<SavedPlaylist>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.5,
            minChildSize: 0.35,
            maxChildSize: 0.85,
            builder: (context, scrollController) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Load playlist',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: playlists.length,
                      itemBuilder: (context, index) {
                        final playlist = playlists[index];
                        return ListTile(
                          title: Text(playlist.name),
                          subtitle: Text(
                            '${playlist.tracks.length} songs · '
                            '${_formatSavedAt(playlist.savedAt)}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Delete playlist?'),
                                  content: Text(
                                    'Remove “${playlist.name}” from saved playlists?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm != true) return;
                              final persistence =
                                  await ref.read(sessionPersistenceProvider.future);
                              await persistence.deleteSavedPlaylist(playlist.id);
                              ref.invalidate(savedPlaylistsProvider);
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                          ),
                          onTap: () => Navigator.of(context).pop(playlist),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
    if (selected == null || !context.mounted) return;

    final current = ref.read(hostSessionProvider).state.playlist;
    if (current.isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace playlist?'),
          content: Text(
            'Load “${selected.name}” and replace the current playlist '
            '(${current.length} songs)?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Load'),
            ),
          ],
        ),
      );
      if (replace != true || !context.mounted) return;
    }

    ref.read(hostSessionProvider.notifier).replacePlaylist(selected.tracks);
    await ref.read(playbackProvider.notifier).stopPlayback();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Loaded “${selected.name}”')),
    );
  }

  Future<void> _sharePlaylist(BuildContext context, HostState state) async {
    if (state.playlist.isEmpty) return;
    final buffer = StringBuffer('${state.sessionName}\n\n');
    for (var i = 0; i < state.playlist.length; i++) {
      final track = state.playlist[i];
      buffer.writeln('${i + 1}. ${track.title} — ${track.artist}');
    }
    await SharePlus.instance.share(
      ShareParams(
        text: buffer.toString().trimRight(),
        subject: state.sessionName,
      ),
    );
  }

  String _formatSavedAt(DateTime savedAt) {
    final local = savedAt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required super.key,
    required this.track,
    required this.index,
    required this.isNowPlaying,
    required this.voteScore,
    required this.onPlay,
    required this.onRemove,
    required this.onMoveTop,
    required this.onMoveBottom,
  });

  final Track track;
  final int index;
  final bool isNowPlaying;
  final int voteScore;
  final VoidCallback onPlay;
  final VoidCallback onRemove;
  final VoidCallback onMoveTop;
  final VoidCallback onMoveBottom;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ReorderableDragStartListener(
        index: index,
        child: const Icon(Icons.drag_handle),
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${track.artist}${voteScore > 0 ? ' · $voteScore votes' : ''}'),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'play':
              onPlay();
            case 'top':
              onMoveTop();
            case 'bottom':
              onMoveBottom();
            case 'remove':
              onRemove();
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'play', child: Text('Play now')),
          const PopupMenuItem(value: 'top', child: Text('Move to top')),
          const PopupMenuItem(value: 'bottom', child: Text('Move to bottom')),
          const PopupMenuItem(value: 'remove', child: Text('Remove')),
        ],
      ),
      tileColor: isNowPlaying
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      onTap: onPlay,
    );
  }
}
