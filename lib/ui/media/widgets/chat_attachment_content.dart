import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart' as audio_players;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:wrytte/domain/models/attachment_contact.dart';
import 'package:wrytte/domain/models/picked_attachment_file.dart';
import 'package:wrytte/domain/models/poll_attachment_draft.dart';
import 'package:wrytte/ui/core/themes/wrytte_theme.dart';

const _contentPadding = EdgeInsets.fromLTRB(18, 78, 18, 112);

class FileAttachmentContent extends StatelessWidget {
  const FileAttachmentContent({
    super.key,
    required this.scrollController,
    required this.files,
    required this.selectedPaths,
    required this.loading,
    required this.onChooseFiles,
    required this.onChooseGallery,
    required this.onChooseAudio,
    required this.onToggle,
  });

  final ScrollController scrollController;
  final List<PickedAttachmentFile> files;
  final Set<String> selectedPaths;
  final bool loading;
  final VoidCallback onChooseFiles;
  final VoidCallback onChooseGallery;
  final VoidCallback onChooseAudio;
  final ValueChanged<PickedAttachmentFile> onToggle;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollController,
      physics: const ClampingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 78)),
        SliverToBoxAdapter(child: _FileSourceRow(
          iconAsset: 'assets/svg/Storage icon.svg', title: 'Internal storage',
          description: 'Browse your system files', onTap: loading ? null : onChooseFiles,
        )),
        SliverToBoxAdapter(child: _FileSourceRow(
          iconAsset: 'assets/svg/Gallery icon Blue.svg', title: 'Gallery',
          description: 'Send original-quality photos or videos', onTap: loading ? null : onChooseGallery,
        )),
        SliverToBoxAdapter(child: _FileSourceRow(
          iconAsset: 'assets/svg/Audio icon.svg', title: 'Audio',
          description: 'Select audio or music files', onTap: loading ? null : onChooseAudio,
        )),
        const SliverToBoxAdapter(child: Padding(
          padding: EdgeInsets.fromLTRB(18, 15, 18, 9),
          child: Text('Recent files', style: TextStyle(color: Color(0xB8C6C6C6), fontSize: 14, fontWeight: FontWeight.w500)),
        )),
        if (files.isNotEmpty) SliverList.builder(
          itemCount: files.length,
          itemBuilder: (_, index) {
            final file = files[index];
            final isAudio = {
              'MP3', 'M4A', 'AAC', 'WAV', 'OGG', 'FLAC', 'OPUS',
            }.contains(file.extension);
            if (isAudio) {
              return _AudioPreviewSelectionRow(
                file: file,
                selected: selectedPaths.contains(file.path),
                onTap: () => onToggle(file),
              );
            }
            return _SelectionRow(
              icon: _fileIcon(file.extension), title: file.name,
              subtitle: _fileDetails(file), selected: selectedPaths.contains(file.path),
              onTap: () => onToggle(file),
            );
          },
        ) else
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Choose a source above to browse files',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0x7A9A9DA4), fontSize: 13),
                ),
              ),
            ),
          ),
      ],
    );
  }
  static IconData _fileIcon(String extension) => switch (extension) {
    'MP3' || 'M4A' || 'AAC' || 'WAV' || 'OGG' => Icons.graphic_eq_rounded,
    'PDF' => Icons.picture_as_pdf_rounded,
    'ZIP' || 'RAR' || '7Z' => Icons.folder_zip_rounded,
    _ => Icons.insert_drive_file_rounded,
  };

  static String _fileDetails(PickedAttachmentFile file) {
    final bytes = file.sizeBytes;
    final size = bytes >= 1048576
        ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
        : '${(bytes / 1024).clamp(1, 9999).round()} KB';
    return file.extension.isEmpty ? size : '$size · ${file.extension}';
  }
}

class ContactAttachmentContent extends StatefulWidget {
  const ContactAttachmentContent({
    super.key,
    required this.scrollController,
    required this.contacts,
    required this.selectedIds,
    required this.loading,
    required this.accessDenied,
    required this.onRetry,
    required this.onOpenSettings,
    required this.onToggle,
  });

  final ScrollController scrollController;
  final List<AttachmentContact> contacts;
  final Set<String> selectedIds;
  final bool loading;
  final bool accessDenied;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final ValueChanged<AttachmentContact> onToggle;

  @override
  State<ContactAttachmentContent> createState() =>
      _ContactAttachmentContentState();
}

