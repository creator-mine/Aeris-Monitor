import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/firmware_provider.dart';
import 'package:aeris/shared/widgets/tr_text.dart';
import 'package:aeris/core/i18n/l10n.dart';

/// Primary Windows workflow: pick a `.bin` or paste a GitHub/HTTPS link,
/// inspect what was staged, then press one button to flash it over USB.
class FirmwareSourceCard extends StatefulWidget {
  const FirmwareSourceCard({super.key});

  @override
  State<FirmwareSourceCard> createState() => _FirmwareSourceCardState();
}

class _FirmwareSourceCardState extends State<FirmwareSourceCard> {
  final TextEditingController _urlController = TextEditingController();
  Timer? _debounce;
  String? _lastAutoUrl;

  @override
  void dispose() {
    _debounce?.cancel();
    _urlController.dispose();
    super.dispose();
  }

  bool _looksLikeFirmwareLink(String value) {
    final lower = value.toLowerCase();
    return lower.endsWith('.bin') ||
        lower.contains('github.com/') ||
        lower.contains('raw.githubusercontent.com/');
  }

  void _onUrlChanged(String value) {
    _debounce?.cancel();
    final url = value.trim();
    if (url.length < 12 || !_looksLikeFirmwareLink(url)) return;
    if (url == _lastAutoUrl) return;

    // Pasting a link is the common case: start the download automatically,
    // while the explicit button below remains available for a retry.
    _debounce = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      _lastAutoUrl = url;
      context.read<FirmwareProvider>().stageFromUrl(url);
    });
  }

  Future<void> _pickFile(FirmwareProvider provider) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Выберите прошивку (.bin)',
      type: FileType.custom,
      allowedExtensions: ['bin'],
    );
    if (result.isEmpty) return;
    final path = result.single.path;
    if (path == null || path.isEmpty) return;
    await provider.stageLocalFirmware(path);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FirmwareProvider>();
    final staged = provider.stagedFirmware;
    final manifest = provider.serverManifest;
    final mismatch =
        staged != null && staged.deviceType != provider.selectedDeviceType;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.system_update_alt, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: TrText(
                    'Прошивка',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: L10n.of(context,
                      'Нужен образ приложения .bin (OTA), не merged/factory'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.info_outline, size: 18),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: TrText(
                          'Выберите firmware.bin, собранный PlatformIO, или '
                          'OTA-образ с сервера/GitHub. Полный merged-образ '
                          'с bootloader не подходит.',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            TrText(
              'Выберите файл или вставьте ссылку — прошивка скачается сама. '
              'Останется нажать «Загрузить».',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: provider.isStaging || provider.isUploading
                      ? null
                      : () => _pickFile(provider),
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const TrText('Выбрать .bin'),
                ),
                if (manifest != null)
                  TextButton.icon(
                    onPressed: provider.canStagePublished
                        ? provider.stagePublishedFirmware
                        : null,
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
                    label: TrText('Опубликованная v${manifest.version}'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: _onUrlChanged,
              onSubmitted: (value) {
                final url = value.trim();
                if (url.isNotEmpty) {
                  _lastAutoUrl = url;
                  provider.stageFromUrl(url);
                }
              },
              decoration: InputDecoration(
                labelText: L10n.of(context, 'Ссылка на .bin или GitHub'),
                hintText: 'https://github.com/owner/repo/releases/latest',
                prefixIcon: const Icon(Icons.link, size: 20),
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                suffixIcon: provider.isStaging
                    ? IconButton(
                        tooltip: L10n.of(context, 'Отменить скачивание'),
                        icon: const Icon(Icons.stop_circle_outlined, size: 20),
                        onPressed: provider.cancelStaging,
                      )
                    : IconButton(
                        tooltip: L10n.of(context, 'Скачать'),
                        icon: const Icon(Icons.download, size: 20),
                        onPressed: provider.isUploading
                            ? null
                            : () {
                                final url = _urlController.text.trim();
                                if (url.isNotEmpty) {
                                  _lastAutoUrl = url;
                                  provider.stageFromUrl(url);
                                }
                              },
                      ),
              ),
            ),
            if (provider.isStaging) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: (provider.downloadProgress ?? 0) > 0
                    ? provider.downloadProgress
                    : null,
              ),
              const SizedBox(height: 4),
              TrText(
                provider.downloadProgress == null
                    ? 'Подготовка файла...'
                    : 'Скачано ${(provider.downloadProgress! * 100).round()}%',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
            if (provider.stageError != null) ...[
              const SizedBox(height: 10),
              _ErrorText(message: provider.stageError!),
            ],
            if (staged != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.blueGrey.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          staged.downloaded
                              ? Icons.cloud_done_outlined
                              : Icons.description_outlined,
                          size: 20,
                          color: Colors.blueGrey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TrText(
                            staged.fileName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Chip(text: staged.deviceLabel),
                        if (staged.version != null)
                          _Chip(text: 'v${staged.version}'),
                        _Chip(text: staged.sizeLabel),
                        _Chip(text: 'sha256 ${staged.shortHash}'),
                      ],
                    ),
                    if (staged.sourceUrl != null) ...[
                      const SizedBox(height: 8),
                      TrText(
                        staged.sourceUrl!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                    if (mismatch) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber,
                              size: 18,
                              color: Colors.orange.shade800,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TrText(
                                'Файл для ${staged.deviceLabel}, а выбрано '
                                '${provider.selectedDeviceType}. Проверьте плату.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                await provider
                                    .selectDeviceType(staged.deviceType);
                              },
                              child: const TrText('Переключить'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: provider.isUploading
                            ? null
                            : provider.clearStagedFirmware,
                        icon: const Icon(Icons.close, size: 16),
                        label: const TrText('Убрать'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      provider.canFlashStaged ? provider.flashStaged : null,
                  icon: provider.isUploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.usb),
                  label: TrText(
                      provider.isUploading ? 'Загрузка...' : 'Загрузить'),
                ),
              ),
              if (provider.selectedPort == null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: TrText(
                    'Подключите плату и выберите COM-порт выше.',
                    style:
                        TextStyle(fontSize: 11, color: Colors.orange.shade800),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;

  const _Chip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TrText(
        text,
        style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  final String message;

  const _ErrorText({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: TrText(
              message,
              style: TextStyle(fontSize: 12, color: Colors.red.shade800),
            ),
          ),
        ],
      ),
    );
  }
}
