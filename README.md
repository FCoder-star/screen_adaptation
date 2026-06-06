# screen_adaptation

# Flutter 375 设计稿屏幕适配与 ScreenUtil 迁移方案

本文档用于说明当前项目的屏幕适配设计，以及老项目从 `flutter_screenutil`
迁移到当前方案时的低成本迁移路径。

当前方案的目标不是复刻 `ScreenUtil` 的全部行为，而是在保留 375 设计稿还原效率的同时，
避免大屏、横屏、折叠屏、分屏场景下出现控件被等比放大、布局失真、字体不可控等问题。


```dart
void main() {
  runApp(MyApp());
}
## 使用
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) {
        return AppDimensScope(child: child ?? const SizedBox.shrink());
      },
    );
  }
}

```



## 1. 背景与目标

设计稿基准尺寸为：

```text
375 x 812
```

项目需要覆盖：

- 320/360/375 等小屏和常规手机宽度
- 390/430 等较宽手机
- 手机横屏
- Android 分屏
- 折叠屏单屏和展开态
- 平板或大屏窗口

核心目标：

- 小于 375dp 的屏幕严格按真实宽度比例压缩。
- 大于等于 375dp 的屏幕基础尺寸不继续放大。
- 宽屏和折叠屏通过响应式布局利用额外空间，而不是放大 padding、按钮、圆角和字号。
- 字号不参与尺寸适配，继续走 `TextTheme` 和系统字体缩放。
- 老项目如果主要使用 `.w`，迁移时尽可能做到只替换导包。

## 2. 当前适配核心思想

当前适配公式：

```dart
scale = (width / 375.0).clamp(0.0, 1.0);
```

含义：

- `width < 375dp`：严格按 `width / 375` 压缩。
- `width >= 375dp`：保持 `1.0`，不放大。

示例：

| 屏幕宽度 | scale | 40 的实际值 | 16 的实际值 |
|---:|---:|---:|---:|
| 320dp | 0.853 | 34.13 | 13.65 |
| 360dp | 0.96 | 38.4 | 15.36 |
| 375dp | 1.0 | 40 | 16 |
| 390dp | 1.0 | 40 | 16 |
| 600dp | 1.0 | 40 | 16 |
| 1024dp | 1.0 | 40 | 16 |

这和传统 `ScreenUtil` 的关键区别是：

```text
ScreenUtil 常见行为：
  屏幕越宽，基础尺寸可能继续放大。

当前方案：
  375 以下压缩，375 以上不放大。
```

这样可以避免 390、430、平板、折叠屏展开后出现 UI 间距过大、按钮过高、圆角过圆的问题。

## 3. AppDimens 设计说明

当前项目的核心文件：

```text
lib/core/layout/app_dimens.dart
```

核心概念：

- `AppDimens`：一次尺寸快照，保存当前可用尺寸和适配比例。
- `AppDimensBinding`：保存根窗口尺寸，给无 `BuildContext` 场景使用。
- `AppDimensScope`：全局尺寸更新入口，放在 `MaterialApp.builder`。
- `AppWindowClass`：窗口宽度分级，用于宽屏结构变化。

设计原则：

- 所有非字号 UI 尺寸都通过统一适配入口。
- 设计稿中的尺寸默认按 Flutter dp 记录。
- 小屏压缩由统一系统处理，页面不手写 `width / 375`。
- 大屏不放大基础尺寸，布局结构通过断点变化。
- 字号不使用 `dp`，避免和系统字体缩放叠加失控。

## 4. 初始化方式

在 `MaterialApp.builder` 中包裹 `AppDimensScope`：

```dart
MaterialApp(
  builder: (context, child) {
    return AppDimensScope(
      child: child ?? const SizedBox.shrink(),
    );
  },
)
```

`AppDimensScope` 每次 build 都会根据当前 `MediaQuery.sizeOf(context)` 更新根尺寸。

因此下面这些变化都可以被跟踪：

- 手机横竖屏切换
- Android 分屏 resize
- 折叠屏从单屏展开
- 大屏窗口尺寸变化

不要只在 `initState` 初始化一次尺寸。尺寸必须跟随根 `MediaQuery` 更新。

