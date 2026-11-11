// Steiner Budget — local-first budgeting, https://steinerdevelopers.dev
// Copyright (C) 2026 Steiner Developers, L.L.C.
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_budget/features/capture/adapters/gemini_nano_structurer.dart';

import 'package:core/core.dart';

/// The hermetic Tier-3 contract: the adapter is only a channel + the pure
/// llm_json parser, so a mocked `localbudget/capture` handler exercises the
/// whole path without a device, AICore or the plugin.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('localbudget/capture');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void mock({bool? status, Object? prompt}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'nanoStatus':
          return status;
        case 'nanoPrompt':
          final p = prompt;
          if (p is Exception) throw p;
          if (p is Error) throw p;
          return p;
      }
      return null;
    });
  }

  test('unreachable channel means unavailable, costs nothing', () async {
    final nano = GeminiNanoStructurer(); // no handler: MissingPluginException
    await pumpEventQueue();
    expect(nano.forCurrency(Currency.resolve('USD')).isAvailable(), isFalse);
  });

  test('unavailable skips the model entirely', () async {
    final asked = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      asked.add(call);
      return call.method == 'nanoStatus' ? false : null;
    });
    final structurer = GeminiNanoStructurer().forCurrency(
      Currency.resolve('USD'),
    );
    await pumpEventQueue();
    expect(structurer.isAvailable(), isFalse);
    expect(await structurer.structure(Uint8List(0), const ['ALDI']), isNull);
    expect(asked.map((c) => c.method), ['nanoStatus']); // no nanoPrompt
  });

  test(
    'available probe + clean JSON answer fills a low-confidence draft',
    () async {
      mock(
        status: true,
        prompt: '{"merchant":"Aldi","date":"2026-10-05","amountCents":2349}',
      );
      final structurer = GeminiNanoStructurer().forCurrency(
        Currency.resolve('USD'),
      );
      await pumpEventQueue();
      expect(structurer.isAvailable(), isTrue);
      final draft = await structurer.structure(
        Uint8List.fromList([1, 2, 3]),
        const ['ALDI 2026'],
      );
      expect(draft!.merchant, 'Aldi');
      expect(draft.date, DateTime.parse('2026-10-05'));
      expect(draft.total, Money(2349, Currency.resolve('USD')));
      expect(draft.merchantConfidence, FieldConfidence.low);
    },
  );

  test('the bound currency stamps the money, never the model', () async {
    mock(status: true, prompt: '{"amountCents":500}');
    final structurer = GeminiNanoStructurer().forCurrency(
      Currency.resolve('EUR'),
    );
    await pumpEventQueue();
    final draft = await structurer.structure(Uint8List(0), const []);
    expect(draft!.total!.currency.code, 'EUR');
  });

  test('model garbage and native failures degrade to null', () async {
    mock(status: true, prompt: 'The receipt shows about 4 euros.');
    final structurer = GeminiNanoStructurer().forCurrency(
      Currency.resolve('USD'),
    );
    await pumpEventQueue();
    expect(await structurer.structure(Uint8List(0), const []), isNull);

    mock(status: true, prompt: PlatformException(code: 'PromptError'));
    final angry = GeminiNanoStructurer().forCurrency(Currency.resolve('USD'));
    await pumpEventQueue();
    expect(await angry.structure(Uint8List(0), const []), isNull);
  });

  test('the prompt sent down carries the OCR lines', () async {
    final asked = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      asked.add(call);
      return call.method == 'nanoStatus' ? true : null;
    });
    final structurer = GeminiNanoStructurer().forCurrency(
      Currency.resolve('USD'),
    );
    await pumpEventQueue();
    await structurer.structure(Uint8List(9), const ['TOTAL 4.20']);
    final prompt = (asked.last.arguments['text'] as String);
    expect(prompt, contains('TOTAL 4.20'));
    expect(prompt, contains('amountCents'));
    expect(asked.last.arguments['image'], isA<Uint8List>());

    // No image (PDF text-only) means no image key to decode natively.
    await structurer.structure(Uint8List(0), const ['TOTAL 4.20']);
    expect(asked.last.arguments.containsKey('image'), isFalse);
  });
}
