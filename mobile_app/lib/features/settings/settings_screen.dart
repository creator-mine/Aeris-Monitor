import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'providers/settings_provider.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Настройки',
      body: Consumer<SettingsProvider>(
        builder: (context, provider, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSection(
                context,
                'Подключение',
                [
                  _buildTextField(
                    context,
                    'API URL',
                    provider.apiUrl,
                    (value) => provider.setApiUrl(value),
                    icon: Icons.link,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    context,
                    'MQTT Брокер',
                    provider.mqttBroker,
                    (value) => provider.setMqttBroker(value),
                    icon: Icons.cloud,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    context,
                    'MQTT Порт',
                    provider.mqttPort.toString(),
                    (value) {
                      final port = int.tryParse(value);
                      if (port != null) {
                        provider.setMqttPort(port);
                      }
                    },
                    icon: Icons.numbers,
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildSection(
                context,
                'Внешний вид',
                [
                  _buildSwitchTile(
                    context,
                    'Тёмная тема',
                    provider.darkMode,
                    (value) => provider.setDarkMode(value),
                    icon: Icons.dark_mode,
                  ),
                  const SizedBox(height: 16),
                  _buildColorThemeSelector(context, provider),
                ],
              ),
              const SizedBox(height: 24),
              _buildSection(
                context,
                'Фон приложения',
                [
                  _buildBackgroundSelector(context, provider),
                ],
              ),
              const SizedBox(height: 24),
              _buildSection(
                context,
                'О приложении',
                [
                  _buildInfoTile(
                    context,
                    'Версия',
                    '1.0.0',
                    icon: Icons.info,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoTile(
                    context,
                    'Разработчик',
                    'IoT Modular System',
                    icon: Icons.code,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildColorThemeSelector(BuildContext context, SettingsProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Акцентный цвет',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: List.generate(AppTheme.accentColors.length, (index) {
            final isSelected = provider.accentColorIndex == index;
            final color = AppTheme.accentColors[index];
            return GestureDetector(
              onTap: () => provider.setAccentColorIndex(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.transparent,
                    width: 3,
                  ),
                  boxShadow: [
                    if (isSelected)
                      BoxShadow(
                        color: color.withOpacity(0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                  ],
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 22)
                    : null,
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildBackgroundSelector(BuildContext context, SettingsProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (provider.backgroundImagePath != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(provider.backgroundImagePath!),
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  height: 180,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('Файл не найден', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Прозрачность: ${(provider.backgroundOpacity * 100).round()}%',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Expanded(
                child: Slider(
                  value: provider.backgroundOpacity,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  label: '${(provider.backgroundOpacity * 100).round()}%',
                  onChanged: (value) => provider.setBackgroundOpacity(value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickImage(context, provider),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Заменить'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => provider.setBackgroundImagePath(null),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Сбросить'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Icon(Icons.image_outlined, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  'Фон не выбран',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Выберите изображение для фона приложения',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _pickImage(context, provider),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Выбрать изображение'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickImage(BuildContext context, SettingsProvider provider) async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
    );
    if (xFile != null) {
      await provider.setBackgroundImagePath(xFile.path);
    }
  }

  Widget _buildSection(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: AppTheme.cardDecoration(
              darkMode: Theme.of(context).brightness == Brightness.dark),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    BuildContext context,
    String label,
    String value,
    Function(String) onChanged, {
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: TextEditingController(text: value),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      keyboardType: keyboardType,
      onChanged: onChanged,
    );
  }

  Widget _buildSwitchTile(
    BuildContext context,
    String title,
    bool value,
    Function(bool) onChanged, {
    required IconData icon,
  }) {
    return SwitchListTile(
      title: Text(title),
      value: value,
      onChanged: onChanged,
      secondary: Icon(icon, color: AppTheme.primaryColor),
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildInfoTile(
    BuildContext context,
    String title,
    String value, {
    required IconData icon,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppTheme.primaryColor),
      title: Text(title),
      subtitle: Text(value),
      contentPadding: EdgeInsets.zero,
    );
  }
}
