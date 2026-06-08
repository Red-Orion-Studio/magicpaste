import 'package:flutter_test/flutter_test.dart';
import 'package:magicpaste/services/l10n.dart';

void main() {
  setUp(() => L10n.forcelang('en'));

  group('L10n.t — English', () {
    test('connected key', () {
      expect(L10n.t('connected'), equals('Connected'));
    });

    test('nav_home key', () {
      expect(L10n.t('nav_home'), equals('Home'));
    });

    test('nav_history key', () {
      expect(L10n.t('nav_history'), equals('History'));
    });

    test('nav_settings key', () {
      expect(L10n.t('nav_settings'), equals('Settings'));
    });

    test('unknown key returns the key itself', () {
      expect(L10n.t('__nonexistent__'), equals('__nonexistent__'));
    });
  });

  group('L10n.t — Spanish', () {
    setUp(() => L10n.forcelang('es'));

    test('connected key in Spanish', () {
      expect(L10n.t('connected'), equals('Conectado'));
    });

    test('nav_history in Spanish', () {
      expect(L10n.t('nav_history'), equals('Historial'));
    });

    test('nav_settings in Spanish', () {
      expect(L10n.t('nav_settings'), equals('Ajustes'));
    });
  });

  group('L10n.t — interpolation', () {
    test('replaces {n} placeholder', () {
      L10n.forcelang('en');
      expect(L10n.t('items', {'n': '7'}), equals('7 items'));
    });

    test('replaces {p} and {h} placeholders', () {
      L10n.forcelang('en');
      final result = L10n.t('port_host', {'p': '49152', 'h': '192.168.1.8'});
      expect(result, contains('49152'));
      expect(result, contains('192.168.1.8'));
    });

    test('step_of placeholder in Spanish', () {
      L10n.forcelang('es');
      expect(L10n.t('step_of', {'n': '1'}), equals('Paso 1 de 2'));
    });

    test('unknown key with args returns key unchanged', () {
      final result = L10n.t('__missing__', {'x': 'foo'});
      expect(result, equals('__missing__'));
    });
  });

  group('L10n.forcelang', () {
    test('switching to es changes lang', () {
      L10n.forcelang('es');
      expect(L10n.lang, equals('es'));
    });

    test('switching to en changes lang', () {
      L10n.forcelang('en');
      expect(L10n.lang, equals('en'));
    });

    test('translation changes when language switches', () {
      L10n.forcelang('en');
      final en = L10n.t('connected');
      L10n.forcelang('es');
      final es = L10n.t('connected');
      expect(en, isNot(equals(es)));
    });
  });
}
