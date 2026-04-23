import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:isv_toolkit/core/preferences_service.dart';
import 'package:isv_toolkit/main.dart';

void main() {
  testWidgets('App smoke test - loads with default preferences', (
    WidgetTester tester,
  ) async {
    // Provide empty in-memory store so no disk access happens during tests.
    SharedPreferences.setMockInitialValues({});
    final prefs = await PreferencesService.load();

    await tester.pumpWidget(ISVToolkitApp(prefs: prefs));

    // App should render without throwing.
    expect(find.byType(ISVToolkitApp), findsOneWidget);
  });
}
