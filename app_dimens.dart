import 'package:flutter/widgets.dart';

import '../theme/app_theme_tokens.dart';

/// 应用窗口宽度分级。
///
/// 尺寸适配负责处理 375dp 以下的小屏压缩；窗口分级负责处理更大的结构变化，
/// 例如手机单栏、平板双栏、编辑器宽屏多面板等。
enum AppWindowClass {
  compact,
  medium,
  expanded;

  bool get isCompact => this == AppWindowClass.compact;

  bool get isMedium => this == AppWindowClass.medium;

  bool get isExpanded => this == AppWindowClass.expanded;
}

/// 应用统一尺寸适配快照。
///
/// 设计思想：
///
/// - 设计稿以 375x812 为基准，设计稿中的非字号尺寸默认按 Flutter dp 记录。
/// - 当实际宽度小于 375dp 时，所有非字号尺寸按 `width / 375` 严格等比压缩。
/// - 当实际宽度大于或等于 375dp 时，基础尺寸保持设计稿原值，不继续放大。
/// - 宽屏、横屏、折叠屏展开后的额外空间交给断点、多栏布局和最大宽度容器处理，
///   不通过放大 padding、圆角、按钮高度等基础尺寸处理。
/// - 字号不使用这里的适配逻辑，继续通过 `TextTheme` 和系统字体缩放管理。
///
/// 使用边界：
///
/// - Widget 或 Dialog 内优先使用 `16.dpc(context)` 或 `context.dimens`。
/// - 没有 `BuildContext` 的场景可以使用根尺寸的 `16.dp`。
/// - Painter、Renderer 或布局计算器中，优先从 Widget 边界传入 [AppDimens]，
///   再使用 `16.dpx(dimens)`。
final class AppDimens {
  const AppDimens({required this.size});

  factory AppDimens.fromSize(Size size) {
    return AppDimens(size: size);
  }

  factory AppDimens.of(BuildContext context) {
    return AppDimens.fromSize(MediaQuery.sizeOf(context));
  }

  static const designWidth = 375.0;

  final Size size;

  /// 当前尺寸缩放比例。
  ///
  /// 小于 375dp 时严格按实际宽度比例压缩；大于等于 375dp 时保持 1.0。
  /// 例如：
  ///
  /// - 360dp: `360 / 375 = 0.96`
  /// - 320dp: `320 / 375 = 0.853...`
  /// - 390dp: `1.0`
  double get scale {
    return (size.width / designWidth).clamp(0.0, 1.0);
  }

  AppWindowClass get windowClass {
    final width = size.width;
    if (width >= AppBreakpoints.medium) {
      return AppWindowClass.expanded;
    }
    if (width >= AppBreakpoints.compact) {
      return AppWindowClass.medium;
    }
    return AppWindowClass.compact;
  }

  bool get isLandscape {
    return size.width > size.height;
  }

  /// 将设计稿中的非字号尺寸转换为当前屏幕下的实际 dp。
  ///
  /// 不要用这个方法处理字体字号。
  double a(num value) {
    return value.toDouble() * scale;
  }

  double get xs => a(AppSpacing.xs);

  double get sm => a(AppSpacing.sm);

  double get md => a(AppSpacing.md);

  double get lg => a(AppSpacing.lg);

  double get xl => a(AppSpacing.xl);

  double get radiusSm => a(AppRadius.sm);

  double get radiusMd => a(AppRadius.md);

  double get radiusLg => a(AppRadius.lg);

  double get iconButton => a(AppSizes.iconButton);

  double get toolbarHeight => a(AppSizes.toolbarHeight);

  EdgeInsets all(num value) {
    return EdgeInsets.all(a(value));
  }

  EdgeInsets symmetric({num horizontal = 0, num vertical = 0}) {
    return EdgeInsets.symmetric(
      horizontal: a(horizontal),
      vertical: a(vertical),
    );
  }

  EdgeInsets only({num left = 0, num top = 0, num right = 0, num bottom = 0}) {
    return EdgeInsets.only(
      left: a(left),
      top: a(top),
      right: a(right),
      bottom: a(bottom),
    );
  }

  BorderRadius radiusAll(num value) {
    return BorderRadius.circular(a(value));
  }
}

/// 根窗口尺寸绑定。
///
/// [AppDimensScope] 会在每次 build 时用根 `MediaQuery` 更新这里的值。
/// 因此折叠屏展开、横竖屏切换、分屏 resize 后，`40.dp` 会读取到最新的根尺寸。
///
/// 注意：这里保存的是根窗口尺寸，不是某个局部 Widget 的约束尺寸。
/// 局部布局、Dialog builder、嵌套 Navigator 中仍优先使用 `40.dpc(context)`。
abstract final class AppDimensBinding {
  static AppDimens _current = const AppDimens(
    size: Size(AppDimens.designWidth, 812),
  );

  static AppDimens get current => _current;

  static void update(AppDimens dimens) {
    _current = dimens;
  }

  @visibleForTesting
  static void reset() {
    _current = const AppDimens(size: Size(AppDimens.designWidth, 812));
  }
}

/// 全局尺寸适配入口组件。
///
/// 应放在 `MaterialApp.builder` 中，确保应用根部每次根据最新 [MediaQuery]
/// 更新 [AppDimensBinding.current]。
class AppDimensScope extends StatelessWidget {
  const AppDimensScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    AppDimensBinding.update(AppDimens.of(context));
    return child;
  }
}

/// Widget 层的尺寸快照入口。
extension AppDimensContextX on BuildContext {
  AppDimens get dimens => AppDimens.of(this);
}

/// 设计稿尺寸的便捷扩展。
///
/// - [dp]：无 context 场景使用根窗口尺寸。
/// - [dpc]：Widget/Dialog 内使用当前 context 尺寸，优先推荐。
/// - [dpx]：无 context 但已持有尺寸快照时使用。
///
/// 字号不要使用这些扩展适配。
extension AppAdaptiveNumX on num {
  double get dp {
    return AppDimensBinding.current.a(this);
  }

  double dpc(BuildContext context) {
    return AppDimens.of(context).a(this);
  }

  double dpx(AppDimens dimens) {
    return dimens.a(this);
  }
}
