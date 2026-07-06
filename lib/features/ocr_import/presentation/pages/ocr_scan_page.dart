import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:submersion/core/constants/units.dart';
import 'package:submersion/features/dive_log/domain/entities/dive_prefill.dart';
import 'package:submersion/features/dive_sites/presentation/providers/site_providers.dart';
import 'package:submersion/features/ocr_import/domain/services/logbook_parser.dart';
import 'package:submersion/features/ocr_import/domain/services/unit_context.dart';
import 'package:submersion/features/ocr_import/presentation/controllers/scan_flow_controller.dart';
import 'package:submersion/features/ocr_import/presentation/providers/ocr_providers.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';

/// Scan a paper logbook page: acquire a photo, run on-device OCR, and
/// open the dive edit form prefilled with whatever was extracted.
class OcrScanPage extends ConsumerStatefulWidget {
  const OcrScanPage({super.key});

  @override
  ConsumerState<OcrScanPage> createState() => _OcrScanPageState();
}

class _OcrScanPageState extends ConsumerState<OcrScanPage> {
  bool _processing = false;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  Future<void> _pickFromCamera() async {
    final file = await ImagePicker().pickImage(source: ImageSource.camera);
    if (file != null) await _process(file.path);
  }

  Future<void> _pickFromGallery() async {
    if (_isMobile) {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file != null) await _process(file.path);
    } else {
      final result = await FilePicker.pickFiles(type: FileType.image);
      final path = result?.files.single.path;
      if (path != null) await _process(path);
    }
  }

  Future<void> _process(String photoPath) async {
    setState(() => _processing = true);
    try {
      final bytes = await File(photoPath).readAsBytes();
      final sites = await ref.read(sitesProvider.future);
      final settings = ref.read(settingsProvider);
      final locale = WidgetsBinding.instance.platformDispatcher.locale;
      final controller = ScanFlowController(
        engine: ref.read(ocrEngineProvider),
        parser: LogbookParser(),
        existingSites: sites,
        fallbackUnits: UnitDefaults(
          depthFeet: settings.depthUnit == DepthUnit.feet,
          pressurePsi: settings.pressureUnit == PressureUnit.psi,
          tempFahrenheit:
              settings.temperatureUnit == TemperatureUnit.fahrenheit,
          weightLbs: settings.weightUnit == WeightUnit.pounds,
        ),
        preferDayFirst: locale.countryCode != 'US',
      );
      final prefill = await controller.process(bytes, photoPath);
      if (!mounted) return;
      if (_isEmptyBeyondPhoto(prefill)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't read much from this page - fields left blank",
            ),
          ),
        );
      }
      context.pushReplacement('/dives/new', extra: prefill);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  bool _isEmptyBeyondPhoto(DivePrefill p) =>
      p.diveNumber == null &&
      p.dateTime == null &&
      p.durationMinutes == null &&
      p.maxDepthMeters == null &&
      p.waterTempCelsius == null &&
      p.airTempCelsius == null &&
      p.rating == null &&
      p.notes == null &&
      p.site == null &&
      p.startPressureBar == null &&
      p.endPressureBar == null &&
      p.o2Percent == null &&
      p.cylinderVolumeLiters == null &&
      p.weightKg == null;

  @override
  Widget build(BuildContext context) {
    final availability = ref.watch(ocrAvailabilityProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Paper Log')),
      body: Center(
        child: switch ((availability.value ?? true, _processing)) {
          (false, _) => Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Text recognition is not available. Install Tesseract to '
              'scan paper logs (for example: sudo apt install '
              'tesseract-ocr).',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          (_, true) => const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Reading page...'),
            ],
          ),
          _ => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.document_scanner_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              if (_isMobile) ...[
                FilledButton.icon(
                  onPressed: _pickFromCamera,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Take Photo'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose Photo'),
                ),
              ] else
                FilledButton.icon(
                  onPressed: _pickFromGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose Photo'),
                ),
            ],
          ),
        },
      ),
    );
  }
}
