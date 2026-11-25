import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'approval.dart';
import 'local_log.dart';
import 'session_controller.dart';

/// System tray icon (green = assistant control live, grey = paused or stopped), a menu with Pause / Resume /
/// Start with Windows / Quit, and "close = hide to tray" while no session is live.
/// The green bar is never hidden: while a session is live the window cannot be hidden.
class AppTray with TrayListener, WindowListener {
  AppTray(this.session, this.log);
  final SessionController session;
  final LocalLog log;

  /// Whether the app starts when you sign in to Windows. Off by default; you switch it on.
  final autostart = ValueNotifier<bool>(false);
  bool _live = false;
  bool _paused = false;
  ControlMode? _mode;

  Future<void> init() async {
    launchAtStartup.setup(
      appName: 'Tether',
      appPath: Platform.resolvedExecutable,
    );
    autostart.value = await launchAtStartup.isEnabled();
    // After the rename to Tether.exe an old "Start with Windows" entry still points at laptop_link.exe: re-point it.
    try {
      if (!autostart.value && Platform.isWindows) {
        final r = await Process.run('reg', [
          'query',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          'Tether',
        ]);
        if ('${r.stdout}'.toLowerCase().contains('laptop_link.exe')) {
          await launchAtStartup.enable();
          autostart.value = await launchAtStartup.isEnabled();
          await log.add('AUTOSTART entry re-pointed to the new program name');
        }
      }
    } catch (_) {}
    trayManager.addListener(this);
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
    session.addListener(_refresh);
    await _refresh(force: true);
  }

  Future<void> setAutostart(bool on) async {
    if (on) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
    autostart.value = await launchAtStartup.isEnabled();
    await log.add('AUTOSTART ${autostart.value ? 'ON' : 'OFF'}');
    await _refresh(force: true);
  }

  Future<void> _refresh({bool force = false}) async {
    final live = session.active;
    final paused = session.paused;
    if (!force && live == _live && paused == _paused && session.mode == _mode) {
      return;
    }
    _live = live;
    _paused = paused;
    _mode = session.mode;
    final green = live && !paused;
    await trayManager.setIcon(
      green ? 'assets/tray_live.ico' : 'assets/tray_paused.ico',
    );
    await trayManager.setToolTip(
      green
          ? 'Tether: assistant control LIVE (${session.mode.label})'
          : (live ? 'Tether: PAUSED (session open)' : 'Tether: stopped'),
    );
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(
            key: 'status',
            label: green
                ? 'Assistant control: LIVE'
                : (live ? 'Assistant control: PAUSED' : 'Stopped'),
            disabled: true,
          ),
          MenuItem(
            key: green ? 'pause' : 'resume',
            label: green ? 'Pause' : (live ? 'Resume' : 'Start session'),
          ),
          MenuItem(
            label: 'Mode: ${session.mode.label}',
            submenu: Menu(
              items: [
                for (final m in ControlMode.values)
                  MenuItem.checkbox(
                    key: 'mode_${m.name}',
                    label: m.title,
                    checked: session.mode == m,
                  ),
              ],
            ),
          ),
          MenuItem.separator(),
          MenuItem(key: 'show', label: 'Show window'),
          MenuItem.checkbox(
            key: 'autostart',
            label: 'Start with Windows',
            checked: autostart.value,
          ),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit'),
        ],
      ),
    );
  }

  @override
  void onTrayIconMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  Future<void> onTrayMenuItemClick(MenuItem item) async {
    switch (item.key) {
      case 'pause':
        await session.setPaused(true);
        break;
      case 'resume':
        if (session.active) {
          await session.setPaused(false);
        } else {
          await session.start(null);
        }
        break;
      case 'mode_ask':
        await session.setMode(ControlMode.ask);
        break;
      case 'mode_auto':
        await session.setMode(ControlMode.auto);
        break;
      case 'mode_smart':
        await session.setMode(ControlMode.smart);
        break;
      case 'show':
        await windowManager.show();
        await windowManager.focus();
        break;
      case 'autostart':
        await setAutostart(!autostart.value);
        break;
      case 'quit':
        await log.add('QUIT from tray');
        await session.stop('quit');
        await trayManager.destroy();
        exit(0);
    }
  }

  /// X button: hide to the tray, but only when no session is live (the green bar must stay visible).
  @override
  Future<void> onWindowClose() async {
    if (session.active) return;
    await windowManager.hide();
  }

  void dispose() {
    session.removeListener(_refresh);
    trayManager.removeListener(this);
    windowManager.removeListener(this);
  }
}