## 5. 三种尺寸调用方式

### 5.1 无 context 场景：`dp`

```dart
final width = 320.dp;
final iconSize = 40.dp;
```

`dp` 使用的是根窗口尺寸，也就是 `AppDimensBinding.current`。

适合：

- provider/controller 中确实没有 context，但只需要根窗口尺寸估算
- 全局 dialog command 中的默认宽度
- 纯工具类中无法拿到局部约束的简单尺寸

注意：

`dp` 不是局部 Widget 的尺寸。嵌套 Navigator、Dialog builder、局部 panel、分屏子区域中，
如果能拿到 context，应优先使用 `dpc(context)`。

### 5.2 Widget/Dialog 中推荐：`dpc(context)`

```dart
Padding(
  padding: EdgeInsets.all(16.dpc(context)),
  child: child,
)
```

Dialog 限宽：

```dart
showDialog(
  context: context,
  builder: (context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 320.dpc(context)),
        child: const ConfirmDialog(),
      ),
    );
  },
);
```

推荐原因：

- 使用当前 Widget 树的 `MediaQuery`。
- Dialog、嵌套 Navigator、折叠屏展开时更准确。
- 更符合 Flutter 的布局上下文模型。

### 5.3 Painter/Renderer/Helper 中：`dpx(dimens)`

在 Widget 边界创建尺寸快照：

```dart
final dimens = context.dimens;
```

传给无 context 的对象：

```dart
class EditorPainter extends CustomPainter {
  const EditorPainter({required this.dimens});

  final AppDimens dimens;

  @override
  void paint(Canvas canvas, Size size) {
    final padding = 16.dpx(dimens);
  }
}
```

适合：

- `CustomPainter`
- 编辑器渲染器
- 布局计算器
- 不应该持有 `BuildContext` 的 UI 计算逻辑

## 6. 语义化尺寸入口

也可以使用 `context.dimens`：

```dart
final d = context.dimens;

SizedBox(height: d.toolbarHeight);
Padding(padding: d.all(16));
BorderRadius radius = d.radiusAll(8);
```

语义化 getter 来自设计 token：

- `d.xs`
- `d.sm`
- `d.md`
- `d.lg`
- `d.xl`
- `d.radiusSm`
- `d.radiusMd`
- `d.radiusLg`
- `d.iconButton`
- `d.toolbarHeight`

设计 token 如 `AppSpacing.md`、`AppRadius.md`、`AppSizes.iconButton` 是设计基准值。
实际 UI 尺寸应走 `AppDimens`，不要直接使用这些 token 作为最终尺寸。

## 7. 375 以下和 375 以上的处理规则

### 7.1 小于 375dp

严格按真实宽度比例压缩。

```text
actual = designValue * width / 375
```

例如 360dp：

```text
16 -> 15.36
40 -> 38.4
320 -> 307.2
```

### 7.2 大于等于 375dp

保持设计稿原始 dp。

```text
390dp: 16 -> 16
430dp: 16 -> 16
600dp: 16 -> 16
1024dp: 16 -> 16
```

宽出来的空间交给响应式布局处理，而不是放大基础尺寸。

## 8. 宽屏、横屏、折叠屏处理策略

`dp` 只处理小屏尺寸压缩，不负责宽屏结构变化。

断点建议：

```text
compact:  width < 600
medium:   600 <= width < 840
expanded: width >= 840
```

处理策略：

- 手机竖屏：单栏布局。
- 手机横屏：高度不足时内容可滚动，底部工具栏可以侧置。
- 600dp 以上：普通表单、设置页、详情页使用最大内容宽度。
- 840dp 以上：编辑器、列表、设置页可切换多栏。
- 折叠屏展开：基础尺寸不放大，显示更多面板或更宽编辑区。

编辑器类页面可以这样变化：

```text
compact:
  [ 编辑区 ]
  [ 底部工具栏 ]

medium:
  [ 工具栏 ][ 编辑区 ]

expanded:
  [ 左侧导航 ][ 编辑区 ][ 右侧属性面板 ]
```

## 9. Dialog / Provider / 无 context 场景

Provider 或 Controller 不建议直接弹 dialog，也不建议长期持有 `BuildContext`。

