import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

class ConnectNowPlayingScreen extends StatelessWidget {
  const ConnectNowPlayingScreen({super.key, required this.state});

  final HostState state;

  @override
  Widget build(BuildContext context) {
    final track = state.nowPlaying;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (track?.artworkUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(track!.artworkUrl!, height: 220, fit: BoxFit.cover),
            ),
          const SizedBox(height: 24),
          Text(
            track?.title ?? 'Nothing playing',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (track != null) Text(track.artist),
          const SizedBox(height: 24),
          LinearProgressIndicator(
            value: state.durationMs == 0
                ? null
                : (state.positionMs / state.durationMs).clamp(0, 1),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatMs(state.positionMs)),
              Text(state.isPlaying ? 'Playing' : 'Paused'),
              Text(_formatMs(state.durationMs)),
            ],
          ),
        ],
      ),
    );
  }

  String _formatMs(int ms) {
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
