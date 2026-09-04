import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/task_model.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';

/// Shows the proof photo a user captured when completing [task], along
/// with the task title and when it was completed. Reached by tapping a
/// completed task (that has a saved proof photo) from the home screen
/// or the dashboard's proof gallery.
class ProofPhotoViewerScreen extends StatelessWidget {
  final Task task;
   ProofPhotoViewerScreen({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final path = task.proofImagePath;
    final file = path != null ? File(path) : null;
    final completedLabel = task.completedAt != null
        ? DateFormat('EEEE, d MMM · h:mm a').format(task.completedAt!)
        : null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(task.title, style:  TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: file == null
                    ?  _MissingPhotoNotice()
                    : FutureBuilder<bool>(
                        future: file.exists(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState != ConnectionState.done) {
                            return  CircularProgressIndicator(
                              color: AppColors.accent,
                            );
                          }
                          if (snapshot.data != true) {
                            return  _MissingPhotoNotice();
                          }
                          return InteractiveViewer(
                            minScale: 1,
                            maxScale: 4,
                            child: Image.file(file, fit: BoxFit.contain),
                          );
                        },
                      ),
              ),
            ),
            if (completedLabel != null)
              Padding(
                padding:  EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                     Icon(Icons.check_circle_rounded,
                        color: AppColors.success, size: 18),
                     SizedBox(width: 8),
                    Text(
                      'Completed $completedLabel',
                      style: AppTextStyles.bodyMuted.copyWith(color: Colors.white70),
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

class _MissingPhotoNotice extends StatelessWidget {
   _MissingPhotoNotice();

  @override
  Widget build(BuildContext context) {
    return  Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.image_not_supported_outlined, size: 48, color: Colors.white38),
        SizedBox(height: 12),
        Text(
          'This proof photo is no longer available on this device.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    );
  }
}
