import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:yaru_window_manager/src/window_manager.dart';
import 'package:yaru_window_platform_interface/yaru_window_platform_interface.dart';

class MockMultiViewDesktop extends Mock implements MultiViewDesktop {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(TitleBarStyle.normal);
    registerFallbackValue(Brightness.light);
  });

  test('register with', () {
    YaruWindowManager.registerWith();
    expect(YaruWindowPlatform.instance, isA<YaruWindowManager>());
  });

  test('close', () async {
    final window = MockMultiViewDesktop();
    when(window.closeWindow).thenAnswer((_) async {});

    await YaruWindowManager((_) => window).close(0);
    verify(window.closeWindow).called(1);
  });
}
