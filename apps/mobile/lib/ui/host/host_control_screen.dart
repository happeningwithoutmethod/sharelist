import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/playback_service.dart';
import '../../services/session_controller.dart';

/// Control tab song details. iframe sits above this in [HostShell]; transport
/// controls sit below so the platform WebView cannot cover them.
class HostControlScreen extends ConsumerWidget {
  const HostControlScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(hostSessionProvider);
    final controller = ref.read(playbackProvider.notifier);
    final nowPlaying = controller.displayTrack ?? host.state.nowPlaying;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: nowPlaying == null
          ? Center(
              child: Text(
                'Nothing playing yet — add tracks from Lists or Requests.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ArtworkSquare(url: nowPlaying.artworkUrl),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          nowPlaying.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          nowPlaying.artist,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ArtworkSquare extends StatelessWidget {
  const _ArtworkSquare({this.url});

  final String? url;

  static const _size = 96.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note,
        size: 40,
        color: scheme.onSurfaceVariant,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _size,
        height: _size,
        child: url == null || url!.isEmpty
            ? placeholder
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => placeholder,
              ),
      ),
    );
  }
}
