# -*- mode: python ; coding: utf-8 -*-

block_cipher = None

a = Analysis(
    ['magicpaste.py'],
    pathex=[],
    binaries=[],
    datas=[
        ('assets/main.html',        'assets'),
        ('assets/toast.html',       'assets'),
        ('assets/logo.png',         'assets'),
        ('assets/icons/logo.png',   'assets/icons'),
        ('assets/icons/magicpaste.ico', 'assets/icons'),
        ('assets/icons/tray_green.png', 'assets/icons'),
        ('assets/icons/tray_red.png',   'assets/icons'),
    ],
    hiddenimports=[
        'webview.platforms.edgechromium',
        'pystray._win32',
        'PIL._tkinter_finder',
        'zeroconf._utils.ipaddress',
        'zeroconf._dns',
        'zeroconf._handlers.answers',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['tkinter'],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='MagicPaste',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,          # no console window
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon='assets/icons/magicpaste.ico',
    version_file=None,
)
