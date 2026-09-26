import 'package:flutter/material.dart';

const gallerySettingsPanelWidth = 340.0;

/// Centers the task label over its content pane.
class GalleryTaskHeader extends StatelessWidget {
  const GalleryTaskHeader({super.key, required this.taskTitle});

  final String taskTitle;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: SizedBox(
      height: kToolbarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 56),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              taskTitle,
              maxLines: 1,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
      ),
    ),
  );
}
