import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

class ConnectNowPlayingScreen extends StatefulWidget {
  const ConnectNowPlayingScreen({super.key, required this.state});

  final HostState state;

  @override
  State<ConnectNowPlayingScreen> createState() =>
      _ConnectNowPlayingScreenState();
}

class _ConnectNowPlayingScreenState extends State<ConnectNowPlayingScreen> {
  Timer? _tick;
  late int _displayPositionMs;
  DateTime _syncedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _displayPositionMs = widget.state.positionMs;
    _syncedAt = DateTime.now();
    _restartTicker();
  }

  @override
  void didUpdateWidget(covariant ConnectNowPlayingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.state;
    final prev = oldWidget.state;
    final trackChanged = prev.nowPlaying?.id != next.nowPlaying?.id ||
        prev.nowPlayingIndex != next.nowPlayingIndex;
    final positionJumped = (next.positionMs - prev.positionMs).abs() > 1500;
    final playStateChanged = prev.isPlaying != next.isPlaying;

    if (trackChanged || positionJumped || playStateChanged) {
      _displayPositionMs = next.positionMs;
      _syncedAt = DateTime.now();
    } else if (next.positionMs >= _displayPositionMs) {
      // Prefer fresher host sync when it arrives.
      _displayPositionMs = next.positionMs;
      _syncedAt = DateTime.now();
    }
    _restartTicker();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _restartTicker() {
    _tick?.cancel();
    if (!widget.state.isPlaying) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !widget.state.isPlaying) return;
      final elapsed = DateTime.now().difference(_syncedAt).inMilliseconds;
      final next = widget.state.positionMs + elapsed;
      final capped = widget.state.durationMs > 0
          ? next.clamp(0, widget.state.durationMs)
          : next;
      setState(() => _displayPositionMs = capped);
    });
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.state.nowPlaying;
    final durationMs = widget.state.durationMs;
    final positionMs = widget.state.isPlaying
        ? _displayPositionMs
        : widget.state.positionMs;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (track?.artworkUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                track!.artworkUrl!,
                height: 220,
                fit: BoxFit.cover,
              ),
            ),
          const SizedBox(height: 24),
          Text(
            track?.title ?? 'Nothing playing',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (track != null) Text(track.artist),
          const SizedBox(height: 24),
          LinearProgressIndicator(
            value: durationMs == 0
                ? null
                : (positionMs / durationMs).clamp(0, 1),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatMs(positionMs)),
              Text(widget.state.isPlaying ? 'Playing' : 'Paused'),
              Text(_formatMs(durationMs)),
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
