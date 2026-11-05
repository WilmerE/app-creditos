import 'package:creditos/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the credits and collections home', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CreditosApp());

    expect(find.text('Gestión de Créditos y Cobros'), findsOneWidget);
  });
}
