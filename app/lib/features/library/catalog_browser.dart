import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';

String catalogCategoryLabel(String category) => switch (category) {
  'courseware' => l10n.catalogCourseware,
  'homework' => l10n.catalogHomework,
  'lab' => l10n.catalogLab,
  'transcript' => l10n.commonTranscript,
  'video' => l10n.catalogVideo,
  'slides' => l10n.catalogSlides,
  'notes' => l10n.commonNotes,
  'reference' => l10n.catalogReference,
  _ => l10n.catalogOther,
};

class CatalogBrowser extends StatefulWidget {
  const CatalogBrowser({
    super.key,
    required this.items,
    required this.query,
    required this.courseId,
    required this.onCourse,
    required this.onOpen,
  });
  final List<Map<String, dynamic>> items;
  final String query, courseId;
  final ValueChanged<String> onCourse;
  final ValueChanged<Map<String, dynamic>> onOpen;
  @override
  State<CatalogBrowser> createState() => _CatalogBrowserState();
}

class _CatalogBrowserState extends State<CatalogBrowser> {
  String _category = '', _type = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final courses = <String, String>{
      for (final i in widget.items) '${i['course_id']}': '${i['course']}',
    };
    final scoped = widget.items
        .where(
          (i) => widget.courseId.isEmpty || i['course_id'] == widget.courseId,
        )
        .toList();
    final types = scoped.map((i) => '${i['file_type']}').toSet().toList()
      ..sort();
    final q = widget.query.trim().toLowerCase();
    final visible = scoped
        .where(
          (i) =>
              (_category.isEmpty || i['category'] == _category) &&
              (_type.isEmpty || i['file_type'] == _type) &&
              (q.isEmpty ||
                  '${i['name']} ${i['lecture'] ?? ''} ${i['course']} ${i['path']}'
                      .toLowerCase()
                      .contains(q)),
        )
        .toList();
    final grouped = <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final i in visible) {
      ((grouped['${i['course']}'] ??= {})['${i['category']}'] ??= []).add(i);
    }
    Widget filter(
      String label,
      String value,
      Map<String, String> options,
      ValueChanged<String> changed,
    ) => SizedBox(
      width: context.isCompact ? double.infinity : 220,
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label:$value:${options.keys.join()}'),
        initialValue: options.containsKey(value) ? value : '',
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: options.entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (v) => changed(v ?? ''),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.catalogTitle(visible.length), style: tt.titleLarge),
        const SizedBox(height: Space.md),
        Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          children: [
            filter(
              l10n.commonCourses,
              widget.courseId,
              {'': l10n.libraryAllCourses, ...courses},
              (v) {
                setState(() {
                  _type = '';
                });
                widget.onCourse(v);
              },
            ),
            filter(l10n.catalogCategory, _category, {
              '': l10n.catalogAllCategories,
              for (final c in [
                'courseware',
                'homework',
                'lab',
                'transcript',
                'video',
                'slides',
                'notes',
                'reference',
                'other',
              ])
                c: '${catalogCategoryLabel(c)} (${scoped.where((i) => i['category'] == c).length})',
            }, (v) => setState(() => _category = v)),
            filter(l10n.catalogFileType, _type, {
              '': l10n.catalogAllTypes,
              for (final t in types) t: t.toUpperCase(),
            }, (v) => setState(() => _type = v)),
          ],
        ),
        const SizedBox(height: Space.sm),
        Text(
          l10n.catalogClassificationHint,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: Space.lg),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Text(l10n.catalogEmpty),
          ),
        for (final course in grouped.entries) ...[
          Text(course.key, style: tt.titleMedium),
          const SizedBox(height: Space.sm),
          for (final group in course.value.entries)
            Card(
              margin: const EdgeInsets.only(bottom: Space.sm),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                key: ValueKey(
                  '${widget.courseId}:$_category:$_type:$q:${course.key}:${group.key}',
                ),
                initiallyExpanded:
                    group.key != 'slides' && group.key != 'video',
                leading: Icon(
                  group.key == 'lab'
                      ? Icons.science_outlined
                      : group.key == 'homework'
                      ? Icons.assignment_outlined
                      : Icons.folder_outlined,
                ),
                title: Text(
                  '${catalogCategoryLabel(group.key)} · ${group.value.length}',
                ),
                children: [
                  for (final item in group.value)
                    ListTile(
                      dense: true,
                      leading: SizedBox(
                        width: 50,
                        child: Text(
                          '${item['file_type']}'.toUpperCase(),
                          style: tt.labelSmall?.copyWith(color: cs.primary),
                        ),
                      ),
                      title: Text('${item['name']}'),
                      subtitle: Text(
                        [
                          if ('${item['lecture'] ?? ''}'.isNotEmpty)
                            '${item['lecture']}',
                          fmtBytes((item['bytes'] as num?) ?? 0),
                        ].join(' · '),
                      ),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                      onTap: () => widget.onOpen(item),
                    ),
                ],
              ),
            ),
          const SizedBox(height: Space.lg),
        ],
      ],
    );
  }
}