推荐模式：

```text
Provider / Controller:
  发出 UI command

Widget:
  监听 command
  使用 context 弹 dialog
  使用 320.dpc(context) 计算宽度
```

如果确实没有 context 且需要尺寸：

```dart
final width = 320.dp;
```

但要记住：

```text
320.dp 使用的是根窗口尺寸，不是局部 overlay 或 panel 的尺寸。
```

如果在 dialog builder 内，优先使用：

```dart
320.dpc(context)
```

## 10. 为什么字号不参与 dp 适配

字号不使用 `dp`，也不使用 `.sp`。

原因：

- 字号本身受系统字体缩放影响。
- 再叠加屏幕宽度缩放容易导致文本 overflow。
- 大屏上字号放大会破坏信息密度。
- Flutter/Material 的 `TextTheme` 已经是更稳定的全局文字体系。

推荐：

```dart
Text(
  title,
  style: Theme.of(context).textTheme.titleMedium,
)
```

不推荐：

```dart
Text(
  title,
  style: TextStyle(fontSize: 16.dp),
)
```

老项目中的 `.sp` 应逐步迁移到 `TextTheme`。

## 11. ScreenUtil 老项目低成本迁移方案

如果老项目主要使用：

```dart
16.w
40.w
EdgeInsets.all(16.w)
BorderRadius.circular(8.w)
```

那么可以新增 ScreenUtil 风格兼容入口：

```dart
extension AppAdaptiveNumX on num {
  double get w => AppDimensBinding.current.a(this);
  double get h => AppDimensBinding.current.a(this);
  double get r => AppDimensBinding.current.a(this);

  double get dp => AppDimensBinding.current.a(this);

  double wc(BuildContext context) => AppDimens.of(context).a(this);
  double hc(BuildContext context) => AppDimens.of(context).a(this);
  double rc(BuildContext context) => AppDimens.of(context).a(this);

  double dpc(BuildContext context) => AppDimens.of(context).a(this);

  double wx(AppDimens dimens) => dimens.a(this);
  double hx(AppDimens dimens) => dimens.a(this);
  double rx(AppDimens dimens) => dimens.a(this);

  double dpx(AppDimens dimens) => dimens.a(this);
}
```

这样老项目大量 `.w` 调用可以保持不动，只替换导包。

## 12. `.w/.h/.r/.sp/.sw/.sh` 迁移映射

| 老写法 | 迁移方式 | 风险 |
|---|---|---|
| `16.w` | 保持 `16.w`，切换导包 | 低 |
| `40.w` | 保持 `40.w`，切换导包 | 低 |
| `8.r` | 保持 `8.r`，切换导包 | 低 |
| `48.h` | 少量小尺寸可保持 `48.h` | 低到中 |
| `300.h` | 改为约束布局、`AspectRatio`、`LayoutBuilder` | 中 |
| `14.sp` | 改为 `TextTheme` | 高 |
| `1.sw` | 改为 `MediaQuery.sizeOf(context).width` | 中 |
| `0.8.sw` | 改为 context 约束下的 maxWidth | 中 |
| `1.sh` | 改为 `MediaQuery.sizeOf(context).height` 或布局约束 | 中 |

本项目已知前提：

- 老项目基本都按 `.w` 适配。
- `.h` 很少。
- `.sp` 基本没有。
- `.sw/.sh` 很少。

因此低成本迁移是可行的。

## 13. 推荐迁移步骤

### Step 1：接入 AppDimens

把 `AppDimens`、`AppDimensScope`、尺寸扩展引入老项目。

### Step 2：替换 ScreenUtilInit

旧：

```dart
ScreenUtilInit(
  designSize: const Size(375, 812),
  builder: (_, child) => MaterialApp(...),
)
```

新：

```dart
MaterialApp(
  builder: (context, child) {
    return AppDimensScope(
      child: child ?? const SizedBox.shrink(),
    );
  },
)
```

### Step 3：批量替换导包

删除：

```dart
import 'package:flutter_screenutil/flutter_screenutil.dart';
```

新增：

```dart
import 'package:your_app/core/layout/app_dimens.dart';
```

大多数 `.w` 调用不需要改。

