import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/session_controller.dart';
import 'package:shared_models/shared_models.dart';

class ConnectPlaylistScreen extends ConsumerWidget {
  const ConnectPlaylistScreen({
    super.key,
    required this.state,
    required this.votedSongIds,
  });

  final HostState state;
  final Set<String> votedSongIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final votingEnabled = state.settings.allowVoting;

    if (state.playlist.isEmpty) {
      return const Center(child: Text('Playlist is empty'));
    }

    return ListView.builder(
      itemCount: state.playlist.length,
      itemBuilder: (context, index) {
        final track = state.playlist[index];
        final isNowPlaying = index == state.nowPlayingIndex;
        final voteScore = state.voteScores[track.id] ?? 0;
        final hasVoted = votedSongIds.contains(track.id);

        return ListTile(
          leading: isNowPlaying ? const Icon(Icons.equalizer) : null,
          title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${track.artist}${voteScore > 0 ? ' · $voteScore votes' : ''}'),
          trailing: votingEnabled
              ? IconButton(
                  onPressed: () => ref.read(connectSessionProvider.notifier).toggleVote(track.id),
                  icon: Icon(hasVoted ? Icons.thumb_up : Icons.thumb_up_outlined),
                )
              : null,
          tileColor: isNowPlaying
              ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
              : null,
        );
      },
    );
  }
}
