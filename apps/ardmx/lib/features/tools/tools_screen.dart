import 'package:flutter/material.dart';

import '../../widgets/app_scaffold.dart';
import '../system_config/widgets/export_import_section.dart';
import 'widgets/copy_scene_section.dart';

/// "Eines" (Tools) screen — actions on the whole configuration, as opposed
/// to "Paràmetres" (day-to-day controls) or "Configuració" (device
/// identity/recovery): copying one scene's channel values onto another,
/// and the full export/import of the device configuration (moved here from
/// Configuració — both are "act on the whole config" tools, not device
/// settings). Shared by ARDMX EVO and ARDMX One v2, same parametrization as
/// the [ExportImportSection] it embeds unchanged.
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({
    super.key,
    required this.origen,
    required this.channelCountVIndex,
    required this.hasAudio,
    required this.hasEvents,
    required this.fileNamePrefix,
  });

  final String origen;
  final int channelCountVIndex;
  final bool hasAudio;
  final bool hasEvents;
  final String fileNamePrefix;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Eines',
      onBack: () => Navigator.of(context).pop(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Section(
              title: 'Copiar canals entre escenes',
              child: CopySceneSection(channelCountVIndex: channelCountVIndex),
            ),
            const SizedBox(height: 8),
            _Section(
              title: 'Exportació/Importació de la configuració',
              child: ExportImportSection(
                origen: origen,
                channelCountVIndex: channelCountVIndex,
                hasAudio: hasAudio,
                hasEvents: hasEvents,
                fileNamePrefix: fileNamePrefix,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
