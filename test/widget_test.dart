import 'package:creditos/app.dart';
import 'package:creditos/core/database/app_database.dart';
import 'package:creditos/core/network/supabase_delta_sync.dart';
import 'package:creditos/injection_container.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the credits and collections home', (
    WidgetTester tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final sync = _TestSupabaseDeltaSync(database);
    getIt.registerSingleton<SupabaseDeltaSync>(sync);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      sync.dispose();
      await getIt.reset();
      await database.close();
    });

    await tester.pumpWidget(const CreditosApp());

    expect(find.text('Llave en Mano'), findsOneWidget);
  });
}

class _TestSupabaseDeltaSync extends SupabaseDeltaSync {
  _TestSupabaseDeltaSync(AppDatabase database) : super(database, null);

  @override
  Future<bool> isRootAccountAvailable() async => false;
}
