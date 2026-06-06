import 'package:flutter/cupertino.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/note.dart';
import '../providers/app_providers.dart';
import '../services/haptics_service.dart';
import '../theme/byepasser_theme.dart';
import '../widgets/app_surface.dart';
import '../widgets/empty_board.dart';
import '../widgets/note_card.dart';
import '../widgets/steam_particles.dart';
import 'note_editor_screen.dart';
import 'steam_release_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final settings = ref.watch(settingsProvider);
    final notes = ref.watch(notesProvider);
    final dyingSoon = ref.watch(dyingSoonNotesProvider);

    return CupertinoPageScaffold(
      backgroundColor: palette.background,
      child: Stack(
        children: [
          CustomScrollView(
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: const Text('Byepasser'),
                backgroundColor: palette.background.withValues(alpha: 0.82),
                border: Border(bottom: BorderSide(color: palette.divider)),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 16),
                  child: Text(
                    'Notes that say bye.',
                    style: TextStyle(
                      color: palette.mutedText,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: _SteamButton(
                    onTap: () async {
                      await HapticsService.tap(settings);
                      if (context.mounted) {
                        Navigator.of(context).push(
                          CupertinoPageRoute<void>(
                            builder: (_) => const SteamReleaseScreen(),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
              if (notes.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyBoard(onCreate: () => _openEditor(context, ref)),
                )
              else ...[
                _SectionHeader(title: 'Dying Soon', count: dyingSoon.length),
                if (dyingSoon.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
                      child: Text(
                        'Nothing urgent right now.',
                        style: TextStyle(
                          color: palette.mutedText,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                else
                  _NotesGrid(
                    notes: dyingSoon,
                    onTap: (note) => _openEditor(context, ref, note.id),
                  ),
                _SectionHeader(title: 'All Notes', count: notes.length),
                _NotesGrid(
                  notes: notes,
                  bottomPadding: 118,
                  onTap: (note) => _openEditor(context, ref, note.id),
                ),
              ],
            ],
          ),
          Positioned(
            right: 20,
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
            child: Semantics(
              button: true,
              label: 'Create note',
              child: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => _openEditor(context, ref),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: palette.accent.withValues(alpha: 0.32),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: 62,
                    height: 62,
                    child: Icon(
                      CupertinoIcons.plus,
                      color: palette.onAccent,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, [
    String? noteId,
  ]) async {
    await HapticsService.tap(ref.read(settingsProvider));
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => NoteEditorScreen(noteId: noteId),
      ),
    );
  }
}

class _SteamButton extends StatelessWidget {
  const _SteamButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppSurface(
      onTap: onTap,
      borderRadius: 26,
      padding: EdgeInsets.zero,
      semanticLabel: 'Let Out the Steam',
      child: SizedBox(
        height: 118,
        child: Stack(
          children: [
            const Positioned.fill(child: SteamParticles(dense: true)),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: palette.steam.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.wind,
                      color: palette.text,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Let Out the Steam',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.text,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Write it down. Let it leave.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.mutedText,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    CupertinoIcons.chevron_forward,
                    color: palette.mutedText,
                    size: 22,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        child: Row(
          children: [
            Text(
              title,
              style: TextStyle(
                color: palette.text,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: TextStyle(
                color: palette.mutedText,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotesGrid extends StatelessWidget {
  const _NotesGrid({
    required this.notes,
    required this.onTap,
    this.bottomPadding = 24,
  });

  final List<Note> notes;
  final ValueChanged<Note> onTap;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.crossAxisExtent >= 650 ? 2 : 1;
        return SliverPadding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, bottomPadding),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate((context, index) {
              final note = notes[index];
              return NoteCard(note: note, onTap: () => onTap(note));
            }, childCount: notes.length),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              mainAxisExtent: 222,
            ),
          ),
        );
      },
    );
  }
}