class _ContactAttachmentContentState extends State<ContactAttachmentContent> {
  static final _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('');

  String _initial(AttachmentContact contact) {
    final name = contact.displayName.trim();
    if (name.isEmpty) return '#';
    final first = name.substring(0, 1).toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(first) ? first : '#';
  }

  Widget _contactRow(AttachmentContact contact) {
    final selected = widget.selectedIds.contains(contact.id);
    final name = contact.displayName.trim().isEmpty
        ? 'Unnamed contact'
        : contact.displayName.trim();
    return InkWell(
      onTap: () => widget.onToggle(contact),
      child: SizedBox(
        height: 62,
        child: Row(
          children: [
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 21,
              backgroundColor: Color(0xFF30343C),
              child: Icon(Icons.person, color: Color(0xFFB8BDC7), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFF1F3F6),
                  fontFamily: WrytteTypography.primaryFontFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? WrytteColors.primary : Colors.transparent,
                border: Border.all(
                  color: selected
                      ? WrytteColors.primary
                      : Colors.white.withValues(alpha: .30),
                  width: 1.2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 15)
                  : null,
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<AttachmentContact>>{};
    for (final contact in widget.contacts) {
      grouped.putIfAbsent(_initial(contact), () => []).add(contact);
    }
    final letters = grouped.keys.toList()..sort();
    final body = <Widget>[];
    for (final letter in letters) {
      body.add(Padding(
        padding: const EdgeInsets.fromLTRB(0, 9, 5, 4),
        child: Text(letter, style: const TextStyle(color: Color(0xFF9DA2AB), fontSize: 13, fontWeight: FontWeight.w500)),
      ));
      for (var i = 0; i < grouped[letter]!.length; i++) {
        body.add(_contactRow(grouped[letter]![i]));
        if (i < grouped[letter]!.length - 1) {
          body.add(Divider(height: 1, indent: 54, color: Colors.white.withValues(alpha: .09)));
        }
      }
    }
    if (widget.loading) {
      body.add(const Padding(padding: EdgeInsets.only(top: 55), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF69A9FF)))));
    } else if (widget.accessDenied) {
      body.add(const Padding(padding: EdgeInsets.only(top: 45, left: 18, right: 18), child: Text('Allow contacts access to see people from your phone.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFB5BAC3), fontSize: 14))));
    } else if (widget.contacts.isEmpty) {
      body.add(const Padding(padding: EdgeInsets.only(top: 45), child: Center(child: Text('No contacts found', style: TextStyle(color: Color(0xFFB5BAC3))))));
    }
    return ColoredBox(
      color: WrytteColors.surfaceRaised,
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(8, 72, 31, 112),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: body),
          ),
          Positioned(
            right: 3,
            top: 72,
            bottom: 70,
            child: SizedBox(
              width: 18,
              child: LayoutBuilder(builder: (_, constraints) {
                final extent = math.min(13.0, constraints.maxHeight / _alphabet.length);
                return Column(children: [
                  for (final letter in _alphabet)
                    SizedBox(height: extent, child: Center(child: Text(letter, style: const TextStyle(color: Color(0xFF69A9FF), fontSize: 10.5, height: 1)))),
                ]);
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class PollAttachmentContent extends StatefulWidget {
  const PollAttachmentContent({
    super.key,
    required this.scrollController,
    required this.onChanged,
  });

  final ScrollController scrollController;
  final ValueChanged<PollAttachmentDraft?> onChanged;

  @override
  State<PollAttachmentContent> createState() => _PollAttachmentContentState();
}

class _PollAttachmentContentState extends State<PollAttachmentContent> {
  final _question = TextEditingController();
  final _description = TextEditingController();
  final _options = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _multiple = true;

  @override
  void dispose() {
    _question.dispose();
    _description.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  void _notify() {
    final question = _question.text.trim();
    final options = _options
        .take(_options.length - 1)
        .map((controller) => controller.text.trim())
        .where((option) => option.isNotEmpty)
        .toList(growable: false);
    widget.onChanged(
      question.isNotEmpty && options.length >= 2
          ? PollAttachmentDraft(
              question: question,
              options: options,
              description: _description.text.trim().isEmpty
                  ? null
                  : _description.text.trim(),
              allowMultipleAnswers: _multiple,
            )
          : null,
    );
  }

  void _onOptionChanged(int index, String value) {
    if (index == _options.length - 1 &&
        value.trim().isNotEmpty &&
        _options.length < 7) {
      setState(() => _options.add(TextEditingController()));
    } else {
      setState(() {});
    }
    _notify();
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
    TextInputAction? textInputAction,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      maxLines: maxLines,
      minLines: maxLines > 1 ? maxLines : 1,
      textInputAction: textInputAction,
      cursorColor: const Color(0xFF6DAAFF),
      style: const TextStyle(
        color: Color(0xFFE9EBEF),
        fontSize: 16,
        height: 1.2,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: Color(0xFF5D616A),
          fontSize: 16,
          height: 1.2,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 15,
        ),
      ),
    );
  }

  Widget _glassGroup({required Widget child, bool navbarStyle = false}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(19),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: navbarStyle
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, .48, 1],
                    colors: [
                      Color.fromRGBO(26, 29, 37, .44),
                      Color.fromRGBO(15, 18, 25, .36),
                      Color.fromRGBO(8, 10, 15, .30),
                    ],
                  )
             : const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.fromRGBO(24, 27, 34, .66),
                      Color.fromRGBO(14, 17, 23, .52),
                    ],
                  ),
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: Colors.white.withValues(alpha: navbarStyle ? .09 : .055),
              width: .8,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _optionsEditor() {
    final widthProgress =
        ((MediaQuery.sizeOf(context).shortestSide - 320) / 152)
            .clamp(0.0, 1.0)
            .toDouble();
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: _options.length,
      onReorder: (oldIndex, newIndex) {
        final addIndex = _options.length - 1;
        if (oldIndex >= addIndex || newIndex > addIndex) return;
        setState(() {
          if (newIndex > oldIndex) newIndex--;
          final option = _options.removeAt(oldIndex);
          _options.insert(newIndex, option);
        });
        _notify();
      },
      proxyDecorator: (child, index, animation) => AnimatedBuilder(
        animation: animation,
        builder: (context, child) => Material(
          color: const Color(0xFF20242B),
          elevation: 10 * animation.value,
          shadowColor: Colors.black.withValues(alpha: .72),
          borderRadius: BorderRadius.circular(19),
          child: child,
        ),
        child: child,
      ),
      itemBuilder: (context, index) {
        final controller = _options[index];
        final isAddField = index == _options.length - 1;
        return KeyedSubtree(
          key: ValueKey<TextEditingController>(controller),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _field(
                      controller: controller,
                      hint: isAddField ? 'Add an option' : 'Option',
                      textInputAction: TextInputAction.next,
                      onChanged: (value) => _onOptionChanged(index, value),
                    ),
                  ),
                  IgnorePointer(
                    ignoring: isAddField,
                    child: Opacity(
                      opacity: isAddField ? 0 : 1,
                      child: ReorderableDragStartListener(
                        index: index,
                        child: SizedBox(
                          width: 38 + (4 * widthProgress),
                          height: 46 + (4 * widthProgress),
                          child: const Column(
                            mainAxisSize: MainAxisSize.max,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                child: Divider(color: Color(0xFF8E949E), height: 3),
                              ),
                              SizedBox(
                                width: 20,
                                child: Divider(color: Color(0xFF8E949E), height: 3),
                              ),
                              SizedBox(
                                width: 20,
                                child: Divider(color: Color(0xFF8E949E), height: 3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (!isAddField)
                Divider(
                  height: 1,
                  indent: 17,
                  endIndent: 17,
                  color: Colors.white.withValues(alpha: .055),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: widget.scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: _contentPadding,
          sliver: SliverList.list(
            children: [
              const Padding(
                padding: EdgeInsetsDirectional.only(start: 14),
                child: _SectionLabel('Question'),
              ),
              const SizedBox(height: 9),
              _glassGroup(
                child: Column(
                  children: [
                    _field(
                      controller: _question,
                      hint: 'Ask question',
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => _notify(),
                    ),
                    Divider(
                      height: 1,
                      indent: 17,
                      endIndent: 17,
                      color: Colors.white.withValues(alpha: .055),
                    ),
                    _field(
                      controller: _description,
                      hint: 'Add description (optional)',
                      maxLines: 2,
                      textInputAction: TextInputAction.newline,
                      onChanged: (_) => _notify(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const Padding(
                padding: EdgeInsetsDirectional.only(start: 14),
                child: _SectionLabel('Options'),
              ),
              const SizedBox(height: 9),
              _glassGroup(child: _optionsEditor()),
              const SizedBox(height: 24),
              _glassGroup(
                navbarStyle: true,
                child: SizedBox(
                  height: 55,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 18,
                      end: 7,
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Allow multiple answers',
                            style: TextStyle(
                              color: Color(0xFFE0E2E7),
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Semantics(
                          button: true,
                          toggled: _multiple,
                          label: 'Allow multiple answers',
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _multiple = !_multiple);
                              _notify();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              width: 55,
                              height: 32,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: _multiple
                                    ? const Color(0xFF69A9FF)
                                    : const Color(0xFF383C45),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: AnimatedAlign(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                                alignment: _multiple
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF7F9FC),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FileSourceRow extends StatelessWidget {
  const _FileSourceRow({required this.iconAsset, required this.title, required this.description, required this.onTap});
  final String iconAsset;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 76,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(children: [
            SvgPicture.asset(
              iconAsset,
              width: 29,
              height: 29,
              colorFilter: const ColorFilter.mode(
                WrytteColors.primary,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 15),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: WrytteColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 7),
              Text(description, style: const TextStyle(color: Color(0xB8C6C6C6), fontSize: 12)),
            ])),
          ]),
        ),
      ),
    ),
  );
}

class _AudioPreviewSelectionRow extends StatefulWidget {
  const _AudioPreviewSelectionRow({
    required this.file,
    required this.selected,
    required this.onTap,
  });

  final PickedAttachmentFile file;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_AudioPreviewSelectionRow> createState() =>
      _AudioPreviewSelectionRowState();
}

class _AudioPreviewSelectionRowState
    extends State<_AudioPreviewSelectionRow> {
  final audio_players.AudioPlayer _player = audio_players.AudioPlayer();
  audio_players.PlayerState _state = audio_players.PlayerState.stopped;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _state = state);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePreview() async {
    try {
      if (_state == audio_players.PlayerState.playing) {
        await _player.pause();
      } else if (_state == audio_players.PlayerState.paused) {
        await _player.resume();
      } else {
        await _player.stop();
        await _player.play(audio_players.DeviceFileSource(widget.file.path));
      }
    } catch (_) {
      if (mounted) setState(() => _state = audio_players.PlayerState.stopped);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _state == audio_players.PlayerState.playing;
    return _SelectionRow(
      icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
      title: widget.file.name,
      subtitle: FileAttachmentContent._fileDetails(widget.file),
      selected: widget.selected,
      onTap: widget.onTap,
      onLeadingTap: _togglePreview,
    );
  }
}

class _SelectionRow extends StatelessWidget {
  const _SelectionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.onLeadingTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLeadingTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: WrytteColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: onLeadingTap == null
                    ? Icon(icon, color: WrytteColors.primary)
                    : IconButton(
                        onPressed: onLeadingTap,
                        icon: Icon(icon, color: WrytteColors.primary),
                        splashRadius: 22,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      style: const TextStyle(
                        color: WrytteColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _SelectionCheck(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.contact,
    required this.selected,
    required this.onTap,
  });

  final AttachmentContact contact;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial = contact.displayName.trim().isEmpty
        ? '?'
        : contact.displayName.trim().characters.first.toUpperCase();
    return _SelectionRow(
      icon: Icons.person_rounded,
      title: '$initial  ${contact.displayName}',
      subtitle: contact.phoneNumber,
      selected: selected,
      onTap: onTap,
    );
  }
}

class _SelectionCheck extends StatelessWidget {
  const _SelectionCheck({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 150),
      width: 25,
      height: 25,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? WrytteColors.primary : Colors.transparent,
        border: Border.all(
          color: selected
              ? WrytteColors.primary
              : Colors.white.withValues(alpha: .34),
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 17)
          : null,
    );
  }
}

class _PollField extends StatelessWidget {
  const _PollField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: onChanged,
    maxLength: 120,
    decoration: InputDecoration(
      hintText: hintText,
      counterText: '',
      filled: true,
      fillColor: WrytteColors.surfaceRaised,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFF9A9DA5),
      fontSize: 15,
      fontWeight: FontWeight.w500,
    ),
  );
}

class _EmptyAttachmentState extends StatelessWidget {
  const _EmptyAttachmentState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, size: 44, color: WrytteColors.textMuted),
      const SizedBox(height: 12),
      Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 7),
      Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: WrytteColors.textMuted, height: 1.35),
      ),
    ],
  );
}

