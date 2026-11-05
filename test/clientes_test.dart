import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:creditos/core/database/app_database.dart';
import 'package:creditos/core/utils/contact_launcher.dart';
import 'package:creditos/features/clientes/data/datasources/client_local_datasource.dart';
import 'package:creditos/features/clientes/domain/entities/client.dart';
import 'package:creditos/features/clientes/domain/repositories/client_repository.dart';
import 'package:creditos/features/clientes/presentation/bloc/client_bloc.dart';
import 'package:creditos/features/clientes/presentation/screens/client_form_screen.dart';

Client _client(
  String id,
  String name, {
  String? dpi,
  String? alias,
  List<String> phones = const [],
}) {
  final now = DateTime(2024, 1, 1);
  return Client(
    id: id,
    fullName: name,
    address: 'Zona 1',
    phones: phones,
    dpi: dpi,
    alias: alias,
    createdAt: now,
    updatedAt: now,
  );
}

class _FakeRepository implements ClientRepository {
  final saved = <Client>[];
  final _controller = StreamController<List<Client>>.broadcast();

  @override
  Stream<List<Client>> watchClients({String query = ''}) async* {
    yield saved;
    yield* _controller.stream;
  }

  @override
  Future<Client?> getById(String id) async => null;

  @override
  Future<void> save(Client client, {String? newPhotoSourcePath}) async {
    saved.add(client);
    _controller.add(List.of(saved));
  }

  @override
  Future<void> delete(String id) async {}
}

void main() {
  group('ClientLocalDataSource', () {
    late AppDatabase db;
    late ClientLocalDataSource source;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      source = ClientLocalDataSource(db);
    });
    tearDown(() => db.close());

    test('inserts, lists with ordered phones and searches', () async {
      await source.insert(
        _client('1', 'Zoila', phones: ['5555-1111', '4444-2222']),
      );
      await source.insert(
        _client('2', 'Ana', dpi: '12345', alias: 'YOLI DE DON NERY'),
      );

      final all = await source.findClients();
      expect(all.map((c) => c.fullName), ['Ana', 'Zoila']);
      expect(all.last.phones, ['5555-1111', '4444-2222']);

      expect((await source.findClients(query: 'yoli')).single.id, '2');
      expect((await source.findClients(query: '123')).single.id, '2');
      expect(await source.findClients(query: 'xyz'), isEmpty);
    });

    test('updates replacing phones and soft deletes', () async {
      final original = _client('1', 'Ana', phones: ['111']);
      await source.insert(original);
      await source.update(
        original.copyWith(fullName: 'Ana Maria', phones: ['222', '333']),
      );

      final updated = (await source.getById('1'))!;
      expect(updated.fullName, 'Ana Maria');
      expect(updated.phones, ['222', '333']);

      await source.softDelete('1', DateTime.now());
      expect(await source.findClients(), isEmpty);
    });
  });

  group('ClientBloc', () {
    test('loads clients and saves a new one', () async {
      final repo = _FakeRepository();
      final bloc = ClientBloc(repo)..add(const ClientsSubscriptionRequested());
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.listStatus, ClientListStatus.success);

      bloc.add(ClientSaved(_client('1', 'Ana')));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bloc.state.clients.single.fullName, 'Ana');
      await bloc.close();
    });
  });

  test('ContactLauncher normalizes numbers', () {
    expect(ContactLauncher.normalizeForWhatsApp('5555-1234'), '50255551234');
    expect(
      ContactLauncher.whatsAppUri('+502 5555 1234').toString(),
      'https://wa.me/50255551234',
    );
  });

  testWidgets('form validates required fields and saves', (tester) async {
    final repo = _FakeRepository();
    final bloc = ClientBloc(repo);
    addTearDown(bloc.close);
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(value: bloc, child: const ClientFormScreen()),
      ),
    );

    await tester.tap(find.text('Guardar cliente'));
    await tester.pump();
    expect(find.text('El nombre es obligatorio'), findsOneWidget);
    expect(find.text('La dirección es obligatoria'), findsOneWidget);
    expect(repo.saved, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre completo *'),
      'Ana',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Dirección / Ubicación *'),
      'Zona 1',
    );
    await tester.tap(find.text('Agregar teléfono'));
    await tester.pump();
    expect(find.text('Teléfono 2'), findsOneWidget);

    await tester.tap(find.text('Guardar cliente'));
    await tester.pump();
    expect(repo.saved.single.fullName, 'Ana');
  });
}