### Step 4：扫描特殊用法

```bash
rg "\.h"
rg "\.sp"
rg "\.sw|\.sh"
rg "ScreenUtil|ScreenUtilInit|flutter_screenutil"
```

处理原则：

- `.w`：基本保留。
- `.r`：基本保留。
- `.h`：少量小尺寸保留，大块高度人工改布局。
- `.sp`：改 `TextTheme`。
- `.sw/.sh`：改 `MediaQuery`、`LayoutBuilder` 或约束布局。

### Step 5：移除依赖

确认没有旧 API 后，从 `pubspec.yaml` 移除：

```yaml
flutter_screenutil
```

然后运行：

```bash
flutter pub get
flutter analyze
flutter test
```

## 14. `.sw/.sh` 的替代方案

屏幕宽：

```dart
final width = MediaQuery.sizeOf(context).width;
```

屏幕高：

```dart
final height = MediaQuery.sizeOf(context).height;
```

弹窗最大宽度：

```dart
final screenWidth = MediaQuery.sizeOf(context).width;
final maxWidth = math.min(
  320.dpc(context),
  screenWidth - 32.dpc(context),
);
```

占父容器比例：

```dart
FractionallySizedBox(
  widthFactor: 0.8,
  child: child,
)
```

固定比例区域：

```dart
AspectRatio(
  aspectRatio: 16 / 9,
  child: child,
)
```

复杂约束：

```dart
LayoutBuilder(
  builder: (context, constraints) {
    return SizedBox(
      width: constraints.maxWidth * 0.8,
      child: child,
    );
  },
)
```

## 15. 风险点与人工检查清单

### 15.1 `.h`

如果 `.h` 用于小尺寸：

```dart
SizedBox(height: 12.h)
```

可以保留。

如果 `.h` 用于大块高度：

```dart
SizedBox(height: 300.h)
```

建议人工检查，改为：

- `Expanded`
- `Flexible`
- `AspectRatio`
- `LayoutBuilder`
- 滚动容器
- 最大/最小高度约束

### 15.2 `.sp`

必须迁移到 `TextTheme`。

### 15.3 `.sw/.sh`

必须确认是根屏幕尺寸还是局部约束。

在分屏、折叠屏、dialog、嵌套 panel 中，根尺寸和当前可用尺寸可能不同。

### 15.4 大屏行为

迁移后 390dp 以上不再放大基础尺寸。

这可能和旧 ScreenUtil 视觉不同，但这是当前方案的设计目标。

## 16. 测试与验收尺寸

建议至少验收：

```text
320 x 568
360 x 640
375 x 812
390 x 844
812 x 375
600 x 960
1024 x 768
折叠屏单屏
折叠屏展开态
```

验收点：

- 320/360 下无横向 overflow。
- 375 下接近设计稿。
- 390 以上基础尺寸不继续放大。
- 横屏高度不足时主内容可滚动。
- 折叠屏展开后布局结构变化，而不是基础尺寸放大。
- dialog 宽度合理，不贴边，不过宽。
- 字号不因屏幕宽度变化。

## 17. 最终代码规范总结

推荐：

```dart
16.dpc(context)
40.dp
16.dpx(dimens)
context.dimens
16.w // 老项目迁移兼容
```

不推荐：

```dart
MediaQuery.sizeOf(context).width / 375
16.sp
1.sw
1.sh
AppSpacing.md // 直接作为实际 UI 尺寸
AppRadius.md  // 直接作为实际 UI 圆角
```

新增代码建议：

- Widget/Dialog：优先 `dpc(context)` 或 `context.dimens`
- 无 context：可以用 `dp`
- 老项目迁移：允许保留 `.w/.h/.r`
- 字号：使用 `TextTheme`
- 宽屏：使用断点、多栏、最大宽度容器
- 比例区域：使用 `AspectRatio`、`FractionallySizedBox`、`LayoutBuilder`

最终结论：

```text
老项目主要使用 .w 时，可以通过新增 .w 兼容扩展实现低成本迁移。
但当前方案不是 ScreenUtil 等价替代：
  小屏严格压缩，大屏不放大；
  字号不缩放；
  宽屏靠布局结构处理。
```
