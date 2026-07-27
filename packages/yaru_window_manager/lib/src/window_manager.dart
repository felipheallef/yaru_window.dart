import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:multiview_desktop/multiview_desktop.dart';
import 'package:yaru_window_platform_interface/yaru_window_platform_interface.dart';

/// A multiview_desktop-based implementation of [YaruWindowPlatform] for
/// macOS and Windows.
class YaruWindowManager extends YaruWindowPlatform {
  YaruWindowManager([@visibleForTesting this._resolve]);

  static void registerWith() {
    YaruWindowPlatform.instance = YaruWindowManager();
  }

  final MultiViewDesktop Function(int id)? _resolve;

  MultiViewDesktop _window(int id) {
    final resolve = _resolve;
    if (resolve != null) return resolve(id);

    // Yaru historically hardcodes id 0 for the primary window.
    if (id == 0) {
      final anchor = MultiViewDesktop.getAnchorId();
      if (anchor != null) {
        return MultiViewDesktop.fromId(anchor);
      }
    }
    return MultiViewDesktop.fromId(id);
  }

  final _listeners = <int, _YaruWindowStatesListener>{};
  final _closeListeners = <int, _YaruWindowOnCloseListener>{};

  _YaruWindowStatesListener _listenerFor(int id) =>
      _listeners.putIfAbsent(id, () => _YaruWindowStatesListener(_window(id)));

  _YaruWindowOnCloseListener _closeListenerFor(int id) => _closeListeners
      .putIfAbsent(id, () => _YaruWindowOnCloseListener(_window(id)));

  Future<void> _invoke(Future<void> Function() method) async {
    try {
      await method();
    } on MissingPluginException catch (_) {
    } on StateError catch (_) {
      // Multi-view not ready yet (startup / teardown).
    }
  }

  Future<T> _get<T>(Future<T> Function() getter, {required T orElse}) async {
    try {
      return await getter();
    } on MissingPluginException catch (_) {
      return orElse;
    } on StateError catch (_) {
      return orElse;
    }
  }

  @override
  Future<void> init(int id) async {
    // multiview_desktop owns engine/window lifecycle; nothing to init.
  }

  @override
  Future<void> close(int id) => _invoke(_window(id).closeWindow);

  @override
  Future<void> drag(int id) => _invoke(_window(id).startDragging);

  @override
  Future<void> fullscreen(int id) =>
      _invoke(() => _window(id).setFullScreen(true));

  @override
  Future<void> hide(int id) => _invoke(_window(id).hide);

  @override
  Future<void> hideTitle(int id) => _invoke(
    () => _window(id).setTitleBarStyle(TitleBarStyle.hidden),
  );

  @override
  Future<void> maximize(int id) => _invoke(_window(id).maximize);

  @override
  Future<void> minimize(int id) => _invoke(_window(id).minimize);

  @override
  Future<void> restore(int id) async {
    final win = _window(id);
    if (await _get(win.isFullScreen, orElse: false)) {
      return _invoke(() => win.setFullScreen(false));
    } else if (await _get(win.isMaximized, orElse: false)) {
      return _invoke(win.unmaximize);
    } else if (await _get(win.isMinimized, orElse: false)) {
      return _invoke(win.restore);
    }
  }

  @override
  Future<void> show(int id) => _invoke(_window(id).show);

  @override
  Future<void> showMenu(int id) => _invoke(_window(id).popUpWindowMenu);

  @override
  Future<void> showTitle(int id) => _invoke(
    () => _window(id).setTitleBarStyle(TitleBarStyle.normal),
  );

  @override
  Future<void> setBackground(int id, Color color) =>
      _invoke(() => _window(id).setBackgroundColor(color));

  @override
  Future<void> setBrightness(int id, Brightness brightness) =>
      _invoke(() => _window(id).setBrightness(brightness));

  @override
  Future<void> setTitle(int id, String title) => _invoke(() async {
    await _window(id).setTitle(title);
    await _listenerFor(id)._updateState();
  });

  @override
  Future<void> setMinimizable(int id, bool minimizable) => _invoke(() async {
    await _window(id).setMinimizable(minimizable);
    await _listenerFor(id)._updateState();
  });

  @override
  Future<void> setMaximizable(int id, bool maximizable) => _invoke(() async {
    await _window(id).setMaximizable(maximizable);
    await _listenerFor(id)._updateState();
  });

  @override
  Future<void> setClosable(int id, bool closable) => _invoke(() async {
    await _window(id).setClosable(closable);
    await _listenerFor(id)._updateState();
  });

  @override
  Future<YaruWindowState> state(int id) => _stateFor(_window(id));

