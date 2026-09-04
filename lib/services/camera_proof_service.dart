import 'dart:io';

import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Handles requesting camera permission, initializing the camera,
/// and saving a proof photo when the user completes a task.
class CameraProofService {
  CameraProofService._internal();
  static final CameraProofService instance = CameraProofService._internal();

  CameraController? _controller;
  List<CameraDescription> _cameras = [];

  Future<bool> requestPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Whether camera permission is already granted, without prompting.
  /// Safe to call any time a screen needs to know current status (e.g.
  /// on load) rather than only right after the user taps "Enable".
  Future<bool> hasPermission() async {
    final status = await Permission.camera.status;
    return status.isGranted;
  }

  /// True once the user has denied camera access AND checked "don't
  /// ask again" (or the platform equivalent) — meaning a further
  /// [requestPermission] call will never show a dialog again; only
  /// the system Settings screen can change it from here.
  Future<bool> isPermanentlyDenied() async {
    final status = await Permission.camera.status;
    return status.isPermanentlyDenied;
  }

  /// Opens this app's system Settings page so the user can grant
  /// Camera access manually when [isPermanentlyDenied] is true.
  Future<void> openSystemSettings() => openAppSettings();

  /// Whether the device actually has camera hardware at all — false
  /// on the iOS Simulator (it has no camera) and on some Android
  /// emulators without a configured virtual camera. Distinct from
  /// permission: a "no hardware" device will always return an empty
  /// list here regardless of what permission says.
  Future<bool> hasCameraHardware() async {
    final cams = await availableCameras();
    return cams.isNotEmpty;
  }

  /// Initializes the camera controller. Call this right before showing
  /// the proof-capture screen, and call [dispose] when leaving it.
  Future<CameraController?> initializeCamera() async {
    final granted = await requestPermission();
    if (!granted) return null;

    _cameras = await availableCameras();
    if (_cameras.isEmpty) return null;

    // Prefer the front camera for a "selfie proof" style check-in.
    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras.first,
    );

    _controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _controller!.initialize();
    return _controller;
  }

  /// Captures a photo and saves it under the app's documents directory.
  /// Returns the saved file path, or null if capture failed.
  Future<String?> captureProofPhoto(String taskId) async {
    if (_controller == null || !_controller!.value.isInitialized) return null;

    try {
      final XFile file = await _controller!.takePicture();

      final dir = await getApplicationDocumentsDirectory();
      final proofDir = Directory('${dir.path}/task_proofs');
      if (!await proofDir.exists()) {
        await proofDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final savedPath = '${proofDir.path}/${taskId}_$timestamp.jpg';
      await File(file.path).copy(savedPath);

      return savedPath;
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}
