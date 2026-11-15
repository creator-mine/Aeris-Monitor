import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:aeris/features/firmware/widgets/android_ota_card.dart';
import 'package:aeris/features/firmware/providers/firmware_provider.dart';
import 'package:aeris/features/firmware/widgets/device_selector.dart';
import 'package:aeris/features/firmware/widgets/port_selector.dart';
import 'package:aeris/features/firmware/widgets/build_log_widget.dart';
import 'package:aeris/features/firmware/widgets/firmware_info_card.dart';
import 'package:aeris/features/firmware/widgets/preflight_card.dart';
import 'package:aeris/features/firmware/widgets/published_version_card.dart';
import 'package:aeris/features/firmware/widgets/version_history.dart';
import 'package:aeris/shared/widgets/app_scaffold.dart';

class FirmwareScreen extends StatelessWidget {
  const FirmwareScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Прошивка',
      body: Consumer<FirmwareProvider>(
        builder: (context, provider, child) {
          final isAndroid =
              !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
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
                            Text(
                              'PlatformIO не найден',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                              ),
                            ),
                            Text(
                              'Установите PlatformIO, чтобы собирать прошивки.',
                              style: TextStyle(fontSize: 12, color: Colors.red.shade600),
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
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.download, size: 18),
                                label: Text(
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
              const SizedBox(height: 8),
              const PublishedVersionCard(),
              const SizedBox(height: 8),
              if (!isAndroid) Card(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
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
                              Icon(Icons.folder, color: Colors.green.shade700, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  provider.sourcePath!,
                                  style: TextStyle(fontSize: 13, color: Colors.green.shade700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (provider.hasUpdates)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'Есть обновления',
                                    style: TextStyle(color: Colors.white, fontSize: 10),
                                  ),
                                ),
                              IconButton(
                                tooltip: 'Скопировать путь',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.copy, size: 18, color: Colors.green),
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: provider.sourcePath!),
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Путь скопирован в буфер обмена'),
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
                          label: const Text('Выбрать папку проекта'),
                        ),
                      if (provider.sourcePath != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            TextButton.icon(
                              onPressed: () async {
                                final result = await FilePicker.getDirectoryPath(
                                  dialogTitle: 'Выберите папку с прошивкой',
                                );
                                if (result != null) {
                                  provider.selectFolder(result);
                                }
                              },
                              icon: const Icon(Icons.folder_open, size: 16),
                              label: const Text('Изменить'),
                            ),
                            const SizedBox(width: 8),
                            TextButton.icon(
                              onPressed: provider.checkForUpdates,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Проверить обновления'),
                            ),
                          ],
                        ),
                        if (provider.updateCheckError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              provider.updateCheckError!,
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (!isAndroid) const FirmwareInfoCard(),
              const SizedBox(height: 8),
              if (!isAndroid) const PreflightCard(),
              const SizedBox(height: 8),
              if (!isAndroid)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _promptVersion(context),
                        icon: Icon(
                          provider.pendingVersion != null ? Icons.tag : Icons.tag_outlined,
                          size: 18,
                        ),
                        label: Text(
                          provider.pendingVersion != null
                              ? 'v${provider.pendingVersion} (ручная)'
                              : 'v${provider.autoNextVersion} (авто)',
                        ),
                      ),
                    ),
                    if (provider.pendingVersion != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Сбросить версию (авто)',
                        onPressed: provider.clearPendingVersion,
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (!isAndroid)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: provider.canBuild && !provider.isBuilding && !provider.isUploading
                            ? provider.build
                            : null,
                        icon: provider.isBuilding
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.build),
                        label: Text(provider.isBuilding ? 'Сборка...' : 'Собрать'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: provider.canUpload && !provider.isBuilding && !provider.isUploading
                            ? provider.upload
                            : null,
                        icon: provider.isUploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.upload),
                        label: Text(provider.isUploading ? 'Загрузка...' : 'Загрузить'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (!isAndroid)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    onPressed: () => _importFirmware(context, provider),
                  icon: const Icon(Icons.file_open, size: 18),
                  label: const Text('Импортировать прошивку'),
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
    final controller = TextEditingController(text: provider.pendingVersion ?? '');
    final formKey = GlobalKey<FormState>();
    final pattern = RegExp(r'^\d+\.\d+\.\d+$');

    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Версия сборки'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Версия (x.y.z)',
              hintText: 'Например: 2.1.0',
              helperText: 'Пусто — автоматически (${provider.autoNextVersion})',
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
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (accepted == true) {
      final valid = provider.setPendingVersion(controller.text);
      if (!valid && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Недопустимый формат версии')),
        );
      }
    }
  }

  Future<void> _importFirmware(
    BuildContext context,
    FirmwareProvider provider,
  ) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Выберите прошивку (.bin)',
      type: FileType.custom,
      allowedExtensions: ['bin'],
    );
    if (result.isEmpty) return;
    final path = result.single.path;
    if (path == null || path.isEmpty) return;

    final version = await provider.importFirmware(path);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          version != null
              ? 'Импортирована v${version.version} для ${version.deviceType}'
              : 'Не удалось импортировать прошивку',
        ),
      ),
    );
  }
}