  @override
  Stream<YaruWindowState> states(int id) => _listenerFor(id).states();

  @override
  Future<void> onClose(int id, FutureOr<bool> Function() handler) {
    return _closeListenerFor(id).addCloseHandler(handler);
  }

  Future<YaruWindowState> _stateFor(MultiViewDesktop win) {
    return Future.wait([
      _get(win.isFocused, orElse: true),
      _get(win.isClosable, orElse: true),
      _get(win.isFullScreen, orElse: false),
      _get(win.isMaximizable, orElse: true),
      _get(win.isMaximized, orElse: false),
      _get(win.isMinimizable, orElse: true),
      _get(win.isMinimized, orElse: false),
      _get(win.isMovable, orElse: true),
      _get(win.getTitle, orElse: ''),
      _get(win.isVisible, orElse: true),
    ]).then((values) {
      final active = values[0] as bool;
      final closable = values[1] as bool;
      final fullscreen = values[2] as bool;
      final maximizable = values[3] as bool;
      final maximized = values[4] as bool;
      final minimizable = values[5] as bool;
      final minimized = values[6] as bool;
      final movable = values[7] as bool;
      final title = values[8] as String;
      final visible = values[9] as bool;
      return YaruWindowState(
        isActive: active,
        isClosable: closable,
        isFullscreen: fullscreen,
        isMaximizable: maximizable && !maximized,
        isMaximized: maximized,
        isMinimizable: minimizable && !minimized,
        isMinimized: minimized,
        isMovable: movable && !kIsWeb,
        isRestorable: fullscreen || maximized || minimized,
        title: title,
        isVisible: visible,
      );
    });
  }
}

class _YaruWindowStatesListener implements WindowListenerCallbacks {
  _YaruWindowStatesListener(this._win);

  final MultiViewDesktop _win;
  StreamController<YaruWindowState>? _controller;
  bool _registered = false;

  Stream<YaruWindowState> states() async* {
    _controller ??= StreamController<YaruWindowState>.broadcast(
      onListen: () {
        if (!_registered) {
          MultiViewDesktop.addListenerForView(_win.id, this);
          _registered = true;
        }
      },
      onCancel: () {
        if (_registered) {
          MultiViewDesktop.removeListenerForView(_win.id, this);
          _registered = false;
        }
      },
    );
    yield* _controller!.stream;
  }

  Future<void> _updateState() async {
    final platform = YaruWindowPlatform.instance;
    if (platform is YaruWindowManager) {
      _controller?.add(await platform._stateFor(_win));
    }
  }

  @override
  void onWindowBlur() => _updateState();
  @override
  void onWindowFocus() => _updateState();
  @override
  void onWindowEnterFullScreen() => _updateState();
  @override
  void onWindowLeaveFullScreen() => _updateState();
  @override
  void onWindowMaximize() => _updateState();
  @override
  void onWindowUnmaximize() => _updateState();
  @override
  void onWindowMinimize() => _updateState();
  @override
  void onWindowRestore() => _updateState();
  @override
  void onWindowClose() {}
  @override
  void onWindowResize() {}
  @override
  void onWindowResized() {}
  @override
  void onWindowMove() {}
  @override
  void onWindowMoved() {}
  @override
  void onWindowEvent(String eventName) {}
}

class _YaruWindowOnCloseListener implements WindowListenerCallbacks {
  _YaruWindowOnCloseListener(this._win) {
    MultiViewDesktop.addListenerForView(_win.id, this);
  }

  final MultiViewDesktop _win;
  final _onCloseHandlers = <FutureOr<bool> Function()>[];

  Future<void> addCloseHandler(FutureOr<bool> Function() handler) async {
    _onCloseHandlers.add(handler);
    await _win.setPreventClose(true);
  }

  Future<void> _handleClose() async {
    for (final handler in _onCloseHandlers) {
      if (!await handler()) {
        return;
      }
    }
    await _win.setPreventClose(false);
    await _win.closeWindow();
  }

  @override
  void onWindowClose() => _handleClose();

  @override
  void onWindowFocus() {}
  @override
  void onWindowBlur() {}
  @override
  void onWindowMaximize() {}
  @override
  void onWindowUnmaximize() {}
  @override
  void onWindowMinimize() {}
  @override
  void onWindowRestore() {}
  @override
  void onWindowResize() {}
  @override
  void onWindowResized() {}
  @override
  void onWindowMove() {}
  @override
  void onWindowMoved() {}
  @override
  void onWindowEnterFullScreen() {}
  @override
  void onWindowLeaveFullScreen() {}
  @override
  void onWindowEvent(String eventName) {}
}
