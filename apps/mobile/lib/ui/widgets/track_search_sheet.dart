import 'package:flutter/material.dart';
import 'package:music_providers/music_providers.dart';
import 'package:shared_models/shared_models.dart';

class TrackSearchSheet extends StatefulWidget {
  const TrackSearchSheet({super.key, required this.provider});

  final MusicProvider provider;

  @override
  State<TrackSearchSheet> createState() => _TrackSearchSheetState();
}

class _TrackSearchSheetState extends State<TrackSearchSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<Track> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await widget.provider.search(query);
      setState(() => _results = results);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final sheetHeight = media.size.height * 0.88;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: sheetHeight,
        child: Material(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          clipBehavior: Clip.antiAlias,
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            )
                          : _results.isEmpty
                              ? Center(
                                  child: Text(
                                    'Search for a song',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  itemCount: _results.length,
                                  itemBuilder: (context, index) {
                                    final track = _results[index];
                                    return ListTile(
                                      leading: track.artworkUrl != null
                                          ? Image.network(
                                              track.artworkUrl!,
                                              width: 48,
                                              height: 48,
                                              fit: BoxFit.cover,
                                            )
                                          : const Icon(Icons.music_note),
                                      title: Text(
                                        track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(track.artist),
                                      onTap: () =>
                                          Navigator.of(context).pop(track),
                                    );
                                  },
                                ),
                ),
                if (_loading) const LinearProgressIndicator(minHeight: 2),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search YouTube Music',
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _search,
                      ),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
