import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:launcher_app/src/screens/store_kit/store_screenshot_lightbox.dart';

void main() {
  testWidgets('צילום המסך בתצוגה המוגדלת מפוענח לכל היותר בגודל המסך',
      (tester) async {
    late ImageProvider provider;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1000, 700), devicePixelRatio: 2),
        child: Builder(
          builder: (context) {
            provider = screenBoundImage(context, 'shot.png');
            return const SizedBox();
          },
        ),
      ),
    );

    expect(provider, isA<ResizeImage>());
    final resized = provider as ResizeImage;
    expect(resized.width, 2048);
    expect(resized.height, 1408);
    expect(resized.policy, ResizeImagePolicy.fit);
    expect(resized.allowUpscaling, isFalse);
  });
}
