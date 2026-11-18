import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:aeris/features/firmware/widgets/android_ota_card.dart';
import 'package:aeris/features/firmware/providers/firmware_provider.dart';
import 'package:aeris/features/firmware/widgets/device_selector.dart';
import 'package:aeris/features/firmware/widgets/firmware_source_card.dart';
import 'package:aeris/features/firmware/widgets/port_selector.dart';
import 'package:aeris/features/firmware/widgets/build_log_widget.dart';
import 'package:aeris/features/firmware/widgets/firmware_info_card.dart';
import 'package:aeris/features/firmware/widgets/preflight_card.dart';
import 'package:aeris/features/firmware/widgets/published_version_card.dart';
import 'package:aeris/features/firmware/widgets/version_history.dart';
import 'package:aeris/shared/widgets/app_scaffold.dart';
import 'package:aeris/shared/widgets/tr_text.dart';
import 'package:aeris/core/i18n/l10n.dart';

class FirmwareScreen extends StatefulWidget {
  const FirmwareScreen({super.key});

  @override
  State<FirmwareScreen> createState() => _FirmwareScreenState();
}

class _FirmwareScreenState extends State<FirmwareScreen> {
  bool _showSourceBuild = false;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Прошивка',
      body: Consumer<FirmwareProvider>(
        builder: (context, provider, child) {
          final isAndroid =
              !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
          final isWindows =
              !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
          return ListView(
            children: [
              if (isAndroid) const AndroidOtaCard(),
              if (!isAndroid && !provider.platformioAvailable)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TrText(
                              'PlatformIO не найден',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                              ),
                            ),
                            TrText(
                              'Установите PlatformIO, чтобы собирать и заливать прошивки.',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.red.shade600),
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: FilledButton.icon(
                                onPressed: provider.isInstallingPlatformio
                                    ? null
                                    : provider.installPlatformIO,
                                icon: provider.isInstallingPlatformio
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.download, size: 18),
                                label: TrText(
                                  provider.isInstallingPlatformio
                                      ? 'Установка...'
                                      : 'Установить PlatformIO',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (!isAndroid) const DeviceSelector(),
              if (!isAndroid) const PortSelector(),
              if (isWindows) const FirmwareSourceCard(),
              const SizedBox(height: 8),
              const PublishedVersionCard(),
              const SizedBox(height: 8),
              if (!isAndroid)
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: ListTile(
                    leading: const Icon(Icons.build_outlined),
                    title: const TrText('Сборка из исходников'),
                    subtitle: const TrText(
                      'PlatformIO, папка проекта, версия и предпросмотр',
                    ),
                    trailing: Icon(
                      _showSourceBuild ? Icons.expand_less : Icons.expand_more,
                    ),
                    onTap: () {
                      setState(() => _showSourceBuild = !_showSourceBuild);
                    },
                  ),
                ),
              if (!isAndroid && _showSourceBuild)
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const TrText(
                          'Исходный код',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (provider.sourcePath != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.folder,
                                    color: Colors.green.shade700, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TrText(
                                    provider.sourcePath!,
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.green.shade700),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (provider.hasUpdates)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const TrText(
                                      'Есть обновления',
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 10),
                                    ),
                                  ),
                                IconButton(
                                  tooltip: L10n.of(context, 'Скопировать путь'),
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.copy,
                                      size: 18, color: Colors.green),
                                  onPressed: () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: provider.sourcePath!),
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: TrText(
                                              'Путь скопирован в буфер обмена'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: () async {
                              final result = await FilePicker.getDirectoryPath(
                                dialogTitle: 'Выберите папку с прошивкой',
                              );
                              if (result != null) {
                                provider.selectFolder(result);
                              }
                            },
                            icon: const Icon(Icons.folder_open),
                            label: const TrText('Выбрать папку проекта'),
                          ),
                        if (provider.sourcePath != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () async {
                                  final result =
                                      await FilePicker.getDirectoryPath(
                                    dialogTitle: 'Выберите папку с прошивкой',
                                  );
                                  if (result != null) {
                                    provider.selectFolder(result);
                                  }
                                },
                                icon: const Icon(Icons.folder_open, size: 16),
                                label: const TrText('Изменить'),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: provider.checkForUpdates,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const TrText('Проверить обновления'),
                              ),
                            ],
                          ),
                          if (provider.updateCheckError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: TrText(
                                provider.updateCheckError!,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.error),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              if (!isAndroid && _showSourceBuild) const FirmwareInfoCard(),
              const SizedBox(height: 8),
              if (!isAndroid && _showSourceBuild) const PreflightCard(),
              const SizedBox(height: 8),
              if (!isAndroid && _showSourceBuild)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _promptVersion(context),
                          icon: Icon(
                            provider.pendingVersion != null
                                ? Icons.tag
                                : Icons.tag_outlined,
                            size: 18,
                          ),
                          label: TrText(
                            provider.pendingVersion != null
                                ? 'v${provider.pendingVersion} (ручная)'
                                : 'v${provider.autoNextVersion} (авто)',
                          ),
                        ),
                      ),
                      if (provider.pendingVersion != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: L10n.of(context, 'Сбросить версию (авто)'),
                          onPressed: provider.clearPendingVersion,
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              if (!isAndroid && _showSourceBuild)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: provider.canBuild &&
                                  !provider.isBuilding &&
                                  !provider.isUploading
                              ? provider.build
                              : null,
                          icon: provider.isBuilding
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.build),
                          label: TrText(
                              provider.isBuilding ? 'Сборка...' : 'Собрать'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: provider.canUpload &&
                                  !provider.isBuilding &&
                                  !provider.isUploading
                              ? provider.upload
                              : null,
                          icon: provider.isUploading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.upload),
                          label: TrText(provider.isUploading
                              ? 'Загрузка...'
                              : 'Загрузить'),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              if (!isAndroid) const BuildLogWidget(),
              const VersionHistory(),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  Future<void> _promptVersion(BuildContext context) async {
    final provider = context.read<FirmwareProvider>();
    final controller =
        TextEditingController(text: provider.pendingVersion ?? '');
    final formKey = GlobalKey<FormState>();
    final pattern = RegExp(r'^\d+\.\d+\.\d+$');

    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const TrText('Версия сборки'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: L10n.of(context, 'Версия (x.y.z)'),
              hintText: L10n.of(context, 'Например: 2.1.0'),
              helperText: L10n.of(context,
                  'Пусто — автоматически (${provider.autoNextVersion})'),
            ),
            validator: (value) {
              final v = value?.trim() ?? '';
              if (v.isEmpty) return null;
              if (!pattern.hasMatch(v)) {
                return 'Формат: три числа через точки, например 2.1.0';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const TrText('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: const TrText('Сохранить'),
          ),
        ],
      ),
    );

    if (accepted == true) {
      final valid = provider.setPendingVersion(controller.text);
      if (!valid && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: TrText('Недопустимый формат версии')),
        );
      }
    }
  }
}
