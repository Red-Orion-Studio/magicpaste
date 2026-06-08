"""Unit tests for the i18n module (i18n.py)."""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import i18n


# ── resolve() ─────────────────────────────────────────────────────────────────

def test_resolve_en():
    assert i18n.resolve('en') == 'en'


def test_resolve_es():
    assert i18n.resolve('es') == 'es'


def test_resolve_system_returns_valid_lang():
    result = i18n.resolve('system')
    assert result in ('en', 'es')


def test_resolve_unknown_falls_back_to_system():
    result = i18n.resolve('fr')
    assert result in ('en', 'es')


# ── strings() ─────────────────────────────────────────────────────────────────

def test_strings_en_returns_dict():
    d = i18n.strings('en')
    assert isinstance(d, dict)
    assert len(d) > 0


def test_strings_es_returns_dict():
    d = i18n.strings('es')
    assert isinstance(d, dict)
    assert len(d) > 0


def test_strings_en_es_have_same_keys():
    assert set(i18n.strings('en').keys()) == set(i18n.strings('es').keys())


def test_strings_values_are_strings():
    for v in i18n.strings('en').values():
        assert isinstance(v, str)


def test_strings_unknown_lang_falls_back_to_en():
    en = i18n.strings('en')
    fr = i18n.strings('fr')
    assert en == fr


# ── t() ───────────────────────────────────────────────────────────────────────

def test_t_known_key_en():
    val = i18n.t('connected', 'en')
    assert val == 'Connected'


def test_t_known_key_es():
    val = i18n.t('connected', 'es')
    assert val == 'Conectado'


def test_t_missing_key_returns_key():
    val = i18n.t('nonexistent_key_xyz', 'en')
    assert val == 'nonexistent_key_xyz'


def test_t_interpolation():
    val = i18n.t('toast_from', 'en', d='Pixel 8')
    assert 'Pixel 8' in val


def test_t_interpolation_es():
    val = i18n.t('ago', 'es', t='5m')
    assert '5m' in val
    assert 'hace' in val


def test_t_history_sub_interpolation():
    val = i18n.t('history_sub', 'en', n=42)
    assert '42' in val


def test_t_missing_lang_falls_back_to_en():
    en_val = i18n.t('status', 'en')
    fr_val = i18n.t('status', 'fr')
    assert en_val == fr_val
