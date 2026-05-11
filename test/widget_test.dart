import 'package:flutter_test/flutter_test.dart';
import 'package:pronostic_hippique/main.dart';

void main() {
  testWidgets('Pronostic Hippique smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PronosticHippiqueApp());
    expect(find.byType(PronosticHippiqueApp), findsOneWidget);
  });
}
